# 安装器

一键安装与卸载流程、目录布局、PATH 注入、服务注册。

- 平台：Windows（Inno Setup / MSIX 待定）
- 安装后布局见 `docs/blueprint.md` §4.1

## M1 组件（版本锁定见 `config/versions.json`）

| 组件 | 版本 | 来源 |
| --- | --- | --- |
| FrankenPHP | 1.12.7 | GitHub Releases（原生 Windows，链接官方 PHP 二进制） |
| MariaDB | 12.3.2 LTS | archive.mariadb.org |
| Redis | 8.10.1 | redis-windows 社区构建（msys2） |
| Composer | 2.10.2 | getcomposer.org |
| APCu | 5.1.28 | PECL（PHP 8.5 TS x64） |
| Adminer | 6.0.1 | adminer.org（单文件，随包安装到 htdocs） |

## 使用

```powershell
# 1. 下载并校验全部组件（SHA-256 锁定在 versions.json）
powershell -ExecutionPolicy Bypass -File installer/scripts/download.ps1

# 2. 初始化运行时（解压、生成配置与密钥、初始化 MariaDB 数据目录）
powershell -ExecutionPolicy Bypass -File installer/scripts/init.ps1

# 3. 查看 / 启动服务
php control-panel/bin/frampp status
php control-panel/bin/frampp start all
php control-panel/bin/frampp stop all
```

## 安全与供应链

- 所有第三方二进制固定版本并校验 SHA-256；`dist/binaries/` 不入库（见 `.gitignore`）
- 服务默认仅绑定 `127.0.0.1`；数据库 / Redis 密码与控制面板令牌由 `init.ps1` 随机生成，存于 `data/secrets.json`
- 控制面板 Web 端（127.0.0.1:8081）的启停操作必须携带面板令牌
