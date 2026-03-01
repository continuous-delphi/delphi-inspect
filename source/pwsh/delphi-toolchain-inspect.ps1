<#
delphi-toolchain-inspect.ps1

Minimal V1:
- Loads the Delphi compiler versions dataset JSON.
- Prints tool version + dataset metadata.

ASCII-only.

USAGE
  pwsh ./source/delphi-toolchain-inspect.ps1
  pwsh ./source/delphi-toolchain-inspect.ps1 -Version
  pwsh ./source/delphi-toolchain-inspect.ps1 -Version -Format json
  pwsh ./source/delphi-toolchain-inspect.ps1 -Resolve -Name <alias>
  pwsh ./source/delphi-toolchain-inspect.ps1 -Resolve <alias>
  pwsh ./source/delphi-toolchain-inspect.ps1 -Resolve -Name <alias> -Format json
  pwsh ./source/delphi-toolchain-inspect.ps1 -DataFile <path>

NOTES
  Default behavior is equivalent to -Version.
  This is intentional: future action switches will short-circuit -Version output.

  -Resolve looks up an alias or VER### string in the dataset (case-insensitive)
  and prints the canonical entry fields.  Exit 4 when the alias is not found.

  -Format selects output format: text (default, human-readable) or json
  (machine envelope with ok/command/tool/result structure).  Error envelopes
  substitute result with error: { code, message }.  Unknown format values are
  rejected by the parameter binder (ValidateSet).
#>

[CmdletBinding(DefaultParameterSetName='Version')]
param(
  [Parameter(ParameterSetName='Version')]
  [switch]$Version,

  [Parameter(ParameterSetName='Resolve', Mandatory=$true)]
  [switch]$Resolve,

  [Parameter(ParameterSetName='Resolve', Mandatory=$true, Position=0)]
  [string]$Name,

  [Parameter(ParameterSetName='ListKnown')]
  [switch]$ListKnown,

  [Parameter(ParameterSetName='DetectInstalled', Mandatory=$true)]
  [switch]$DetectInstalled,

  [Parameter(ParameterSetName='DetectInstalled', Mandatory=$true)]
  [ValidateSet('Win32', 'Win64')]
  [string]$Platform,

  [Parameter(ParameterSetName='DetectInstalled', Mandatory=$true)]
  [ValidateSet('DCC', 'MSBuild')]
  [string]$BuildSystem,

  [Parameter()]
  [string]$DataFile,

  [Parameter()]
  [ValidateSet('text', 'json')]
  [string]$Format = 'text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Tool version (bump per Continuous Delphi versioning policy for tooling)
$ToolVersion = '0.1.0'

function Resolve-DefaultDataFilePath {
  param([string]$ScriptPath)

  $scriptDir = Split-Path -Parent $ScriptPath

  # Prefer the submodule layout:
  #   ../delphi-compiler-versions/data/delphi-compiler-versions.json
  # Use Join-Path to remain path-separator-safe if invoked on non-Windows runners.
  $repoRoot    = Join-Path $scriptDir '..' '..'
  $specRoot    = Join-Path $repoRoot 'submodules' 'delphi-compiler-versions'
  $dataDir     = Join-Path $specRoot 'data'
  $defaultPath = Join-Path $dataDir 'delphi-compiler-versions.json'

  return $defaultPath
}

function Import-JsonData {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Data file not found: $Path"
  }

  # Use -Raw to avoid array-of-lines behavior
  $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
  try {
    return $text | ConvertFrom-Json
  } catch {
    throw "Failed to parse JSON in data file: $Path. $($_.Exception.Message)"
  }
}


function Write-JsonOutput {
  param(
    [Parameter(Mandatory=$true)]
    [object]$Object
  )
  # Single write to stdout; stable for CI.
  Write-Output ($Object | ConvertTo-Json -Depth 10 -Compress)
}

function Write-JsonError {
  param(
    [string]$ToolVersion,
    [string]$Command,
    [int]$Code,
    [string]$Message
  )
  Write-JsonOutput ([pscustomobject]@{
    ok      = $false
    command = $Command
    tool    = [pscustomobject]@{ name = 'delphi-toolchain-inspect'; impl = 'pwsh'; version = $ToolVersion }
    error   = [pscustomobject]@{ code = $Code; message = $Message }
  } )
}

function Write-VersionInfo {
  param(
    [string]$ToolVersion,
    [psobject]$Data,
    [string]$Format = 'text'
  )

  $schemaVersion = $Data.schemaVersion
  $dataVersion   = $Data.dataVersion

  # generated date lives under meta.generatedUtcDate in our dataset
  $generated = $null
  if ($null -ne $Data.meta -and $null -ne $Data.meta.generatedUtcDate) {
    $generated = $Data.meta.generatedUtcDate
  }

  if ($Format -eq 'json') {
    Write-JsonOutput ([pscustomobject]@{
      ok      = $true
      command = 'version'
      tool    = [pscustomobject]@{ name = 'delphi-toolchain-inspect'; impl = 'pwsh'; version = $ToolVersion }
      result  = [pscustomobject]@{
        schemaVersion      = $schemaVersion
        dataVersion        = $dataVersion
        generatedUtcDate   = $generated
      }
    } )
    return
  }

  Write-Output ("delphi-toolchain-inspect {0}" -f $ToolVersion)
  Write-Output ("dataVersion     {0}" -f $dataVersion)
  Write-Output ("schemaVersion   {0}" -f $schemaVersion)
  if (-not [string]::IsNullOrWhiteSpace($generated)) {
    Write-Output ("generated       {0}" -f $generated)
  }
}

function Resolve-VersionEntry {
  param(
    [string]$Name,
    [psobject]$Data
  )

  foreach ($entry in $Data.versions) {
    # Check verDefine first -- not stored in aliases by design
    if ($null -ne $entry.verDefine -and
        [string]::Equals($entry.verDefine, $Name, [System.StringComparison]::OrdinalIgnoreCase)) {
      return $entry
    }
    # Check productName -- not stored in aliases by design
    if ($null -ne $entry.productName -and
        [string]::Equals($entry.productName, $Name, [System.StringComparison]::OrdinalIgnoreCase)) {
      return $entry
    }
    # Then scan aliases
    if ($null -ne $entry.aliases) {
      foreach ($alias in $entry.aliases) {
        if ([string]::Equals($alias, $Name, [System.StringComparison]::OrdinalIgnoreCase)) {
          return $entry
        }
      }
    }
  }
  return $null
}

function Write-ResolveOutput {
  param(
    [psobject]$Entry,
    [string]$ToolVersion = '',
    [string]$Format = 'text'
  )

  if ($Format -eq 'json') {
    Write-JsonOutput ([pscustomobject]@{
      ok      = $true
      command = 'resolve'
      tool    = [pscustomobject]@{ name = 'delphi-toolchain-inspect'; impl = 'pwsh'; version = $ToolVersion }
      result  = [pscustomobject]@{
        verDefine          = $Entry.verDefine
        productName        = $Entry.productName
        compilerVersion    = $Entry.compilerVersion
        packageVersion     = $Entry.packageVersion
        regKeyRelativePath = $Entry.regKeyRelativePath
        aliases            = $Entry.aliases
      }
    } )
    return
  }

  # Label column is 20 chars wide to accommodate 'regKeyRelativePath' 
  Write-Output ("verDefine           {0}" -f $Entry.verDefine)
  Write-Output ("productName         {0}" -f $Entry.productName)
  Write-Output ("compilerVersion     {0}" -f $Entry.compilerVersion)
  if (-not [string]::IsNullOrWhiteSpace($Entry.packageVersion)) {
    Write-Output ("packageVersion      {0}" -f $Entry.packageVersion)
  }
  if (-not [string]::IsNullOrWhiteSpace($Entry.regKeyRelativePath)) {
    Write-Output ("regKeyRelativePath  {0}" -f $Entry.regKeyRelativePath)
  }
  if ($Entry.aliases -and $Entry.aliases.Count -gt 0) {
    Write-Output ("aliases             {0}" -f ($Entry.aliases -join ', '))
  }
}

function Write-ListKnownOutput {
  param(
    [psobject]$Data,
    [string]$ToolVersion = '',
    [string]$Format = 'text'
  )

  if ($Format -eq 'json') {
    $versions = @($Data.versions | ForEach-Object {
      [pscustomobject]@{
        verDefine          = $_.verDefine
        productName        = $_.productName
        compilerVersion    = $_.compilerVersion
        packageVersion     = $_.packageVersion
        regKeyRelativePath = $_.regKeyRelativePath
        aliases            = $_.aliases
        notes              = $_.notes
      }
    })
    Write-JsonOutput ([pscustomobject]@{
      ok      = $true
      command = 'listKnown'
      tool    = [pscustomobject]@{ name = 'delphi-toolchain-inspect'; impl = 'pwsh'; version = $ToolVersion }
      result  = [pscustomobject]@{
        schemaVersion    = $Data.schemaVersion
        dataVersion      = $Data.dataVersion
        generatedUtcDate = if ($null -ne $Data.meta) { $Data.meta.generatedUtcDate } else { $null }
        versions         = $versions
      }
    })
    return
  }

  # Text: entry list -- fixed-width columns
  # verDefine 12, compilerVersion 10, packageVersion 6, productName (trailing)
  foreach ($entry in $Data.versions) {
    Write-Output ("{0,-12}{1,-10}{2,-6}{3}" -f `
      $entry.verDefine, $entry.compilerVersion, $entry.packageVersion, $entry.productName)
  }
}

function Get-RegistryRootDir {
  param([string]$RelativePath)

  $subKey = $RelativePath.TrimStart('\')

  foreach ($hive in @([Microsoft.Win32.RegistryHive]::CurrentUser, [Microsoft.Win32.RegistryHive]::LocalMachine)) {
    $baseKey = $null
    $regKey  = $null
    try {
      $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey($hive, [Microsoft.Win32.RegistryView]::Registry32)
      $regKey  = $baseKey.OpenSubKey($subKey)
      if ($null -ne $regKey) {
        $val = $regKey.GetValue('RootDir')
        if (-not [string]::IsNullOrWhiteSpace([string]$val)) {
          return [string]$val
        }
      }
    } finally {
      if ($null -ne $regKey)  { $regKey.Close()  }
      if ($null -ne $baseKey) { $baseKey.Close() }
    }
  }
  return $null
}

function Test-EnvOptionsLibraryPath {
  param(
    [string]$Path,
    [string]$Platform
  )

  try {
    [xml]$xml = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $platformPropMap = @{
      Win32 = 'DelphiLibraryPath'
      Win64 = 'DelphiLibraryPathWin64'
    }
    $propName = $platformPropMap[$Platform]    
    $nodes     = $xml.SelectNodes("//*[local-name()='$propName']")
    foreach ($node in $nodes) {
      if (-not [string]::IsNullOrWhiteSpace($node.InnerText)) {
        return $true
      }
    }
    return $false
  } catch {
    return $false
  }
}

function Get-DccReadiness {
  param(
    [psobject]$Entry,
    [string]$Platform
  )

  $compilerExe = if ($Platform -eq 'Win64') { 'dcc64.exe' } else { 'dcc32.exe' }
  $cfgFile     = if ($Platform -eq 'Win64') { 'dcc64.cfg' } else { 'dcc32.cfg' }

  $result = [pscustomobject]@{
    verDefine     = $Entry.verDefine
    productName   = $Entry.productName
    readiness     = 'notFound'
    registryFound = $null
    rootDirExists = $null
    compilerFound = $null
    cfgFound      = $null
  }

  if ('DCC' -notin $Entry.supportedBuildSystems -or $Platform -notin $Entry.supportedPlatforms) {
    $result.readiness = 'notApplicable'
    return $result
  }

  if ([string]::IsNullOrWhiteSpace($Entry.regKeyRelativePath)) {
    $result.registryFound = $false
    return $result
  }

  $rootDir = Get-RegistryRootDir -RelativePath $Entry.regKeyRelativePath
  if ($null -eq $rootDir) {
    $result.registryFound = $false
    return $result
  }

  $binPath = Join-Path $rootDir 'bin'
  $result.registryFound = $true
  $result.rootDirExists = Test-Path -LiteralPath $rootDir
  $result.compilerFound = Test-Path -LiteralPath (Join-Path $binPath $compilerExe)
  $result.cfgFound      = Test-Path -LiteralPath (Join-Path $binPath $cfgFile)

  if ($result.rootDirExists -and $result.compilerFound -and $result.cfgFound) {
    $result.readiness = 'ready'
  } else {
    $result.readiness = 'partialInstall'
  }

  return $result
}

function Get-MSBuildReadiness {
  param(
    [psobject]$Entry,
    [string]$Platform
  )

  $result = [pscustomobject]@{
    verDefine                = $Entry.verDefine
    productName              = $Entry.productName
    readiness                = 'notFound'
    registryFound            = $null
    rootDirExists            = $null
    rsvarsFound              = $null
    envOptionsFound          = $null
    envOptionsHasLibraryPath = $null
  }

  if ('MSBuild' -notin $Entry.supportedBuildSystems -or $Platform -notin $Entry.supportedPlatforms) {
    $result.readiness = 'notApplicable'
    return $result
  }

  if ([string]::IsNullOrWhiteSpace($Entry.regKeyRelativePath)) {
    $result.registryFound = $false
    return $result
  }

  $rootDir = Get-RegistryRootDir -RelativePath $Entry.regKeyRelativePath
  if ($null -eq $rootDir) {
    $result.registryFound = $false
    return $result
  }

  $binPath    = Join-Path $rootDir 'bin'
  $bdsVersion = Split-Path -Leaf $Entry.regKeyRelativePath
  $envOptPath = Join-Path $env:APPDATA 'Embarcadero' 'BDS' $bdsVersion 'EnvOptions.proj'

  $result.registryFound   = $true
  $result.rootDirExists   = Test-Path -LiteralPath $rootDir
  $result.rsvarsFound     = Test-Path -LiteralPath (Join-Path $binPath 'rsvars.bat')
  $result.envOptionsFound = Test-Path -LiteralPath $envOptPath

  if ($result.envOptionsFound) {
    $result.envOptionsHasLibraryPath = Test-EnvOptionsLibraryPath -Path $envOptPath -Platform $Platform
  }

  if ($result.rootDirExists -and $result.rsvarsFound -and $result.envOptionsFound -and $result.envOptionsHasLibraryPath) {
    $result.readiness = 'ready'
  } else {
    $result.readiness = 'partialInstall'
  }

  return $result
}

function Write-DetectInstalledOutput {
  param(
    [object[]]$Installations,
    [string]$Platform,
    [string]$BuildSystem,
    [string]$ToolVersion = '',
    [string]$Format = 'text'
  )

  if ($Format -eq 'json') {
    $items = @($Installations | ForEach-Object {
      $inst = $_
      if ($BuildSystem -eq 'DCC') {
        [pscustomobject]@{
          verDefine     = $inst.verDefine
          productName   = $inst.productName
          readiness     = $inst.readiness
          registryFound = $inst.registryFound
          rootDirExists = $inst.rootDirExists
          compilerFound = $inst.compilerFound
          cfgFound      = $inst.cfgFound
        }
      } else {
        [pscustomobject]@{
          verDefine                = $inst.verDefine
          productName              = $inst.productName
          readiness                = $inst.readiness
          registryFound            = $inst.registryFound
          rootDirExists            = $inst.rootDirExists
          rsvarsFound              = $inst.rsvarsFound
          envOptionsFound          = $inst.envOptionsFound
          envOptionsHasLibraryPath = $inst.envOptionsHasLibraryPath
        }
      }
    })
    Write-JsonOutput ([pscustomobject]@{
      ok      = $true
      command = 'detectInstalled'
      tool    = [pscustomobject]@{ name = 'delphi-toolchain-inspect'; impl = 'pwsh'; version = $ToolVersion }
      result  = [pscustomobject]@{
        platform      = $Platform
        buildSystem   = $BuildSystem
        installations = $items
      }
    })
    return
  }

  # Text format: only show detected installations (readiness != notFound)
  # @() forces empty array -- Where-Object returns $null under StrictMode when no matches
  $found = @($Installations | Where-Object { $_.readiness -in @('ready', 'partialInstall') })
  if ($found.Count -eq 0) {
    Write-Output 'No installations found'
    return
  }

  $firstBlock = $true
  foreach ($inst in $found) {
    if (-not $firstBlock) { Write-Output '' }
    $firstBlock = $false

    Write-Output ("{0,-10} {1}" -f $inst.verDefine, $inst.productName)
    Write-Output ("  {0,-26}{1}" -f 'readiness', $inst.readiness)
    Write-Output ("  {0,-26}{1}" -f 'registryFound', $inst.registryFound.ToString().ToLower())
    Write-Output ("  {0,-26}{1}" -f 'rootDirExists', $inst.rootDirExists.ToString().ToLower())
    if ($BuildSystem -eq 'DCC') {
      Write-Output ("  {0,-26}{1}" -f 'compilerFound', $inst.compilerFound.ToString().ToLower())
      Write-Output ("  {0,-26}{1}" -f 'cfgFound', $inst.cfgFound.ToString().ToLower())
    } else {
      Write-Output ("  {0,-26}{1}" -f 'rsvarsFound', $inst.rsvarsFound.ToString().ToLower())
      Write-Output ("  {0,-26}{1}" -f 'envOptionsFound', $inst.envOptionsFound.ToString().ToLower())
      $hasLibStr = ($null -ne $inst.envOptionsHasLibraryPath) ? $inst.envOptionsHasLibraryPath.ToString().ToLower() : 'null'
      Write-Output ("  {0,-26}{1}" -f 'envOptionsHasLibraryPath', $hasLibStr)
    }
  }
}

# Guard: skip top-level execution when the script is dot-sourced for testing.
# Pester dot-sources the file to import functions; $MyInvocation.InvocationName
# is '.' in that case. Direct execution always sets it to the script path.
if ($MyInvocation.InvocationName -eq '.') { return }

try {
  $commandName = 'version'  # safe default for outer catch error reporting
  $scriptPath = $PSCommandPath
  if ([string]::IsNullOrWhiteSpace($scriptPath)) {
    throw "Cannot resolve script path. Run as a file, not dot-sourced."
  }

  # Default behavior: if no action switches specified, treat as -Version.
  # Mutual exclusion and mandatory -Name are enforced by parameter sets.
  $doVersion = $Version
  if (-not $doVersion -and -not $Resolve -and -not $ListKnown -and -not $DetectInstalled) { $doVersion = $true }
  $commandName = if ($Resolve) { 'resolve' } elseif ($ListKnown) { 'listKnown' } elseif ($DetectInstalled) { 'detectInstalled' } else { 'version' }

  if ([string]::IsNullOrWhiteSpace($DataFile)) {
    $DataFile = Resolve-DefaultDataFilePath -ScriptPath $scriptPath
  }

  # NOTE: dataset errors exit here directly (exit 3) rather than propagating
  # to the outer catch.  As more exit codes are added, consider extracting the
  # dispatch block into an Invoke-Main function that returns an exit code, with
  # a single exit at the script's top level.  That eliminates scattered exit
  # calls and makes the code table easy to audit in one place.
  try {
    $data = Import-JsonData -Path $DataFile
  } catch {
    if ($Format -eq 'json') {
      Write-JsonError -ToolVersion $ToolVersion -Command $commandName -Code 3 -Message $_.Exception.Message
    } else {
      Write-Error $_.Exception.Message -ErrorAction Continue
    }
    exit 3
  }

  if ($doVersion) {
    Write-VersionInfo -ToolVersion $ToolVersion -Data $data -Format $Format
    exit 0
  }

  if ($Resolve) {
    $entry = Resolve-VersionEntry -Name $Name -Data $data
    if ($null -eq $entry) {
      if ($Format -eq 'json') {
        Write-JsonError -ToolVersion $ToolVersion -Command 'resolve' -Code 4 -Message "Alias not found: $Name"
      } else {
        Write-Error "Alias not found: $Name" -ErrorAction Continue
      }
      exit 4
    }
    Write-ResolveOutput -Entry $entry -ToolVersion $ToolVersion -Format $Format
    exit 0
  }

  if ($ListKnown) {
    Write-ListKnownOutput -Data $data -ToolVersion $ToolVersion -Format $Format
    exit 0
  }

  if ($DetectInstalled) {
    $installations = $null
    try {
      $installations = @($data.versions | ForEach-Object {
        if ($BuildSystem -eq 'DCC') {
          Get-DccReadiness -Entry $_ -Platform $Platform
        } else {
          Get-MSBuildReadiness -Entry $_ -Platform $Platform
        }
      })
    } catch {
      if ($Format -eq 'json') {
        Write-JsonError -ToolVersion $ToolVersion -Command 'detectInstalled' -Code 5 -Message "Registry access failed: $($_.Exception.Message)"
      } else {
        Write-Error "Registry access failed: $($_.Exception.Message)" -ErrorAction Continue
      }
      exit 5
    }
    # @() forces empty array -- Where-Object returns $null under StrictMode when no matches
    $anyFound = @($installations | Where-Object { $_.readiness -in @('ready', 'partialInstall') }).Count -gt 0
    Write-DetectInstalledOutput -Installations $installations -Platform $Platform -BuildSystem $BuildSystem -ToolVersion $ToolVersion -Format $Format
    if (-not $anyFound) { exit 6 }
    exit 0
  }

  exit 0
} catch {
  if ($Format -eq 'json') {
    Write-JsonError -ToolVersion $ToolVersion -Command $commandName -Code 1 -Message $_.Exception.Message
  } else {
    Write-Error $_.Exception.Message -ErrorAction Continue
  }
  exit 1
}