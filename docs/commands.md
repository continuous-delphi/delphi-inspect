# delphi-toolchain-inspect Command Reference

This document describes the command-line interface for
`delphi-toolchain-inspect.ps1`.

------------------------------------------------------------------------

# Overview

`delphi-toolchain-inspect` provides four primary actions:

-   `-Version` --- Display tool and dataset metadata
-   `-Resolve` --- Resolve a Delphi alias or VER### constant to
    canonical version data
-   `-ListKnown` --- List all known Delphi versions from the dataset
-   `-DetectInstalled` --- Detect installed Delphi versions on this
    machine and report readiness for a specific platform and build
    system

By default, invoking the script with **no switches** performs the
`-Version` action.

------------------------------------------------------------------------

# Usage

    pwsh ./source/pwsh/delphi-toolchain-inspect.ps1 [action] [options]

------------------------------------------------------------------------

# Actions

## -Version

Display tool version and dataset metadata.

### Examples

    pwsh delphi-toolchain-inspect.ps1
    pwsh delphi-toolchain-inspect.ps1 -Version
    pwsh delphi-toolchain-inspect.ps1 -Version -Format json

### Output (text format, default)

Labels are left-padded to a fixed column width.

    delphi-toolchain-inspect 0.1.0
    dataVersion     0.1.0
    schemaVersion   1.0.0
    generated       2026-01-01

If `generatedUtcDate` is null, empty, or whitespace in the dataset,
the `generated` line is omitted.

### Output (json format)

    {
      "ok": true,
      "command": "version",
      "tool": {
        "name": "delphi-toolchain-inspect",
        "impl": "pwsh",
        "version": "0.1.0"
      },
      "result": {
        "schemaVersion": "1.0.0",
        "dataVersion": "0.1.0",
        "generatedUtcDate": "2026-01-01"
      }
    }

`generatedUtcDate` is always present in JSON output; it is `null`
when absent from the dataset.

------------------------------------------------------------------------

## -Resolve

Resolve a Delphi alias or VER### constant to its canonical dataset
entry.

### Syntax

    -Resolve <name>
    -Resolve -Name <name>

`-Name` is mandatory.  It may be supplied positionally (first argument
after `-Resolve`) or explicitly via `-Name`.  Omitting it is a
parameter binding error (exit code 1).

Matching is case-insensitive.  The lookup checks each entry in order:
`verDefine` (e.g. `VER150`), then `productName` (e.g. `Delphi 7`),
then the `aliases` array (e.g. `D7`, `Delphi 11`).  The first match
wins.

### Examples

    pwsh delphi-toolchain-inspect.ps1 -Resolve D7
    pwsh delphi-toolchain-inspect.ps1 -Resolve "Delphi 11"
    pwsh delphi-toolchain-inspect.ps1 -Resolve -Name VER150
    pwsh delphi-toolchain-inspect.ps1 -Resolve VER350 -Format json

### Output (text format, default)

Labels are left-padded to a 20-character column width.  Optional fields
that are null or empty in the dataset are omitted.

    verDefine           VER150
    productName         Delphi 7
    compilerVersion     15.0
    packageVersion      70
    regKeyRelativePath  \Software\Borland\Delphi\7.0
    aliases             VER150, Delphi7, D7

### Output (json format)

All `result` fields are always present regardless of null status.
Optional fields absent from the dataset appear as `null` rather than
being omitted.

    {
      "ok": true,
      "command": "resolve",
      "tool": {
        "name": "delphi-toolchain-inspect",
        "impl": "pwsh",
        "version": "0.1.0"
      },
      "result": {
        "verDefine": "VER150",
        "productName": "Delphi 7",
        "compilerVersion": "15.0",
        "packageVersion": "70",
        "regKeyRelativePath": "\\Software\\Borland\\Delphi\\7.0",
        "aliases": ["VER150", "Delphi7", "D7"]
      }
    }

------------------------------------------------------------------------

## -ListKnown

List all known Delphi versions from the dataset.

### Examples

    pwsh delphi-toolchain-inspect.ps1 -ListKnown
    pwsh delphi-toolchain-inspect.ps1 -ListKnown -Format json
    pwsh delphi-toolchain-inspect.ps1 -ListKnown -DataFile ./data/custom.json

### Output (text format, default)

One line per entry in fixed-width columns: verDefine (12), compilerVersion (10),
packageVersion (6), productName (trailing).

```text
VER90       9.0       20    Delphi 2
VER100      10.0      30    Delphi 3
VER120      12.0      40    Delphi 4
VER130      13.0      50    Delphi 5
VER140      14.0      60    Delphi 6
VER150      15.0      70    Delphi 7
VER170      17.0      90    Delphi 2005
VER180      18.0      100   Delphi 2006
VER185      18.5      110   Delphi 2007
VER200      20.0      120   Delphi 2009
VER210      21.0      140   Delphi 2010
VER220      22.0      150   Delphi XE
VER230      23.0      160   Delphi XE2
VER240      24.0      170   Delphi XE3
VER250      25.0      180   Delphi XE4
VER260      26.0      190   Delphi XE5
VER270      27.0      200   Delphi XE6
VER280      28.0      210   Delphi XE7
VER290      29.0      220   Delphi XE8
VER300      30.0      230   Delphi 10 Seattle
VER310      31.0      240   Delphi 10.1 Berlin
VER320      32.0      250   Delphi 10.2 Tokyo
VER330      33.0      260   Delphi 10.3 Rio
VER340      34.0      270   Delphi 10.4 Sydney
VER350      35.0      280   Delphi 11 Alexandria
VER360      36.0      290   Delphi 12 Athens
VER370      37.0      370   Delphi 13 Florence
```

### Output (json format)
_Only one entry shown in the example for brevity...
will actually have a `versions` entry for every item in the dataset_


    {
      "ok": true,
      "command": "listKnown",
      "tool": {
        "name": "delphi-toolchain-inspect",
        "impl": "pwsh",
        "version": "0.1.0"
      },
      "result": {
        "schemaVersion": "1.0.0",
        "dataVersion": "0.1.0",
        "generatedUtcDate": "2026-01-01",
        "versions": [
          {
            "verDefine": "VER150",
            "productName": "Delphi 7",
            "compilerVersion": "15.0",
            "packageVersion": "70",
            "regKeyRelativePath": "\\Software\\Borland\\Delphi\\7.0",
            "aliases": ["VER150", "Delphi7", "D7"],
            "notes": []
          }
        ]
      }
    }

All version entry fields are always present regardless of null status.

------------------------------------------------------------------------

## -DetectInstalled

Scan this machine for installed Delphi versions and report their
readiness for a specific platform and build system combination.

Both `-Platform` and `-BuildSystem` are mandatory.  The tool reports
readiness for just the provided combination. To assess multiple build
systems or platforms, invoke the command multiple times.

### Syntax

    -DetectInstalled -Platform <platform> -BuildSystem <buildSystem>

### Parameters

`-Platform` (mandatory)

Valid values: `Win32`, `Win64`

The target compilation platform to assess. 

`-BuildSystem` (mandatory)

Valid values: `DCC`, `MSBuild`

The build system to assess readiness for.

- `DCC` -- direct invocation of the command-line compiler
  (`dcc32.exe` or `dcc64.exe` depending on platform).  Requires the
  compiler binary and a correctly configured `.cfg` file.
- `MSBuild` -- MSBuild-based builds driven by `.dproj` files.
  Requires `rsvars.bat` and a correctly populated `EnvOptions.proj`
  in the expected `%APPDATA%` path for the current user.

### Platform support scope

Only `Win32` and `Win64` are currently supported.  Support for other
platforms (Linux64, macOS, Android, iOS) will be added in future
releases based on demand.

### Detection mechanism

Before performing any registry check, the tool consults the
`supportedBuildSystems` and `supportedPlatforms` arrays in the dataset
entry.  If the requested build system or platform is absent from the
entry's arrays, the entry is assigned `readiness: notApplicable` and
no registry access is attempted for that entry. (For example, `MSBuild`
is notApplicable for Delphi 3 and `Win64` is notApplicable for Delphi 7.)

Detection is otherwise registry-based.  The tool scans the Windows
registry under the following hive paths (HKCU checked before HKLM):

- Delphi 7 and earlier: `\Software\Borland\Delphi\<ProductVersion>`
- Delphi 2005 - 2007: `\Software\Borland\BDS\<bdsVersion>`
- Delphi 2009 - 2010: `\Software\CodeGear\BDS\<bdsVersion>`
- Delphi XE and later:  `\Software\Embarcadero\BDS\<bdsVersion>`

The `bdsVersion` value (e.g. `21.0`) is derived from the
`regKeyRelativePath` field in the dataset.  The `RootDir` registry
value under the key is the primary indicator of a valid installation.

Registry access uses the 32-bit registry view explicitly
(`RegistryView.Registry32`) to avoid WOW64 redirection issues on
64-bit Windows, which is a common source of silent detection failures.

**Limitation**: manual (xcopy) installations without registry entries
are not detected by this command.  If a registry entry is absent but
the compiler is known to be present, the installation will appear as
not found.  A future `-SearchPath` option may address this.

### Readiness states

Each dataset entry is assessed and assigned a `readiness` value:

- `ready` -- all required components appear to be present
- `partialInstall` -- registry found but one or more required
  components are missing or unverifiable
- `notFound` -- registry was checked but no entry was detected for
  this version
- `notApplicable` -- this version does not support the requested
  platform or build system; no registry check was performed

### DCC readiness components

When `-BuildSystem DCC` is specified, the following are assessed:

| Field            | Description                                              |
|------------------|----------------------------------------------------------|
| `registryFound`  | Registry key exists for this version                     |
| `rootDirExists`  | `RootDir` registry value resolves to an existing path    |
| `compilerFound`  | `dcc32.exe` (or `dcc64.exe`) exists under `<RootDir>\bin`|
| `cfgFound`       | `dcc32.cfg` (or `dcc64.cfg`) exists under `<RootDir>\bin`|

`ready` requires `rootDirExists`, `compilerFound`, and `cfgFound` to
all be true.

Note: the presence of the `.cfg` file does not validate that the
library paths within it are correct.  A `.cfg` with stale paths
(e.g. from a copied installation where paths were not updated) will
show `cfgFound: true` but builds will still fail with
`F1027 Unit not found: 'System.pas'`.  Path validation is currently
outside the scope of this command but may be considered in a future
update.

### MSBuild readiness components

When `-BuildSystem MSBuild` is specified, the following are assessed:

| Field                      | Description                                        |
|----------------------------|----------------------------------------------------|
| `registryFound`            | Registry key exists for this version               |
| `rootDirExists`            | `RootDir` registry value resolves to existing path |
| `rsvarsFound`              | `rsvars.bat` exists under `<RootDir>\bin`          |
| `envOptionsFound`          | `EnvOptions.proj` exists at the expected path      |
| `envOptionsHasLibraryPath` | `EnvOptions.proj` contains at least one non-empty  |
|                            | `DelphiLibraryPath` property for the target platform|

The expected `EnvOptions.proj` path is:

    %APPDATA%\Roaming\Embarcadero\BDS\<bdsVersion>\EnvOptions.proj

`ready` requires `rootDirExists`, `rsvarsFound`, `envOptionsFound`,
and `envOptionsHasLibraryPath` to all be true.

Note: if `EnvOptions.proj` is missing, MSBuild will emit a warning
(`Expected configuration file missing`) but will not fail immediately.
Builds that rely on third-party library paths will fail with
`F1026 File not found` errors that can be difficult to diagnose.
This is a common silent failure mode on manually configured build
servers.

### Examples

    pwsh delphi-toolchain-inspect.ps1 -DetectInstalled -Platform Win32 -BuildSystem DCC
    pwsh delphi-toolchain-inspect.ps1 -DetectInstalled -Platform Win64 -BuildSystem MSBuild
    pwsh delphi-toolchain-inspect.ps1 -DetectInstalled -Platform Win32 -BuildSystem DCC -Format json

### Output (text format, default)

Only entries with readiness `ready` or `partialInstall` are listed,
in dataset order.  Entries with readiness `notFound` or `notApplicable`
are silently omitted.  If no entries remain after filtering, a single
line is emitted:

    No installations found

Otherwise, one block per detected installation:

    VER340     Delphi 10.4 Sydney
      readiness                 ready
      registryFound             true
      rootDirExists             true
      compilerFound             true
      cfgFound                  true

    VER350     Delphi 11 Alexandria
      readiness                 partialInstall
      registryFound             true
      rootDirExists             true
      compilerFound             true
      cfgFound                  false

Versions with no registry entry are silently omitted from text output.
Use `-Format json` to see all known versions including those not found.

### Output (json format)

`installations` is always an array.  Every version known to the
dataset is present in the array.  Entries that were not checked appear
with null component fields; the `readiness` value distinguishes why:

- `notFound` -- registry was checked; `registryFound` is `false`
- `notApplicable` -- no check was performed; `registryFound` is `null`

Use `-Format json` to inspect which versions are `notApplicable` for
the requested platform or build system combination.

    {
      "ok": true,
      "command": "detectInstalled",
      "tool": {
        "name": "delphi-toolchain-inspect",
        "impl": "pwsh",
        "version": "0.1.0"
      },
      "result": {
        "platform": "Win32",
        "buildSystem": "DCC",
        "installations": [
          {
            "verDefine": "VER340",
            "productName": "Delphi 10.4 Sydney",
            "readiness": "ready",
            "registryFound": true,
            "rootDirExists": true,
            "compilerFound": true,
            "cfgFound": true
          },
          {
            "verDefine": "VER350",
            "productName": "Delphi 11 Alexandria",
            "readiness": "partialInstall",
            "registryFound": true,
            "rootDirExists": true,
            "compilerFound": true,
            "cfgFound": false
          },
          {
            "verDefine": "VER370",
            "productName": "Delphi 13 Florence",
            "readiness": "notFound",
            "registryFound": false,
            "rootDirExists": null,
            "compilerFound": null,
            "cfgFound": null
          }
        ]
      }
    }

For MSBuild, the component fields are `registryFound`, `rootDirExists`,
`rsvarsFound`, `envOptionsFound`, and `envOptionsHasLibraryPath`.
The `readiness` field is always present regardless of build system.

`platform` and `buildSystem` are always echoed back in the result so
consumers do not need to track what was requested.

------------------------------------------------------------------------

# Common Options

## -Format

Controls output format.

Valid values:

-   `text` (default)
-   `json`

Examples:

    -Format text
    -Format json

If an invalid value is supplied, PowerShell parameter binding fails
(exit code 1).

------------------------------------------------------------------------

## -DataFile

Override the default dataset path.

    -DataFile <path>

If omitted, the default submodule dataset path is used.

If the file does not exist or cannot be parsed, the tool exits with
code 3.

Note: `-DetectInstalled` uses the dataset to drive the list of versions
to scan for.  Supplying a custom `-DataFile` will limit detection to
the versions present in that file.

------------------------------------------------------------------------

# Parameter Rules

-   `-Version`, `-Resolve`, `-ListKnown`, and `-DetectInstalled` are
    mutually exclusive (enforced by PowerShell parameter sets; exit
    code 1 if more than one is supplied).
-   With no action switch, the default action is `-Version`.
-   `-Resolve` requires `-Name`; it may be supplied positionally.
-   `-DetectInstalled` requires both `-Platform` and `-BuildSystem`;
    neither may be supplied positionally.
-   `-Format` applies to all actions.
-   Parameter binding errors are handled by PowerShell (exit code 1).

------------------------------------------------------------------------

# Exit Codes

| Code | Meaning |
|------|---------|
| `0` | Success |
| `1` | PowerShell parameter binding error or unexpected internal error |
| `2` | Reserved (script-body argument validation; not currently used) |
| `3` | Dataset missing or unreadable |
| `4` | Alias not found (`-Resolve` only) |
| `5` | Registry access error (`-DetectInstalled` only) |
| `6` | No installations found (`-DetectInstalled` only) |

------------------------------------------------------------------------

# Error Behavior

## Text format (default)

-   On success: stdout contains output, stderr is empty.
-   On parameter binding errors (exit 1): PowerShell emits its own
    error text to stderr before the script body runs (unknown parameters,
    missing mandatory parameters, conflicting parameter sets),
    stdout is empty.
-   On reserved/unused argument error (exit 2): not currently reachable;
    reserved for future script-body argument validation. Behavior when
    emitted will follow the same pattern as exit 3: stderr contains the
    error message, stdout is empty.    
-   On dataset errors (exit 3): stderr contains the error message,
    stdout is empty.
-   On unknown alias (exit 4): stderr contains "Alias not found",
    stdout is empty.
-   On registry access error (exit 5): stderr contains the error
    message, stdout is empty.
-   On no installations found (exit 6): stdout contains
    "No installations found", stderr is empty.

## JSON format (-Format json)

-   On success: stdout contains the JSON success envelope, stderr is
    empty.
-   On parameter binding errors (exit 1): PowerShell emits its own
    error text to stderr before the script body runs; no JSON envelope
    is produced.
-   On reserved/unused argument error (exit 2): not currently reachable;
-   On dataset errors (exit 3), unknown alias (exit 4), or registry
    access error (exit 5): stdout contains a JSON error envelope,
    stderr is empty.
-   On no installations found (exit 6): stdout contains the normal
    JSON success envelope (ok: true) with all installations listed as
    notFound; stderr is empty.  Exit code 6 is the signal -- the
    envelope is still well-formed and machine-readable.

JSON error envelope:

    {
      "ok": false,
      "command": "detectInstalled",
      "tool": { ... },
      "error": {
        "code": 5,
        "message": "Registry access failed: ..."
      }
    }

------------------------------------------------------------------------

# Output Stability

-   Text output is designed to be human-readable.  Label column widths
    may change between versions.
-   JSON output is intended for CI and automation.  JSON output consists
    of a single JSON object written to stdout.  No other text is
    written to stdout alongside it.
-   Property names in JSON `result` match the dataset field names
    exactly (e.g. `verDefine`, `productName`, `compilerVersion`,
    `regKeyRelativePath`).
-   The `readiness` string values (`ready`, `partialInstall`,
    `notFound`) are considered stable API surface once this command
    reaches stable maturity.  Do not take a dependency on the
    individual component fields (e.g. `cfgFound`) for pass/fail
    decisions -- use `readiness` instead.
