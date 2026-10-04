[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$drivers = Join-Path $projectRoot 'drivers'
$workRoot = Join-Path $projectRoot ("build\prepare-drivers-" + [guid]::NewGuid())
$stage = Join-Path $workRoot 'drivers'
$previous = Join-Path $workRoot 'previous'
$archivePath = Join-Path $workRoot 'dlssg_for_sm86.zip'

function Assert-WorkspacePath([string] $Path) {
  $resolved = [System.IO.Path]::GetFullPath($Path)
  if (-not $resolved.StartsWith($projectRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "拒绝操作项目目录之外的路径：$resolved"
  }
}

foreach ($path in @($drivers, $workRoot, $stage, $previous)) {
  Assert-WorkspacePath $path
}

$api = 'https://api.github.com/repos/sdli1995/dlssg_for_sm86'
$headers = @{
  'User-Agent' = 'DLSSG-SM86-Manager-Build'
  Accept = 'application/vnd.github+json'
}
if ($env:GITHUB_TOKEN) { $headers.Authorization = "Bearer $env:GITHUB_TOKEN" }

New-Item -ItemType Directory -Path $stage -Force | Out-Null
$activated = $false
try {
  $release = Invoke-RestMethod -Uri "$api/releases/latest" -Headers $headers -TimeoutSec 60
  $tag = [string] $release.tag_name
  if ($tag -notmatch '^[0-9A-Za-z._-]+$') { throw '上游 Release 缺少有效版本号。' }
  $commit = Invoke-RestMethod -Uri "$api/commits/$tag" -Headers $headers -TimeoutSec 60
  $sha = [string] $commit.sha
  if ($sha -notmatch '^[0-9a-f]{40}$') { throw '无法解析上游 Release 的提交。' }

  Write-Host "下载上游 Release：$tag ($sha)"
  Invoke-WebRequest -Uri "$api/zipball/$sha" -Headers $headers -OutFile $archivePath -TimeoutSec 600
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $required = @('version.dll', 'winmm.dll', 'dbghelp.dll', 'dinput8.dll', 'dlssg_sm86.ini', 'THIRD_PARTY_NOTICES.txt')
  $archive = [System.IO.Compression.ZipFile]::OpenRead($archivePath)
  try {
    # GitHub archives wrap the release in one repository directory.
    $roots = @($archive.Entries | ForEach-Object { ($_.FullName -split '/')[0] } | Sort-Object -Unique)
    if ($roots.Count -ne 1) { throw '上游压缩包目录结构异常。' }
    foreach ($name in $required) {
      $paths = @($name)
      if ($name -like '*.dll' -and $name -ne 'version.dll') {
        $paths += @("alternatives/$name", "altnative/$name")
      }
      $entry = $null
      foreach ($path in $paths) {
        $entry = $archive.GetEntry("$($roots[0])/$path")
        if ($null -ne $entry) { break }
      }
      if ($null -eq $entry -or $entry.Length -le 0) { throw "上游 Release $tag 缺少有效文件：$name" }
      # Extract only the allowlisted files, never historical versions.
      [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, (Join-Path $stage $name))
    }
  } finally {
    $archive.Dispose()
  }
  $metadata = @{ tag_name = $tag; commit = $sha } | ConvertTo-Json
  [System.IO.File]::WriteAllText((Join-Path $stage 'release.json'), $metadata, [System.Text.UTF8Encoding]::new($false))

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
  Write-Host "已准备离线驱动：$drivers ($tag)"
} finally {
  # Keep the previous directory if a filesystem error prevented rollback.
  if ($activated -or -not (Test-Path -LiteralPath $previous)) {
    Remove-Item -LiteralPath $workRoot -Recurse -Force
  }
}
