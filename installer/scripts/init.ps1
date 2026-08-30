<#
.SYNOPSIS
    FRAMPP 运行时初始化：创建安装布局、解压组件、生成配置与密钥、初始化 MariaDB。

.DESCRIPTION
    - 幂等：已存在的组件/配置/密钥不会重复生成。
    - 依赖 download.ps1 已把组件缓存到 dist/binaries（未缓存时自动调用下载）。
    - 产物全部位于 <RuntimeDir>（默认 dist/runtime），不写系统目录。

.PARAMETER Root
    仓库根目录。

.PARAMETER CacheDir
    组件缓存目录。

.PARAMETER RuntimeDir
    运行时目录（安装后布局的根）。

.PARAMETER SkipDbInit
    跳过 MariaDB 数据目录初始化（用于测试）。
#>
[CmdletBinding()]
param(
    [string]$Root,
    [string]$CacheDir,
    [string]$RuntimeDir,
    [switch]$SkipDbInit
)

if (-not $Root) { $Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path }
if (-not $CacheDir) { $CacheDir = Join-Path $Root "dist\binaries" }
if (-not $RuntimeDir) { $RuntimeDir = Join-Path $Root "dist\runtime" }

$ErrorActionPreference = "Stop"

function Write-Step([string]$Message) {
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function New-Secret([int]$Length = 24) {
    $bytes = New-Object byte[] $Length
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    return ($bytes | ForEach-Object { $_.ToString("x2") }) -join ""
}

function Invoke-Native {
    # 原生程序（mysql.exe 等）的 stderr 在 PS 5.1 下会被当作错误记录；
    # EAP=Stop 会误终止脚本，这里临时降级并返回退出码。
    param([scriptblock]$ScriptBlock)
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & $ScriptBlock
        return $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $prevEap
    }
}

function Write-JsonFile([string]$Path, $Object) {
    # 必须无 BOM：PowerShell 5.1 的 Set-Content -Encoding UTF8 会写 BOM，
    # 导致 PHP json_decode 报 "Syntax error"
    $json = $Object | ConvertTo-Json
    [System.IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding($false)))
}

function Convert-PathToForward([string]$Path) {
    return $Path.Replace("\", "/")
}

function Test-PortOpen([int]$Port, [int]$TimeoutMs = 500) {
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $task = $client.ConnectAsync("127.0.0.1", $Port)
        if (-not $task.Wait($TimeoutMs)) { $client.Close(); return $false }
        $ok = $client.Connected
        $client.Close()
        return $ok
    } catch {
        return $false
    }
}

function Move-ExtractedIfNested([string]$TargetDir) {
    # 部分 zip 顶层只有一个目录；把它提升一层，保持布局扁平
    $files = Get-ChildItem -LiteralPath $TargetDir -Force
    if ($files.Count -eq 1 -and $files[0].PSIsContainer) {
        $nested = $files[0].FullName
        Get-ChildItem -LiteralPath $nested -Force | Move-Item -Destination $TargetDir -Force
        Remove-Item -LiteralPath $nested -Force -Recurse
    }
}

$config = Get-Content -Raw -LiteralPath (Join-Path $Root "installer\config\versions.json") | ConvertFrom-Json

# 1. 布局
$dirs = @(
    (Join-Path $RuntimeDir "modules\frankenphp"),
    (Join-Path $RuntimeDir "modules\mariadb"),
    (Join-Path $RuntimeDir "modules\redis"),
    (Join-Path $RuntimeDir "modules\composer"),
    (Join-Path $RuntimeDir "modules\control-panel\web"),
    (Join-Path $RuntimeDir "modules\agent"),
    (Join-Path $RuntimeDir "modules\templates"),
    (Join-Path $RuntimeDir "bin"),
    (Join-Path $RuntimeDir "etc"),
    (Join-Path $RuntimeDir "etc\caddy.d"),
    (Join-Path $RuntimeDir "htdocs"),
    (Join-Path $RuntimeDir "logs"),
    (Join-Path $RuntimeDir "var\mariadb"),
    (Join-Path $RuntimeDir "var\redis")
)
foreach ($d in $dirs) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
}
Write-Step "Runtime layout ready: $RuntimeDir"

# 2. 确保组件就绪：已解压/已安装的跳过；缺失时才需要缓存（调用下载器补齐）
foreach ($prop in $config.components.PSObject.Properties) {
    $name = $prop.Name
    $c = $prop.Value
    $cacheFile = Join-Path $CacheDir $c.cacheFile
    $needsCache = $false
    if ($c.kind -eq "zip") {
        $targetDir = Join-Path $RuntimeDir $c.installDir
        $marker = Join-Path $targetDir ".extracted-$($c.version)"
        if (-not (Test-Path -LiteralPath $marker)) {
            $needsCache = $true
        }
    } else {
        # phar / 单文件组件：检查安装目标
        if ($name -eq "composer") {
            $dest = Join-Path $RuntimeDir "bin\composer.phar"
        } elseif ($name -eq "adminer") {
            $dest = Join-Path $RuntimeDir "htdocs\adminer.php"
        } else {
            $dest = $null
        }
        if ($dest -ne $null -and -not (Test-Path -LiteralPath $dest)) {
            $needsCache = $true
        }
    }
    if ($needsCache -and -not (Test-Path -LiteralPath $cacheFile)) {
        Write-Step "Missing cache file for $($prop.Name), running download.ps1"
        & (Join-Path $PSScriptRoot "download.ps1") -Root $Root -CacheDir $CacheDir
        break
    }
}

# 3. 解压 zip 组件
foreach ($prop in $config.components.PSObject.Properties) {
    $name = $prop.Name
    $c = $prop.Value
    if ($c.kind -ne "zip") { continue }
    $targetDir = Join-Path $RuntimeDir $c.installDir
    $marker = Join-Path $targetDir ".extracted-$($c.version)"
    if (Test-Path -LiteralPath $marker) {
        Write-Step "Already extracted: $name"
        continue
    }
    Write-Step "Extracting $name ..."
    $zip = Join-Path $CacheDir $c.cacheFile
    Expand-Archive -LiteralPath $zip -DestinationPath $targetDir -Force
    Move-ExtractedIfNested $targetDir
    New-Item -ItemType File -Path $marker -Force | Out-Null
}

# 4. Composer
$composerTarget = Join-Path $RuntimeDir "modules\composer\composer.phar"
if (-not (Test-Path -LiteralPath $composerTarget)) {
    Copy-Item -LiteralPath (Join-Path $CacheDir $config.components.composer.cacheFile) -Destination $composerTarget
    Write-Step "Composer installed: $composerTarget"
}

# Adminer（单文件，放入 htdocs 由 FrankenPHP 直接提供）
$adminerTarget = Join-Path $RuntimeDir "htdocs\adminer.php"
if (-not (Test-Path -LiteralPath $adminerTarget)) {
    Copy-Item -LiteralPath (Join-Path $CacheDir $config.components.adminer.cacheFile) -Destination $adminerTarget
    Write-Step "Adminer installed: $adminerTarget"
}

# 项目模板（控制面板 new-project 使用）
$templatesCopy = Join-Path $RuntimeDir "modules\templates\project-minimal"
if (-not (Test-Path -LiteralPath $templatesCopy)) {
    $srcTpl = Join-Path $Root "installer\templates\project-minimal"
    if (Test-Path -LiteralPath $srcTpl) {
        New-Item -ItemType Directory -Force -Path (Join-Path $RuntimeDir "modules\templates") | Out-Null
        Copy-Item -LiteralPath $srcTpl -Destination $templatesCopy -Recurse
        Write-Step "Project templates installed"
    }
}

# 5. 密钥（仅在首次生成）
$secretsFile = Join-Path $RuntimeDir "var\secrets.json"
if (-not (Test-Path -LiteralPath $secretsFile)) {
    $secrets = [ordered]@{
        mariadb_root_password   = New-Secret
        mariadb_readonly_password = New-Secret
        redis_password          = New-Secret
        panel_token             = New-Secret 16
    }
    Write-JsonFile $secretsFile $secrets
    Write-Step "Secrets generated: $secretsFile"
} else {
    $secrets = Get-Content -Raw -LiteralPath $secretsFile | ConvertFrom-Json
    Write-JsonFile $secretsFile $secrets   # 规范化：去掉旧版可能存在的 BOM
    Write-Step "Secrets loaded (existing)"
}

# 6. 配置文件
function Fill-Template([string]$TemplatePath, [hashtable]$Values, [string]$OutPath) {
    # 显式 UTF-8 读取：PS 5.1 的 Get-Content 对无 BOM 文件默认按 ANSI 解码，中文会乱码
    $content = [System.IO.File]::ReadAllText($TemplatePath, [System.Text.Encoding]::UTF8)
    foreach ($k in $Values.Keys) {
        $content = $content.Replace("{{$k}}", [string]$Values[$k])
    }
    # 无 BOM 写入（PS 5.1 Set-Content 会加 BOM，Caddy / Redis 无法解析）
    [System.IO.File]::WriteAllText($OutPath, $content, (New-Object System.Text.UTF8Encoding($false)))
}

$templatesDir = Join-Path $Root "installer\templates"

$phpIni = Join-Path $RuntimeDir "etc\php.ini"
if (-not (Test-Path -LiteralPath $phpIni)) {
    Copy-Item -LiteralPath (Join-Path $templatesDir "php.ini.template") -Destination $phpIni
}

$redisConf = Join-Path $RuntimeDir "etc\redis.conf"
Fill-Template (Join-Path $templatesDir "redis.conf.template") @{
    REDIS_PASSWORD = $secrets.redis_password
    DATA_DIR       = Convert-PathToForward (Join-Path $RuntimeDir "var\redis")
    LOG_FILE       = Convert-PathToForward (Join-Path $RuntimeDir "logs\redis.log")
    UNIX_SOCKET_CONF = "# unix socket disabled (tcp mode; Windows)"
    REDIS_PORT     = 6379
} $redisConf

# IP 访问控制配置（Windows 官方 FrankenPHP 暂未内置 caddy-access-filter，默认关闭）
$accessConfigPath = Join-Path $RuntimeDir "etc\access.json"
if (-not (Test-Path -LiteralPath $accessConfigPath)) {
    Write-JsonFile $accessConfigPath @{
        enabled        = $false
        supported      = $false
        default_action = "allow"
        geoip_db       = ""
        geoip_format   = ""
    }
}
$accessRulesPath = Join-Path $RuntimeDir "etc\access-filter.rules"
if (-not (Test-Path -LiteralPath $accessRulesPath)) {
    [System.IO.File]::WriteAllText(
        $accessRulesPath,
        "# FRAMPP IP 访问规则 / IP access rules`n# 格式: <IP|CIDR|code:XX> <allow|block>`n",
        (New-Object System.Text.UTF8Encoding($false))
    )
}
$accessCaddyPath = Join-Path $RuntimeDir "etc\access-filter.caddy"
[System.IO.File]::WriteAllText($accessCaddyPath, "# access-filter disabled`n", (New-Object System.Text.UTF8Encoding($false)))

$caddyD = Join-Path $RuntimeDir "etc\caddy.d"
$caddyDReadme = Join-Path $caddyD "00-default.caddy"
if (-not (Test-Path -LiteralPath $caddyDReadme)) {
    [System.IO.File]::WriteAllText(
        $caddyDReadme,
        "# 在此目录放置额外的站点配置（*.caddy）`n# Place additional site configs (*.caddy) in this directory.`n",
        (New-Object System.Text.UTF8Encoding($false))
    )
}

$caddyFile = Join-Path $RuntimeDir "etc\Caddyfile"
Fill-Template (Join-Path $templatesDir "Caddyfile.template") @{
    HTDOCS        = Convert-PathToForward (Join-Path $RuntimeDir "htdocs")
    PANEL_ROOT    = Convert-PathToForward (Join-Path $RuntimeDir "modules\control-panel\web")
    LOGS_DIR      = Convert-PathToForward (Join-Path $RuntimeDir "logs")
    ACCESS_IMPORT = "# access-filter disabled"
    CADDY_D       = Convert-PathToForward $caddyD
    ADMIN_ADDR    = "127.0.0.1:2019"
} $caddyFile

$htdocsIndex = Join-Path $RuntimeDir "htdocs\index.php"
if (-not (Test-Path -LiteralPath $htdocsIndex)) {
    Copy-Item -LiteralPath (Join-Path $templatesDir "htdocs\index.php") -Destination $htdocsIndex
}

# 复制控制面板到运行时（安装布局下 Root == RuntimeDir 时跳过，避免自我复制）
$panelSrc = Join-Path $Root "control-panel\web"
$panelDestDir = Join-Path $RuntimeDir "modules\control-panel\web"
$srcResolved = (Resolve-Path -LiteralPath $panelSrc -ErrorAction SilentlyContinue).Path
$dstResolved = (Resolve-Path -LiteralPath $panelDestDir -ErrorAction SilentlyContinue).Path
if ($srcResolved -and $dstResolved -and $srcResolved -eq $dstResolved) {
    Write-Step "Control panel already in place (installed layout)"
} elseif (Test-Path -LiteralPath (Join-Path $panelSrc "index.php")) {
    New-Item -ItemType Directory -Force -Path $panelDestDir | Out-Null
    Copy-Item -Path (Join-Path $panelSrc "*") -Destination $panelDestDir -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $Root "control-panel\src") -Destination (Join-Path $RuntimeDir "modules\control-panel\") -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $Root "control-panel\bin") -Destination (Join-Path $RuntimeDir "modules\control-panel\") -Recurse -Force
    Write-Step "Control panel copied to runtime"
}

# 9. bin 命令包装（Windows .cmd）
$cmdSrc = Join-Path $Root "installer\runtime\bin\windows"
if (-not (Test-Path -LiteralPath $cmdSrc)) {
    $cmdSrc = Join-Path $RuntimeDir "installer\runtime\bin\windows"
}
if (Test-Path -LiteralPath $cmdSrc) {
    Copy-Item -Path (Join-Path $cmdSrc "*.cmd") -Destination (Join-Path $RuntimeDir "bin") -Force
    Write-Step "Command wrappers installed: bin/*.cmd"
}

# 7. MariaDB 数据目录初始化（install-db 直接设置 root 密码；随后临时启动创建只读账号）
$dbInitialized = $false
$ports = @{ http = 8080; panel = 8081; mysql = 3306; redis = 6379 }
$mariadbBin = Join-Path $RuntimeDir "modules\mariadb\bin"
if (-not $SkipDbInit -and (Test-Path -LiteralPath (Join-Path $mariadbBin "mariadb-install-db.exe"))) {
$datadir = Join-Path $RuntimeDir "var\mariadb"
    $initialized = Test-Path -LiteralPath (Join-Path $datadir "mysql")
    if (-not $initialized) {
        Write-Step "Initializing MariaDB data directory ..."
        $installDbLog = Join-Path $RuntimeDir "logs\mariadb-install-db.log"
        Push-Location $mariadbBin
        # 密码不在 install-db 阶段设置（避免其 --password 行为差异），改为启动后由 SQL 显式设置
        $code = Invoke-Native { & (Join-Path $mariadbBin "mariadb-install-db.exe") --datadir=$datadir *> $installDbLog }
        Pop-Location
        if ($code -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $datadir "mysql"))) {
            Write-Warning "mariadb-install-db failed (exit=$code), see $installDbLog"
        } else {
            $initialized = $true
        }
    }

    if ($initialized) {
        # 临时启动 -> 创建只读账号 -> 优雅关闭
        # 注意：mariadbd 用 --log-error 自管日志，避免 Start-Process 重定向句柄在 PS 5.1 下的兼容问题
        $serverErr = Join-Path $RuntimeDir "logs\mariadb.err.log"
        $pidFile = Join-Path $RuntimeDir "var\mariadb.pid"
        $mysql = Join-Path $mariadbBin "mysql.exe"
        $mysqladmin = Join-Path $mariadbBin "mysqladmin.exe"
        $rootPw = [string]$secrets.mariadb_root_password
        $roPw = [string]$secrets.mariadb_readonly_password
        $sql = "ALTER USER 'root'@'localhost' IDENTIFIED BY '$rootPw'; " +
               "CREATE USER IF NOT EXISTS 'frampp_ro'@'127.0.0.1' IDENTIFIED BY '$roPw'; " +
               "GRANT SELECT, SHOW VIEW ON *.* TO 'frampp_ro'@'127.0.0.1'; FLUSH PRIVILEGES;"
        $bootstrapLog = Join-Path $RuntimeDir "logs\mariadb-init-user.log"

        $proc = Start-Process -FilePath (Join-Path $mariadbBin "mariadbd.exe") `
            -ArgumentList @(
                "--datadir=$datadir",
                "--port=$($ports.mysql)",
                "--bind-address=127.0.0.1",
                "--log-error=$serverErr"
            ) `
            -WorkingDirectory $RuntimeDir `
            -WindowStyle Hidden -PassThru
        $proc.Id | Out-File -Encoding ascii $pidFile

        $portReady = $false
        for ($i = 0; $i -lt 60 -and -not $portReady; $i++) {
            Start-Sleep -Milliseconds 500
            try {
                $client = New-Object System.Net.Sockets.TcpClient
                $task = $client.ConnectAsync("127.0.0.1", $ports.mysql)
                if ($task.Wait(300) -and $client.Connected) { $portReady = $true }
                $client.Close()
            } catch { }
        }

        if ($portReady) {
            # 尝试无密码（全新数据目录）；失败则回退到密码 / skip-grant-tables
            $bootstrapOk = ((Invoke-Native { & $mysql --connect-timeout=5 -h 127.0.0.1 -P $($ports.mysql) -u root -e $sql *> $bootstrapLog }) -eq 0)
            if (-not $bootstrapOk) {
                $bootstrapOk = ((Invoke-Native { & $mysql --connect-timeout=5 -h 127.0.0.1 -P $($ports.mysql) -u root -p"$rootPw" -e $sql *>> $bootstrapLog }) -eq 0)
            }
            if (-not $bootstrapOk) {
                Write-Warning "常规方式设置密码失败，改用 skip-grant-tables 重置（仅本机临时操作）"
                if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force }
                Start-Sleep -Milliseconds 500
                $proc = Start-Process -FilePath (Join-Path $mariadbBin "mariadbd.exe") `
                    -ArgumentList @(
                        "--datadir=$datadir",
                        "--port=$($ports.mysql)",
                        "--bind-address=127.0.0.1",
                        "--skip-grant-tables",
                        "--log-error=$serverErr"
                    ) `
                    -WorkingDirectory $RuntimeDir `
                    -WindowStyle Hidden -PassThru
                Start-Sleep -Seconds 3
                $bootstrapOk = ((Invoke-Native { & $mysql --connect-timeout=5 -h 127.0.0.1 -P $($ports.mysql) -u root -e "FLUSH PRIVILEGES; $sql" *>> $bootstrapLog }) -eq 0)
            }

            if ($bootstrapOk) {
                # 用新密码验证后优雅关闭
                $verifyOk = ((Invoke-Native { & $mysql --connect-timeout=5 -h 127.0.0.1 -P $($ports.mysql) -u root -p"$rootPw" -e "SELECT 'init-ok' AS result;" *>> $bootstrapLog }) -eq 0)
                Invoke-Native { & $mysqladmin --connect-timeout=5 -h 127.0.0.1 -P $($ports.mysql) -u root -p"$rootPw" shutdown *>> $bootstrapLog } | Out-Null
                $dbInitialized = $verifyOk
                if (-not $verifyOk) {
                    Write-Warning "MariaDB 密码验证失败，数据目录可能损坏，请删除后重新 init"
                    if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force }
                }
            } else {
                Write-Warning "MariaDB 账号初始化失败，见 $bootstrapLog"
                if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force }
            }
        } else {
            Write-Warning "MariaDB 未能监听端口，跳过只读账号创建；日志见 $serverErr"
            if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force }
        }
        if (Test-Path -LiteralPath $pidFile) { Remove-Item -LiteralPath $pidFile -Force }
    }
}

# 8. 运行时清单
$runtime = [ordered]@{
    created_at  = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssK")
    root        = $RuntimeDir
    ports       = $ports
    components  = @{
        frankenphp = $config.components.frankenphp.version
        mariadb    = $config.components.mariadb.version
        redis      = $config.components.redis.version
        composer   = $config.components.composer.version
    }
    db_initialized = $dbInitialized
}
Write-JsonFile (Join-Path $RuntimeDir "var\runtime.json") $runtime

Write-Step "Done. Runtime ready at $RuntimeDir"
Write-Output "DB_INITIALIZED=$dbInitialized"
