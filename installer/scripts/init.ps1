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
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path,
    [string]$CacheDir = (Join-Path $Root "dist\binaries"),
    [string]$RuntimeDir = (Join-Path $Root "dist\runtime"),
    [switch]$SkipDbInit
)

$ErrorActionPreference = "Stop"

function Write-Step([string]$Message) {
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function New-Secret([int]$Length = 24) {
    $bytes = New-Object byte[] $Length
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    return ($bytes | ForEach-Object { $_.ToString("x2") }) -join ""
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
    (Join-Path $RuntimeDir "frankenphp"),
    (Join-Path $RuntimeDir "mariadb"),
    (Join-Path $RuntimeDir "redis"),
    (Join-Path $RuntimeDir "bin"),
    (Join-Path $RuntimeDir "htdocs"),
    (Join-Path $RuntimeDir "logs"),
    (Join-Path $RuntimeDir "data\mariadb"),
    (Join-Path $RuntimeDir "data\redis"),
    (Join-Path $RuntimeDir "control-panel\web")
)
foreach ($d in $dirs) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
}
Write-Step "Runtime layout ready: $RuntimeDir"

# 2. 确保组件缓存齐全（缺失时调用下载器）
foreach ($prop in $config.components.PSObject.Properties) {
    $c = $prop.Value
    $cacheFile = Join-Path $CacheDir $c.cacheFile
    if (-not (Test-Path -LiteralPath $cacheFile)) {
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
$composerTarget = Join-Path $RuntimeDir "bin\composer.phar"
if (-not (Test-Path -LiteralPath $composerTarget)) {
    Copy-Item -LiteralPath (Join-Path $CacheDir $config.components.composer.cacheFile) -Destination $composerTarget
    Write-Step "Composer installed: $composerTarget"
}

# 5. 密钥（仅在首次生成）
$secretsFile = Join-Path $RuntimeDir "data\secrets.json"
if (-not (Test-Path -LiteralPath $secretsFile)) {
    $secrets = [ordered]@{
        mariadb_root_password   = New-Secret
        mariadb_readonly_password = New-Secret
        redis_password          = New-Secret
        panel_token             = New-Secret 16
    }
    $secrets | ConvertTo-Json | Set-Content -LiteralPath $secretsFile -Encoding UTF8
    Write-Step "Secrets generated: $secretsFile"
} else {
    $secrets = Get-Content -Raw -LiteralPath $secretsFile | ConvertFrom-Json
    Write-Step "Secrets loaded (existing)"
}

# 6. 配置文件
function Fill-Template([string]$TemplatePath, [hashtable]$Values, [string]$OutPath) {
    $content = Get-Content -Raw -LiteralPath $TemplatePath
    foreach ($k in $Values.Keys) {
        $content = $content.Replace("{{$k}}", [string]$Values[$k])
    }
    Set-Content -LiteralPath $OutPath -Value $content -Encoding UTF8
}

$templatesDir = Join-Path $Root "installer\templates"

$phpIni = Join-Path $RuntimeDir "frankenphp\php.ini"
if (-not (Test-Path -LiteralPath $phpIni)) {
    Copy-Item -LiteralPath (Join-Path $templatesDir "php.ini.template") -Destination $phpIni
}

$redisConf = Join-Path $RuntimeDir "redis\redis.conf"
Fill-Template (Join-Path $templatesDir "redis.conf.template") @{
    REDIS_PASSWORD = $secrets.redis_password
    DATA_DIR       = Convert-PathToForward (Join-Path $RuntimeDir "data\redis")
    LOG_FILE       = Convert-PathToForward (Join-Path $RuntimeDir "logs\redis.log")
} $redisConf

$caddyFile = Join-Path $RuntimeDir "Caddyfile"
Fill-Template (Join-Path $templatesDir "Caddyfile.template") @{
    HTDOCS     = Convert-PathToForward (Join-Path $RuntimeDir "htdocs")
    PANEL_ROOT = Convert-PathToForward (Join-Path $RuntimeDir "control-panel\web")
    LOGS_DIR   = Convert-PathToForward (Join-Path $RuntimeDir "logs")
} $caddyFile

$htdocsIndex = Join-Path $RuntimeDir "htdocs\index.php"
if (-not (Test-Path -LiteralPath $htdocsIndex)) {
    Copy-Item -LiteralPath (Join-Path $templatesDir "htdocs\index.php") -Destination $htdocsIndex
}

# 复制控制面板 Web 目录到运行时
$panelSrc = Join-Path $Root "control-panel\web"
if (Test-Path -LiteralPath (Join-Path $panelSrc "index.php")) {
    Copy-Item -Path (Join-Path $panelSrc "*") -Destination (Join-Path $RuntimeDir "control-panel\web") -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $Root "control-panel\src") -Destination (Join-Path $RuntimeDir "control-panel\") -Recurse -Force
}

# 7. MariaDB 数据目录初始化（install-db 直接设置 root 密码；随后临时启动创建只读账号）
$dbInitialized = $false
$ports = @{ http = 8080; panel = 8081; mysql = 3306; redis = 6379 }
$mariadbBin = Join-Path $RuntimeDir "mariadb\bin"
if (-not $SkipDbInit -and (Test-Path -LiteralPath (Join-Path $mariadbBin "mariadb-install-db.exe"))) {
    $datadir = Join-Path $RuntimeDir "data\mariadb"
    $initialized = Test-Path -LiteralPath (Join-Path $datadir "mysql")
    if (-not $initialized) {
        Write-Step "Initializing MariaDB data directory ..."
        $installDbLog = Join-Path $RuntimeDir "logs\mariadb-install-db.log"
        Push-Location $mariadbBin
        # 密码不在 install-db 阶段设置（避免其 --password 行为差异），改为启动后由 SQL 显式设置
        & (Join-Path $mariadbBin "mariadb-install-db.exe") --datadir=$datadir *>&1 |
            Tee-Object -FilePath $installDbLog
        $code = $LASTEXITCODE
        Pop-Location
        if ($code -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $datadir "mysql"))) {
            Write-Warning "mariadb-install-db failed (exit=$code), see $installDbLog"
        } else {
            $initialized = $true
        }
    }

    if ($initialized) {
        # 临时启动 -> 创建只读账号 -> 优雅关闭
        $serverLog = Join-Path $RuntimeDir "logs\mariadb.log"
        $serverErr = Join-Path $RuntimeDir "logs\mariadb.err.log"
        $pidFile = Join-Path $RuntimeDir "data\mariadb.pid"
        $proc = Start-Process -FilePath (Join-Path $mariadbBin "mariadbd.exe") `
            -ArgumentList @(
                "--datadir=$datadir",
                "--port=$($ports.mysql)",
                "--bind-address=127.0.0.1",
                "--console"
            ) `
            -WorkingDirectory $RuntimeDir `
            -WindowStyle Hidden -RedirectStandardOutput $serverLog -RedirectStandardError $serverErr -PassThru
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
            $mysql = Join-Path $mariadbBin "mysql.exe"
            $rootPw = [string]$secrets.mariadb_root_password
            $roPw = [string]$secrets.mariadb_readonly_password
            $sql = "ALTER USER 'root'@'localhost' IDENTIFIED BY '$rootPw'; " +
                   "CREATE USER IF NOT EXISTS 'frampp_ro'@'127.0.0.1' IDENTIFIED BY '$roPw'; " +
                   "GRANT SELECT, SHOW VIEW ON *.* TO 'frampp_ro'@'127.0.0.1'; FLUSH PRIVILEGES;"
            $bootstrapLog = Join-Path $RuntimeDir "logs\mariadb-init-user.log"

            # 尝试无密码（全新数据目录）；失败则回退到密码 / skip-grant-tables
            & $mysql -h 127.0.0.1 -P $($ports.mysql) -u root -e $sql *>&1 | Out-File $bootstrapLog -Encoding UTF8
            $bootstrapOk = ($LASTEXITCODE -eq 0)
            if (-not $bootstrapOk) {
                & $mysql -h 127.0.0.1 -P $($ports.mysql) -u root -p"$rootPw" -e $sql *>&1 |
                    Out-File $bootstrapLog -Encoding UTF8 -Append
                $bootstrapOk = ($LASTEXITCODE -eq 0)
            }
            if (-not $bootstrapOk) {
                Write-Warning "常规方式设置密码失败，改用 skip-grant-tables 重置（仅本机临时操作）"
                Stop-Process -Id $proc.Id -Force
                Start-Sleep -Milliseconds 500
                $proc = Start-Process -FilePath (Join-Path $mariadbBin "mariadbd.exe") `
                    -ArgumentList @(
                        "--datadir=$datadir",
                        "--port=$($ports.mysql)",
                        "--bind-address=127.0.0.1",
                        "--skip-grant-tables",
                        "--console"
                    ) `
                    -WorkingDirectory $RuntimeDir `
                    -WindowStyle Hidden -RedirectStandardOutput $serverLog -RedirectStandardError $serverErr -PassThru
                Start-Sleep -Seconds 3
                & $mysql -h 127.0.0.1 -P $($ports.mysql) -u root -e "FLUSH PRIVILEGES; $sql" *>&1 |
                    Out-File $bootstrapLog -Encoding UTF8 -Append
                $bootstrapOk = ($LASTEXITCODE -eq 0)
            }

            $mysqladmin = Join-Path $mariadbBin "mysqladmin.exe"
            if ($bootstrapOk) {
                # 用新密码验证后优雅关闭
                & $mysql -h 127.0.0.1 -P $($ports.mysql) -u root -p"$rootPw" -e "SELECT 'init-ok' AS result;" *>&1 |
                    Out-File $bootstrapLog -Encoding UTF8 -Append
                $verifyOk = ($LASTEXITCODE -eq 0)
                & $mysqladmin -h 127.0.0.1 -P $($ports.mysql) -u root -p"$rootPw" shutdown *>&1 | Out-Null
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
$runtime | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $RuntimeDir "data\runtime.json") -Encoding UTF8

Write-Step "Done. Runtime ready at $RuntimeDir"
Write-Output "DB_INITIALIZED=$dbInitialized"
