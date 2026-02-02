# 全链路测试方案 (Full-Stack Testing Plan) - Cloud Neutral Toolkit

## 1. 测试目标 (Testing Objectives)

本方案旨在评估系统在以下两个核心维度的表现：
1. **性能边界**: 在不同并发压力下的请求每秒处理数 (QPS) 和响应延迟 (Latency)。
2. **容量评估**: 在当前硬件配置（GCP Cloud Run $1000m$ CPU / $512Mi$ RAM）下，系统能稳定支撑的最大在线用户数量。

---

## 2. 核心测试场景 (Test Scenarios)

### S1: 基础认证与鉴权 (Auth & Session)
- **路径**: `GET /api/auth/session`
- **操作**: 模拟用户高频刷新页面或前端拦截器进行的 Session 校验。
- **预期**: 轻量级操作，高并发下延迟应稳定在 10ms 以内。

### S2: 管理后台数据聚合 (Admin Metrics)
- **路径**: `GET /api/admin/users/metrics`
- **操作**: 聚合大量 PostgreSQL 用户记录及订阅状态。
- **预期**: 属于计算/IO 密集型操作，需评估大规模数据下的查询响应时间。

### S3: 智能问答 (RAG Ask AI)
- **路径**: `POST /api/askai` (Streaming)
- **操作**: 涉及向量库检索 + 大模型流式输出。
- **预期**: 连接保持时间长，需评估连接数并发限制。

### S4: 代理转发 (Proxy/Xray)
- **路径**: VLESS / XHTTP 流量转发
- **操作**: 模拟真实网络代理流量。
- **预期**: 评估 CPU 对加密流量的处理瓶颈。

---

## 3. 评估模型 (Estimation Methodology)

### 3.1 QPS 与延迟评估
利用 **Little's Law** 结合压测结果进行推算：
$$QPS = \frac{\text{并发连接数}}{\text{平均响应时间 (Latency)}}$$

- **低负载**: 验证系统原生延迟（Baseline）。
- **线性增长区**: 并发的增加伴随着 QPS 的等比增加。
- **拐点区 (Saturating Point)**: 延迟开始显著上升，QPS 增长趋缓，代表 CPU/内存达到瓶颈。

### 3.2 最大在线用户数量评估 (Max Online Users)
在线用户数与 QPS 的换算取决于**用户行为模型 (User Behavior Model)**：
- **活跃用户定义**: 假设一个活跃用户每 30 秒产生一次 API 请求。
- **计算公式**: 
  $$\text{Max Users} = \text{Stable QPS} \times 30$$

- **内存瓶颈**: 每个 WebSocket/Long-polling 连接占用约 20-50KB 内存，按 $512Mi$ 可分配内存计算：
  $$\text{Max Connections} \approx \frac{512 \times 1024 \times 0.8}{50} \approx 8000+$$

---

## 4. 推荐压测工具 (Recommended Tooling)

### 推荐使用: **k6 (by Grafana)**
- **选择理由**: JS/TS 脚本支持，高性能，原生支持 HTTP/2 和 WebSocket，适合本地/CI 集成。
- **脚本示例**:
```javascript
import http from 'k6/http';
import { check, sleep } from 'k6';

export let options = {
  stages: [
    { duration: '30s', target: 20 }, // 预热
    { duration: '1m', target: 100 }, // 压力测试
    { duration: '20s', target: 0 },  // 冷却
  ],
};

export default function () {
  let res = http.get('https://accounts.svc.plus/api/auth/session');
  check(res, { 'status was 200': (r) => r.status == 200 });
  sleep(1);
}
```

---

## 5. 执行与验证计划 (Execution Plan)

1. **基准测试 (Baseline)**: 在单并发下记录核心路径延迟。
2. **阶梯加压 (Step Load)**: 逐步增加并发用户数 (VU)，记录每个阶段的 QPS 和 Error Rate。
3. **稳定性测试 (Soak Test)**: 在容量上限的 80% 负载下运行 1 小时，观察内存是否泄漏。
4. **报告导出**: 记录 CPU Usage vs QPS 曲线，确定系统设计的“甜点区”。

---
**拟制人**: Antigravity Assistant
**日期**: 2026-02-02
