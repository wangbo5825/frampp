# 安装器

一键安装与卸载流程、目录布局、PATH 注入、服务注册。

- 平台：Windows（Inno Setup）、Linux x86_64（自解压 `.run`）、Docker（单镜像）
- 安装后布局见 `docs/blueprint.md` §4.1

## 组件矩阵（版本锁定见 `config/versions*.json`）

Windows：

| 组件 | 版本 | 来源 |
| --- | --- | --- |
| FrankenPHP | 1.12.7 | GitHub Releases（原生 Windows，链接官方 PHP 二进制） |
| MariaDB | 12.3.2 LTS | archive.mariadb.org |
| Redis | 8.10.1 | redis-windows 社区构建（msys2） |
| Composer | 2.10.2 | getcomposer.org |
| APCu | 5.1.28 | PECL（PHP 8.5 TS x64） |
| Adminer | 6.0.1 | adminer.org（单文件，随包安装到 htdocs） |

Linux x86_64：

- FrankenPHP 1.12.7：源码定制构建（去部分扩展 + Souin + `caddy-access-filter` + UPX，glibc mostly static）
- MariaDB 12.3.2：源码编译精简版
- Redis 8.10.1：官方源码静态编译
- Python 3.13.15：`python-build-standalone` 精简运行时

## 使用

```powershell
# 1. 下载并校验全部组件（SHA-256 锁定在 versions.json）
powershell -ExecutionPolicy Bypass -File installer/scripts/download.ps1

# 2. 初始化运行时（解压、生成配置与密钥、初始化 MariaDB 数据目录）
powershell -ExecutionPolicy Bypass -File installer/scripts/init.ps1

# 3. 查看 / 启动服务
bin/frampp status
bin/frampp start all
bin/frampp stop all
```

## 构建安装器与镜像（M4 / M5）

```powershell
powershell -ExecutionPolicy Bypass -File installer/scripts/build-installer.ps1
# Windows 产物：dist/installer/frampp-setup-8.5-0.6.0-windows-x64.exe

pwsh -File installer/scripts/build-linux-package.ps1 -Env linux-x86_64
# Linux 产物：dist/installer/frampp-setup-8.5-0.6.0-linux-x86_64.run

pwsh -File installer/scripts/build-docker.ps1 -ImageName frampp
# Docker 产物：frampp:0.6.0 镜像（复用上面的 .run 载荷）
```

### Docker 镜像

Dockerfile 复用 Linux `.run` 产物，`--extract-only` 解压而不初始化，镜像首启动
时才生成随机密钥与 MariaDB 数据目录。默认以非 root 用户 `frampp` 运行，入口
脚本见 `installer/scripts/linux/docker-entrypoint.sh`。

```bash
docker run -d --name frampp \
  -p 8080:8080 -p 8081:8081 \
  -v frampp-data:/opt/frampp/var \
  -v frampp-logs:/opt/frampp/logs \
  -v frampp-htdocs:/opt/frampp/htdocs \
  frampp:0.6.0
```

详细卷、端口与发布说明见 [docs/docker.md](../docs/docker.md)。

安装器行为：

- 打包干净运行时（不含开发机数据/密钥），安装时自动运行 `init.ps1` 生成配置、密钥与 MariaDB 数据目录，并启动三件套
- 卸载时先停止服务再删除（Linux 运行 `bin/uninstall`，含 `var/`、`logs/` 与 init 生成的配置）
- 安装 / 升级 / 卸载流程见 [docs/upgrade.md](../docs/upgrade.md)

## 安全与供应链

- 所有第三方二进制固定版本并校验 SHA-256；`dist/binaries/` 不入库（见 `.gitignore`）
- 服务默认仅绑定 `127.0.0.1`；数据库 / Redis 密码与控制面板令牌由 `init.ps1` 随机生成，存于 `var/secrets.json`
- 控制面板 Web 端（127.0.0.1:8081）的启停操作必须携带面板令牌
- 代码签名列为里程碑 M4 的成本项（证书采购），当前安装器未签名，SmartScreen 可能提示
