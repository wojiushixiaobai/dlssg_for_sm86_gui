[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$buildOutput = Join-Path $projectRoot 'build\windows\x64\runner\Release'
$releaseRoot = Join-Path $projectRoot 'release'
$bundle = Join-Path $releaseRoot 'dlssg-for-sm86-manager'
$zip = Join-Path $releaseRoot 'dlssg-for-sm86-manager-portable.zip'

function Assert-WorkspacePath([string] $Path) {
  $resolved = [System.IO.Path]::GetFullPath($Path)
  if (-not $resolved.StartsWith($projectRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "拒绝操作项目目录之外的路径：$resolved"
  }
}

Assert-WorkspacePath $buildOutput
Assert-WorkspacePath $bundle
Assert-WorkspacePath $zip

Push-Location $projectRoot
try {
  if (Test-Path -LiteralPath $buildOutput -PathType Container) {
    Remove-Item -LiteralPath $buildOutput -Recurse -Force
  }
  flutter pub get
  if ($LASTEXITCODE -ne 0) { throw "flutter pub get 失败：$LASTEXITCODE" }
  flutter test
  if ($LASTEXITCODE -ne 0) { throw "flutter test 失败：$LASTEXITCODE" }
  # Ship the complete icon font; incremental builds can retain an older subset.
  flutter build windows --release --no-tree-shake-icons
  if ($LASTEXITCODE -ne 0) { throw "flutter build windows 失败：$LASTEXITCODE" }
} finally {
  Pop-Location
}

if (-not (Test-Path -LiteralPath $buildOutput -PathType Container)) {
  throw "Flutter Release 输出不存在：$buildOutput"
}
New-Item -ItemType Directory -Force -Path $releaseRoot | Out-Null
if (Test-Path -LiteralPath $bundle) { Remove-Item -LiteralPath $bundle -Recurse -Force }
Copy-Item -LiteralPath $buildOutput -Destination $bundle -Recurse -Force
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
Compress-Archive -LiteralPath $bundle -DestinationPath $zip -CompressionLevel Optimal
Write-Host "已生成：$zip"
