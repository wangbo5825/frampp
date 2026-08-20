<#
.SYNOPSIS
    FRAMPP Linux 安装包构建：准备干净的暂存目录（dist/staging-linux），
    下载/编译组件并打包为 tar.gz（XAMPP 风格一键安装包）。

.DESCRIPTION
    - 组件矩阵：installer/config/versions-linux-x86_64.json（哈希锁定）
    - Redis 由官方源码静态编译（installer/scripts/linux/build-redis.sh）
    - 产物：dist/installer/frampp-setup-<channel>-<version>-linux-x86_64.tar.gz
    - 运行环境：Linux + pwsh 7 + tar（CI ubuntu 与本地 Linux 均可）

.PARAMETER Root
    仓库根目录。

.PARAMETER AppVersion
    FRAMPP 版本号（默认读取仓库 VERSION 文件）。
#>
[CmdletBinding()]
param(
    [string]$Root,
    [string]$CacheDir,
    [string]$StagingDir,
    [string]$ToolsDir,
    [string]$AppVersion,
    [string]$Channel = "8.5",
    [string]$Env = "linux-x86_64"
)

if (-not $Root) { $Root = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path }
if (-not $CacheDir) { $CacheDir = Join-Path $Root "dist/binaries" }
if (-not $StagingDir) { $StagingDir = Join-Path $Root "dist/staging-linux" }
if (-not $ToolsDir) { $ToolsDir = Join-Path $Root "dist/tools" }
if (-not $AppVersion) { $AppVersion = (Get-Content -LiteralPath (Join-Path $Root "VERSION") -Raw).Trim() }

$ErrorActionPreference = "Stop"

function Write-Step([string]$Message) { Write-Host "==> $Message" -ForegroundColor Cyan }

if ($Env -ne "linux-x86_64") {
    throw "本脚本仅用于 linux-x86_64（当前: $Env）"
}

$versionsFile = Join-Path $Root "installer/config/versions-linux-x86_64.json"
$config = Get-Content -Raw -LiteralPath $versionsFile | ConvertFrom-Json
if ($config.platform -ne "linux-x86_64") {
    throw "versions 文件平台不匹配: $versionsFile"
}

$installerDir = Join-Path $Root "dist/installer"
New-Item -ItemType Directory -Force -Path $installerDir | Out-Null
New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null

# 1. 组件缓存（哈希锁定，缺失时自动下载）
$required = @(
    $config.components.frankenphp.cacheFile,
    $config.components.mariadb.cacheFile,
    $config.components.redis.cacheFile,
    $config.components.composer.cacheFile,
    $config.components.adminer.cacheFile
)
$missing = @($required | Where-Object { -not (Test-Path -LiteralPath (Join-Path $CacheDir $_)) })
if ($missing.Count -gt 0) {
    Write-Step "组件缓存缺失，运行 download.ps1（linux 版本清单）"
    & (Join-Path $PSScriptRoot "download.ps1") -Root $Root -CacheDir $CacheDir -ConfigPath $versionsFile
}

# 2. 干净暂存
if (Test-Path -LiteralPath $StagingDir) {
    Remove-Item -LiteralPath $StagingDir -Recurse -Force
}
$layout = @(
    (Join-Path $StagingDir "frankenphp"),
    (Join-Path $StagingDir "mariadb"),
    (Join-Path $StagingDir "redis"),
    (Join-Path $StagingDir "bin"),
    (Join-Path $StagingDir "htdocs"),
    (Join-Path $StagingDir "logs"),
    (Join-Path $StagingDir "data"),
    (Join-Path $StagingDir "control-panel"),
    (Join-Path $StagingDir "agent"),
    (Join-Path $StagingDir "installer/scripts"),
    (Join-Path $StagingDir "installer/config"),
    (Join-Path $StagingDir "installer/templates"),
    (Join-Path $StagingDir "docs"),
    (Join-Path $StagingDir "templates")
)
foreach ($d in $layout) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
Write-Step "暂存目录就绪: $StagingDir"

# 3. 组件
# FrankenPHP：单文件静态二进制
Write-Step "安装 FrankenPHP $($config.components.frankenphp.version)"
Copy-Item -LiteralPath (Join-Path $CacheDir $config.components.frankenphp.cacheFile) -Destination (Join-Path $StagingDir "frankenphp/frankenphp")
& chmod +x (Join-Path $StagingDir "frankenphp/frankenphp")

# MariaDB：bintar tarball
Write-Step "解压 MariaDB $($config.components.mariadb.version)"
$mariaTar = Join-Path $CacheDir $config.components.mariadb.cacheFile
& tar -xzf $mariaTar -C (Join-Path $StagingDir "mariadb")
$top = Get-ChildItem -LiteralPath (Join-Path $StagingDir "mariadb") -Force
if ($top.Count -eq 1 -and $top[0].PSIsContainer) {
    $nested = $top[0].FullName
    Get-ChildItem -LiteralPath $nested -Force | Move-Item -Destination (Join-Path $StagingDir "mariadb") -Force
    Remove-Item -LiteralPath $nested -Recurse -Force
}
Get-ChildItem -LiteralPath (Join-Path $StagingDir "mariadb/bin") -File | ForEach-Object { & chmod +x $_.FullName }

# Redis：官方源码静态编译（复用 dist/tools 下的构建产物，避免重复编译）
$redisBinDir = Join-Path $ToolsDir "redis-linux-x86_64"
$redisMarker = Join-Path $redisBinDir ".built-$($config.components.redis.version)"
if (-not (Test-Path -LiteralPath (Join-Path $redisBinDir "redis-server")) -or -not (Test-Path -LiteralPath $redisMarker)) {
    Write-Step "编译 Redis $($config.components.redis.version)（静态）"
    & bash (Join-Path $PSScriptRoot "linux/build-redis.sh") `
        (Join-Path $CacheDir $config.components.redis.cacheFile) `
        $redisBinDir `
        $config.components.redis.version
    New-Item -ItemType File -Path $redisMarker -Force | Out-Null
} else {
    Write-Step "复用已编译 Redis（$redisBinDir）"
}
foreach ($redisBin in @("redis-server", "redis-cli")) {
    Copy-Item -LiteralPath (Join-Path $redisBinDir $redisBin) -Destination (Join-Path $StagingDir "redis")
    & chmod +x (Join-Path (Join-Path $StagingDir "redis") $redisBin)
}

# Composer / Adminer
Write-Step "安装 Composer / Adminer"
Copy-Item -LiteralPath (Join-Path $CacheDir $config.components.composer.cacheFile) -Destination (Join-Path $StagingDir "bin/composer.phar")
Copy-Item -LiteralPath (Join-Path $CacheDir $config.components.adminer.cacheFile) -Destination (Join-Path $StagingDir "htdocs/adminer.php")

# 4. 仓库内容（控制面板 / Agent / 模板 / 文档 / 安装脚本）
Write-Step "复制控制面板 / Agent / 模板 / 文档"
Copy-Item -Path (Join-Path $Root "control-panel/web/*") -Destination (Join-Path $StagingDir "control-panel/web") -Recurse -Force
Copy-Item -LiteralPath (Join-Path $Root "control-panel/src") -Destination (Join-Path $StagingDir "control-panel") -Recurse -Force
Copy-Item -LiteralPath (Join-Path $Root "control-panel/bin") -Destination (Join-Path $StagingDir "control-panel") -Recurse -Force
Copy-Item -LiteralPath (Join-Path $Root "agent") -Destination (Join-Path $StagingDir "agent") -Recurse -Force
Copy-Item -Path (Join-Path $Root "installer/scripts/*") -Destination (Join-Path $StagingDir "installer/scripts") -Recurse -Force
Copy-Item -Path (Join-Path $Root "installer/config/*") -Destination (Join-Path $StagingDir "installer/config") -Recurse -Force
Copy-Item -Path (Join-Path $Root "installer/templates/*") -Destination (Join-Path $StagingDir "installer/templates") -Recurse -Force
Copy-Item -Path (Join-Path $Root "docs/*") -Destination (Join-Path $StagingDir "docs") -Recurse -Force
Copy-Item -LiteralPath (Join-Path $Root "installer/templates/project-minimal") -Destination (Join-Path $StagingDir "templates/project-minimal") -Recurse -Force
Copy-Item -LiteralPath (Join-Path $Root "README.md") -Destination (Join-Path $StagingDir "README.md")
Copy-Item -LiteralPath (Join-Path $Root "LICENSE") -Destination (Join-Path $StagingDir "LICENSE")
Copy-Item -LiteralPath (Join-Path $Root "VERSION") -Destination (Join-Path $StagingDir "VERSION")

# 默认站点首页
Copy-Item -LiteralPath (Join-Path $Root "installer/templates/htdocs/index.php") -Destination (Join-Path $StagingDir "htdocs/index.php")

# 一键安装/卸载脚本与 CLI 包装器（包根目录）
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "linux/install.sh") -Destination (Join-Path $StagingDir "install.sh")
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "linux/uninstall.sh") -Destination (Join-Path $StagingDir "uninstall.sh")
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "linux/frampp-wrapper.sh") -Destination (Join-Path $StagingDir "bin/frampp")
foreach ($bin in @("install.sh", "uninstall.sh", "bin/frampp")) {
    & chmod +x (Join-Path $StagingDir $bin)
}

# 5. 打包（顶层目录 frampp/，owner/group 归一化以便复现）
$outName = "frampp-setup-$Channel-$AppVersion-$Env.tar.gz"
$out = Join-Path $installerDir $outName
if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Force }
$parent = Split-Path $StagingDir -Parent
$base = Split-Path $StagingDir -Leaf
Push-Location $parent
try {
    Write-Step "打包 -> $out"
    & tar -czf $out --transform "s,^$base,frampp," --owner=0 --group=0 --numeric-owner $base
    if ($LASTEXITCODE -ne 0) { throw "tar 打包失败" }
} finally {
    Pop-Location
}

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $out).Hash.ToLower()
Write-Step "产物: $out ($([math]::Round((Get-Item -LiteralPath $out).Length / 1MB, 1)) MB)"
Write-Output "SHA256  $hash  $outName"
Write-Output "BUILD_OK"
