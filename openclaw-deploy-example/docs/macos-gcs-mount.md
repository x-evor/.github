# macOS 本机共享挂载（已切换到 JuiceFS）

旧的 `rclone nfsmount + GCS` 路线不再作为默认推荐方案。

新的默认方案见：

- [Windows / macOS / Linux 共享挂载方案（JuiceFS + PostgreSQL + GCS）](juicefs-gcs-mount.md)

保留说明：

- Cloud Run 仍然保持现有 GCS volume 默认实现。
- `scripts/macos_mount_gcs_openclaw.sh` 仅作为旧兼容脚本保留，不再建议作为新的多端共享挂载方案。
