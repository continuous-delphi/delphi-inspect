<#
 -----------------------------------------------------------------------------
 delphi-inspect

 A PowerShell utility for deterministic Delphi toolchain discovery and normalization.

 Part of Continuous-Delphi: Strengthening Delphi's continued success
 https://github.com/continuous-delphi

 Project repository:
 https://github.com/continuous-delphi/delphi-inspect

 Includes canonical compiler version data from:
 https://github.com/continuous-delphi/delphi-compiler-versions

 Copyright (c) 2026 Darian Miller
 Licensed under the MIT License.
 https://opensource.org/licenses/MIT
 SPDX-License-Identifier: MIT
 -----------------------------------------------------------------------------

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
  pwsh ./source/delphi-inspect.ps1 -Locate -Name <alias>
  pwsh ./source/delphi-inspect.ps1 -Locate <alias>
  pwsh ./source/delphi-inspect.ps1 -Locate -Name <alias> -Format json
  pwsh ./source/delphi-inspect.ps1 -ListInstalled -Platform Win32 -BuildSystem DCC
  pwsh ./source/delphi-inspect.ps1 -ListInstalled -Platform Win32 -BuildSystem DCC -Readiness all
  pwsh ./source/delphi-inspect.ps1 -ListInstalled -Platform Win32 -BuildSystem DCC -Readiness partialInstall

NOTES
  Default behavior is equivalent to -Version.
  This is intentional: future action switches will short-circuit -Version output.

  -Resolve looks up an alias or VER### string in the dataset (case-insensitive)
  and prints the canonical entry fields.  Exit 4 when the alias is not found.

  -Locate looks up an alias or VER### string (same matching as -Resolve) and
  returns the RootDir of the installed version from the registry.
  Exit 4 when the alias is not found in the dataset.
  Exit 6 when the version is not installed (registry entry absent or RootDir empty).

  -DetectLatest scans all dataset entries and returns the single highest-versioned
  entry whose readiness is 'ready' for the specified platform and build system.
  Exit 0 on success; exit 6 when no ready installation exists.

  Dataset resolution order when -DataFile is not supplied:
    1. <scriptDir>/delphi-compiler-versions.json  (sibling / standalone deployment)
    2. <repoRoot>/submodules/delphi-compiler-versions/data/delphi-compiler-versions.json
    3. $EmbeddedData compiled into the script (run tools/Update-EmbeddedData.ps1 to refresh)
  The first path that exists on disk is used.  If neither file is found the
  script falls back to the embedded dataset, making it fully self-contained.

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
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'ExitInvalidArguments',
  Justification='Reserved exit code constant; not yet referenced in code paths')]
param(
  [Parameter(ParameterSetName='Version')]
  [switch]$Version,

  [Parameter(ParameterSetName='Resolve', Mandatory=$true)]
  [switch]$Resolve,

  [Parameter(ParameterSetName='Locate', Mandatory=$true)]
  [switch]$Locate,

  [Parameter(ParameterSetName='Resolve', Mandatory=$true, Position=0)]
  [Parameter(ParameterSetName='Locate',  Mandatory=$true, Position=0)]
  [string]$Name,

  [Parameter(ParameterSetName='ListKnown')]
  [switch]$ListKnown,

  [Parameter(ParameterSetName='ListInstalled', Mandatory=$true)]
  [switch]$ListInstalled,

  [Parameter(ParameterSetName='DetectLatest', Mandatory=$true)]
  [switch]$DetectLatest,

  [Parameter(ParameterSetName='ListInstalled', Mandatory=$true)]
  [Parameter(ParameterSetName='DetectLatest')]
  [ValidateSet('Win32', 'Win64', 'WinARM64EC', 'macOS32', 'macOS64', 'macOSARM64', 'Linux64', 'iOS32', 'iOSSimulator32', 'iOS64', 'iOSSimulator64', 'Android32', 'Android64')]
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

# Tool version
$ToolVersion = '1.3.0'

# Exit code constants -- single source of truth for the exit code contract.
$ExitSuccess              = 0   # normal completion
$ExitUnexpectedError      = 1   # unhandled exception or PS binder failure
$ExitInvalidArguments     = 2   # reserved; not currently used
$ExitDatasetError         = 3   # data file missing or unparseable
$ExitAliasNotFound        = 4   # -Resolve name not in dataset
$ExitRegistryError        = 5   # -ListInstalled registry access failure
$ExitNoInstallationsFound = 6   # -ListInstalled: no ready/partial entries

# BEGIN-CD-HOSTLOG
# -----------------------------------------------------------------------------
# Write-CDHostLog v0.1.0
# Source: https://github.com/continuous-delphi/delphi-logger
#
# Universal output function for Continuous-Delphi PowerShell tooling.
# Opt-in structured logging via ContinuousDelphi.Logger module.
# See: https://github.com/continuous-delphi/delphi-logger/docs/output-modes.md
# -----------------------------------------------------------------------------

# Logger detection -- check once at load time whether the caller has loaded
# ContinuousDelphi.Logger. If so, structured events are emitted alongside
# native PowerShell stream output. If not, Write-CDHostLog routes to native
# Write-Output / Write-Verbose / Write-Host / Write-Warning / Write-Error only.
$script:LoggerAvailable = [bool](Get-Module -Name 'ContinuousDelphi.Logger')
$script:LoggerCaptureOutput = if ($script:LoggerAvailable) {
  $script:CDLoggerState = (Get-Module -Name 'ContinuousDelphi.Logger').SessionState.PSVariable.GetValue('CDLoggerState')
  if ($null -ne $script:CDLoggerState) { $script:CDLoggerState.CaptureOutput } else { $false }
} else { $false }

function Write-CDHostLog {
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification='Write-Host is used intentionally for Info/Success level output to stream 6 without polluting the pipeline')]
  param(
    [Parameter(Mandatory)]
    $Message,

    [ValidateSet('Output','Trace','Debug','Verbose','Info','Success','Warning','Error','Fatal')]
    [string]$Level = 'Info',

    [string]$EventId,
    [hashtable]$Data,

    [switch]$LogOnly
  )

  # Write to native PowerShell stream (unless LogOnly)
  if (-not $LogOnly) {
    switch ($Level) {
      'Output' {
        Write-Output $Message
      }
      { $_ -in 'Trace','Debug','Verbose' } {
        Write-Verbose $Message
      }
      { $_ -in 'Info','Success' } {
        Write-Host $Message
      }
      'Warning' {
        Write-Warning $Message
      }
      { $_ -in 'Error','Fatal' } {
        Write-Error $Message -ErrorAction Continue
      }
    }
  }

  # Also emit structured log event if logger available
  if ($script:LoggerAvailable) {
    $msgStr = [string]$Message
    if ([string]::IsNullOrWhiteSpace($msgStr)) { return }
    if ($Level -eq 'Output') {
      if (-not $script:LoggerCaptureOutput) { return }
      $logLevel = 'Info'
    } else {
      $logLevel = $Level
    }
    $params = @{ Level = $logLevel; Message = $msgStr }
    if ($EventId) { $params.EventId = $EventId }
    if ($Data)    { $params.Data = $Data }
    Write-CDLogEvent @params
  }
}

function Complete-CDActivity {
  param(
    [int]$ExitCode,
    [string]$Command,
    [string]$Message
  )
  if (-not $script:LoggerAvailable) { return }
  $result = New-CDActivityResult `
    -ToolVersion $ToolVersion `
    -Activity $Command `
    -ExitCode $ExitCode `
    -Message $Message
  Write-Information -MessageData $result -Tags @('CDLog', 'ActivityResult')
}
# END-CD-HOSTLOG

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

# Embedded dataset -- fallback used when no data file is found on disk.
# Run tools/update-delphi-compiler-versions-json.ps1 to refresh from the submodule.
# BEGIN-DELPHI-COMPILER-VERSIONS-JSON
$EmbeddedData = @'
{
  "$schema": "https://continuous-delphi.github.io/delphi-compiler-versions/schemas/1.2.0/delphi-compiler-versions.schema.json",
  "schemaVersion": "1.2.0",
  "dataVersion": "1.2.0",
  "meta": {
    "generatedUtcDate": "2026-03-21",
    "scope": {
      "includeFromVer": "VER90",
      "excluded": [
        "C++Builder-only entries",
        ".NET-only Delphi entries"
      ]
    },
    "registryResolutionNotes": [
      "regKeyRelativePath is hive-agnostic. Discovery tooling should check HKCU first, then HKLM.",
      "Installation directory is typically available under <key>\\RootDir for Delphi 5+; Delphi 2-4 do not set RootDir."
    ],
    "platformNotes": [
      "supportedPlatforms represents the union of all platforms across all point releases within a version family.",
      "See individual entry notes for platforms introduced in sub-version point releases.",
      "Tooling should check supportedBuildSystems and supportedPlatforms before assessing installation readiness.",
      "Return notApplicable readiness when the requested buildSystem or platform is absent from the supported arrays."
    ],
    "project": {
      "name": "delphi-compiler-versions",
      "repository": "https://github.com/continuous-delphi/delphi-compiler-versions",
      "organization": "https://github.com/continuous-delphi",
      "maintainers": [
        {
          "name": "Darian Miller",
          "role": "primary",
          "url": "https://github.com/darianmiller"
        }
      ]
    },
    "description": {
      "summary": "Canonical Delphi compiler version mapping based on official VER### symbols.",
      "purpose": "Provides a single source of truth for Delphi compiler version detection across tooling, CI, and code generation."
    },
    "license": {
      "name": "MIT",
      "spdx": "MIT",
      "url": "https://opensource.org/licenses/MIT"
    }
  },
  "versions": [
    {
      "verDefine": "VER90",
      "compilerVersion": "9.0",
      "productName": "Delphi 2",
      "packageVersion": "20",
      "regKeyRelativePath": "\\Software\\Borland\\Delphi\\2.0",
      "supportedBuildSystems": ["DCC"],
      "supportedPlatforms": ["Win32"],
      "aliases": ["Delphi2", "D2"],
      "notes": [
        "Delphi 2 installs do not record RootDir in the registry; discovery may require manual configuration.",
        "CompilerVersion constant not available at runtime; compilerVersion value is inferred."
      ]
    },
    {
      "verDefine": "VER100",
      "compilerVersion": "10.0",
      "productName": "Delphi 3",
      "packageVersion": "30",
      "regKeyRelativePath": "\\Software\\Borland\\Delphi\\3.0",
      "supportedBuildSystems": ["DCC"],
      "supportedPlatforms": ["Win32"],
      "aliases": ["Delphi3", "D3"],
      "notes": [
        "Delphi 3 installs do not record RootDir in the registry; discovery may require manual configuration.",
        "CompilerVersion constant not available at runtime; compilerVersion value is inferred."
      ]
    },
    {
      "verDefine": "VER120",
      "compilerVersion": "12.0",
      "productName": "Delphi 4",
      "packageVersion": "40",
      "regKeyRelativePath": "\\Software\\Borland\\Delphi\\4.0",
      "supportedBuildSystems": ["DCC"],
      "supportedPlatforms": ["Win32"],
      "aliases": ["Delphi4", "D4"],
      "notes": [
        "Delphi 4 installs do not record RootDir in the registry; discovery may require manual configuration.",
        "CompilerVersion constant not available at runtime; compilerVersion value is inferred."
      ]
    },
    {
      "verDefine": "VER130",
      "compilerVersion": "13.0",
      "productName": "Delphi 5",
      "packageVersion": "50",
      "regKeyRelativePath": "\\Software\\Borland\\Delphi\\5.0",
      "supportedBuildSystems": ["DCC"],
      "supportedPlatforms": ["Win32"],
      "aliases": ["Delphi5", "D5"],
      "notes": [
        "CompilerVersion constant not available at runtime; compilerVersion value is inferred."
      ]
    },
    {
      "verDefine": "VER140",
      "compilerVersion": "14.0",
      "productName": "Delphi 6",
      "packageVersion": "60",
      "regKeyRelativePath": "\\Software\\Borland\\Delphi\\6.0",
      "supportedBuildSystems": ["DCC"],
      "supportedPlatforms": ["Win32"],
      "aliases": ["Delphi6", "D6"],
      "notes": []
    },
    {
      "verDefine": "VER150",
      "compilerVersion": "15.0",
      "productName": "Delphi 7",
      "packageVersion": "70",
      "regKeyRelativePath": "\\Software\\Borland\\Delphi\\7.0",
      "supportedBuildSystems": ["DCC"],
      "supportedPlatforms": ["Win32"],
      "aliases": ["Delphi7", "D7"],
      "notes": []
    },
    {
      "verDefine": "VER170",
      "compilerVersion": "17.0",
      "productName": "Delphi 2005",
      "packageVersion": "90",
      "regKeyRelativePath": "\\Software\\Borland\\BDS\\3.0",
      "supportedBuildSystems": ["DCC"],
      "supportedPlatforms": ["Win32"],
      "aliases": ["Delphi2005", "D2005"],
      "notes": []
    },
    {
      "verDefine": "VER180",
      "compilerVersion": "18.0",
      "productName": "Delphi 2006",
      "packageVersion": "100",
      "regKeyRelativePath": "\\Software\\Borland\\BDS\\4.0",
      "supportedBuildSystems": ["DCC"],
      "supportedPlatforms": ["Win32"],
      "aliases": ["Delphi2006", "D2006"],
      "notes": ["Delphi 2007 also defines VER180 (shared with Delphi 2006). Use VER185 for 2007-only identification."]
    },
    {
      "verDefine": "VER185",
      "compilerVersion": "18.5",
      "productName": "Delphi 2007",
      "packageVersion": "110",
      "regKeyRelativePath": "\\Software\\Borland\\BDS\\5.0",
      "supportedBuildSystems": ["DCC", "MSBuild"],
      "supportedPlatforms": ["Win32"],
      "aliases": ["Delphi2007", "D2007"],
      "notes": [
        "Delphi 2007 also defines VER180 (shared with Delphi 2006). Use VER185 for 2007-only identification.",
        "First version to support MSBuild via .dproj project files."
      ]
    },
    {
      "verDefine": "VER200",
      "compilerVersion": "20.0",
      "productName": "Delphi 2009",
      "packageVersion": "120",
      "regKeyRelativePath": "\\Software\\CodeGear\\BDS\\6.0",
      "supportedBuildSystems": ["DCC", "MSBuild"],
      "supportedPlatforms": ["Win32"],
      "aliases": ["Delphi2009", "D2009"],
      "notes": []
    },
    {
      "verDefine": "VER210",
      "compilerVersion": "21.0",
      "productName": "Delphi 2010",
      "packageVersion": "140",
      "regKeyRelativePath": "\\Software\\CodeGear\\BDS\\7.0",
      "supportedBuildSystems": ["DCC", "MSBuild"],
      "supportedPlatforms": ["Win32"],
      "aliases": ["Delphi2010", "D2010"],
      "notes": []
    },
    {
      "verDefine": "VER220",
      "compilerVersion": "22.0",
      "productName": "Delphi XE",
      "packageVersion": "150",
      "regKeyRelativePath": "\\Software\\Embarcadero\\BDS\\8.0",
      "supportedBuildSystems": ["DCC", "MSBuild"],
      "supportedPlatforms": ["Win32"],
      "aliases": ["DelphiXE", "XE"],
      "notes": []
    },
    {
      "verDefine": "VER230",
      "compilerVersion": "23.0",
      "productName": "Delphi XE2",
      "packageVersion": "160",
      "regKeyRelativePath": "\\Software\\Embarcadero\\BDS\\9.0",
      "supportedBuildSystems": ["DCC", "MSBuild"],
      "supportedPlatforms": ["Win32", "Win64", "macOS32"],
      "aliases": ["DelphiXE2", "XE2"],
      "notes": [
        "First version to support Win64, and macOS 32-bit targets (experimental iOS32 not included)",
        "DocWiki notes FireMonkey package versions 160/161 for XE2 updates; packageVersion here reflects the main table value."
      ]
    },
    {
      "verDefine": "VER240",
      "compilerVersion": "24.0",
      "productName": "Delphi XE3",
      "packageVersion": "170",
      "regKeyRelativePath": "\\Software\\Embarcadero\\BDS\\10.0",
      "supportedBuildSystems": ["DCC", "MSBuild"],
      "supportedPlatforms": ["Win32", "Win64", "macOS32"],
      "aliases": ["DelphiXE3", "XE3"],
      "notes": ["Experimental iOS32 support not included in supportedPlatforms"]
    },
    {
      "verDefine": "VER250",
      "compilerVersion": "25.0",
      "productName": "Delphi XE4",
      "packageVersion": "180",
      "regKeyRelativePath": "\\Software\\Embarcadero\\BDS\\11.0",
      "supportedBuildSystems": ["DCC", "MSBuild"],
      "supportedPlatforms": ["Win32", "Win64", "macOS32", "iOS32", "iOSSimulator32"],
      "aliases": ["DelphiXE4", "XE4"],
      "notes": [
        "First version to support full iOS device/simulator/App Store deployment (experimental Android not included)."
      ]
    },
    {
      "verDefine": "VER260",
      "compilerVersion": "26.0",
      "productName": "Delphi XE5",
      "packageVersion": "190",
      "regKeyRelativePath": "\\Software\\Embarcadero\\BDS\\12.0",
      "supportedBuildSystems": ["DCC", "MSBuild"],
      "supportedPlatforms": ["Win32", "Win64", "macOS32", "iOS32", "iOSSimulator32", "Android32"],
      "aliases": ["DelphiXE5", "XE5"],
      "notes": ["First version to support Android 32-bit"]
    },
    {
      "verDefine": "VER270",
      "compilerVersion": "27.0",
      "productName": "Delphi XE6",
      "packageVersion": "200",
      "regKeyRelativePath": "\\Software\\Embarcadero\\BDS\\14.0",
      "supportedBuildSystems": ["DCC", "MSBuild"],
      "supportedPlatforms": ["Win32", "Win64", "macOS32", "iOS32", "iOSSimulator32", "Android32"],
      "aliases": ["DelphiXE6", "XE6"],
      "notes": [
        "Product version jumps from 12.0 to 14.0 in the DocWiki table (skip 'unlucky 13')."
      ]
    },
    {
      "verDefine": "VER280",
      "compilerVersion": "28.0",
      "productName": "Delphi XE7",
      "packageVersion": "210",
      "regKeyRelativePath": "\\Software\\Embarcadero\\BDS\\15.0",
      "supportedBuildSystems": ["DCC", "MSBuild"],
      "supportedPlatforms": ["Win32", "Win64", "macOS32", "iOS32", "iOSSimulator32", "Android32"],
      "aliases": ["DelphiXE7", "XE7"],
      "notes": []
    },
    {
      "verDefine": "VER290",
      "compilerVersion": "29.0",
      "productName": "Delphi XE8",
      "packageVersion": "220",
      "regKeyRelativePath": "\\Software\\Embarcadero\\BDS\\16.0",
      "supportedBuildSystems": ["DCC", "MSBuild"],
      "supportedPlatforms": ["Win32", "Win64", "macOS32", "macOS64", "iOS32", "iOSSimulator32", "Android32"],
      "aliases": ["DelphiXE8", "XE8"],
      "notes": [
        "First version to support macOS 64-bit (Intel)."
      ]
    },
    {
      "verDefine": "VER300",
      "compilerVersion": "30.0",
      "productName": "Delphi 10 Seattle",
      "packageVersion": "230",
      "regKeyRelativePath": "\\Software\\Embarcadero\\BDS\\17.0",
      "supportedBuildSystems": ["DCC", "MSBuild"],
      "supportedPlatforms": ["Win32", "Win64", "macOS32", "macOS64", "iOS32", "iOSSimulator32", "iOS64", "Android32"],
      "aliases": ["Delphi 10", "Seattle", "10 Seattle"],
      "notes": []
    },
    {
      "verDefine": "VER310",
      "compilerVersion": "31.0",
      "productName": "Delphi 10.1 Berlin",
      "packageVersion": "240",
      "regKeyRelativePath": "\\Software\\Embarcadero\\BDS\\18.0",
      "supportedBuildSystems": ["DCC", "MSBuild"],
      "supportedPlatforms": ["Win32", "Win64", "macOS32", "macOS64", "iOS32", "iOSSimulator32", "iOS64", "Android32"],
      "aliases": ["Delphi 10.1", "Berlin", "10.1 Berlin"],
      "notes": []
    },
    {
      "verDefine": "VER320",
      "compilerVersion": "32.0",
      "productName": "Delphi 10.2 Tokyo",
      "packageVersion": "250",
      "regKeyRelativePath": "\\Software\\Embarcadero\\BDS\\19.0",
      "supportedBuildSystems": ["DCC", "MSBuild"],
      "supportedPlatforms": ["Win32", "Win64", "macOS32", "macOS64", "iOS32", "iOSSimulator32", "iOS64", "Android32", "Linux64"],
      "aliases": ["Delphi 10.2", "Tokyo", "10.2 Tokyo"],
      "notes": [
        "First version to support Linux 64-bit."
      ]
    },
    {
      "verDefine": "VER330",
      "compilerVersion": "33.0",
      "productName": "Delphi 10.3 Rio",
      "packageVersion": "260",
      "regKeyRelativePath": "\\Software\\Embarcadero\\BDS\\20.0",
      "supportedBuildSystems": ["DCC", "MSBuild"],
      "supportedPlatforms": ["Win32", "Win64", "macOS64", "iOS32", "iOSSimulator32", "iOS64", "Android32", "Android64", "Linux64"],
      "aliases": ["Delphi 10.3", "Rio", "10.3 Rio"],
      "notes": [
        "macOS 32-bit dropped in this version family (Catalina removed 32-bit app support at the OS level).",
        "macOS 64-bit (Intel) added in 10.3 Update 2 (point release); 10.3.0 and 10.3.1 do not include macOS 64-bit.",
        "Android 64-bit added in 10.3 Update 3 (point release); earlier 10.3.x releases do not include Android 64-bit."
      ]
    },
    {
      "verDefine": "VER340",
      "compilerVersion": "34.0",
      "productName": "Delphi 10.4 Sydney",
      "packageVersion": "270",
      "regKeyRelativePath": "\\Software\\Embarcadero\\BDS\\21.0",
      "supportedBuildSystems": ["DCC", "MSBuild"],
      "supportedPlatforms": ["Win32", "Win64", "macOS64", "iOS32", "iOS64", "Android32", "Android64", "Linux64"],
      "aliases": ["Delphi 10.4", "Sydney", "10.4 Sydney"],
      "notes": ["Apple removed 32-bit simulator support from Xcode, effectively killing iOSSimulator32"]
    },
    {
      "verDefine": "VER350",
      "compilerVersion": "35.0",
      "productName": "Delphi 11 Alexandria",
      "packageVersion": "280",
      "regKeyRelativePath": "\\Software\\Embarcadero\\BDS\\22.0",
      "supportedBuildSystems": ["DCC", "MSBuild"],
      "supportedPlatforms": ["Win32", "Win64", "macOS64", "macOSARM64", "iOS32", "iOS64", "iOSSimulator64", "Android32", "Android64", "Linux64"],
      "aliases": ["Delphi 11", "Alexandria", "11 Alexandria"],
      "notes": [
        "First version to support macOS ARM64 (Apple Silicon).",
        "11.2 added iOS Simulator ARM 64-bit"
      ]
    },
    {
      "verDefine": "VER360",
      "compilerVersion": "36.0",
      "productName": "Delphi 12 Athens",
      "packageVersion": "290",
      "regKeyRelativePath": "\\Software\\Embarcadero\\BDS\\23.0",
      "supportedBuildSystems": ["DCC", "MSBuild"],
      "supportedPlatforms": ["Win32", "Win64", "macOS64", "macOSARM64", "iOS64", "iOSSimulator64", "Android32", "Android64", "Linux64"],
      "aliases": ["Delphi 12", "Athens", "12 Athens"],
      "notes": []
    },
    {
      "verDefine": "VER370",
      "compilerVersion": "37.0",
      "productName": "Delphi 13 Florence",
      "packageVersion": "370",
      "regKeyRelativePath": "\\Software\\Embarcadero\\BDS\\37.0",
      "supportedBuildSystems": ["DCC", "MSBuild"],
      "supportedPlatforms": ["Win32", "Win64", "macOS64", "macOSARM64", "iOS64", "iOSSimulator64", "Android32", "Android64", "Linux64", "WinARM64EC"],
      "aliases": ["Delphi 13", "Florence", "13 Florence"],
      "notes": [
        "RAD Studio 13 unifies internal version numbers to 37 (registry, RTL, packages).",
        "Update 1 for RAD Studio 13 Florence added support for WinARM64EC"
      ]
    }
  ]
}
'@
# END-DELPHI-COMPILER-VERSIONS-JSON

function Resolve-DefaultDataFilePath {
  param([string]$ScriptPath)

  if ([string]::IsNullOrWhiteSpace($ScriptPath) -or -not (Test-Path -LiteralPath $ScriptPath)) {
    throw "Resolve-DefaultDataFilePath: ScriptPath is missing or does not exist: '$ScriptPath'"
  }

  $scriptDir = Split-Path -Parent $ScriptPath

  # Candidate 1 (preferred): sibling file next to the script
  #   <scriptDir>/delphi-compiler-versions.json
  # Checked first so a locally deployed dataset takes precedence over the submodule.
  $siblingPath = Join-Path $scriptDir 'delphi-compiler-versions.json'
  Write-CDHostLog -Level Verbose -Message "Dataset candidate 1 (sibling): $siblingPath"

  if (Test-Path -LiteralPath $siblingPath) {
    Write-CDHostLog -Level Verbose -Message "Dataset resolved to sibling file"
    return $siblingPath
  }

  # Candidate 2: submodule layout relative to repo root
  #   <repoRoot>/submodules/delphi-compiler-versions/data/delphi-compiler-versions.json
  # Use Join-Path to remain path-separator-safe if invoked on non-Windows runners.
  $repoRoot      = Split-Path $scriptDir -Parent
  $specRoot      = Join-Path (Join-Path $repoRoot 'submodules') 'delphi-compiler-versions'
  $submodulePath = Join-Path (Join-Path $specRoot 'data') 'delphi-compiler-versions.json'
  Write-CDHostLog -Level Verbose -Message "Dataset candidate 2 (submodule): $submodulePath"

  if (Test-Path -LiteralPath $submodulePath) {
    Write-CDHostLog -Level Verbose -Message "Dataset resolved to submodule file"
    return $submodulePath
  }

  # Neither found: return $null to signal the caller to use embedded data.
  Write-CDHostLog -Level Verbose -Message "No external dataset found; will use embedded data"
  return $null
}

function Import-JsonData {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Data file not found: $Path"
  }

  Write-CDHostLog -Level Verbose -Message "Loading dataset from: $Path"
  # Use -Raw to avoid array-of-lines behavior
  $text = Get-Content -LiteralPath $Path -Raw
  try {
    $parsed = $text | ConvertFrom-Json
    $versionCount = if ($null -ne $parsed.versions) { @($parsed.versions).Count } else { 0 }
    Write-CDHostLog -Level Verbose -Message "Dataset loaded: $versionCount version entries" -Data @{ path = $Path; versionCount = $versionCount }
    return $parsed
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
  Write-CDHostLog -Level Output -Message ($Object | ConvertTo-Json -Depth 10 -Compress)
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
    tool    = [pscustomobject]@{ name = 'delphi-inspect'; version = $ToolVersion }
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
    Write-CDHostLog -Level Output -Message ([pscustomobject]@{
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
      tool    = [pscustomobject]@{ name = 'delphi-inspect'; version = $ToolVersion }
      result  = [pscustomobject]@{
        schemaVersion      = $schemaVersion
        dataVersion        = $dataVersion
        generatedUtcDate   = $generated
      }
    } )
    return
  }

  Write-CDHostLog -Level Output -Message ("delphi-inspect {0}" -f $ToolVersion)
  Write-CDHostLog -Level Output -Message ("dataVersion     {0}" -f $dataVersion)
  Write-CDHostLog -Level Output -Message ("schemaVersion   {0}" -f $schemaVersion)
  if (-not [string]::IsNullOrWhiteSpace($generated)) {
    Write-CDHostLog -Level Output -Message ("generated       {0}" -f $generated)
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
    Write-CDHostLog -Level Output -Message ([pscustomobject]@{
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
      tool    = [pscustomobject]@{ name = 'delphi-inspect'; version = $ToolVersion }
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
  Write-CDHostLog -Level Output -Message ("verDefine           {0}" -f $Entry.verDefine)
  Write-CDHostLog -Level Output -Message ("productName         {0}" -f $Entry.productName)
  Write-CDHostLog -Level Output -Message ("compilerVersion     {0}" -f $Entry.compilerVersion)
  if (-not [string]::IsNullOrWhiteSpace($Entry.packageVersion)) {
    Write-CDHostLog -Level Output -Message ("packageVersion      {0}" -f $Entry.packageVersion)
  }
  if (-not [string]::IsNullOrWhiteSpace($Entry.regKeyRelativePath)) {
    Write-CDHostLog -Level Output -Message ("regKeyRelativePath  {0}" -f $Entry.regKeyRelativePath)
  }
  if ($null -ne $Entry.aliases -and $Entry.aliases.Count -gt 0) {
    Write-CDHostLog -Level Output -Message ("aliases             {0}" -f ($Entry.aliases -join ', '))
  }
}

function Write-LocateOutput {
  param(
    [psobject]$Entry,
    [string]$RootDir,
    [string]$ToolVersion = '',
    [string]$Format = 'object'
  )

  if ($Format -eq 'object') {
    Write-CDHostLog -Level Output -Message ([pscustomobject]@{
      verDefine   = $Entry.verDefine
      productName = $Entry.productName
      rootDir     = $RootDir
    })
    return
  }

  if ($Format -eq 'json') {
    Write-JsonOutput ([pscustomobject]@{
      ok      = $true
      command = 'locate'
      tool    = [pscustomobject]@{ name = 'delphi-inspect'; version = $ToolVersion }
      result  = [pscustomobject]@{
        verDefine   = $Entry.verDefine
        productName = $Entry.productName
        rootDir     = $RootDir
      }
    })
    return
  }

  # text format -- label column matches -Resolve at 20 chars
  Write-CDHostLog -Level Output -Message ("verDefine           {0}" -f $Entry.verDefine)
  Write-CDHostLog -Level Output -Message ("productName         {0}" -f $Entry.productName)
  Write-CDHostLog -Level Output -Message ("rootDir             {0}" -f $RootDir)
}

function Write-ListKnownOutput {
  param(
    [psobject]$Data,
    [string]$ToolVersion = '',
    [string]$Format = 'object'
  )

  if ($Format -eq 'object') {
    foreach ($entry in $Data.versions) {
      Write-CDHostLog -Level Output -Message ([pscustomobject]@{
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
      tool    = [pscustomobject]@{ name = 'delphi-inspect'; version = $ToolVersion }
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
    Write-CDHostLog -Level Output -Message ("{0,-12}{1,-10}{2,-6}{3}" -f `
      $entry.verDefine, $entry.compilerVersion, $entry.packageVersion, $entry.productName)
  }
}

function Get-RegistryRootDir {
  param([string]$RelativePath)

  $subKey = $RelativePath.TrimStart('\')

  foreach ($hive in @([Microsoft.Win32.RegistryHive]::CurrentUser, [Microsoft.Win32.RegistryHive]::LocalMachine)) {
    $hiveName = if ($hive -eq [Microsoft.Win32.RegistryHive]::CurrentUser) { 'HKCU' } else { 'HKLM' }
    $baseKey = $null
    $regKey  = $null
    try {
      $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey($hive, [Microsoft.Win32.RegistryView]::Registry32)
      $regKey  = $baseKey.OpenSubKey($subKey)
      if ($null -ne $regKey) {
        $val = $regKey.GetValue('RootDir')
        if (-not [string]::IsNullOrWhiteSpace([string]$val)) {
          Write-CDHostLog -Level Debug -Message "Registry RootDir found in ${hiveName}: $subKey = $val"
          return [string]$val
        }
        Write-CDHostLog -Level Debug -Message "Registry key found in ${hiveName}: $subKey but RootDir is empty"
      } else {
        Write-CDHostLog -Level Debug -Message "Registry key not found in ${hiveName}: $subKey"
      }
    } finally {
      if ($null -ne $regKey)  { $regKey.Close()  }
      if ($null -ne $baseKey) { $baseKey.Close() }
    }
  }
  Write-CDHostLog -Level Debug -Message "Registry RootDir not found in any hive: $subKey"
  return $null
}

function Test-EnvOptionsLibraryPath {
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Platform',
    Justification='Platform differentiation is in the XML Condition attributes, not the element name; parameter kept for interface consistency')]
  param(
    [string]$Path,
    [string]$Platform
  )

  try {
    [xml]$xml = Get-Content -LiteralPath $Path -Raw
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
    Write-CDHostLog -Level Warning -Message "Entry '$($Entry.verDefine)' is missing supportedBuildSystems or supportedPlatforms -- treating as notApplicable"
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

  Write-CDHostLog -Level Debug -Message "DCC readiness: $($Entry.verDefine) = $($result.readiness)" `
    -Data @{ verDefine = $Entry.verDefine; readiness = $result.readiness; platform = $Platform }
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
    Write-CDHostLog -Level Warning -Message "Entry '$($Entry.verDefine)' is missing supportedBuildSystems or supportedPlatforms -- treating as notApplicable"
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
  $envOptPath = Join-Path (Join-Path (Join-Path (Join-Path $env:APPDATA 'Embarcadero') 'BDS') $bdsVersion) 'EnvOptions.proj'

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

  Write-CDHostLog -Level Debug -Message "MSBuild readiness: $($Entry.verDefine) = $($result.readiness)" `
    -Data @{ verDefine = $Entry.verDefine; readiness = $result.readiness; platform = $Platform }
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
    foreach ($inst in $Installations) { Write-CDHostLog -Level Output -Message $inst }
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
      tool    = [pscustomobject]@{ name = 'delphi-inspect'; version = $ToolVersion }
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
    Write-CDHostLog -Level Output -Message 'No installations found'
    return
  }

  $firstBlock = $true
  foreach ($inst in $Installations) {
    if (-not $firstBlock) { Write-CDHostLog -Level Output -Message '' }
    $firstBlock = $false

    $regFoundStr    = if ($null -ne $inst.registryFound)  { $inst.registryFound.ToString().ToLower()  } else { 'null' }
    $rootDirStr     = if ($null -ne $inst.rootDir)         { $inst.rootDir                              } else { 'null' }
    $rootExistsStr  = if ($null -ne $inst.rootDirExists)   { $inst.rootDirExists.ToString().ToLower()   } else { 'null' }
    Write-CDHostLog -Level Output -Message ("{0,-10} {1}" -f $inst.verDefine, $inst.productName)
    Write-CDHostLog -Level Output -Message ("  {0,-26}{1}" -f 'readiness', $inst.readiness)
    Write-CDHostLog -Level Output -Message ("  {0,-26}{1}" -f 'registryFound', $regFoundStr)
    Write-CDHostLog -Level Output -Message ("  {0,-26}{1}" -f 'rootDir', $rootDirStr)
    Write-CDHostLog -Level Output -Message ("  {0,-26}{1}" -f 'rootDirExists', $rootExistsStr)
    if ($BuildSystem -eq 'DCC') {
      $compFoundStr = if ($null -ne $inst.compilerFound) { $inst.compilerFound.ToString().ToLower() } else { 'null' }
      $cfgFoundStr  = if ($null -ne $inst.cfgFound)      { $inst.cfgFound.ToString().ToLower()      } else { 'null' }
      Write-CDHostLog -Level Output -Message ("  {0,-26}{1}" -f 'compilerFound', $compFoundStr)
      Write-CDHostLog -Level Output -Message ("  {0,-26}{1}" -f 'cfgFound', $cfgFoundStr)
    } else {
      $rsvPathStr     = if ($null -ne $inst.rsvarsPath)               { $inst.rsvarsPath                                    } else { 'null' }
      $rsvFoundStr    = if ($null -ne $inst.rsvarsFound)              { $inst.rsvarsFound.ToString().ToLower()              } else { 'null' }
      $compFoundStr   = if ($null -ne $inst.compilerFound)            { $inst.compilerFound.ToString().ToLower()            } else { 'null' }
      $envOptFoundStr = if ($null -ne $inst.envOptionsFound)          { $inst.envOptionsFound.ToString().ToLower()          } else { 'null' }
      $hasLibStr      = if ($null -ne $inst.envOptionsHasLibraryPath) { $inst.envOptionsHasLibraryPath.ToString().ToLower() } else { 'null' }
      Write-CDHostLog -Level Output -Message ("  {0,-26}{1}" -f 'rsvarsPath', $rsvPathStr)
      Write-CDHostLog -Level Output -Message ("  {0,-26}{1}" -f 'rsvarsFound', $rsvFoundStr)
      Write-CDHostLog -Level Output -Message ("  {0,-26}{1}" -f 'compilerFound', $compFoundStr)
      Write-CDHostLog -Level Output -Message ("  {0,-26}{1}" -f 'envOptionsFound', $envOptFoundStr)
      Write-CDHostLog -Level Output -Message ("  {0,-26}{1}" -f 'envOptionsHasLibraryPath', $hasLibStr)
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
    if ($null -ne $Installation) { Write-CDHostLog -Level Output -Message $Installation }
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
      tool    = [pscustomobject]@{ name = 'delphi-inspect'; version = $ToolVersion }
      result  = [pscustomobject]@{
        platform     = $Platform
        buildSystem  = $BuildSystem
        installation = $instObj
      }
    })
    return
  }

  if ($null -eq $Installation) {
    Write-CDHostLog -Level Output -Message 'No ready installation found'
    return
  }

  Write-CDHostLog -Level Output -Message ("{0,-10} {1}" -f $Installation.verDefine, $Installation.productName)
  Write-CDHostLog -Level Output -Message ("  {0,-26}{1}" -f 'readiness', $Installation.readiness)
  Write-CDHostLog -Level Output -Message ("  {0,-26}{1}" -f 'registryFound', $Installation.registryFound.ToString().ToLower())
  Write-CDHostLog -Level Output -Message ("  {0,-26}{1}" -f 'rootDir', $Installation.rootDir)
  Write-CDHostLog -Level Output -Message ("  {0,-26}{1}" -f 'rootDirExists', $Installation.rootDirExists.ToString().ToLower())
  if ($BuildSystem -eq 'DCC') {
    Write-CDHostLog -Level Output -Message ("  {0,-26}{1}" -f 'compilerFound', $Installation.compilerFound.ToString().ToLower())
    Write-CDHostLog -Level Output -Message ("  {0,-26}{1}" -f 'cfgFound', $Installation.cfgFound.ToString().ToLower())
  } else {
    Write-CDHostLog -Level Output -Message ("  {0,-26}{1}" -f 'rsvarsPath', $Installation.rsvarsPath)
    Write-CDHostLog -Level Output -Message ("  {0,-26}{1}" -f 'rsvarsFound', $Installation.rsvarsFound.ToString().ToLower())
    $compFoundStr = if ($null -ne $Installation.compilerFound) { $Installation.compilerFound.ToString().ToLower() } else { 'null' }
    Write-CDHostLog -Level Output -Message ("  {0,-26}{1}" -f 'compilerFound', $compFoundStr)
    Write-CDHostLog -Level Output -Message ("  {0,-26}{1}" -f 'envOptionsFound', $Installation.envOptionsFound.ToString().ToLower())
    $hasLibStr = if ($null -ne $Installation.envOptionsHasLibraryPath) { $Installation.envOptionsHasLibraryPath.ToString().ToLower() } else { 'null' }
    Write-CDHostLog -Level Output -Message ("  {0,-26}{1}" -f 'envOptionsHasLibraryPath', $hasLibStr)
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
  if (-not $doVersion -and -not $Resolve -and -not $Locate -and -not $ListKnown -and -not $ListInstalled -and -not $DetectLatest) { $doVersion = $true }
  $commandName = if ($Resolve) { 'resolve' } elseif ($Locate) { 'locate' } elseif ($ListKnown) { 'listKnown' } elseif ($ListInstalled) { 'listInstalled' } elseif ($DetectLatest) { 'detectLatest' } else { 'version' }
  Write-CDHostLog -Level Verbose -Message "Command: $commandName, Format: $Format"

  $useEmbedded = $false
  if ([string]::IsNullOrWhiteSpace($DataFile)) {
    $resolvedPath = Resolve-DefaultDataFilePath -ScriptPath $scriptPath
    if ($null -ne $resolvedPath) {
      $DataFile = $resolvedPath
    } else {
      $useEmbedded = $true
    }
  }

  # NOTE: dataset errors exit here directly (exit 3) rather than propagating
  # to the outer catch.  As more exit codes are added, consider extracting the
  # dispatch block into an Invoke-Main function that returns an exit code, with
  # a single exit at the script's top level.  That eliminates scattered exit
  # calls and makes the code table easy to audit in one place.
  try {
    if ($useEmbedded) {
      Write-CDHostLog -Level Verbose -Message "Using embedded dataset"
    }
    $data = if ($useEmbedded) {
      $EmbeddedData | ConvertFrom-Json
    } else {
      Import-JsonData -Path $DataFile
    }
  } catch {
    if ($Format -eq 'json') {
      Write-JsonError -ToolVersion $ToolVersion -Command $commandName -Code $ExitDatasetError -Message $_.Exception.Message
    } else {
      Write-CDHostLog -Level Error -Message $_.Exception.Message -EventId 'DATASET-ERROR'
    }
    Complete-CDActivity -ExitCode $ExitDatasetError -Command $commandName -Message $_.Exception.Message
    exit $ExitDatasetError
  }

  if ($doVersion) {
    Write-VersionInfo -ToolVersion $ToolVersion -Data $data -Format $Format
    Complete-CDActivity -ExitCode $ExitSuccess -Command 'version'
    exit $ExitSuccess
  }

  if ($Resolve) {
    $entry = Resolve-VersionEntry -Name $Name -Data $data
    if ($null -eq $entry) {
      if ($Format -eq 'json') {
        Write-JsonError -ToolVersion $ToolVersion -Command 'resolve' -Code $ExitAliasNotFound -Message "Alias not found: $Name"
      } else {
        Write-CDHostLog -Level Error -Message "Alias not found: $Name" -EventId 'ALIAS-NOT-FOUND'
      }
      Complete-CDActivity -ExitCode $ExitAliasNotFound -Command 'resolve' -Message "Alias not found: $Name"
      exit $ExitAliasNotFound
    }
    Write-ResolveOutput -Entry $entry -ToolVersion $ToolVersion -Format $Format
    Complete-CDActivity -ExitCode $ExitSuccess -Command 'resolve'
    exit $ExitSuccess
  }

  if ($Locate) {
    $entry = Resolve-VersionEntry -Name $Name -Data $data
    if ($null -eq $entry) {
      if ($Format -eq 'json') {
        Write-JsonError -ToolVersion $ToolVersion -Command 'locate' -Code $ExitAliasNotFound -Message "Alias not found: $Name"
      } else {
        Write-CDHostLog -Level Error -Message "Alias not found: $Name" -EventId 'ALIAS-NOT-FOUND'
      }
      Complete-CDActivity -ExitCode $ExitAliasNotFound -Command 'locate' -Message "Alias not found: $Name"
      exit $ExitAliasNotFound
    }
    if ([string]::IsNullOrWhiteSpace($entry.regKeyRelativePath)) {
      if ($Format -eq 'json') {
        Write-JsonError -ToolVersion $ToolVersion -Command 'locate' -Code $ExitNoInstallationsFound -Message "No registry path known for: $Name"
      } else {
        Write-CDHostLog -Level Error -Message "No registry path known for: $Name" -EventId 'NO-REGISTRY-PATH'
      }
      Complete-CDActivity -ExitCode $ExitNoInstallationsFound -Command 'locate' -Message "No registry path known for: $Name"
      exit $ExitNoInstallationsFound
    }
    $rootDir = $null
    try {
      $rootDir = Get-RegistryRootDir -RelativePath $entry.regKeyRelativePath
    } catch {
      if ($Format -eq 'json') {
        Write-JsonError -ToolVersion $ToolVersion -Command 'locate' -Code $ExitRegistryError -Message "Registry access failed: $($_.Exception.Message)"
      } else {
        Write-CDHostLog -Level Error -Message "Registry access failed: $($_.Exception.Message)" -EventId 'REGISTRY-ERROR'
      }
      Complete-CDActivity -ExitCode $ExitRegistryError -Command 'locate' -Message "Registry access failed: $($_.Exception.Message)"
      exit $ExitRegistryError
    }
    if ($null -eq $rootDir) {
      if ($Format -eq 'json') {
        Write-JsonError -ToolVersion $ToolVersion -Command 'locate' -Code $ExitNoInstallationsFound -Message "Not installed: $Name"
      } else {
        Write-CDHostLog -Level Error -Message "Not installed: $Name" -EventId 'NOT-INSTALLED'
      }
      Complete-CDActivity -ExitCode $ExitNoInstallationsFound -Command 'locate' -Message "Not installed: $Name"
      exit $ExitNoInstallationsFound
    }
    Write-LocateOutput -Entry $entry -RootDir $rootDir -ToolVersion $ToolVersion -Format $Format
    Complete-CDActivity -ExitCode $ExitSuccess -Command 'locate'
    exit $ExitSuccess
  }

  if ($ListKnown) {
    Write-ListKnownOutput -Data $data -ToolVersion $ToolVersion -Format $Format
    Complete-CDActivity -ExitCode $ExitSuccess -Command 'listKnown'
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
        Write-CDHostLog -Level Error -Message "Registry access failed: $($_.Exception.Message)" -EventId 'REGISTRY-ERROR'
      }
      Complete-CDActivity -ExitCode $ExitRegistryError -Command 'listInstalled' -Message "Registry access failed: $($_.Exception.Message)"
      exit $ExitRegistryError
    }
    if ('all' -in $Readiness) {
      $filtered = @($installations)
    } else {
      $filtered = @($installations | Where-Object { $_.readiness -in $Readiness })
    }
    Write-ListInstalledOutput -Installations $filtered -Platform $Platform -BuildSystem $BuildSystem -ToolVersion $ToolVersion -Format $Format
    if ($filtered.Count -eq 0) {
      Complete-CDActivity -ExitCode $ExitNoInstallationsFound -Command 'listInstalled' -Message 'No installations found'
      exit $ExitNoInstallationsFound
    }
    Complete-CDActivity -ExitCode $ExitSuccess -Command 'listInstalled'
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
        Write-CDHostLog -Level Error -Message "Registry access failed: $($_.Exception.Message)" -EventId 'REGISTRY-ERROR'
      }
      Complete-CDActivity -ExitCode $ExitRegistryError -Command 'detectLatest' -Message "Registry access failed: $($_.Exception.Message)"
      exit $ExitRegistryError
    }
    # @() forces empty array -- Where-Object returns $null under StrictMode when no matches
    $readyEntries = @($installations | Where-Object { $_.readiness -eq 'ready' })
    $latest = if ($readyEntries.Count -gt 0) { $readyEntries[-1] } else { $null }
    Write-DetectLatestOutput -Installation $latest -Platform $Platform -BuildSystem $BuildSystem -ToolVersion $ToolVersion -Format $Format
    if ($null -eq $latest) {
      Complete-CDActivity -ExitCode $ExitNoInstallationsFound -Command 'detectLatest' -Message 'No ready installation found'
      exit $ExitNoInstallationsFound
    }
    Complete-CDActivity -ExitCode $ExitSuccess -Command 'detectLatest'
    exit $ExitSuccess
  }

  Complete-CDActivity -ExitCode $ExitSuccess -Command $commandName
  exit $ExitSuccess
} catch {
  $errMsg = if ([string]::IsNullOrWhiteSpace($_.Exception.Message)) { $_.ToString() } else { $_.Exception.Message }
  if ([string]::IsNullOrWhiteSpace($errMsg)) { $errMsg = 'Unknown error' }
  if ($Format -eq 'json') {
    Write-JsonError -ToolVersion $ToolVersion -Command $commandName -Code $ExitUnexpectedError -Message $errMsg
  } else {
    Write-CDHostLog -Level Fatal -Message $errMsg -EventId 'UNEXPECTED-ERROR'
  }
  Complete-CDActivity -ExitCode $ExitUnexpectedError -Command $commandName -Message $errMsg
  exit $ExitUnexpectedError
}
