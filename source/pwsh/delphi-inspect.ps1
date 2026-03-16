<#
delphi-inspect.ps1

Minimal V1:
- Loads the Delphi compiler versions dataset JSON.
- Prints tool version + dataset metadata.

ASCII-only.

USAGE
  pwsh ./source/delphi-inspect.ps1
  pwsh ./source/delphi-inspect.ps1 -Version
  pwsh ./source/delphi-inspect.ps1 -Version -Format json
  pwsh ./source/delphi-inspect.ps1 -Resolve -Name <alias>
  pwsh ./source/delphi-inspect.ps1 -Resolve <alias>
  pwsh ./source/delphi-inspect.ps1 -Resolve -Name <alias> -Format json
  pwsh ./source/delphi-inspect.ps1 -DataFile <path>
  pwsh ./source/delphi-inspect.ps1 -DetectLatest -Platform Win32 -BuildSystem DCC
  pwsh ./source/delphi-inspect.ps1 -DetectLatest -Platform Win32 -BuildSystem DCC -Format json
  pwsh ./source/delphi-inspect.ps1 -ListInstalled -Platform Win32 -BuildSystem DCC
  pwsh ./source/delphi-inspect.ps1 -ListInstalled -Platform Win32 -BuildSystem DCC -Readiness all
  pwsh ./source/delphi-inspect.ps1 -ListInstalled -Platform Win32 -BuildSystem DCC -Readiness partialInstall

NOTES
  Default behavior is equivalent to -Version.
  This is intentional: future action switches will short-circuit -Version output.

  -Resolve looks up an alias or VER### string in the dataset (case-insensitive)
  and prints the canonical entry fields.  Exit 4 when the alias is not found.

  -DetectLatest scans all dataset entries and returns the single highest-versioned
  entry whose readiness is 'ready' for the specified platform and build system.
  Exit 0 on success; exit 6 when no ready installation exists.

  -Format selects output format.  Valid values: object (default), text, json.
    object -- emit PowerShell objects to the pipeline (default; best for scripting)
    text   -- human-readable formatted output
    json   -- machine envelope with ok/command/tool/result structure
  Error envelopes substitute result with error: { code, message }.  Unknown format
  values are rejected by the parameter binder (ValidateSet).

  -Readiness (ListInstalled only) filters results by readiness state.
  Default is @('ready').  Use -Readiness all to include all states.
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

  [Parameter(ParameterSetName='ListInstalled', Mandatory=$true)]
  [switch]$ListInstalled,

  [Parameter(ParameterSetName='DetectLatest', Mandatory=$true)]
  [switch]$DetectLatest,

  [Parameter(ParameterSetName='ListInstalled', Mandatory=$true)]
  [Parameter(ParameterSetName='DetectLatest')]
  [ValidateSet('Win32', 'Win64', 'macOS32', 'macOS64', 'macOSARM64', 'Linux64', 'iOS32', 'iOSSimulator32', 'iOS64', 'iOSSimulator64', 'Android32', 'Android64')]
  [string]$Platform = 'Win32',

  [Parameter(ParameterSetName='ListInstalled', Mandatory=$true)]
  [Parameter(ParameterSetName='DetectLatest')]
  [ValidateSet('DCC', 'MSBuild')]
  [string]$BuildSystem = 'MSBuild',

  [Parameter(ParameterSetName='ListInstalled')]
  [ValidateSet('ready', 'partialInstall', 'notFound', 'notApplicable', 'all')]
  [string[]]$Readiness = @('ready'),

  [Parameter()]
  [string]$DataFile,

  [Parameter()]
  [ValidateSet('text', 'json', 'object')]
  [string]$Format = 'object'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Tool version (bump per Continuous Delphi versioning policy for tooling)
$ToolVersion = '0.1.0'

# Exit code constants -- single source of truth for the exit code contract.
$ExitSuccess              = 0   # normal completion
$ExitUnexpectedError      = 1   # unhandled exception or PS binder failure
$ExitInvalidArguments     = 2   # reserved; not currently used
$ExitDatasetError         = 3   # data file missing or unparseable
$ExitAliasNotFound        = 4   # -Resolve name not in dataset
$ExitRegistryError        = 5   # -ListInstalled registry access failure
$ExitNoInstallationsFound = 6   # -ListInstalled: no ready/partial entries

# Platform -> compiler base-name map; shared by Get-DccReadiness and Get-MSBuildReadiness.
$script:CompilerMap = @{
  'Win32'        = 'dcc32'
  'Win64'        = 'dcc64'
  'macOS32'      = 'dccosx'
  'macOS64'      = 'dccosx64'
  'macOSARM64'   = 'dccosxarm64'
  'Linux64'      = 'dcclinux64'
  'iOS32'          = 'dcciosarm'
  'iOSSimulator32' = 'dccios32'
  'iOS64'          = 'dcciosarm64'
  'iOSSimulator64' = 'dcciossimarm64'
  'Android32'    = 'dccaarm'
  'Android64'    = 'dccaarm64'
}

function Resolve-DefaultDataFilePath {
  param([string]$ScriptPath)

  if ([string]::IsNullOrWhiteSpace($ScriptPath) -or -not (Test-Path -LiteralPath $ScriptPath)) {
    throw "Resolve-DefaultDataFilePath: ScriptPath is missing or does not exist: '$ScriptPath'"
  }

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
  $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8NoBOM
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
    tool    = [pscustomobject]@{ name = 'delphi-inspect'; impl = 'pwsh'; version = $ToolVersion }
    error   = [pscustomobject]@{ code = $Code; message = $Message }
  } )
}

function Write-VersionInfo {
  param(
    [string]$ToolVersion,
    [psobject]$Data,
    [string]$Format = 'object'
  )

  $schemaVersion = $Data.schemaVersion
  $dataVersion   = $Data.dataVersion

  # generated date lives under meta.generatedUtcDate in our dataset
  $generated = $null
  if ($null -ne $Data.meta -and $null -ne $Data.meta.generatedUtcDate) {
    $generated = $Data.meta.generatedUtcDate
  }

  if ($Format -eq 'object') {
    Write-Output ([pscustomobject]@{
      schemaVersion    = $schemaVersion
      dataVersion      = $dataVersion
      generatedUtcDate = $generated
    })
    return
  }

  if ($Format -eq 'json') {
    Write-JsonOutput ([pscustomobject]@{
      ok      = $true
      command = 'version'
      tool    = [pscustomobject]@{ name = 'delphi-inspect'; impl = 'pwsh'; version = $ToolVersion }
      result  = [pscustomobject]@{
        schemaVersion      = $schemaVersion
        dataVersion        = $dataVersion
        generatedUtcDate   = $generated
      }
    } )
    return
  }

  Write-Output ("delphi-inspect {0}" -f $ToolVersion)
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
    [string]$Format = 'object'
  )

  if ($Format -eq 'object') {
    Write-Output ([pscustomobject]@{
      verDefine          = $Entry.verDefine
      productName        = $Entry.productName
      compilerVersion    = $Entry.compilerVersion
      packageVersion     = $Entry.packageVersion
      regKeyRelativePath = $Entry.regKeyRelativePath
      aliases            = $Entry.aliases
    })
    return
  }

  if ($Format -eq 'json') {
    Write-JsonOutput ([pscustomobject]@{
      ok      = $true
      command = 'resolve'
      tool    = [pscustomobject]@{ name = 'delphi-inspect'; impl = 'pwsh'; version = $ToolVersion }
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
  if ($null -ne $Entry.aliases -and $Entry.aliases.Count -gt 0) {
    Write-Output ("aliases             {0}" -f ($Entry.aliases -join ', '))
  }
}

function Write-ListKnownOutput {
  param(
    [psobject]$Data,
    [string]$ToolVersion = '',
    [string]$Format = 'object'
  )

  if ($Format -eq 'object') {
    foreach ($entry in $Data.versions) {
      Write-Output ([pscustomobject]@{
        verDefine          = $entry.verDefine
        productName        = $entry.productName
        compilerVersion    = $entry.compilerVersion
        packageVersion     = $entry.packageVersion
        regKeyRelativePath = $entry.regKeyRelativePath
        aliases            = $entry.aliases
        notes              = $entry.notes
      })
    }
    return
  }

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
      tool    = [pscustomobject]@{ name = 'delphi-inspect'; impl = 'pwsh'; version = $ToolVersion }
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
    [xml]$xml = Get-Content -LiteralPath $Path -Raw -Encoding UTF8NoBOM
    # RAD Studio uses 'DelphiLibraryPath' for all platforms (Win32, Win64, etc.).
    # Platform differentiation is in the PropertyGroup Condition attributes, not
    # the element name.  'DelphiLibraryPathWin64' does not exist in practice.
    $nodes = $xml.SelectNodes("//*[local-name()='DelphiLibraryPath']")
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
  $compilerExe = "$($script:CompilerMap[$Platform]).exe"
  $cfgFile     = "$($script:CompilerMap[$Platform]).cfg"

  $result = [pscustomobject]@{
    verDefine     = $Entry.verDefine
    productName   = $Entry.productName
    readiness     = 'notFound'
    registryFound = $null
    rootDir       = $null
    rootDirExists = $null
    compilerFound = $null
    cfgFound      = $null
  }

  if ($null -eq $Entry.supportedBuildSystems -or $null -eq $Entry.supportedPlatforms) {
    Write-Warning "Entry '$($Entry.verDefine)' is missing supportedBuildSystems or supportedPlatforms -- treating as notApplicable"
    $result.readiness = 'notApplicable'
    return $result
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

  $compilerBinFolder = if ($script:CompilerMap[$Platform].EndsWith('64')) { 'bin64' } else { 'bin' }
  $compilerBinPath   = Join-Path $rootDir $compilerBinFolder
  $result.registryFound = $true
  $result.rootDir       = $rootDir
  $result.rootDirExists = Test-Path -LiteralPath $rootDir
  $result.compilerFound = Test-Path -LiteralPath (Join-Path $compilerBinPath $compilerExe)
  $result.cfgFound      = Test-Path -LiteralPath (Join-Path $compilerBinPath $cfgFile)

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

  $compilerExe = "$($script:CompilerMap[$Platform]).exe"

  $result = [pscustomobject]@{
    verDefine                = $Entry.verDefine
    productName              = $Entry.productName
    readiness                = 'notFound'
    registryFound            = $null
    rootDir                  = $null
    rsvarsPath               = $null
    rootDirExists            = $null
    rsvarsFound              = $null
    compilerFound            = $null
    envOptionsFound          = $null
    envOptionsHasLibraryPath = $null
  }

  if ($null -eq $Entry.supportedBuildSystems -or $null -eq $Entry.supportedPlatforms) {
    Write-Warning "Entry '$($Entry.verDefine)' is missing supportedBuildSystems or supportedPlatforms -- treating as notApplicable"
    $result.readiness = 'notApplicable'
    return $result
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

  $binPath           = Join-Path $rootDir 'bin'
  $compilerBinFolder = if ($script:CompilerMap[$Platform].EndsWith('64')) { 'bin64' } else { 'bin' }
  $compilerBinPath   = Join-Path $rootDir $compilerBinFolder
  $bdsVersion = Split-Path -Leaf $Entry.regKeyRelativePath
  $envOptPath = Join-Path $env:APPDATA 'Embarcadero' 'BDS' $bdsVersion 'EnvOptions.proj'

  $result.registryFound   = $true
  $result.rootDir         = $rootDir
  $result.rsvarsPath      = Join-Path $binPath 'rsvars.bat'
  $result.rootDirExists   = Test-Path -LiteralPath $rootDir
  $result.rsvarsFound     = Test-Path -LiteralPath $result.rsvarsPath
  $result.compilerFound   = Test-Path -LiteralPath (Join-Path $compilerBinPath $compilerExe)
  $result.envOptionsFound = Test-Path -LiteralPath $envOptPath

  if ($result.envOptionsFound) {
    $result.envOptionsHasLibraryPath = Test-EnvOptionsLibraryPath -Path $envOptPath -Platform $Platform
  }

  if ($result.rootDirExists -and $result.rsvarsFound -and $result.compilerFound -and $result.envOptionsFound -and $result.envOptionsHasLibraryPath) {
    $result.readiness = 'ready'
  } else {
    $result.readiness = 'partialInstall'
  }

  return $result
}

function Write-ListInstalledOutput {
  param(
    [object[]]$Installations,
    [string]$Platform,
    [string]$BuildSystem,
    [string]$ToolVersion = '',
    [string]$Format = 'object'
  )

  if ($Format -eq 'object') {
    foreach ($inst in $Installations) { Write-Output $inst }
    return
  }

  if ($Format -eq 'json') {
    $items = @($Installations | ForEach-Object {
      $inst = $_
      if ($BuildSystem -eq 'DCC') {
        [pscustomobject]@{
          verDefine     = $inst.verDefine
          productName   = $inst.productName
          readiness     = $inst.readiness
          registryFound = $inst.registryFound
          rootDir       = $inst.rootDir
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
          rootDir                  = $inst.rootDir
          rsvarsPath               = $inst.rsvarsPath
          rootDirExists            = $inst.rootDirExists
          rsvarsFound              = $inst.rsvarsFound
          compilerFound            = $inst.compilerFound
          envOptionsFound          = $inst.envOptionsFound
          envOptionsHasLibraryPath = $inst.envOptionsHasLibraryPath
        }
      }
    })
    Write-JsonOutput ([pscustomobject]@{
      ok      = $true
      command = 'listInstalled'
      tool    = [pscustomobject]@{ name = 'delphi-inspect'; impl = 'pwsh'; version = $ToolVersion }
      result  = [pscustomobject]@{
        platform      = $Platform
        buildSystem   = $BuildSystem
        installations = $items
      }
    })
    return
  }

  # Text format: emit everything received (filtering is done by the caller via -Readiness)
  # @() ensures Count is available even when $Installations binds as $null under StrictMode
  if (@($Installations).Count -eq 0) {
    Write-Output 'No installations found'
    return
  }

  $firstBlock = $true
  foreach ($inst in $Installations) {
    if (-not $firstBlock) { Write-Output '' }
    $firstBlock = $false

    $regFoundStr    = if ($null -ne $inst.registryFound)  { $inst.registryFound.ToString().ToLower()  } else { 'null' }
    $rootExistsStr  = if ($null -ne $inst.rootDirExists)   { $inst.rootDirExists.ToString().ToLower()   } else { 'null' }
    Write-Output ("{0,-10} {1}" -f $inst.verDefine, $inst.productName)
    Write-Output ("  {0,-26}{1}" -f 'readiness', $inst.readiness)
    Write-Output ("  {0,-26}{1}" -f 'registryFound', $regFoundStr)
    Write-Output ("  {0,-26}{1}" -f 'rootDirExists', $rootExistsStr)
    if ($BuildSystem -eq 'DCC') {
      $compFoundStr = if ($null -ne $inst.compilerFound) { $inst.compilerFound.ToString().ToLower() } else { 'null' }
      $cfgFoundStr  = if ($null -ne $inst.cfgFound)      { $inst.cfgFound.ToString().ToLower()      } else { 'null' }
      Write-Output ("  {0,-26}{1}" -f 'compilerFound', $compFoundStr)
      Write-Output ("  {0,-26}{1}" -f 'cfgFound', $cfgFoundStr)
    } else {
      $rsvFoundStr    = if ($null -ne $inst.rsvarsFound)              { $inst.rsvarsFound.ToString().ToLower()              } else { 'null' }
      $compFoundStr   = if ($null -ne $inst.compilerFound)            { $inst.compilerFound.ToString().ToLower()            } else { 'null' }
      $envOptFoundStr = if ($null -ne $inst.envOptionsFound)          { $inst.envOptionsFound.ToString().ToLower()          } else { 'null' }
      $hasLibStr      = if ($null -ne $inst.envOptionsHasLibraryPath) { $inst.envOptionsHasLibraryPath.ToString().ToLower() } else { 'null' }
      Write-Output ("  {0,-26}{1}" -f 'rsvarsFound', $rsvFoundStr)
      Write-Output ("  {0,-26}{1}" -f 'compilerFound', $compFoundStr)
      Write-Output ("  {0,-26}{1}" -f 'envOptionsFound', $envOptFoundStr)
      Write-Output ("  {0,-26}{1}" -f 'envOptionsHasLibraryPath', $hasLibStr)
    }
  }
}

function Write-DetectLatestOutput {
  param(
    [object]$Installation,
    [string]$Platform,
    [string]$BuildSystem,
    [string]$ToolVersion = '',
    [string]$Format = 'object'
  )

  if ($Format -eq 'object') {
    if ($null -ne $Installation) { Write-Output $Installation }
    return
  }

  if ($Format -eq 'json') {
    $instObj = $null
    if ($null -ne $Installation) {
      if ($BuildSystem -eq 'DCC') {
        $instObj = [pscustomobject]@{
          verDefine     = $Installation.verDefine
          productName   = $Installation.productName
          readiness     = $Installation.readiness
          registryFound = $Installation.registryFound
          rootDir       = $Installation.rootDir
          rootDirExists = $Installation.rootDirExists
          compilerFound = $Installation.compilerFound
          cfgFound      = $Installation.cfgFound
        }
      } else {
        $instObj = [pscustomobject]@{
          verDefine                = $Installation.verDefine
          productName              = $Installation.productName
          readiness                = $Installation.readiness
          registryFound            = $Installation.registryFound
          rootDir                  = $Installation.rootDir
          rsvarsPath               = $Installation.rsvarsPath
          rootDirExists            = $Installation.rootDirExists
          rsvarsFound              = $Installation.rsvarsFound
          compilerFound            = $Installation.compilerFound
          envOptionsFound          = $Installation.envOptionsFound
          envOptionsHasLibraryPath = $Installation.envOptionsHasLibraryPath
        }
      }
    }
    Write-JsonOutput ([pscustomobject]@{
      ok      = $true
      command = 'detectLatest'
      tool    = [pscustomobject]@{ name = 'delphi-inspect'; impl = 'pwsh'; version = $ToolVersion }
      result  = [pscustomobject]@{
        platform     = $Platform
        buildSystem  = $BuildSystem
        installation = $instObj
      }
    })
    return
  }

  if ($null -eq $Installation) {
    Write-Output 'No ready installation found'
    return
  }

  Write-Output ("{0,-10} {1}" -f $Installation.verDefine, $Installation.productName)
  Write-Output ("  {0,-26}{1}" -f 'readiness', $Installation.readiness)
  Write-Output ("  {0,-26}{1}" -f 'registryFound', $Installation.registryFound.ToString().ToLower())
  Write-Output ("  {0,-26}{1}" -f 'rootDir', $Installation.rootDir)
  Write-Output ("  {0,-26}{1}" -f 'rootDirExists', $Installation.rootDirExists.ToString().ToLower())
  if ($BuildSystem -eq 'DCC') {
    Write-Output ("  {0,-26}{1}" -f 'compilerFound', $Installation.compilerFound.ToString().ToLower())
    Write-Output ("  {0,-26}{1}" -f 'cfgFound', $Installation.cfgFound.ToString().ToLower())
  } else {
    Write-Output ("  {0,-26}{1}" -f 'rsvarsPath', $Installation.rsvarsPath)
    Write-Output ("  {0,-26}{1}" -f 'rsvarsFound', $Installation.rsvarsFound.ToString().ToLower())
    $compFoundStr = if ($null -ne $Installation.compilerFound) { $Installation.compilerFound.ToString().ToLower() } else { 'null' }
    Write-Output ("  {0,-26}{1}" -f 'compilerFound', $compFoundStr)
    Write-Output ("  {0,-26}{1}" -f 'envOptionsFound', $Installation.envOptionsFound.ToString().ToLower())
    $hasLibStr = if ($null -ne $Installation.envOptionsHasLibraryPath) { $Installation.envOptionsHasLibraryPath.ToString().ToLower() } else { 'null' }
    Write-Output ("  {0,-26}{1}" -f 'envOptionsHasLibraryPath', $hasLibStr)
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
  if (-not $doVersion -and -not $Resolve -and -not $ListKnown -and -not $ListInstalled -and -not $DetectLatest) { $doVersion = $true }
  $commandName = if ($Resolve) { 'resolve' } elseif ($ListKnown) { 'listKnown' } elseif ($ListInstalled) { 'listInstalled' } elseif ($DetectLatest) { 'detectLatest' } else { 'version' }

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
      Write-JsonError -ToolVersion $ToolVersion -Command $commandName -Code $ExitDatasetError -Message $_.Exception.Message
    } else {
      Write-Error $_.Exception.Message -ErrorAction Continue
    }
    exit $ExitDatasetError
  }

  if ($doVersion) {
    Write-VersionInfo -ToolVersion $ToolVersion -Data $data -Format $Format
    exit $ExitSuccess
  }

  if ($Resolve) {
    $entry = Resolve-VersionEntry -Name $Name -Data $data
    if ($null -eq $entry) {
      if ($Format -eq 'json') {
        Write-JsonError -ToolVersion $ToolVersion -Command 'resolve' -Code $ExitAliasNotFound -Message "Alias not found: $Name"
      } else {
        Write-Error "Alias not found: $Name" -ErrorAction Continue
      }
      exit $ExitAliasNotFound
    }
    Write-ResolveOutput -Entry $entry -ToolVersion $ToolVersion -Format $Format
    exit $ExitSuccess
  }

  if ($ListKnown) {
    Write-ListKnownOutput -Data $data -ToolVersion $ToolVersion -Format $Format
    exit $ExitSuccess
  }

  if ($ListInstalled) {
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
        Write-JsonError -ToolVersion $ToolVersion -Command 'listInstalled' -Code $ExitRegistryError -Message "Registry access failed: $($_.Exception.Message)"
      } else {
        Write-Error "Registry access failed: $($_.Exception.Message)" -ErrorAction Continue
      }
      exit $ExitRegistryError
    }
    if ('all' -in $Readiness) {
      $filtered = @($installations)
    } else {
      $filtered = @($installations | Where-Object { $_.readiness -in $Readiness })
    }
    Write-ListInstalledOutput -Installations $filtered -Platform $Platform -BuildSystem $BuildSystem -ToolVersion $ToolVersion -Format $Format
    if ($filtered.Count -eq 0) { exit $ExitNoInstallationsFound }
    exit $ExitSuccess
  }

  if ($DetectLatest) {
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
        Write-JsonError -ToolVersion $ToolVersion -Command 'detectLatest' -Code $ExitRegistryError -Message "Registry access failed: $($_.Exception.Message)"
      } else {
        Write-Error "Registry access failed: $($_.Exception.Message)" -ErrorAction Continue
      }
      exit $ExitRegistryError
    }
    # @() forces empty array -- Where-Object returns $null under StrictMode when no matches
    $readyEntries = @($installations | Where-Object { $_.readiness -eq 'ready' })
    $latest = if ($readyEntries.Count -gt 0) { $readyEntries[-1] } else { $null }
    Write-DetectLatestOutput -Installation $latest -Platform $Platform -BuildSystem $BuildSystem -ToolVersion $ToolVersion -Format $Format
    if ($null -eq $latest) { exit $ExitNoInstallationsFound }
    exit $ExitSuccess
  }

  exit $ExitSuccess
} catch {
  if ($Format -eq 'json') {
    Write-JsonError -ToolVersion $ToolVersion -Command $commandName -Code $ExitUnexpectedError -Message $_.Exception.Message
  } else {
    Write-Error $_.Exception.Message -ErrorAction Continue
  }
  exit $ExitUnexpectedError
}
