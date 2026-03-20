# OpenClaw Gateway Runbook

适用场景：

- `https://openclaw.svc.plus/overview` 显示 `pairing required`
- `openclaw devices list` 默认执行失败，报 `gateway token mismatch`
- 需要在 `root@openclaw.svc.plus` 上快速确认网关、浏览器配对和 CLI 鉴权状态

## 目标状态

- `openclaw-gateway.service` 正常运行
- 浏览器侧 `openclaw-control-ui` 已配对
- `https://openclaw.svc.plus/overview` 可以连上网关
- 远端 CLI 可以正常执行 `openclaw devices list`

## 关键现象

这次故障里有两条链路：

1. 浏览器设备未批准，所以 UI 显示 `pairing required`
2. 远端 CLI 默认鉴权路径异常，`openclaw devices list` 不带 `--token` 会报：

```text
unauthorized: gateway token mismatch
```

注意：

- 只要显式传入 gateway token 后命令恢复正常，就说明网关服务本身是健康的
- 这时真正要处理的是浏览器配对，CLI 默认 token mismatch 可先按已知问题绕过

## 1. 确认网关服务

在远端执行：

```bash
ssh root@openclaw.svc.plus

systemctl --user status openclaw-gateway.service --no-pager
ss -ltnp | grep 18789
```

预期：

- `openclaw-gateway.service` 为 `active (running)`
- `127.0.0.1:18789` 正在监听

## 2. 从配置文件读取 gateway token

```bash
TOKEN="$(jq -r '.gateway.auth.token' /root/.openclaw/openclaw.json)"
echo "$TOKEN"
```

同时确认本地配置里的两个 token 一致：

```bash
jq -r '.gateway.auth.token,.gateway.remote.token' /root/.openclaw/openclaw.json
```

这两个值必须完全相同。

## 3. 验证是不是“默认 CLI 路径异常”

先跑默认命令：

```bash
openclaw devices list
```

如果报：

```text
gateway token mismatch
```

再用显式 token 复测：

```bash
openclaw devices list --json --token "$TOKEN"
openclaw gateway health --token "$TOKEN"
```

判定标准：

- 显式 `--token` 成功
- 默认命令失败

则说明：

- 网关 token 本身没坏
- 服务端 token 也没坏
- 是当前 CLI 默认鉴权路径异常

本次现场就是这个状态。

## 4. 检查浏览器是否处于待批准状态

```bash
openclaw devices list --json --token "$TOKEN"
```

重点看 `pending` 里有没有类似下面的设备：

```json
{
  "clientId": "openclaw-control-ui",
  "clientMode": "webchat",
  "platform": "MacIntel"
}
```

如果有，说明浏览器已经发起配对请求，但网关还没批准。

## 5. 批准浏览器配对请求

把 `openclaw-control-ui` 的 `requestId` 取出来并批准：

```bash
REQ="$(openclaw devices list --json --token "$TOKEN" | jq -r '.pending[] | select(.clientId=="openclaw-control-ui") | .requestId' | tail -n 1)"
echo "$REQ"

openclaw devices approve "$REQ" --token "$TOKEN"
```

再次检查：

```bash
openclaw devices list --json --token "$TOKEN"
```

预期：

- `pending` 为空
- `paired` 里出现 `openclaw-control-ui`

## 6. 让浏览器重新连接

在浏览器侧执行：

1. 保持 `WebSocket URL = wss://openclaw.svc.plus`
2. `Gateway token` 填当前 token
3. 点击 `连接` 或直接刷新页面

如果之前页面一直停在旧状态，直接整页刷新一次更稳。

## 7. 回归检查

### 服务端

```bash
openclaw devices list --json --token "$TOKEN"
openclaw gateway health --token "$TOKEN"
journalctl --user -u openclaw-gateway.service -n 100 --no-pager
```

重点看日志里是否还在重复出现：

- `reason=pairing required`
- `reason=token_mismatch`

### 浏览器端

预期：

- `版本` 不再是 `不适用`
- `健康状况` 不再是 `离线`
- 右侧不再出现 `pairing required`

## 8. 已知问题与临时绕过

本次现场发现一个已知异常：

- `/root/.openclaw/openclaw.json` 里的 `gateway.auth.token` 和 `gateway.remote.token` 一致
- `openclaw-gateway.service` 的 `ExecStart` token 也一致
- 但 `openclaw devices list` 默认执行仍然报 `token mismatch`
- 显式 `--token "$TOKEN"` 可以正常工作

在定位出 CLI 默认鉴权来源之前，远端管理命令统一用显式 token：

```bash
TOKEN="$(jq -r '.gateway.auth.token' /root/.openclaw/openclaw.json)"

openclaw devices list --json --token "$TOKEN"
openclaw gateway health --token "$TOKEN"
openclaw devices approve <requestId> --token "$TOKEN"
```

这比盲目重装或改 token 更安全，因为它已经证明网关当前接受的 token 是正确的。

## 9. 常用排障命令

```bash
systemctl --user status openclaw-gateway.service --no-pager
systemctl --user cat openclaw-gateway.service

jq '.gateway' /root/.openclaw/openclaw.json
jq '.' /root/.openclaw/devices/pending.json
jq '.' /root/.openclaw/devices/paired.json

journalctl --user -u openclaw-gateway.service -n 200 --no-pager
ss -ltnp | grep 18789
```

## 10. 这次实际处理摘要

这次是按下面顺序恢复的：

1. 确认网关进程和 `127.0.0.1:18789` 正常监听
2. 从 `/root/.openclaw/openclaw.json` 取出 gateway token
3. 验证默认 `openclaw devices list` 失败，但显式 `--token` 成功
4. 用显式 token 列出 pending devices
5. 找到 `openclaw-control-ui` 的 pending request
6. 执行 `openclaw devices approve <requestId> --token "$TOKEN"`
7. 确认设备从 `pending` 进入 `paired`
8. 让浏览器刷新并重新连接
