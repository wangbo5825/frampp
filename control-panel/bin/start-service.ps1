param(
    [Parameter(Mandatory = $true)][string]$JsonArgs
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $JsonArgs)) {
    throw "JsonArgs 文件不存在: $JsonArgs"
}

$a = Get-Content -Raw -LiteralPath $JsonArgs | ConvertFrom-Json

$p = Start-Process `
    -FilePath $a.file `
    -ArgumentList $a.args `
    -WorkingDirectory $a.cwd `
    -WindowStyle Hidden `
    -RedirectStandardOutput $a.stdout `
    -RedirectStandardError $a.stderr `
    -PassThru

Start-Sleep -Milliseconds 400

if ($p.HasExited) {
    throw "进程启动后立即退出: $($a.file) exit=$($p.ExitCode)"
}

$p.Id | Out-File -Encoding ascii -LiteralPath $a.pidFile
Write-Output "PID=$($p.Id)"
