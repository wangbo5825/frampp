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

function Write-JsonNoBom([string]$Path, $Object) {
    [System.IO.File]::WriteAllText(
        $Path,
        ($Object | ConvertTo-Json),
        (New-Object System.Text.UTF8Encoding($false))
    )
}

function Test-VersionsFile([string]$Path, [string]$Platform) {
    $label = $Platform
    Assert-True (Test-Path -LiteralPath $Path) "versions file exists: $label"
    if (-not (Test-Path -LiteralPath $Path)) { return }

    $config = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
    Assert-True ($config.schema -eq 1) "$label schema = 1"
    Assert-True ($config.platform -eq $Platform) "$label declares platform"
    Assert-True ([string]$config.channel -ne "") "$label declares channel"

    $required = @("name", "version", "url", "sha256", "cacheFile", "kind", "installDir")
    foreach ($prop in $config.components.PSObject.Properties) {
        foreach ($field in $required) {
            Assert-True ($null -ne $prop.Value.$field -and [string]$prop.Value.$field -ne "") "$label component '$($prop.Name)' has field '$field'"
        }
        $sha = [string]$prop.Value.sha256
        if ($sha -ne "PENDING") {
            Assert-True ($sha -match '^[0-9A-Fa-f]{64}$') "$label component '$($prop.Name)' sha256 is 64 hex chars"
        }
        Assert-True ($prop.Value.kind -in @("zip", "phar", "binary", "tar.gz", "src")) "$label component '$($prop.Name)' kind valid"
    }
    $names = @($config.components.PSObject.Properties.Name | Sort-Object)
    Assert-True ($names -contains "frankenphp" -and $names -contains "mariadb" -and
                 $names -contains "redis" -and $names -contains "composer") "$label declares four core components"

    # 本地已缓存时校验哈希
    $cacheDir = Join-Path $Root "dist/binaries"
    if (Test-Path -LiteralPath $cacheDir) {
        foreach ($prop in $config.components.PSObject.Properties) {
            $c = $prop.Value
            if ($c.sha256 -eq "PENDING") { continue }
            $file = Join-Path $cacheDir $c.cacheFile
            if (Test-Path -LiteralPath $file) {
                $actual = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
                Assert-True ($actual -eq $c.sha256) "$label cached $($c.cacheFile) sha256 matches"
            }
        }
    }
}

# 1. 版本清单（Windows + Linux）
Test-VersionsFile (Join-Path $Root "installer/config/versions.json") "windows-x64"
Test-VersionsFile (Join-Path $Root "installer/config/versions-linux-x86_64.json") "linux-x86_64"

# 2. 通道注册
$channels = Get-Content -Raw -LiteralPath (Join-Path $Root "installer/config/channels.json") | ConvertFrom-Json
$envs = @($channels.channels | Where-Object { $_.id -eq "8.5" } | ForEach-Object { $_.envs })
Assert-True ($envs -contains "windows-x64") "channel 8.5 supports windows-x64"
Assert-True ($envs -contains "linux-x86_64") "channel 8.5 supports linux-x86_64"

# 3. 配置模板
$tpl = Join-Path $Root "installer/templates"
$phpIni = Get-Content -Raw -LiteralPath (Join-Path $tpl "php.ini.template")
Assert-True ($phpIni -match 'apc\.enable_cli\s*=\s*1') "php.ini template enables APCu CLI"
Assert-True ($phpIni -match 'extension\s*=\s*apcu') "php.ini template loads apcu extension"

$phpIniLinux = Get-Content -Raw -LiteralPath (Join-Path $tpl "php.ini.linux.template")
Assert-True ($phpIniLinux -match 'apc\.enable_cli\s*=\s*1') "php.ini.linux template enables APCu CLI"
Assert-True ($phpIniLinux -notmatch '(?m)^\s*extension\s*=') "php.ini.linux template has no dynamic extension lines"

$redisConf = Get-Content -Raw -LiteralPath (Join-Path $tpl "redis.conf.template")
Assert-True ($redisConf -match 'bind 127\.0\.0\.1') "redis.conf binds loopback only"
Assert-True ($redisConf -match 'requirepass \{\{REDIS_PASSWORD\}\}') "redis.conf has password placeholder"

$caddy = Get-Content -Raw -LiteralPath (Join-Path $tpl "Caddyfile.template")
Assert-True ($caddy -match 'try_files \{path\} \{path\}/index\.php index\.php') "Caddyfile has try_files index rewrite"
Assert-True ($caddy -match '\n\s*php\s*\n') "Caddyfile uses php handler"
Assert-True ($caddy -match '\n\s*file_server\s*\n') "Caddyfile uses file_server"
Assert-True ($caddy -match '127\.0\.0\.1:8081') "Caddyfile exposes panel on 8081"
Assert-True ($caddy -match '\{\{ACCESS_IMPORT\}\}') "Caddyfile template has access-filter import placeholder"
Assert-True ($caddy -match '\{\{CADDY_D\}\}.*\.caddy') "Caddyfile template imports etc/caddy.d/*.caddy"

# 4. 安装器资产（Windows + Linux）
$setupIss = Get-Content -Raw -LiteralPath (Join-Path $Root "installer/setup.iss")
Assert-True ($setupIss -match '\[UninstallRun\]') "setup.iss stops services on uninstall"
Assert-True ($setupIss -match 'init\.ps1') "setup.iss runs init.ps1 on install"
Assert-True ($setupIss -match 'OutputBaseFilename=frampp-setup-\{#Channel\}-{#MyAppVersion\}-{#TargetEnv\}') "setup.iss names artifacts by channel/version/env"
Assert-True (Test-Path -LiteralPath (Join-Path $Root "installer/scripts/build-installer.ps1")) "build-installer.ps1 exists"
Assert-True (Test-Path -LiteralPath (Join-Path $Root "installer/scripts/build-linux-package.ps1")) "build-linux-package.ps1 exists"
Assert-True (Test-Path -LiteralPath (Join-Path $Root "installer/scripts/release.ps1")) "release.ps1 exists"
Assert-True (Test-Path -LiteralPath (Join-Path $Root "Dockerfile")) "Dockerfile exists"
Assert-True (Test-Path -LiteralPath (Join-Path $Root "docker-compose.yml")) "docker-compose.yml exists"
Assert-True (Test-Path -LiteralPath (Join-Path $Root "installer/scripts/build-docker.ps1")) "build-docker.ps1 exists"
foreach ($linuxScript in @(
    "installer/scripts/linux/init.sh",
    "installer/scripts/linux/build-redis.sh",
    "installer/scripts/linux/docker-entrypoint.sh",
    "installer/scripts/linux/docker-healthcheck.sh",
    "installer/runtime/bin/frampp",
    "installer/runtime/bin/php",
    "installer/runtime/bin/composer",
    "installer/runtime/bin/python",
    "installer/runtime/bin/pip",
    "installer/runtime/bin/env",
    "installer/runtime/bin/uninstall",
    "installer/runtime/bin/framppd",
    "installer/runtime/bin/install-systemd",
    "installer/runtime/frampp.service.template"
)) {
    Assert-True (Test-Path -LiteralPath (Join-Path $Root $linuxScript)) "$linuxScript exists"
}
$framppWrapper = Get-Content -Raw -LiteralPath (Join-Path $Root "installer/runtime/bin/frampp")
Assert-True ($framppWrapper -match '\binit\b') "bin/frampp wrapper supports init"
$runHeader = Get-Content -Raw -LiteralPath (Join-Path $Root "installer/scripts/linux/frampp-installer.sh")
Assert-True ($runHeader -match '\-\-extract-only') "frampp-installer.sh supports --extract-only"
$buildLinux = Get-Content -Raw -LiteralPath (Join-Path $Root "installer/scripts/build-linux-package.ps1")
Assert-True ($buildLinux -match 'installer/scripts/linux') "build-linux-package.ps1 stages runtime scripts under installer/scripts/linux"
Assert-True ($buildLinux -match '\(Join-Path \$StagingDir "installer/scripts/linux"\)') "build-linux-package.ps1 layout pre-creates installer/scripts/linux dir"
Assert-True (Test-Path -LiteralPath (Join-Path $Root "installer/config/channels.json")) "channels.json exists"
Assert-True (Test-Path -LiteralPath (Join-Path $Root "docs/releases.md")) "docs/releases.md exists"
Assert-True (Test-Path -LiteralPath (Join-Path $Root "docs/user/README.md")) "docs/user/README.md exists"
Assert-True (Test-Path -LiteralPath (Join-Path $Root "docs/user/upgrade.md")) "docs/user/upgrade.md exists"
Assert-True (Test-Path -LiteralPath (Join-Path $Root "docs/user/docker.md")) "docs/user/docker.md exists"
Assert-True (Test-Path -LiteralPath (Join-Path $Root "docs/blueprint.md")) "docs/blueprint.md exists"
Assert-True ($setupIss -match 'docs\\user') "setup.iss ships docs/user only"
Assert-True ($buildLinux -match 'docs/user') "build-linux-package.ps1 ships docs/user only"
$versionFile = Get-Content -Raw -LiteralPath (Join-Path $Root "VERSION")
Assert-True ($versionFile -match '^\d+\.\d+\.\d+\s*$') "VERSION file is a semver"

# 5. PHP lint（控制面板 + Agent）与 CLI 冒烟（需要 php；CI 中由 setup-php 提供）
$php = Get-Command php -ErrorAction SilentlyContinue
if ($php) {
    $phpFiles = Get-ChildItem -Path (Join-Path $Root "control-panel"), (Join-Path $Root "agent") -Recurse -Filter *.php
    foreach ($f in $phpFiles) {
        & php -l $f.FullName | Out-Null
        Assert-True ($LASTEXITCODE -eq 0) "php -l $($f.Name)"
    }

    # 构造一个假的运行时目录验证 CLI status 输出
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("frampp-test-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path (Join-Path $tmp "var"), (Join-Path $tmp "logs"), (Join-Path $tmp "etc"), (Join-Path $tmp "installer\templates") | Out-Null
    Copy-Item -LiteralPath (Join-Path $Root "installer\templates\Caddyfile.template") -Destination (Join-Path $tmp "installer\templates\Caddyfile.template")
    Copy-Item -LiteralPath (Join-Path $Root "installer\templates\redis.conf.template") -Destination (Join-Path $tmp "installer\templates\redis.conf.template")
    Copy-Item -LiteralPath (Join-Path $Root "installer\templates\php.ini.linux.template") -Destination (Join-Path $tmp "installer\templates\php.ini.linux.template")
    Write-JsonNoBom (Join-Path $tmp "var/runtime.json") @{
        created_at = (Get-Date -Format o)
        root = $tmp
        ports = @{ http = 8080; panel = 8081; mysql = 3306; redis = 6379 }
    }
    Write-JsonNoBom (Join-Path $tmp "var/secrets.json") @{
        panel_token = "test-token"
        mariadb_root_password = "x"
        redis_password = "y"
    }

    $cli = Join-Path $Root "control-panel/bin/frampp"
    $out = & php $cli status --json --home $tmp 2>&1 | Out-String
    Assert-True ($LASTEXITCODE -eq 0) "frampp status exits 0"
    $json = $out | ConvertFrom-Json
    Assert-True ($null -ne $json.frankenphp -and $null -ne $json.mariadb -and $null -ne $json.redis) "frampp status lists three services"
    Assert-True (-not $json.frankenphp.running) "frankenphp reports stopped in empty runtime"

    # 孤儿检测：daemon 启动者已退出但服务进程存活 => orphan=true（只读状态，不清理）
    Write-JsonNoBom (Join-Path $tmp "var/redis.pid") @{
        pid = $PID
        launcher_pid = 999999
        launcher_type = "daemon"
        started_at = (Get-Date -Format o)
    }
    $stOut = (& php $cli status --json --home $tmp 2>&1 | Out-String)
    $stJson = $stOut | ConvertFrom-Json
    Assert-True ($stJson.redis.running) "orphan detection: service process alive"
    Assert-True ($stJson.redis.orphan) "orphan detection: dead daemon launcher -> orphan"
    Remove-Item -LiteralPath (Join-Path $tmp "var/redis.pid") -Force

    # cleanup：进程已不存在的 PID 文件（JSON 新格式 + 纯整数旧格式）应被清理且不杀进程
    Write-JsonNoBom (Join-Path $tmp "var/frankenphp.pid") @{
        pid = 999998
        launcher_pid = 999999
        launcher_type = "daemon"
        started_at = (Get-Date -Format o)
    }
    [System.IO.File]::WriteAllText((Join-Path $tmp "var/mariadb.pid"), "123456", (New-Object System.Text.UTF8Encoding($false)))
    $clOut = (& php $cli cleanup --json --home $tmp 2>&1 | Out-String)
    Assert-True ($LASTEXITCODE -eq 0) "frampp cleanup exits 0"
    $clJson = $clOut | ConvertFrom-Json
    Assert-True ($clJson.skipped -contains "frankenphp") "cleanup removes stale JSON pid file"
    Assert-True ($clJson.skipped -contains "mariadb") "cleanup parses legacy integer pid file"
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $tmp "var/frankenphp.pid"))) "cleanup deleted JSON pid file"
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $tmp "var/mariadb.pid"))) "cleanup deleted legacy pid file"

    # 传输模式：默认 tcp；Windows 拒绝切换到 unix socket，Linux 完整验证切换
    $modeOut = (& php $cli mode status --json --home $tmp 2>&1 | Out-String)
    $modeJson = $modeOut | ConvertFrom-Json
    Assert-True ($modeJson.mode -eq "tcp") "frampp mode defaults to tcp"
    Assert-True ($modeJson.admin -eq "http://127.0.0.1:2019") "frampp mode tcp admin address"
    if ($IsWindows) {
        & php $cli mode sock --json --home $tmp 2>&1 | Out-Null
        Assert-True ($LASTEXITCODE -ne 0) "frampp mode sock rejected on Windows"
    } else {
        $sockOut = (& php $cli mode sock --json --home $tmp 2>&1 | Out-String)
        Assert-True ($LASTEXITCODE -eq 0) "frampp mode sock succeeds on Linux"
        $sockJson = $sockOut | ConvertFrom-Json
        Assert-True ($sockJson.mode -eq "sock") "frampp mode switched to sock"
        $rt = Get-Content -Raw -LiteralPath (Join-Path $tmp "var/runtime.json") | ConvertFrom-Json
        Assert-True ($rt.mode -eq "sock") "runtime.json mode updated"
        $caddy = Get-Content -Raw -LiteralPath (Join-Path $tmp "etc/Caddyfile")
        Assert-True ($caddy -match 'admin unix//') "Caddyfile admin uses unix socket"
        $redisConf = Get-Content -Raw -LiteralPath (Join-Path $tmp "etc/redis.conf")
        Assert-True ($redisConf -match 'unixsocket .*redis\.sock') "redis.conf enables unix socket"
        $phpIni = Get-Content -Raw -LiteralPath (Join-Path $tmp "etc/php.ini")
        Assert-True ($phpIni -match 'mysql\.sock') "php.ini points at mysql socket"
        $tcpOut = (& php $cli mode tcp --json --home $tmp 2>&1 | Out-String)
        Assert-True ($LASTEXITCODE -eq 0) "frampp mode tcp succeeds"
        $caddy2 = Get-Content -Raw -LiteralPath (Join-Path $tmp "etc/Caddyfile")
        Assert-True ($caddy2 -match 'admin 127\.0\.0\.1:2019') "Caddyfile admin back to tcp"
    }

    # new-project minimal（模板回退到仓库 installer/templates/project-minimal）
    $npOut = (& php $cli new-project demo minimal --json --home $tmp 2>&1 | Out-String)
    Assert-True ($LASTEXITCODE -eq 0) "frampp new-project exits 0"
    $np = $npOut | ConvertFrom-Json
    Assert-True ($np.name -eq "demo") "new-project returns project name"
    Assert-True (Test-Path -LiteralPath (Join-Path $tmp "htdocs/demo/public/index.php")) "new-project creates public/index.php"

    Remove-Item -LiteralPath $tmp -Recurse -Force

    # MCP 协议冒烟：initialize / tools/list / 只读 SQL 拦截（无需运行时即可验证）
    $mcp = Join-Path $Root "agent/bin/frampp-mcp"
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
