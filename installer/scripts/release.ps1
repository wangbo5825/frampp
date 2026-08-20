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
    [string]$Version,
    [string[]]$Channels,
    [string]$Env = "windows-x64",
    [switch]$Publish
)

$ErrorActionPreference = "Stop"
if (-not $Root) { $Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path }
if (-not $Version) { $Version = (Get-Content -LiteralPath (Join-Path $Root "VERSION") -Raw).Trim() }

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
    if ($Env -eq "windows-x64") {
        & (Join-Path $PSScriptRoot "build-installer.ps1") -Root $Root -AppVersion $Version -Channel $ch -Env $Env
        $artifact = Join-Path $installerDir "frampp-setup-$ch-$Version-$Env.exe"
    } elseif ($Env -eq "linux-x86_64") {
        & (Join-Path $PSScriptRoot "build-linux-package.ps1") -Root $Root -AppVersion $Version -Channel $ch -Env $Env
        $artifact = Join-Path $installerDir "frampp-setup-$ch-$Version-$Env.run"
    } else {
        throw "未支持的环境: $Env（支持 windows-x64 / linux-x86_64）"
    }
    if (-not (Test-Path -LiteralPath $artifact)) {
        throw "构建产物缺失: $artifact"
    }
    $artifacts += $artifact
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
    $gh = (Get-Command gh -ErrorAction SilentlyContinue).Source
    if (-not $gh) {
        $gh = "C:\Users\silen\AppData\Local\Programs\gh\bin\gh.exe"
    }
    if (-not (Test-Path -LiteralPath $gh)) { throw "未找到 gh CLI: $gh" }
    $tag = "v$Version"
    $notes = @"
FRAMPP $Version

## 安装包 / Installers

- 通道 / Channel：$($Channels -join ', ')（环境 / Env：$Env）
- 校验 / Verify：请核对安装包哈希 / check the hashes in SHA256SUMS.txt
$(if ($Env -eq "linux-x86_64") {
    "- Linux：\`frampp-setup-$($Channels -join ',')-$Version-linux-x86_64.run\`（XAMPP 风格单文件自解压安装器 / XAMPP-style single-file self-extracting installer）"
} else {
    "- Windows：\`frampp-setup-$($Channels -join ',')-$Version-windows-x64.exe\`（Inno Setup 一键安装 / one-click installer）"
})

## 说明 / Notes

- 一键安装，安装时自动初始化（MariaDB 数据目录、随机密钥、配置）并启动三件套 / One-click install with automatic init (MariaDB datadir, random secrets, configs) and service start
- 卸载自动停止服务并清理数据 / Uninstall stops services and cleans data
- 组件版本见 / Component versions: installer/config/versions*.json
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
