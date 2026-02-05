# Skill: os-capacity-patrol

## Purpose

标准化 Linux 节点磁盘容量巡检与安全清理流程，避免系统盘被日志/缓存持续占满导致服务不稳定。

## Trigger

出现以下任一情况时立即执行：

- `df -h /` 使用率 >= 80%
- 系统告警提示磁盘空间不足
- 服务异常伴随大量日志写入（例如 journal/syslog 快速增长）

## Scope

适用于 Cloud-Neutral Toolkit 维护的 Linux 节点（如 `hk-xhttp`, `jp-xhttp`, `us-xhttp`）。

## Inspection Commands

```bash
df -h
du -xhd1 / | sort -hr | head -n 20
du -xhd2 /var | sort -hr | head -n 30
du -xhd2 /root | sort -hr | head -n 40
find /root /var -xdev -type f -size +100M -printf "%s %p\n" | sort -nr | head -n 40
```

## Safe Cleanup Baseline

```bash
journalctl --vacuum-size=200M
apt-get clean
rm -rf /root/go/pkg/mod /root/go/pkg/sumdb /root/.cache/go-build
logrotate -f /etc/logrotate.conf
rm -f /var/log/syslog.1
```

> 禁止清理：数据库数据目录、应用持久化目录、未知业务文件。

## Persistent Protection (Mandatory)

配置 journald 上限，防止再次打满：

文件：`/etc/systemd/journald.conf.d/99-disk-cap.conf`

```ini
[Journal]
SystemMaxUse=200M
RuntimeMaxUse=50M
SystemKeepFree=1G
```

生效命令：

```bash
systemctl restart systemd-journald
journalctl --vacuum-size=200M
journalctl --disk-usage
```

## Verification Gate

执行后必须确认：

1. `/` 使用率降至 < 70%
2. `journalctl --disk-usage` <= 200M（接近即可）
3. 关键服务仍在运行（如 `agent-svc-plus`, `xray`, `nginx`）
4. 保留清理前后 `df -h /` 记录

## Multi-Host Rolling Procedure

多机执行时遵循顺序：

1. 单台试运行（确认无副作用）
2. 逐台执行（hk -> jp -> us）
3. 每台完成后立即做 `df -h /` 和服务状态检查

## Rollback / Recovery

若清理后异常：

- 先恢复服务：`systemctl restart <service>`
- 若涉及日志策略误配，移除 drop-in 并重启 journald：
  - `rm -f /etc/systemd/journald.conf.d/99-disk-cap.conf`
  - `systemctl restart systemd-journald`
- 必要时从备份恢复误删文件
