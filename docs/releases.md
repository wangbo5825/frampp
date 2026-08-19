# FRAMPP 版本发布

## 发布模型

产品定位：**面向普通用户的一键安装**（类似 XAMPP），按 **FRAMPP 版本 × 组件通道 × 环境** 发布不同的一键安装包；**不提供**高级用户的多 PHP 版本并存（Laragon / Herd 式）。

命名规则：

```text
frampp-setup-<channel>-<version>-<env>.exe
示例：frampp-setup-8.5-0.1.0-windows-x64.exe
```

- `<channel>`：组件通道（当前 `8.5` = FrankenPHP 1.12.7 / PHP 8.5.9 / MariaDB 12.3.2 / Redis 8.10.1）
- `<version>`：FRAMPP 版本号（语义化，随 Release 递增）
- `<env>`：目标环境（当前 `windows-x64`；Linux / macOS / Docker 属 M5）

## 发布步骤

```powershell
# 1. 构建全部通道 + 生成 SHA256SUMS.txt（不发布）
powershell -ExecutionPolicy Bypass -File installer/scripts/release.ps1 -Version 0.1.0

# 2. 指定通道/环境
powershell -ExecutionPolicy Bypass -File installer/scripts/release.ps1 -Version 0.1.0 -Channel 8.5 -Env windows-x64

# 3. 发布到 GitHub Releases（自动创建 tag v<version> 并上传安装包与哈希清单）
powershell -ExecutionPolicy Bypass -File installer/scripts/release.ps1 -Version 0.1.0 -Publish
```

产物位于 `dist/installer/`：

- `frampp-setup-<channel>-<version>-<env>.exe`：Inno Setup 一键安装包（安装时自动初始化并启动三件套；卸载自动停服清理）
- `SHA256SUMS.txt`：全部安装包哈希，供用户核对

## 新增通道

1. 确认目标组件矩阵（如 FrankenPHP 提供 PHP 8.4 Windows 构建）
2. 新增 `installer/config/versions-<channel>.json`（复制现有矩阵并调整版本/哈希）
3. 在 `installer/config/channels.json` 注册通道（`id`、`label`、`default`、`envs`）
4. 跑 `release.ps1 -Channel <新通道>` 验证构建与测试

## 校验

```powershell
Get-FileHash frampp-setup-8.5-0.1.0-windows-x64.exe -Algorithm SHA256
# 与 SHA256SUMS.txt 中对应行比对
```
