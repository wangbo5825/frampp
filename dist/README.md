# dist/

第三方二进制（FrankenPHP / MariaDB / Redis / Composer / Python）**不提交到仓库**，由安装器 / 构建脚本按版本下载并校验哈希。

- 入口：`installer/scripts/download.ps1`（版本与哈希见 `installer/config/versions.json`）
- `binaries/`：下载缓存目录（已 gitignore）
- `runtime/`：本机初始化出的运行时目录（已 gitignore，等同安装后布局）
