[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$buildOutput = Join-Path $projectRoot 'build\windows\x64\runner\Release'
$releaseRoot = Join-Path $projectRoot 'release'
$bundle = Join-Path $releaseRoot 'dlssg-for-sm86-manager'
$zip = Join-Path $releaseRoot 'dlssg-for-sm86-manager-portable.zip'

Push-Location $projectRoot
try {
  flutter pub get
  flutter test
  flutter build windows --release
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
