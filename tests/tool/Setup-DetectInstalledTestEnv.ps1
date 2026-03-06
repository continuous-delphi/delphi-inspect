# Setup-DetectInstalledTestEnv.ps1
# Crude test environment for -DetectInstalled manual testing.
# Uses VER90 (Delphi 2) -- least likely to be installed on any real machine.
#
# Usage:
#   .\Setup-DetectInstalledTestEnv.ps1 -Readiness partialInstall
#   .\Setup-DetectInstalledTestEnv.ps1 -Readiness ready
#   .\Setup-DetectInstalledTestEnv.ps1 -Cleanup

param(
  [Parameter(ParameterSetName='Setup', Mandatory=$true)]
  [ValidateSet('registryOnly', 'partialInstall', 'ready')]
  [string]$Readiness,

  [Parameter(ParameterSetName='Cleanup', Mandatory=$true)]
  [switch]$Cleanup
)

# VER90 = Delphi 2, BDS version 9.0, Borland-era registry path
$RegKey     = 'HKCU:\Software\Borland\Delphi\2.0'
$RootDir    = 'C:\Delphi\test\2.0'
$BinDir     = "$RootDir\bin"
$RsvarsPath = "$BinDir\rsvars.bat"
$EnvOptDir  = "$env:APPDATA\Embarcadero\BDS\2.0"
$EnvOptPath = "$EnvOptDir\EnvOptions.proj"

if ($Cleanup) {
  Write-Host 'Cleaning up test environment for VER90 (Delphi 2)...'

  if (Test-Path $RegKey) {
    Remove-Item -Path $RegKey -Recurse -Force
    Write-Host "  Removed registry key: $RegKey"
  }

  if (Test-Path $RootDir) {
    Remove-Item -Path $RootDir -Recurse -Force
    Write-Host "  Removed directory: $RootDir"
  }

  if (Test-Path $EnvOptPath) {
    Remove-Item -Path $EnvOptPath -Force
    Write-Host "  Removed: $EnvOptPath"
  }

  if (Test-Path $EnvOptDir) {
    # Only remove if empty
    if (-not (Get-ChildItem $EnvOptDir)) {
      Remove-Item -Path $EnvOptDir -Force
      Write-Host "  Removed empty dir: $EnvOptDir"
    }
  }

  Write-Host 'Done.'
  exit 0
}

# --- Setup ---

Write-Host "Setting up test environment for VER90 (Delphi 2) -- target readiness: $Readiness"

# Always: registry key + RootDir value
New-Item -Path $RegKey -Force | Out-Null
New-ItemProperty -Path $RegKey -Name 'RootDir' -Value $RootDir -PropertyType String -Force | Out-Null
Write-Host "  Registry key set: $RegKey\RootDir = $RootDir"

if ($Readiness -eq 'registryOnly') {
  Write-Host 'Done. (registryOnly -- no filesystem changes)'
  exit 0
}

# partialInstall and ready: create RootDir on disk
New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
Write-Host "  Created: $BinDir"

if ($Readiness -eq 'partialInstall') {
  Write-Host 'Done. (partialInstall -- rootDirExists true, rsvars/envOptions missing)'
  exit 0
}

# ready: rsvars.bat + EnvOptions.proj with DelphiLibraryPath
Set-Content -Path $RsvarsPath -Value '@REM rsvars stub for test' -Encoding UTF8NoBOM
Write-Host "  Created: $RsvarsPath"

New-Item -ItemType Directory -Path $EnvOptDir -Force | Out-Null
@"
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup>
    <DelphiLibraryPath>$RootDir\lib\win32\release</DelphiLibraryPath>
  </PropertyGroup>
</Project>
"@ | Set-Content -Path $EnvOptPath -Encoding UTF8NoBOM
Write-Host "  Created: $EnvOptPath"

Write-Host 'Done. (ready -- all MSBuild Win32 components present)'
