<#
.SYNOPSIS
Publish (or update) a Gitee release and upload installer assets.

.DESCRIPTION
Mirrors a FRAMPP release to Gitee: creates the release from a tag if it does
not exist, then uploads the given assets. Files larger than Gitee's 100 MB
attachment limit are skipped with a warning.

.PARAMETER Token
Gitee personal access token (required; scope: projects).

.PARAMETER Repo
Gitee repository "owner/repo" (default: wang_bo_wang_bo/frampp).

.PARAMETER Tag
Tag to publish, e.g. v0.3.0.

.PARAMETER Name
Release title (defaults to "FRAMPP <Tag>").

.PARAMETER NotesFile
Path to a Markdown file with the release notes (English-first).

.PARAMETER Assets
One or more files to upload as release attachments.

.PARAMETER TargetBranch
Branch/commit the tag points to (default: master).

.EXAMPLE
pwsh -File installer/scripts/publish-gitee.ps1 -Token $env:GITEE_TOKEN -Tag v0.3.0 `
  -NotesFile .tmp-notes.md -Assets dist/installer/frampp-setup-8.5-0.3.0-windows-x64.exe,dist/installer/SHA256SUMS.txt
#>
param(
    [Parameter(Mandatory = $true)][string]$Token,
    [string]$Repo = "wang_bo_wang_bo/frampp",
    [Parameter(Mandatory = $true)][string]$Tag,
    [string]$Name = "FRAMPP $Tag",
    [string]$NotesFile = "",
    [string[]]$Assets = @(),
    [string]$TargetBranch = "master"
)

$ErrorActionPreference = "Stop"
$base = "https://gitee.com/api/v5/repos/$Repo"

function Get-Release {
    param([string]$Uri)
    try {
        return Invoke-RestMethod -Uri $Uri -Method Get
    }
    catch {
        if ($_.Exception.Response.StatusCode.value__ -eq 404) { return $null }
        throw
    }
}

$release = Get-Release "$base/releases/tags/$Tag`?access_token=$Token"
if (-not $release) {
    $body = @{
        access_token      = $Token
        tag_name          = $Tag
        name              = $Name
        target_commitish  = $TargetBranch
    }
    if ($NotesFile) { $body.body = Get-Content -Raw -Path $NotesFile }
    $release = Invoke-RestMethod -Uri "$base/releases" -Method Post -Body $body
    Write-Host "Created release $Tag (id $($release.id))"
}
else {
    Write-Host "Release $Tag already exists (id $($release.id)); uploading missing assets"
}

foreach ($asset in $Assets) {
    $item = Get-Item -LiteralPath $asset
    if ($item.Length -gt 100MB) {
        Write-Warning "Skipped $($item.Name) ($([math]::Round($item.Length / 1MB)) MB) - Gitee attachment limit is 100 MB per file"
        continue
    }
    $form = @{
        access_token = $Token
        file         = $item
    }
    $att = Invoke-RestMethod -Uri "$base/releases/$($release.id)/attach_files" -Method Post -Form $form
    Write-Host "Uploaded $($att.name) -> $($att.browser_download_url)"
}
