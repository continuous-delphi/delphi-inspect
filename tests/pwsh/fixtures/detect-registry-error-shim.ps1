# detect-registry-error-shim.ps1
# Test shim: injects a registry access failure into the -ListInstalled path.
#
# Dot-sources delphi-inspect.ps1 to import all functions and exit-code
# constants (the dot-source guard fires so only the pre-guard definitions load),
# then overrides Get-RegistryRootDir with a version that always throws, then
# runs Import-JsonData and the detect loop to trigger exit code 5.

param(
  [string]$DataFile,

  [ValidateSet('text', 'json', 'object')]
  [string]$Format = 'object',

  [ValidateSet('Win32', 'Win64')]
  [string]$Platform = 'Win32',

  [ValidateSet('DCC', 'MSBuild')]
  [string]$BuildSystem = 'DCC'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Dot-source the main script to import functions and exit-code constants.
# The dot-source guard ($MyInvocation.InvocationName -eq '.') fires and returns
# before the top-level try/catch, so only functions and variables defined above
# the guard (including all $Exit* constants) are imported.
$mainScript = Join-Path $PSScriptRoot '..' '..' '..' 'source' 'pwsh' 'delphi-inspect.ps1'
$mainScript = [System.IO.Path]::GetFullPath($mainScript)

# Save the shim's parameter values before dot-sourcing.  When a script is dot-sourced
# its param() block runs in the calling scope, resetting any variables that share a name
# with the dot-sourced script's parameters to their default values.
$savedDataFile    = $DataFile
$savedFormat      = $Format
$savedPlatform    = $Platform
$savedBuildSystem = $BuildSystem

. $mainScript

# Restore the shim's parameter values so the detect loop uses the correct arguments.
$DataFile    = $savedDataFile
$Format      = $savedFormat
$Platform    = $savedPlatform
$BuildSystem = $savedBuildSystem

# Override Get-RegistryRootDir to always throw, simulating a registry access failure.
# This overwrites the dot-sourced definition in the current scope; Get-DccReadiness
# and Get-MSBuildReadiness call it by name so they pick up this version.
function Get-RegistryRootDir {
  param([string]$RelativePath)
  throw "Simulated registry access failure for path: $RelativePath"
}

# Mirror the Import-JsonData call from the dispatch block.
try {
  $data = Import-JsonData -Path $DataFile
} catch {
  if ($Format -eq 'json') {
    Write-JsonError -ToolVersion $ToolVersion -Command 'listInstalled' -Code $ExitDatasetError -Message $_.Exception.Message
  } else {
    Write-Error $_.Exception.Message -ErrorAction Continue
  }
  exit $ExitDatasetError
}

# Mirror the detect loop from the dispatch block.  The overridden Get-RegistryRootDir
# throws for any entry that reaches the registry check, which the catch converts to exit 5.
try {
  $null = @($data.versions | ForEach-Object {
    if ($BuildSystem -eq 'DCC') {
      Get-DccReadiness -Entry $_ -Platform $Platform
    } else {
      Get-MSBuildReadiness -Entry $_ -Platform $Platform
    }
  })
} catch {
  if ($Format -eq 'json') {
    Write-JsonError -ToolVersion $ToolVersion -Command 'listInstalled' -Code $ExitRegistryError -Message "Registry access failed: $($_.Exception.Message)"
  } else {
    Write-Error "Registry access failed: $($_.Exception.Message)" -ErrorAction Continue
  }
  exit $ExitRegistryError
}

exit $ExitSuccess
