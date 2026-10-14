[CmdletBinding()]
param([string] $Tag)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$drivers = Join-Path $projectRoot 'drivers'
$workRoot = Join-Path $projectRoot ("build\prepare-drivers-" + [guid]::NewGuid())
$stage = Join-Path $workRoot 'drivers'
$previous = Join-Path $workRoot 'previous'
$api = 'https://api.github.com/repos/sdli1995/dlssg_for_sm86/releases'
$headers = @{ 'User-Agent' = 'DLSSG-SM86-Manager-Build'; Accept = 'application/vnd.github+json' }
if ($env:GITHUB_TOKEN) { $headers.Authorization = "Bearer $env:GITHUB_TOKEN" }

function Assert-WorkspacePath([string] $Path) {
  $resolved = [System.IO.Path]::GetFullPath($Path)
  if (-not $resolved.StartsWith($projectRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "拒绝操作项目目录之外的路径：$resolved"
  }
}

foreach ($path in @($drivers, $workRoot, $stage, $previous)) {
  Assert-WorkspacePath $path
}

New-Item -ItemType Directory -Path $stage -Force | Out-Null
$activated = $false
try {
  $releaseEndpoint = if ($Tag) { "$api/tags/$([uri]::EscapeDataString($Tag))" } else { "$api/latest" }
  $release = Invoke-RestMethod -Uri $releaseEndpoint -Headers $headers -TimeoutSec 60
  $releaseTag = [string] $release.tag_name
  if ($releaseTag -in @('.', '..') -or $releaseTag -notmatch '^[0-9A-Za-z._+-]+$') { throw '上游 Release 缺少有效版本号。' }
  $versionName = $releaseTag -replace '^[vV](?=\d)', ''
  $assets = @($release.assets | Where-Object { $_.name -in @("dlssg-release-$releaseTag-x64.zip", "dlssg-release-$versionName-x64.zip") })
  if ($assets.Count -ne 1) { throw "上游 Release $releaseTag 未提供唯一的完整 x64 ZIP 附件。" }
  $archiveName = [string] $assets[0].name
  $archiveUrl = [string] $assets[0].browser_download_url
  if ($archiveUrl -notmatch '^https://') { throw '上游 Release 附件下载地址无效。' }
  Write-Host "下载完整离线驱动包：$archiveName"
  Invoke-WebRequest -Uri $archiveUrl -OutFile (Join-Path $stage $archiveName) -TimeoutSec 600
  # Keep the release ZIP intact. The manager validates and unpacks it locally.

  # Replace an existing local preparation only after the new files are ready.
  if (Test-Path -LiteralPath $drivers) {
    Move-Item -LiteralPath $drivers -Destination $previous
  }
  try {
    Move-Item -LiteralPath $stage -Destination $drivers
    $activated = $true
  } catch {
    if (Test-Path -LiteralPath $previous) {
      Move-Item -LiteralPath $previous -Destination $drivers
    }
    throw
  }
  Write-Host "已准备离线驱动：$drivers\$archiveName"
} finally {
  # Keep the previous directory if a filesystem error prevented rollback.
  if ($activated -or -not (Test-Path -LiteralPath $previous)) {
    Remove-Item -LiteralPath $workRoot -Recurse -Force
  }
}
