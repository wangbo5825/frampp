<#
.SYNOPSIS
    FRAMPP Docker 镜像构建：基于已生成的 Linux .run 安装包构建单镜像。

.DESCRIPTION
    复用 build-linux-package.ps1 的产物（不重复编译组件）。镜像首启动时才运行
    init.sh，避免把随机密钥烘焙进镜像。构建后可用 docker run / docker compose 启动。

.EXAMPLE
    pwsh -File installer/scripts/build-linux-package.ps1 -Env linux-x86_64
    pwsh -File installer/scripts/build-docker.ps1
#>
[CmdletBinding()]
param(
    [string]$Root,
    [string]$AppVersion,
    [string]$Channel = "8.5",
    [string]$Env = "linux-x86_64",
    [string]$ImageName = "frampp",
    [string]$Registry = "",
    [switch]$Push,
    [switch]$TagLatest
)

if (-not $Root) { $Root = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path }
if (-not $AppVersion) { $AppVersion = (Get-Content -LiteralPath (Join-Path $Root "VERSION") -Raw).Trim() }

$pkg = Join-Path $Root "dist/installer/frampp-setup-$Channel-$AppVersion-$Env.run"
if (-not (Test-Path -LiteralPath $pkg)) {
    throw "缺少 Linux 安装包: $pkg（请先运行 build-linux-package.ps1 -Env linux-x86_64）"
}

$relativePkg = "dist/installer/" + (Split-Path -Leaf $pkg)
$tag = if ($Registry) { "$Registry/$ImageName`:$AppVersion" } else { "$ImageName`:$AppVersion" }

$args = @("build", "-t", $tag, "--build-arg", "FRAMPP_PACKAGE=$relativePkg", $Root)
& docker @args
if ($LASTEXITCODE -ne 0) { throw "docker build 失败 (exit $LASTEXITCODE)" }

if ($TagLatest) {
    $latest = if ($Registry) { "$Registry/$ImageName`:latest" } else { "$ImageName`:latest" }
    & docker tag $tag $latest
}

if ($Push) {
    & docker push $tag
    if ($LASTEXITCODE -ne 0) { throw "docker push 失败 (exit $LASTEXITCODE)" }
    if ($TagLatest) {
        & docker push $latest
        if ($LASTEXITCODE -ne 0) { throw "docker push latest 失败 (exit $LASTEXITCODE)" }
    }
}

Write-Output "DOCKER_BUILD_OK $tag"
