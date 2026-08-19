<#
.SYNOPSIS
    FRAMPP Release 发布：按通道（PHP 版本线）与环境构建一键安装包、生成哈希清单，
    可选直接发布到 GitHub Releases。

.EXAMPLE
    pwsh installer/scripts/release.ps1 -Version 0.1.0 -Channel 8.5 -Env windows-x64
    pwsh installer/scripts/release.ps1 -Version 0.1.0 -Publish
#>
[CmdletBinding()]
param(
    [string]$Root,
    [string]$Version = "0.1.0",
    [string[]]$Channels,
    [string]$Env = "windows-x64",
    [switch]$Publish
)

$ErrorActionPreference = "Stop"
if (-not $Root) { $Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path }

function Write-Step([string]$Message) { Write-Host "==> $Message" -ForegroundColor Cyan }

# 1. 通道校验
$channelsFile = Join-Path $Root "installer\config\channels.json"
$channelsCfg = Get-Content -Raw -LiteralPath $channelsFile | ConvertFrom-Json
if (-not $Channels -or $Channels.Count -eq 0) {
    $Channels = @($channelsCfg.channels | Where-Object { $_.default } | ForEach-Object { $_.id })
}
$known = @($channelsCfg.channels | ForEach-Object { $_.id })
foreach ($ch in $Channels) {
    if ($ch -notin $known) {
        throw "未知通道: $ch（可用：$($known -join ', ')）"
    }
    if ($Env -notin @($channelsCfg.channels | Where-Object { $_.id -eq $ch } | ForEach-Object { $_.envs })) {
        throw "通道 $ch 不支持环境 $Env"
    }
}

$installerDir = Join-Path $Root "dist\installer"
New-Item -ItemType Directory -Force -Path $installerDir | Out-Null

# 2. 逐个通道构建
$artifacts = @()
foreach ($ch in $Channels) {
    Write-Step "构建通道 $ch ($Env) ..."
    & (Join-Path $PSScriptRoot "build-installer.ps1") -Root $Root -AppVersion $Version -Channel $ch -Env $Env
    $exe = Join-Path $installerDir "frampp-setup-$ch-$Version-$Env.exe"
    if (-not (Test-Path -LiteralPath $exe)) {
        throw "构建产物缺失: $exe"
    }
    $artifacts += $exe
}

# 3. 哈希清单
$sumsFile = Join-Path $installerDir "SHA256SUMS.txt"
$sumsLines = foreach ($a in $artifacts) {
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $a).Hash.ToLower()
    "$hash  $(Split-Path $a -Leaf)"
}
$sumsLines | Set-Content -LiteralPath $sumsFile -Encoding ascii
Write-Step "哈希清单: $sumsFile"

# 4. 可选：发布 GitHub Release
if ($Publish) {
    $gh = "C:\Users\silen\AppData\Local\Programs\gh\bin\gh.exe"
    if (-not (Test-Path -LiteralPath $gh)) { throw "未找到 gh CLI: $gh" }
    $tag = "v$Version"
    $notes = @"
FRAMPP $Version

## 安装包

- 通道：$($Channels -join ', ')（环境：$Env）
- 校验：安装后请核对 SHA256SUMS.txt

## 说明

- 一键安装（Inno Setup），安装时自动初始化（MariaDB 数据目录、随机密钥、配置）并启动三件套
- 卸载自动停止服务并清理数据
- 组件版本见 installer/config/versions.json
"@
    Write-Step "发布 GitHub Release $tag ..."
    $existing = & $gh release view $tag --json tagName 2>$null
    if ($existing) {
        Write-Step "Release $tag 已存在，跳过创建（仅上传/覆盖资产由 CI 流程负责）"
    } else {
        $assetArgs = @()
        foreach ($a in $artifacts) { $assetArgs += $a }
        & $gh release create $tag --title "FRAMPP $Version" --notes $notes $assetArgs
        if ($LASTEXITCODE -ne 0) { throw "gh release create 失败" }
    }
    & $gh release upload $tag $sumsFile --clobber
}

Write-Output "RELEASE_OK"
