<#
.SYNOPSIS
    FRAMPP M1 冒烟测试：版本清单、哈希缓存、配置模板、控制面板运行时。
    在 CI（ubuntu + windows）与本机均可执行。
#>
[CmdletBinding()]
param(
    [string]$Root
)

$ErrorActionPreference = "Stop"
if (-not $Root) { $Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path }
$failures = @()

function Assert-True([bool]$Condition, [string]$Message) {
    if ($Condition) {
        Write-Host "PASS: $Message"
    } else {
        Write-Host "FAIL: $Message" -ForegroundColor Red
        $script:failures += $Message
    }
}

# 1. versions.json 结构
$versionsPath = Join-Path $Root "installer\config\versions.json"
$config = Get-Content -Raw -LiteralPath $versionsPath | ConvertFrom-Json
Assert-True ($config.schema -eq 1) "versions.json schema = 1"
Assert-True ([string]$config.channel -ne "") "versions.json declares channel"

$required = @("name", "version", "url", "sha256", "cacheFile", "kind", "installDir")
foreach ($prop in $config.components.PSObject.Properties) {
    foreach ($field in $required) {
        Assert-True ($null -ne $prop.Value.$field -and [string]$prop.Value.$field -ne "") "component '$($prop.Name)' has field '$field'"
    }
    $sha = [string]$prop.Value.sha256
    if ($sha -ne "PENDING") {
        Assert-True ($sha -match '^[0-9A-Fa-f]{64}$') "component '$($prop.Name)' sha256 is 64 hex chars"
    }
    Assert-True ($prop.Value.kind -in @("zip", "phar")) "component '$($prop.Name)' kind valid"
}
Assert-True (($config.components.PSObject.Properties.Name | Sort-Object) -contains "frankenphp" -and
             ($config.components.PSObject.Properties.Name | Sort-Object) -contains "mariadb" -and
             ($config.components.PSObject.Properties.Name | Sort-Object) -contains "redis" -and
             ($config.components.PSObject.Properties.Name | Sort-Object) -contains "composer") "all four core components declared"

# 2. 缓存哈希（本地已下载时校验）
$cacheDir = Join-Path $Root "dist\binaries"
if (Test-Path -LiteralPath $cacheDir) {
    foreach ($prop in $config.components.PSObject.Properties) {
        $c = $prop.Value
        if ($c.sha256 -eq "PENDING") { continue }
        $file = Join-Path $cacheDir $c.cacheFile
        if (Test-Path -LiteralPath $file) {
            $actual = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
            Assert-True ($actual -eq $c.sha256) "cached $($c.cacheFile) sha256 matches"
        }
    }
}

# 3. 配置模板
$tpl = Join-Path $Root "installer\templates"
$phpIni = Get-Content -Raw -LiteralPath (Join-Path $tpl "php.ini.template")
Assert-True ($phpIni -match 'apc\.enable_cli\s*=\s*1') "php.ini template enables APCu CLI"
Assert-True ($phpIni -match 'extension\s*=\s*apcu') "php.ini template loads apcu extension"

$redisConf = Get-Content -Raw -LiteralPath (Join-Path $tpl "redis.conf.template")
Assert-True ($redisConf -match 'bind 127\.0\.0\.1') "redis.conf binds loopback only"
Assert-True ($redisConf -match 'requirepass \{\{REDIS_PASSWORD\}\}') "redis.conf has password placeholder"

$caddy = Get-Content -Raw -LiteralPath (Join-Path $tpl "Caddyfile.template")
Assert-True ($caddy -match 'php_server') "Caddyfile uses php_server"
Assert-True ($caddy -match '127\.0\.0\.1:8081') "Caddyfile exposes panel on 8081"

# 5. 安装器资产
$setupIss = Get-Content -Raw -LiteralPath (Join-Path $Root "installer\setup.iss")
Assert-True ($setupIss -match '\[UninstallRun\]') "setup.iss stops services on uninstall"
Assert-True ($setupIss -match 'init\.ps1') "setup.iss runs init.ps1 on install"
Assert-True ($setupIss -match 'OutputBaseFilename=frampp-setup-\{#Channel\}-{#MyAppVersion\}-{#Env\}') "setup.iss names artifacts by channel/version/env"
Assert-True (Test-Path -LiteralPath (Join-Path $Root "installer\scripts\build-installer.ps1")) "build-installer.ps1 exists"
Assert-True (Test-Path -LiteralPath (Join-Path $Root "installer\scripts\release.ps1")) "release.ps1 exists"
Assert-True (Test-Path -LiteralPath (Join-Path $Root "installer\config\channels.json")) "channels.json exists"
Assert-True (Test-Path -LiteralPath (Join-Path $Root "docs\upgrade.md")) "docs/upgrade.md exists"
Assert-True (Test-Path -LiteralPath (Join-Path $Root "docs\releases.md")) "docs/releases.md exists"

# 4. PHP lint（控制面板 + Agent）与 CLI 冒烟（需要 php；CI 中由 setup-php 提供）
$php = Get-Command php -ErrorAction SilentlyContinue
if ($php) {
    $phpFiles = Get-ChildItem -Path (Join-Path $Root "control-panel"), (Join-Path $Root "agent") -Recurse -Filter *.php
    foreach ($f in $phpFiles) {
        & php -l $f.FullName | Out-Null
        Assert-True ($LASTEXITCODE -eq 0) "php -l $($f.Name)"
    }

    # 构造一个假的运行时目录验证 CLI status 输出
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("frampp-test-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path (Join-Path $tmp "data"), (Join-Path $tmp "logs") | Out-Null
    @{ created_at = (Get-Date -Format o); root = $tmp; ports = @{ http = 8080; panel = 8081; mysql = 3306; redis = 6379 } } |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $tmp "data\runtime.json") -Encoding UTF8
    @{ panel_token = "test-token"; mariadb_root_password = "x"; redis_password = "y" } |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $tmp "data\secrets.json") -Encoding UTF8

    $cli = Join-Path $Root "control-panel\bin\frampp"
    $out = & php $cli status --json --home $tmp 2>&1 | Out-String
    Assert-True ($LASTEXITCODE -eq 0) "frampp status exits 0"
    $json = $out | ConvertFrom-Json
    Assert-True ($null -ne $json.frankenphp -and $null -ne $json.mariadb -and $null -ne $json.redis) "frampp status lists three services"
    Assert-True (-not $json.frankenphp.running) "frankenphp reports stopped in empty runtime"

    # new-project minimal（模板回退到仓库 installer/templates/project-minimal）
    $npOut = (& php $cli new-project demo minimal --json --home $tmp 2>&1 | Out-String)
    Assert-True ($LASTEXITCODE -eq 0) "frampp new-project exits 0"
    $np = $npOut | ConvertFrom-Json
    Assert-True ($np.name -eq "demo") "new-project returns project name"
    Assert-True (Test-Path -LiteralPath (Join-Path $tmp "htdocs\demo\public\index.php")) "new-project creates public/index.php"

    Remove-Item -LiteralPath $tmp -Recurse -Force

    # MCP 协议冒烟：initialize / tools/list / 只读 SQL 拦截（无需运行时即可验证）
    $mcp = Join-Path $Root "agent\bin\frampp-mcp"
    $messages = @(
        '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","clientInfo":{"name":"ci"},"capabilities":{}}}',
        '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}',
        '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"mysql.query","arguments":{"sql":"DROP TABLE x"}}}'
    ) -join "`n"
    $mcpOut = $messages | & php $mcp 2>&1
    $mcpJson = $mcpOut | Where-Object { $_ -match '^\{"jsonrpc"' } | ForEach-Object { $_ | ConvertFrom-Json }
    $initResp = $mcpJson | Where-Object { $_.id -eq 1 } | Select-Object -First 1
    $listResp = $mcpJson | Where-Object { $_.id -eq 2 } | Select-Object -First 1
    $badResp = $mcpJson | Where-Object { $_.id -eq 3 } | Select-Object -First 1
    Assert-True ($null -ne $initResp -and $initResp.result.serverInfo.name -eq "frampp-agent") "MCP initialize returns frampp-agent"
    Assert-True ($null -ne $listResp -and @($listResp.result.tools).Count -ge 10) "MCP tools/list returns >=10 tools"
    Assert-True ($null -ne $badResp -and $badResp.result.isError -eq $true) "MCP rejects non-readonly SQL"
}

if ($failures.Count -gt 0) {
    Write-Host "`n$($failures.Count) test(s) failed" -ForegroundColor Red
    exit 1
}
Write-Host "`nAll tests passed" -ForegroundColor Green
