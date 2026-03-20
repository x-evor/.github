set -euo pipefail

CFG="$HOME/.openclaw/openclaw.json"
BAK="$HOME/.openclaw/openclaw.json.bak.$(date +%Y%m%d-%H%M%S)"

cp "$CFG" "$BAK"
echo "Backup: $BAK"

tmp="$(mktemp)"
jq '
.gateway.mode = "local" |
.gateway.bind = "loopback" |
.gateway.port = ( .gateway.port // 18789 ) |

# 网关鉴权（若为空则自动生成占位，建议你后续替换成强 token）
.gateway.auth = (.gateway.auth // {}) |
.gateway.auth.token = ( .gateway.auth.token // "CHANGE_ME_STRONG_TOKEN_$(date +%s)" ) |

# Browser/Web 自动化能力
.web = (.web // {}) |
.web.automation = (.web.automation // {}) |
.web.automation.enabled = true |
.web.automation.runtime = "node" |
.web.automation.browserMode = "full_control" |
.web.automation.attachOnly = false |
.web.automation.fileUpload = true |
.web.automation.screenshots = true |
.web.automation.logging = true |
.web.automation.submitConfirmation = true |
.web.automation.sessionReuse = true |
.web.automation.captchaHandoff = "manual_required" |

# 域名白名单
.web.allowlist = (
((.web.allowlist // []) + ["zhipin.com","liepin.com","linkedin.com","indeed.com"])
| unique
) |

# 插件白名单（按你当前环境）
.plugins = (.plugins // {}) |
.plugins.allow = (
((.plugins.allow // []) + ["memos-cloud-openclaw-plugin"])
| unique
)
' "$CFG" > "$tmp"

mv "$tmp" "$CFG"
echo "Patched: $CFG"

openclaw gateway restart
openclaw status
openclaw security audit
