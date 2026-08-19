<#
.SYNOPSIS
    FRAMPP 组件下载器：按 versions.json 下载第三方二进制到缓存目录并校验 SHA-256。

.DESCRIPTION
    - 已缓存且哈希匹配的文件直接跳过（可断点续传）。
    - 哈希不匹配时删除并重新下载一次，仍失败则报错退出。
    - 输出每行一条 "OK <name> <sha256>"，便于 CI 解析。

.PARAMETER Root
    仓库根目录（默认取脚本所在目录的上一级）。

.PARAMETER ConfigPath
    versions.json 路径。

.PARAMETER CacheDir
    缓存目录（默认 <Root>/dist/binaries）。

.PARAMETER Force
    忽略缓存强制重新下载。
#>
[CmdletBinding()]
param(
    [string]$Root,
    [string]$ConfigPath,
    [string]$CacheDir,
    [switch]$Force
)

if (-not $Root) { $Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path }
if (-not $ConfigPath) { $ConfigPath = Join-Path $Root "installer\config\versions.json" }
if (-not $CacheDir) { $CacheDir = Join-Path $Root "dist\binaries" }

$ErrorActionPreference = "Stop"

function Get-Sha256([string]$Path) {
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
}

function Get-CurlCommand {
    if ($IsWindows) { return "curl.exe" }
    return "curl"
}

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "versions.json not found: $ConfigPath"
}
New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null

$config = Get-Content -Raw -LiteralPath $ConfigPath | ConvertFrom-Json
if ($config.schema -ne 1) {
    throw "Unsupported versions.json schema: $($config.schema)"
}

$curl = Get-CurlCommand
$failed = @()

foreach ($prop in $config.components.PSObject.Properties) {
    $name = $prop.Name
    $c = $prop.Value
    $target = Join-Path $CacheDir $c.cacheFile

    if (-not $c.url -or -not $c.cacheFile) {
        throw "Component '$name' is missing url/cacheFile"
    }

    $downloaded = $false
    if ((Test-Path -LiteralPath $target) -and -not $Force) {
        $actual = Get-Sha256 $target
        if ($actual -eq $c.sha256) {
            Write-Output "CACHED $name"
            continue
        }
        if ($c.sha256 -ne "PENDING") {
            Write-Warning "Hash mismatch for $name (expected $($c.sha256), got $actual); redownloading"
        }
    }

    # 下载：断点续传 + 自动重试（github.com 在部分网络环境不稳定）
    for ($attempt = 1; $attempt -le 4; $attempt++) {
        Write-Host "Downloading $name ... (attempt $attempt)"
        & $curl -fL --retry 3 --retry-all-errors --retry-delay 5 -C - -sS $c.url -o $target
        if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $target) -and (Get-Item -LiteralPath $target).Length -gt 0) {
            $downloaded = $true
            break
        }
        Start-Sleep -Seconds 8
    }

    if (-not $downloaded) {
        $failed += $name
        Write-Error "Failed to download $name"
        continue
    }

    if ($c.sha256 -ne "PENDING") {
        $actual = Get-Sha256 $target
        if ($actual -ne $c.sha256) {
            Remove-Item -LiteralPath $target -Force
            $failed += $name
            Write-Error "SHA-256 verification failed for ${name}: expected $($c.sha256), got $actual"
            continue
        }
    }

    Write-Output "OK $name $(Get-Sha256 $target)"
}

if ($failed.Count -gt 0) {
    throw "Download failed for: $($failed -join ', ')"
}
Write-Output "ALL_OK"
