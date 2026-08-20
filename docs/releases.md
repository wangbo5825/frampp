# FRAMPP 版本发布

## 发布模型

产品定位：**面向普通用户的一键安装**（类似 XAMPP），按 **FRAMPP 版本 × 组件通道 × 环境** 发布不同的一键安装包；**不提供**高级用户的多 PHP 版本并存（Laragon / Herd 式）。

命名规则：

```text
frampp-setup-<channel>-<version>-<env>.<ext>
示例：frampp-setup-8.5-0.2.0-windows-x64.exe
示例：frampp-setup-8.5-0.2.0-linux-x86_64.tar.gz
```

- `<channel>`：组件通道（当前 `8.5` = FrankenPHP 1.12.7 / PHP 8.5.9 / MariaDB 12.3.2 / Redis 8.10.1）
- `<version>`：FRAMPP 版本号（语义化，随 Release 递增，来源：仓库 `VERSION` 文件）
- `<env>`：目标环境（`windows-x64` / `linux-x86_64`；macOS / Docker 属 M5）
- `<ext>`：`.exe`（Windows，Inno Setup）或 `.tar.gz`（Linux，解压后运行 `./install.sh`）

## 发布步骤

```powershell
# 1. Windows 安装包（在 Windows 上执行，需要 Inno Setup 便携版自动下载）
powershell -ExecutionPolicy Bypass -File installer/scripts/release.ps1 -Env windows-x64

# 2. Linux 安装包（在 Linux + pwsh 7 上执行；Redis 由官方源码静态编译，需 Docker 或 gcc）
pwsh -File installer/scripts/release.ps1 -Env linux-x86_64

# 3. 发布到 GitHub Releases（自动创建 tag v<version> 并上传安装包与哈希清单）
powershell -ExecutionPolicy Bypass -File installer/scripts/release.ps1 -Env windows-x64 -Publish
pwsh -File installer/scripts/release.ps1 -Env linux-x86_64 -Publish
```

产物位于 `dist/installer/`：

- `frampp-setup-<channel>-<version>-<env>.exe`：Inno Setup 一键安装包（安装时自动初始化并启动三件套；卸载自动停服清理）
- `frampp-setup-<channel>-<version>-linux-x86_64.tar.gz`：Linux 自包含包（解压后 `./install.sh` 一键初始化并启动；目录可整体移动）
- `SHA256SUMS.txt`：全部安装包哈希，供用户核对

## Linux 一键安装（用户侧）

```bash
tar -xzf frampp-setup-8.5-0.2.0-linux-x86_64.tar.gz   # 解压出 frampp/
cd frampp
./install.sh                                          # 一键安装：初始化 + 启动 + 打印地址
./bin/frampp status                                   # 查看服务状态
./uninstall.sh                                        # 停止服务并可选清理数据
```

Linux 包自包含三件套二进制（FrankenPHP 静态构建、MariaDB bintar、Redis 官方源码静态编译），
不依赖系统包管理器；运行时仅需常见工具（bash / tar / openssl 或 /dev/urandom）。

## 新增通道

1. 确认目标组件矩阵（如 FrankenPHP 提供 PHP 8.4 Windows 构建）
2. 按环境新增版本清单（Windows：`installer/config/versions.json`；Linux：`installer/config/versions-linux-x86_64.json`）
3. 在 `installer/config/channels.json` 注册通道（`id`、`label`、`default`、`envs`）
4. 跑 `release.ps1 -Channel <新通道>` 验证构建与测试

## 校验

```powershell
Get-FileHash frampp-setup-8.5-0.1.0-windows-x64.exe -Algorithm SHA256
sha256sum frampp-setup-8.5-0.2.0-linux-x86_64.tar.gz
# 与 SHA256SUMS.txt 中对应行比对
```
