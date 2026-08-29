<#
.SYNOPSIS
    FRAMPP 安装器构建：准备干净的分发暂存目录（dist/staging），下载 Inno Setup 便携版并编译 setup.iss。

.DESCRIPTION
    - 暂存目录不包含开发机生成的数据（var/、logs/、etc/ 配置、测试项目），
      安装后由 init.ps1 在目标机生成。
    - Inno Setup 下载到 dist/tools/inno（已存在则跳过）。
#>
[CmdletBinding()]
param(
    [string]$Root,
    [string]$CacheDir,
    [string]$StagingDir,
    [string]$ToolsDir,
    [string]$InnoVersion = "7.1.0-x64",
    [string]$AppVersion = "0.1.0",
    [string]$Channel = "8.5",
    [string]$Env = "windows-x64"
)

if (-not $Root) { $Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path }
if (-not $CacheDir) { $CacheDir = Join-Path $Root "dist\binaries" }
if (-not $StagingDir) { $StagingDir = Join-Path $Root "dist\staging" }
if (-not $ToolsDir) { $ToolsDir = Join-Path $Root "dist\tools" }

$ErrorActionPreference = "Stop"

function Write-Step([string]$Message) { Write-Host "==> $Message" -ForegroundColor Cyan }

# 1. 组件缓存与暂存（fresh init，跳过数据库初始化）
if (-not (Test-Path -LiteralPath (Join-Path $CacheDir "frankenphp-windows-x86_64.zip"))) {
    Write-Step "组件缓存缺失，先运行 download.ps1"
    & (Join-Path $PSScriptRoot "download.ps1") -Root $Root -CacheDir $CacheDir
}
$fpMarker = Get-ChildItem -LiteralPath (Join-Path $StagingDir "modules\frankenphp") -Filter ".extracted-*" -Force -ErrorAction SilentlyContinue
if (-not $fpMarker) {
    if (Test-Path -LiteralPath $StagingDir) {
        Remove-Item -LiteralPath $StagingDir -Recurse -Force
    }
    Write-Step "准备分发暂存目录（fresh init, SkipDbInit）"
    & (Join-Path $PSScriptRoot "init.ps1") -Root $Root -CacheDir $CacheDir -RuntimeDir $StagingDir -SkipDbInit
}

# 2. 清理开发机产物，仅保留可分发内容
Write-Step "清理暂存目录中的开发机数据"
foreach ($p in @(
    (Join-Path $StagingDir "var"),
    (Join-Path $StagingDir "logs")
)) {
    if (Test-Path -LiteralPath $p) {
        Get-ChildItem -LiteralPath $p -Force | Remove-Item -Recurse -Force
    }
}
foreach ($f in @(
    (Join-Path $StagingDir "etc\Caddyfile"),
    (Join-Path $StagingDir "etc\redis.conf"),
    (Join-Path $StagingDir "etc\php.ini"),
    (Join-Path $StagingDir "etc\access.json"),
    (Join-Path $StagingDir "etc\access-filter.rules"),
    (Join-Path $StagingDir "etc\access-filter.caddy")
)) {
    if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force }
}
Get-ChildItem -LiteralPath (Join-Path $StagingDir "htdocs") -Force |
    Where-Object { $_.Name -notin @("index.php", "adminer.php") } |
    Remove-Item -Recurse -Force

# 3. Inno Setup（便携安装到 dist/tools/inno）
New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null
$iscc = Join-Path $ToolsDir "inno\ISCC.exe"
if (-not (Test-Path -LiteralPath $iscc)) {
    $installer = Join-Path $ToolsDir "innosetup-$InnoVersion.exe"
    if (-not (Test-Path -LiteralPath $installer)) {
        $url = "https://github.com/jrsoftware/issrc/releases/download/is-7_1_0/innosetup-$InnoVersion.exe"
        Write-Step "下载 Inno Setup $InnoVersion ..."
        curl.exe -fL --retry 3 --retry-all-errors --retry-delay 5 -sS $url -o $installer
        if ($LASTEXITCODE -ne 0) { throw "Inno Setup 下载失败" }
    }
    Write-Step "安装 Inno Setup 到 $ToolsDir\inno"
    & $installer /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /DIR="$ToolsDir\inno"
    if ($LASTEXITCODE -ne 0) { throw "Inno Setup 安装失败（可能需要管理员权限）" }
    # 安装器可能在子进程中收尾，等待 ISCC.exe 出现
    for ($i = 0; $i -lt 60 -and -not (Test-Path -LiteralPath $iscc); $i++) {
        Start-Sleep -Seconds 1
    }
    if (-not (Test-Path -LiteralPath $iscc)) { throw "Inno Setup 安装后未找到 ISCC.exe" }
}

# 4. 编译（产物命名：frampp-setup-<channel>-<version>-<env>.exe）
#    ISPP 定义经 include 文件传入，避免 /D 命令行值（含连字符）被当作表达式解析
$issFile = Join-Path $Root "installer\setup.iss"
Write-Step "编译安装器 -> dist/installer/frampp-setup-$Channel-$AppVersion-$Env.exe"
$definesFile = Join-Path $StagingDir "release-defines.iss"
$defines = "#define MyAppVersion `"$AppVersion`"`r`n" +
           "#define Channel `"$Channel`"`r`n" +
           "#define TargetEnv `"$Env`"`r`n"
[System.IO.File]::WriteAllText($definesFile, $defines, [System.Text.Encoding]::ASCII)
& $iscc $issFile
if ($LASTEXITCODE -ne 0) { throw "ISCC 编译失败（exit=$LASTEXITCODE）" }
Get-ChildItem -LiteralPath (Join-Path $Root "dist\installer") | Select-Object Name,Length,LastWriteTime
Write-Output "BUILD_OK"
