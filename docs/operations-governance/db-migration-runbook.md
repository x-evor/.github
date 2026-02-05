---

# PostgreSQL Migration Runbook (Cloud-Neutral Toolkit)

## Scope
This runbook covers PostgreSQL database migrations between two hosts (source → target) with:
- **Backup/Restore**
- **Stop-write migration** (short maintenance window, consistent)
- **Online migration** (full copy + incremental sync)

It is tailored for containerized Postgres (`docker exec postgresql-svc-plus`) and the current stack:
- **accounts.svc.plus** → database `account`
- **rag-server.svc.plus** → database `knowledge_db`
- **postgres** database → can be reinitialized

---

## 1) 迁移准备（条件）

- [ ] 确认源/目标主机 IP 或域名
- [ ] 确认维护窗口（若停写迁移）
- [ ] 确认 Postgres 版本（源/目标）
- [ ] 确认扩展（如 `vector`, `pg_jieba`, `hstore`）
- [ ] 目标磁盘空间 ≥ 2× 备份大小
- [ ] 确认 root SSH 访问权限
- [ ] 确认容器名（默认 `postgresql-svc-plus`）
- [ ] 确认 `POSTGRES_PASSWORD`（更新应用配置时需要）

### 1.1 备份/恢复（通用基础）

```bash
# On SOURCE
ssh root@SOURCE_HOST "docker exec postgresql-svc-plus pg_dumpall -U postgres --clean --if-exists > /root/pg_dumpall.sql"
ssh root@SOURCE_HOST "ls -lh /root/pg_dumpall.sql"
```

按库备份（推荐）：

```bash
# account database
ssh root@SOURCE_HOST "docker exec postgresql-svc-plus pg_dump -U postgres -d account -Fc > /root/account.dump"

# knowledge_db database
ssh root@SOURCE_HOST "docker exec postgresql-svc-plus pg_dump -U postgres -d knowledge_db -Fc > /root/knowledge_db.dump"
```

恢复到目标：

```bash
# Transfer
scp root@SOURCE_HOST:/root/account.dump /root/
scp root@SOURCE_HOST:/root/knowledge_db.dump /root/

# Restore
ssh root@TARGET_HOST "docker exec -i postgresql-svc-plus createdb -U postgres account"
ssh root@TARGET_HOST "docker exec -i postgresql-svc-plus createdb -U postgres knowledge_db"

ssh root@TARGET_HOST "docker exec -i postgresql-svc-plus pg_restore -U postgres -d account /root/account.dump"
ssh root@TARGET_HOST "docker exec -i postgresql-svc-plus pg_restore -U postgres -d knowledge_db /root/knowledge_db.dump"
```

---

## 2) 迁移窗口（停写/不停写选择）

### 2.1 停写迁移（短暂维护窗口）

- 暂停 **accounts.svc.plus**、**rag-server.svc.plus** 的写入
- 确认无活跃事务：

```bash
ssh root@SOURCE_HOST "docker exec postgresql-svc-plus psql -U postgres -d postgres -c \"select datname, count(*) from pg_stat_activity where state <> 'idle' group by datname;\""
```

### 2.2 不停写迁移（全量 + 增量）

- 先做全量拷贝（与 1.1 一致）
- 再做增量同步：
  - 逻辑复制（publication/subscription）
  - 或 WAL 方案（`pg_basebackup` + WAL shipping）

> 选择与权限/拓扑匹配的方案；不停写迁移通常更复杂但停机时间更短。

---

## 3) 迁移执行

### 3.1 停写迁移执行（推荐）

```bash
ssh root@SOURCE_HOST "docker exec postgresql-svc-plus pg_dump -U postgres -d account -Fc > /root/account.dump"
ssh root@SOURCE_HOST "docker exec postgresql-svc-plus pg_dump -U postgres -d knowledge_db -Fc > /root/knowledge_db.dump"
```

恢复到目标（见 1.1）。

### 3.2 不停写迁移执行（概览）

1) 全量拷贝（`pg_dump`/`pg_restore`）  
2) 建立增量同步（逻辑复制或 WAL）  
3) 追平后切流  
4) 关闭同步  

---

## 4) 验证（迁移后校验）

### 4.1 基础校验

```bash
ssh root@TARGET_HOST "docker exec postgresql-svc-plus psql -U postgres -d postgres -Atc \"select datname, pg_database_size(datname) from pg_database where datistemplate=false order by datname;\""
```

### 4.2 一致性校验（建议）

- **行数对比（关键表）**：
```bash
# 示例：账户/用户/组织等关键表（按实际表名替换）
ssh root@SOURCE_HOST "docker exec postgresql-svc-plus psql -U postgres -d account -Atc \"select 'users', count(*) from users;\""
ssh root@TARGET_HOST "docker exec postgresql-svc-plus psql -U postgres -d account -Atc \"select 'users', count(*) from users;\""
```

- **抽样 checksum（可选）**：
```bash
# 需要 pgcrypto：select digest(...) as sha256
ssh root@SOURCE_HOST "docker exec postgresql-svc-plus psql -U postgres -d account -Atc \"select encode(digest(string_agg(id::text, ',' order by id), 'sha256'), 'hex') from users;\""
ssh root@TARGET_HOST "docker exec postgresql-svc-plus psql -U postgres -d account -Atc \"select encode(digest(string_agg(id::text, ',' order by id), 'sha256'), 'hex') from users;\""
```

### 4.3 应用验证

- 账号登录/读写是否正常（accounts）
- RAG 查询是否正常（knowledge_db）
- 观察错误日志

---

## 5) 扩展/FTS 特例（knowledge_db）

If `pg_dump` crashes on `pg_ts_config_map` (seen with `jieba_search`):

### Workaround
1) **Drop generated column** that depends on `jieba_search`:
```bash
ssh root@SOURCE_HOST "docker exec postgresql-svc-plus psql -U postgres -d knowledge_db -c \"ALTER TABLE documents DROP COLUMN IF EXISTS content_tsv;\""
```

2) **Drop `jieba_search` config**:
```bash
ssh root@SOURCE_HOST "docker exec postgresql-svc-plus psql -U postgres -d knowledge_db -c \"DROP TEXT SEARCH CONFIGURATION IF EXISTS public.jieba_search;\""
```

3) Run schema + data dumps:
```bash
ssh root@SOURCE_HOST "docker exec postgresql-svc-plus pg_dump -U postgres -d knowledge_db --schema-only -Fp > /root/knowledge_db_schema.sql"
ssh root@SOURCE_HOST "docker exec postgresql-svc-plus pg_dump -U postgres -d knowledge_db --data-only -Fp > /root/knowledge_db_data.sql"
```

4) Recreate `jieba_search` + column **after restore** on target:
```bash
# create config
ssh root@TARGET_HOST "docker exec postgresql-svc-plus psql -U postgres -d knowledge_db -c \"CREATE TEXT SEARCH CONFIGURATION public.jieba_search ( COPY = public.jiebacfg );\""

# recreate column (note: use 'A'::\"char\")
ssh root@TARGET_HOST "docker exec postgresql-svc-plus psql -U postgres -d knowledge_db -c \"ALTER TABLE documents ADD COLUMN content_tsv tsvector GENERATED ALWAYS AS (setweight(to_tsvector('jieba_search'::regconfig, COALESCE(content, ''::text)), 'A'::\"char\")) STORED;\""
```

---

---

## 6) 回滚方案

- Keep old DB running until validation complete
- If failure, revert app configs to source host
- Document failure cause and retry plan

---

## 7) Reference Endpoints

- **New DB TLS endpoint:** `postgresql.svc.plus:443`
- **Client stunnel endpoint:** `127.0.0.1:15432`

---

## 8) Example: Current Migration Map

- Source: `34.85.14.134`
- Target: `postgresql.svc.plus`
- `accounts.svc.plus` → database `account`
- `rag-server.svc.plus` → database `knowledge_db`

---

## 9) 迁移记录（2026-02-05）

### 9.1 基本信息

- 停写窗口：已停写
- 源主机：`34.85.93.244`
- 目标主机：`34.84.219.111`
- 数据库：
  - `account`
  - `knowledge_db`
  - `postgres`（可重新初始化）

### 9.2 迁移步骤摘要

- `account`：
  - 源库导出 `pg_dump -Fc`
  - 目标库 `createdb` + `pg_restore`
- `knowledge_db`：
  - 由于 `pg_ts_config_map` 崩溃（`jieba_search` 相关），先在源库移除 `jieba_search`/`content_tsv`
  - 使用 schema/data 分离导出
  - 目标库恢复 schema/data
  - 目标库安装 `pg_jieba` 并补回 `jieba_search`/`content_tsv`

### 9.3 pg_jieba 处理

目标主机为 Debian 12（Postgres 17），无现成 `pg_jieba` 包，采用源码安装：

- 依赖：`build-essential git postgresql-server-dev-17 cmake`
- 源码：
  - `git clone https://github.com/jaiminpan/pg_jieba.git`
  - `git submodule update --init --recursive`
  - `cmake .. -DPostgreSQL_TYPE_INCLUDE_DIR=/usr/include/postgresql/17/server`
  - `make && make install`

补回配置与生成列：

```sql
CREATE EXTENSION IF NOT EXISTS pg_jieba WITH SCHEMA public;
CREATE TEXT SEARCH CONFIGURATION public.jieba_search ( COPY = public.jiebacfg );
ALTER TABLE documents
  ADD COLUMN content_tsv tsvector GENERATED ALWAYS AS
  (setweight(to_tsvector('jieba_search'::regconfig, COALESCE(content, ''::text)),
             'A'::pg_catalog."char")) STORED;
```

### 9.4 验证结果

- 目标库存在 `account` / `knowledge_db`
- 关键表行数一致（源/目标均为 0）
- 扩展一致性：目标补齐 `pg_jieba`
- 应用侧旧 DB 链接已修复
