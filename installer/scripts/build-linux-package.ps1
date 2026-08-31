<#
.SYNOPSIS
    FRAMPP Linux 安装包构建：准备干净的暂存目录（dist/staging-linux），
    下载/编译组件并打包为 XAMPP 风格单文件 .run（自解压安装器）。

.DESCRIPTION
    - 组件矩阵：installer/config/versions-linux-x86_64.json（哈希锁定）
    - Redis 由官方源码静态编译（installer/scripts/linux/build-redis.sh）
    - MySQL 8.0 由官方 glibc 2.17 minimal 包裁剪（installer/scripts/linux/trim-mysql.sh）
    - 产物：dist/installer/frampp-<version>-linux-x86_64.run（v0.7.0 起简化命名）
    - .run = 自解压脚本头 + tar.gz 载荷；运行后自动校验、解压并执行 bin/frampp init
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
    $config.components.mysql.cacheFile,
    $config.components.redis.cacheFile,
    $config.components.composer.cacheFile,
    $config.components.adminer.cacheFile,
    $config.components.python.cacheFile
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
$moduleDir = Join-Path $StagingDir "modules"
$layout = @(
    (Join-Path $moduleDir "frankenphp"),
    (Join-Path $moduleDir "mysql"),
    (Join-Path $moduleDir "redis"),
    (Join-Path $moduleDir "python"),
    (Join-Path $moduleDir "composer"),
    (Join-Path $moduleDir "agent"),
    (Join-Path $moduleDir "control-panel"),
    (Join-Path $moduleDir "control-panel/web"),
    (Join-Path $moduleDir "templates"),
    (Join-Path $StagingDir "bin"),
    (Join-Path $StagingDir "etc"),
    (Join-Path $StagingDir "var"),
    (Join-Path $StagingDir "htdocs"),
    (Join-Path $StagingDir "logs"),
    (Join-Path $StagingDir "share/templates"),
    (Join-Path $StagingDir "docs")
)
foreach ($d in $layout) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
Write-Step "暂存目录就绪: $StagingDir"

# 3. 组件
# FrankenPHP：定制源码构建（精简扩展 + Souin + UPX + musl 完全静态）
# 在 Alpine 容器内 musl 静态构建，产物无 glibc 依赖，兼容任意发行版。
$fpBinDir = Join-Path $ToolsDir "frankenphp-linux-x86_64"
$fpMarker = Join-Path $fpBinDir ".built-$($config.components.frankenphp.version)-musl-accessfilter1.2.0"
if (-not (Test-Path -LiteralPath (Join-Path $fpBinDir "frankenphp")) -or -not (Test-Path -LiteralPath $fpMarker)) {
    Write-Step "编译 FrankenPHP $($config.components.frankenphp.version)（定制: 精简扩展 + Souin + UPX）"
    & bash (Join-Path $PSScriptRoot "linux/build-frankenphp-musl.sh") `
        (Join-Path $CacheDir $config.components.frankenphp.cacheFile) `
        $fpBinDir `
        $config.components.frankenphp.version
    if ($LASTEXITCODE -ne 0) { throw "FrankenPHP 构建失败 (exit $LASTEXITCODE)" }
    New-Item -ItemType File -Path $fpMarker -Force | Out-Null
} else {
    Write-Step "复用已编译 FrankenPHP（$fpBinDir）"
}
Copy-Item -LiteralPath (Join-Path $fpBinDir "frankenphp") -Destination (Join-Path $moduleDir "frankenphp/frankenphp")
& chmod +x (Join-Path $moduleDir "frankenphp/frankenphp")

# MySQL 8.0：官方 glibc 2.17 minimal tarball 裁剪（CentOS 7 兼容，自带 OpenSSL）
$mysqlBinDir = Join-Path $ToolsDir "mysql-linux-x86_64"
$mysqlMarker = Join-Path $mysqlBinDir ".built-$($config.components.mysql.version)-glibc2.17"
if (-not (Test-Path -LiteralPath (Join-Path $mysqlBinDir "bin/mysqld")) -or -not (Test-Path -LiteralPath $mysqlMarker)) {
    Write-Step "裁剪 MySQL $($config.components.mysql.version)（官方 glibc 2.17 minimal）"
    & bash (Join-Path $PSScriptRoot "linux/trim-mysql.sh") `
        (Join-Path $CacheDir $config.components.mysql.cacheFile) `
        $mysqlBinDir `
        $config.components.mysql.version
    if ($LASTEXITCODE -ne 0) { throw "MySQL 裁剪失败 (exit $LASTEXITCODE)" }
    New-Item -ItemType File -Path $mysqlMarker -Force | Out-Null
} else {
    Write-Step "复用已裁剪 MySQL（$mysqlBinDir）"
}
Copy-Item -Path (Join-Path $mysqlBinDir "*") -Destination (Join-Path $moduleDir "mysql") -Recurse -Force
Get-ChildItem -LiteralPath (Join-Path $moduleDir "mysql/bin") -File | ForEach-Object { & chmod +x $_.FullName }
Get-ChildItem -LiteralPath (Join-Path $moduleDir "mysql/lib/plugin") -File -ErrorAction SilentlyContinue | ForEach-Object { & chmod +x $_.FullName }

# Redis：官方源码静态编译（复用 dist/tools 下的构建产物，避免重复编译）
$redisBinDir = Join-Path $ToolsDir "redis-linux-x86_64"
$redisMarker = Join-Path $redisBinDir ".built-$($config.components.redis.version)"
if (-not (Test-Path -LiteralPath (Join-Path $redisBinDir "redis-server")) -or -not (Test-Path -LiteralPath $redisMarker)) {
    Write-Step "编译 Redis $($config.components.redis.version)（静态）"
    & bash (Join-Path $PSScriptRoot "linux/build-redis.sh") `
        (Join-Path $CacheDir $config.components.redis.cacheFile) `
        $redisBinDir `
        $config.components.redis.version
    if ($LASTEXITCODE -ne 0) { throw "Redis 构建失败 (exit $LASTEXITCODE)" }
    New-Item -ItemType File -Path $redisMarker -Force | Out-Null
} else {
    Write-Step "复用已编译 Redis（$redisBinDir）"
}
foreach ($redisBin in @("redis-server", "redis-cli")) {
    Copy-Item -LiteralPath (Join-Path $redisBinDir $redisBin) -Destination (Join-Path $moduleDir "redis")
    & chmod +x (Join-Path (Join-Path $moduleDir "redis") $redisBin)
}

# Python：独立精简运行时
$pyBinDir = Join-Path $ToolsDir "python-linux-x86_64"
$pyMarker = Join-Path $pyBinDir ".built-$($config.components.python.version)"
if (-not (Test-Path -LiteralPath (Join-Path $pyBinDir "bin/python3")) -or -not (Test-Path -LiteralPath $pyMarker)) {
    Write-Step "准备 Python $($config.components.python.version)（精简独立运行时）"
    & bash (Join-Path $PSScriptRoot "linux/build-python.sh") `
        (Join-Path $CacheDir $config.components.python.cacheFile) `
        $pyBinDir `
        $config.components.python.version
    if ($LASTEXITCODE -ne 0) { throw "Python 构建失败 (exit $LASTEXITCODE)" }
    New-Item -ItemType File -Path $pyMarker -Force | Out-Null
} else {
    Write-Step "复用已准备 Python（$pyBinDir）"
}
$stagingPython = Join-Path $moduleDir "python"
& bash -c "set -e; mkdir -p '$stagingPython'; cp -a '$pyBinDir'/.' '$stagingPython'/" 2>$null
if ($LASTEXITCODE -ne 0) {
    # 兜底：某些环境无法调用 bash 时退回 Copy-Item（但不保证软链接保留）
    Copy-Item -Path (Join-Path $pyBinDir "*") -Destination $stagingPython -Recurse -Force
}
Get-ChildItem -LiteralPath (Join-Path $stagingPython "bin") -File | ForEach-Object { & chmod +x $_.FullName }

# Composer / Adminer
Write-Step "安装 Composer / Adminer"
Copy-Item -LiteralPath (Join-Path $CacheDir $config.components.composer.cacheFile) -Destination (Join-Path $moduleDir "composer/composer.phar")
Copy-Item -LiteralPath (Join-Path $CacheDir $config.components.adminer.cacheFile) -Destination (Join-Path $StagingDir "htdocs/adminer.php")

# 4. 仓库内容（控制面板 / Agent / 模板 / 文档 / 运行时脚本）
Write-Step "复制控制面板 / Agent / 模板 / 文档"
Copy-Item -Path (Join-Path $Root "control-panel/web/*") -Destination (Join-Path $moduleDir "control-panel/web") -Recurse -Force
Copy-Item -LiteralPath (Join-Path $Root "control-panel/src") -Destination (Join-Path $moduleDir "control-panel") -Recurse -Force
Copy-Item -LiteralPath (Join-Path $Root "control-panel/bin") -Destination (Join-Path $moduleDir "control-panel") -Recurse -Force
Copy-Item -LiteralPath (Join-Path $Root "agent") -Destination (Join-Path $moduleDir "agent") -Recurse -Force
# 运行时脚本 → bin/（构建脚本不进安装包；安装包内不再包含 installer/）
foreach ($runtimeScript in @("init.sh", "docker-entrypoint.sh", "docker-healthcheck.sh")) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "linux/$runtimeScript") -Destination (Join-Path $StagingDir "bin")
}
# 版本清单与配置模板 → share/ 与 share/templates/
Copy-Item -LiteralPath (Join-Path $Root "installer/config/versions-linux-x86_64.json") -Destination (Join-Path $StagingDir "share/versions-linux-x86_64.json")
Copy-Item -Path (Join-Path $Root "installer/templates/*") -Destination (Join-Path $StagingDir "share/templates") -Recurse -Force
Copy-Item -LiteralPath (Join-Path $Root "installer/runtime/frampp.service.template") -Destination (Join-Path $StagingDir "share/templates/frampp.service.template")
Copy-Item -Path (Join-Path $Root "docs/user/*") -Destination (Join-Path $StagingDir "docs") -Recurse -Force
Copy-Item -LiteralPath (Join-Path $Root "installer/templates/project-minimal") -Destination (Join-Path $moduleDir "templates/project-minimal") -Recurse -Force
Copy-Item -LiteralPath (Join-Path $Root "README.md") -Destination (Join-Path $StagingDir "README.md")
Copy-Item -LiteralPath (Join-Path $Root "LICENSE") -Destination (Join-Path $StagingDir "LICENSE")
Copy-Item -LiteralPath (Join-Path $Root "VERSION") -Destination (Join-Path $StagingDir "VERSION")

# 默认站点首页
Copy-Item -LiteralPath (Join-Path $Root "installer/templates/htdocs/index.php") -Destination (Join-Path $StagingDir "htdocs/index.php")

# bin 命令包装（Linux）
Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot "../runtime/bin") -File |
    Copy-Item -Destination (Join-Path $StagingDir "bin") -Force
foreach ($bin in (Get-ChildItem -LiteralPath (Join-Path $StagingDir "bin") -File)) {
    & chmod +x $bin.FullName
}

# 根目录总控命令（LAMPP 风格）：frampp -> bin/frampp（相对符号链接，可随目录整体移动）
$masterLink = Join-Path $StagingDir "frampp"
if (Test-Path -LiteralPath $masterLink) { Remove-Item -LiteralPath $masterLink -Force }
New-Item -ItemType SymbolicLink -Path $masterLink -Target "bin/frampp" | Out-Null
Write-Step "根目录总控命令 / root master command: frampp -> bin/frampp"

# 5. 打包为 XAMPP 风格单文件 .run（自解压安装器）
#    Payload = 暂存目录内容（无顶层目录）的 tar.gz；Header = 自解压脚本。
#    Package as an XAMPP-style single-file .run (self-extracting installer).
#    v0.7.0 起命名简化为 frampp-<version>-<env>.run（通道并入 Release note）
$outName = "frampp-$AppVersion-$Env.run"
$out = Join-Path $installerDir $outName
$payload = Join-Path $installerDir "frampp-linux-payload.tar.gz"
if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Force }
if (Test-Path -LiteralPath $payload) { Remove-Item -LiteralPath $payload -Force }

Push-Location $StagingDir
try {
    Write-Step "打包载荷 -> $payload"
    & tar -czf $payload --owner=0 --group=0 --numeric-owner .
    if ($LASTEXITCODE -ne 0) { throw "tar 载荷打包失败" }
} finally {
    Pop-Location
}

# 生成自解压头（先替换固定字段，再按最终字节长度计算载荷偏移）
$template = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "linux/frampp-installer.sh")
$template = $template -replace "`r`n", "`n"
$template = $template.Replace("__APP_VERSION__", $AppVersion).Replace("__CHANNEL__", $Channel)
$headerUtf8 = New-Object System.Text.UTF8Encoding($false)
$headerBytes = $headerUtf8.GetBytes($template)
$payloadOffset = $headerBytes.Length + 1
$payloadHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $payload).Hash.ToLower()

$template = $template.Replace(
    'PAYLOAD_OFFSET="0000000000000000"',
    'PAYLOAD_OFFSET="' + $payloadOffset.ToString().PadLeft(16, '0') + '"'
)
$template = $template.Replace(
    'PAYLOAD_SHA256="0000000000000000000000000000000000000000000000000000000000000000"',
    'PAYLOAD_SHA256="' + $payloadHash + '"'
)
$headerBytes = $headerUtf8.GetBytes($template)

Write-Step "组装自解压安装器 -> $out"
$fs = [System.IO.File]::Open($out, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
try {
    $fs.Write($headerBytes, 0, $headerBytes.Length)
    $payloadStream = [System.IO.File]::OpenRead($payload)
    try {
        $payloadStream.CopyTo($fs)
    } finally {
        $payloadStream.Dispose()
    }
} finally {
    $fs.Dispose()
}
& chmod +x $out
Remove-Item -LiteralPath $payload -Force

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $out).Hash.ToLower()
Write-Step "产物: $out ($([math]::Round((Get-Item -LiteralPath $out).Length / 1MB, 1)) MB)"
Write-Output "SHA256  $hash  $outName"
Write-Output "BUILD_OK"
