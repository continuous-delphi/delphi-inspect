# Command Reference

This document describes the command-line interface for
`delphi-inspect.ps1`.

------------------------------------------------------------------------

# Overview

`delphi-inspect.ps1` provides five primary actions:

-   `-Version` --- Display tool and dataset metadata
-   `-Resolve` --- Resolve a Delphi alias or VER### constant to
    canonical version data
-   `-ListKnown` --- List all known Delphi versions from the dataset
-   `-ListInstalled` --- List all Delphi versions with readiness state
-   `-DetectLatest` --- Return the single highest-versioned ready install

By default, invoking the script with **no switches** performs the
`-Version` action.

------------------------------------------------------------------------

# Usage

    pwsh ./source/pwsh/delphi-inspect.ps1 [action] [options]

------------------------------------------------------------------------

# Actions

## -Version

Display tool version and dataset metadata.

### Examples

    pwsh delphi-inspect.ps1
    pwsh delphi-inspect.ps1 -Version
    pwsh delphi-inspect.ps1 -Version -Format json
    $v = pwsh delphi-inspect.ps1 -Version

### Output (object format, default)

Returns one `pscustomobject` with properties:

    schemaVersion    -- dataset schema version string
    dataVersion      -- dataset data version string
    generatedUtcDate -- dataset generation date (null if absent from dataset)

Note: `toolVersion` is intentionally omitted from the object.  The caller
already knows which script they invoked.

### Output (text format)

Labels are left-padded to a fixed column width.

    delphi-inspect 0.1.0
    dataVersion     0.1.0
    schemaVersion   1.0.0
    generated       2026-01-01


### Output (json format)

    {
      "ok": true,
      "command": "version",
      "tool": {
        "name": "delphi-inspect",
        "impl": "pwsh",
        "version": "0.1.0"
      },
      "result": {
        "schemaVersion": "1.0.0",
        "dataVersion": "0.1.0",
        "generatedUtcDate": "2026-01-01"
      }
    }


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

    pwsh delphi-inspect.ps1 -Resolve D7
    pwsh delphi-inspect.ps1 -Resolve "Delphi 11"
    pwsh delphi-inspect.ps1 -Resolve -Name VER150
    pwsh delphi-inspect.ps1 -Resolve VER350 -Format json

### Output (object format, default)

Returns one `pscustomobject` with properties: `verDefine`, `productName`,
`compilerVersion`, `packageVersion`, `regKeyRelativePath`, `aliases`.
All fields are always present; optional dataset fields appear as `null`
when absent.

### Output (text format)

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
        "name": "delphi-inspect",
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

    pwsh delphi-inspect.ps1 -ListKnown
    pwsh delphi-inspect.ps1 -ListKnown -Format json
    pwsh delphi-inspect.ps1 -ListKnown -DataFile ./data/custom.json

### Output (object format, default)

Returns one `pscustomobject` per version entry.  Fields: `verDefine`,
`productName`, `compilerVersion`, `packageVersion`, `regKeyRelativePath`,
`aliases`, `notes`.  PowerShell collects the stream as an array when
assigned: `$all = .\tool.ps1 -ListKnown`.

### Output (text format)

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
        "name": "delphi-inspect",
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

## -ListInstalled

Scan this machine for installed Delphi versions and report their
readiness for a specific platform and build system combination.

Both `-Platform` and `-BuildSystem` are mandatory.  The tool reports
readiness for just the provided combination. To assess multiple build
systems or platforms, invoke the command multiple times.

### Syntax

    -ListInstalled -Platform <platform> -BuildSystem <buildSystem>

### Parameters

`-Platform` (mandatory)

Valid values: 

  - `Win32`
  - `Win64`
  - `macOS32`
  - `macOS64`
  - `macOSARM64`
  - `Linux64`
  - `iOS32`
  - `iOSSimulator32`
  - `iOS64`
  - `iOSSimulator64`
  - `Android32`
  - `Android64`

The target compilation platform to assess.

`-BuildSystem` (mandatory)

Valid values: `DCC`, `MSBuild`

The build system to assess readiness for.

`-Readiness` (optional, default: `@('ready')`)

Valid values: `ready`, `partialInstall`, `notFound`, `notApplicable`, `all`

Filters the output to entries matching the specified readiness state(s).
Multiple values may be specified as an array.  The special value `all`
bypasses filtering entirely and returns every entry regardless of state.

Default is `@('ready')`, meaning only fully ready installations are
returned.  Exit code 6 fires when the filtered list is empty.

**Behavior change vs prior releases:** Previous releases always returned
all entries in JSON format regardless of state.  If you relied on that
behavior, add `-Readiness all` to restore it.

- `DCC` -- direct invocation of the command-line compiler
  (`dcc32.exe` or `dcc64.exe` depending on platform).  Requires the
  compiler binary and a correctly configured `.cfg` file.
- `MSBuild` -- MSBuild-based builds driven by `.dproj` files.
  Requires `rsvars.bat` and a correctly populated `EnvOptions.proj`
  in the expected `%APPDATA%` path for the current user.

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
| `rsvarsPath`               | Full path to `rsvars.bat` under `<RootDir>\bin`    |
| `rsvarsFound`              | `rsvars.bat` exists at `rsvarsPath`                |
| `envOptionsFound`          | `EnvOptions.proj` exists at the expected path      |
| `envOptionsHasLibraryPath` | `EnvOptions.proj` contains at least one non-empty  |
|                            | `DelphiLibraryPath` property for the target platform|

The expected `EnvOptions.proj` path is:

    %APPDATA%\Embarcadero\BDS\<bdsVersion>\EnvOptions.proj

`ready` requires `rootDirExists`, `rsvarsFound`, `envOptionsFound`,
and `envOptionsHasLibraryPath` to all be true.

Note: if `EnvOptions.proj` is missing, MSBuild will emit a warning
(`Expected configuration file missing`) but will not fail immediately.
Builds that rely on third-party library paths will fail with
`F1026 File not found` errors that can be difficult to diagnose.
This is a common silent failure mode on manually configured build
servers.

### Examples

    pwsh delphi-inspect.ps1 -ListInstalled -Platform Win32 -BuildSystem DCC
    pwsh delphi-inspect.ps1 -ListInstalled -Platform Win64 -BuildSystem MSBuild
    pwsh delphi-inspect.ps1 -ListInstalled -Platform Win32 -BuildSystem DCC -Format json
    pwsh delphi-inspect.ps1 -ListInstalled -Platform Win32 -BuildSystem DCC -Readiness all
    pwsh delphi-inspect.ps1 -ListInstalled -Platform Win32 -BuildSystem DCC -Readiness ready,partialInstall
    pwsh delphi-inspect.ps1 -ListInstalled -Platform Win32 -BuildSystem DCC -Readiness all -Format json
    $inst = pwsh delphi-inspect.ps1 -ListInstalled -Platform Win32 -BuildSystem DCC -Readiness all

### Output (object format, default)

Returns one object per entry that passes the `-Readiness` filter.
The objects are the internal readiness result objects emitted directly.
PowerShell collects them as an array when assigned:

    $inst = .\tool.ps1 -ListInstalled -Platform Win32 -BuildSystem DCC -Readiness all

When the filtered list is empty, exit code 6 is returned and nothing is
emitted to the pipeline.

### Output (text format)

Only entries passing the `-Readiness` filter are listed, in dataset order.
If no entries remain after filtering, a single line is emitted:

    No installations found

Otherwise, one block per entry that passed the `-Readiness` filter:

    VER340     Delphi 10.4 Sydney
      readiness                 ready
      registryFound             true
      rootDir                   C:\Program Files (x86)\Embarcadero\Studio\21.0\
      rootDirExists             true
      compilerFound             true
      cfgFound                  true

    VER350     Delphi 11 Alexandria
      readiness                 partialInstall
      registryFound             true
      rootDir                   C:\Program Files (x86)\Embarcadero\Studio\22.0\
      rootDirExists             true
      compilerFound             true
      cfgFound                  false

Use `-Readiness all` to include all entries.  Use `-Format json` or
`-Format object` to access the full dataset including entries not returned
by the current readiness filter.

### Output (json format)

`installations` is always an array of entries that passed the `-Readiness`
filter.  Use `-Readiness all` to ensure all known versions are present.

Entries that were not checked appear with null component fields; the
`readiness` value distinguishes why:

- `notFound` -- registry was checked; `registryFound` is `false`
- `notApplicable` -- no check was performed; `registryFound` is `null`

Use `-Readiness all -Format json` to inspect all versions including those
that are `notApplicable` for the requested platform or build system.

    {
      "ok": true,
      "command": "listInstalled",
      "tool": {
        "name": "delphi-inspect",
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
            "rootDir": "C:\\Program Files (x86)\\Embarcadero\\Studio\\21.0\\",
            "rootDirExists": true,
            "compilerFound": true,
            "cfgFound": true
          },
          {
            "verDefine": "VER350",
            "productName": "Delphi 11 Alexandria",
            "readiness": "partialInstall",
            "registryFound": true,
            "rootDir": "C:\\Program Files (x86)\\Embarcadero\\Studio\\22.0\\",
            "rootDirExists": true,
            "compilerFound": true,
            "cfgFound": false
          },
          {
            "verDefine": "VER370",
            "productName": "Delphi 13 Florence",
            "readiness": "notFound",
            "registryFound": false,
            "rootDir": null,
            "rootDirExists": null,
            "compilerFound": null,
            "cfgFound": null
          }
        ]
      }
    }

For MSBuild, the component fields are `registryFound`, `rootDir`,
`rsvarsPath`, `rootDirExists`, `rsvarsFound`, `envOptionsFound`, and
`envOptionsHasLibraryPath`.
The `readiness` field is always present regardless of build system.

`platform` and `buildSystem` are always echoed back in the result so
consumers do not need to track what was requested.

------------------------------------------------------------------------

## -DetectLatest

Scan this machine for installed Delphi versions and return the single
highest-versioned entry whose readiness is `ready` for the specified
platform and build system combination.

Unlike `-ListInstalled`, this command returns at most one entry and
ignores `partialInstall` entries.  It is intended for CI pipelines
that need a single, unambiguous compiler path without post-processing
the full list.

### Syntax

    -DetectLatest [-Platform <platform>] [-BuildSystem <buildSystem>]

### Parameters

`-Platform` (optional, default: `Win32`)

Valid values: 

  - `Win32`
  - `Win64`
  - `macOS32`
  - `macOS64`
  - `macOSARM64`
  - `Linux64`
  - `iOS32`
  - `iOSSimulator32`
  - `iOS64`
  - `iOSSimulator64`
  - `Android32`
  - `Android64`

The target compilation platform to assess.

`-BuildSystem` (optional, default: `MSBuild`)

Valid values: `DCC`, `MSBuild`

The build system to assess readiness for.  See `-ListInstalled` for
a description of the `DCC` and `MSBuild` readiness criteria.

### Examples

    pwsh delphi-inspect.ps1 -DetectLatest
    pwsh delphi-inspect.ps1 -DetectLatest -Platform Win32 -BuildSystem DCC
    pwsh delphi-inspect.ps1 -DetectLatest -Platform Win64 -BuildSystem MSBuild -Format json

### Output (object format, default)

Returns zero or one object.  If a ready installation is found, the
readiness result object is emitted directly.  If no ready installation
exists, nothing is emitted and exit code 6 is returned.

    $latest = .\tool.ps1 -DetectLatest
    if ($null -eq $latest) { Write-Error 'No Delphi found' }

### Output (text format)

When a ready installation is found, one block is emitted.  DCC example:

    VER360     Delphi 12 Athens
      readiness                 ready
      registryFound             true
      rootDir                   C:\Program Files (x86)\Embarcadero\Studio\23.0\
      rootDirExists             true
      compilerFound             true
      cfgFound                  true

MSBuild example:

    VER360     Delphi 12 Athens
      readiness                 ready
      registryFound             true
      rootDir                   C:\Program Files (x86)\Embarcadero\Studio\23.0\
      rootDirExists             true
      rsvarsPath                C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\rsvars.bat
      rsvarsFound               true
      envOptionsFound           true
      envOptionsHasLibraryPath  true

When no ready installation is found (exit 6):

    No ready installation found

### Output (json format)

When a ready installation is found:

    {
      "ok": true,
      "command": "detectLatest",
      "tool": {
        "name": "delphi-inspect",
        "impl": "pwsh",
        "version": "0.1.0"
      },
      "result": {
        "platform": "Win32",
        "buildSystem": "DCC",
        "installation": {
          "verDefine": "VER360",
          "productName": "Delphi 12 Athens",
          "readiness": "ready",
          "registryFound": true,
          "rootDir": "C:\\Program Files (x86)\\Embarcadero\\Studio\\23.0\\",
          "rootDirExists": true,
          "compilerFound": true,
          "cfgFound": true
        }
      }
    }

When no ready installation is found (exit 6), `installation` is `null`
and the envelope is still well-formed (`ok: true`):

    {
      "ok": true,
      "command": "detectLatest",
      "tool": { ... },
      "result": {
        "platform": "Win32",
        "buildSystem": "DCC",
        "installation": null
      }
    }

For MSBuild, the component fields inside `installation` are
`registryFound`, `rootDir`, `rsvarsPath`, `rootDirExists`, `rsvarsFound`,
`envOptionsFound`, and `envOptionsHasLibraryPath`.

`platform` and `buildSystem` are always echoed back in the result.

------------------------------------------------------------------------

# Common Options

## -Format

Controls output format.

Valid values:

-   `object` (default) -- emits PowerShell objects to the pipeline.
    Assign directly or pipe to other commands.  No text formatting is
    applied.  Best for scripting and automation within PowerShell.
-   `text` -- human-readable formatted output, one record per line or
    block.  Labels are left-padded to a fixed column width.
-   `json` -- machine envelope with `ok`/`command`/`tool`/`result`
    structure.  Suitable for CI pipelines and non-PowerShell consumers.

Examples:

    -Format object
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

Note: `-ListInstalled` uses the dataset to drive the list of versions
to scan for.  Supplying a custom `-DataFile` will limit detection to
the versions present in that file.

------------------------------------------------------------------------

# Parameter Rules

-   `-Version`, `-Resolve`, `-ListKnown`, `-ListInstalled`, and
    `-DetectLatest` are mutually exclusive (enforced by PowerShell
    parameter sets; exit code 1 if more than one is supplied).
-   With no action switch, the default action is `-Version`.
-   `-Resolve` requires `-Name`; it may be supplied positionally.
-   `-ListInstalled` requires both `-Platform` and `-BuildSystem`;
    neither may be supplied positionally.
-   `-DetectLatest` accepts `-Platform` and `-BuildSystem` as optional
    parameters with defaults (`Win32` and `MSBuild` respectively);
    neither may be supplied positionally.
-   `-Format` applies to all actions.  Default is `object`.
-   `-Readiness` applies to `-ListInstalled` only.  Default is
    `@('ready')`.  Use `all` to bypass filtering.
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
| `5` | Registry access error (`-ListInstalled` and `-DetectLatest` only) |
| `6` | No installations found (`-ListInstalled` and `-DetectLatest` only) |


**PowerShell implementation note:** the PowerShell binder runs before the
script body, so parameter binding failures (missing mandatory parameter,
conflicting parameter set) also produce exit 1.  They are distinguishable
from script-body errors only by the stderr message.  Exit 2 is reserved for
invalid-argument conditions detected inside the script body.

------------------------------------------------------------------------

# Error Behavior

## Object format (default, -Format object) and Text format (-Format text)

Object mode follows the same error behavior as text mode: errors are
written to stderr, nothing is written to stdout on error.

-   On success: objects (or text lines) go to stdout, stderr is empty.
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
-   On no installations found (exit 6): in text mode, stdout contains
    "No installations found" (for `-ListInstalled`) or
    "No ready installation found" (for `-DetectLatest`), stderr is empty.
    In object mode, nothing is emitted to the pipeline; exit code 6 is
    the signal.

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
    JSON success envelope (ok: true); stderr is empty.  Exit code 6 is
    the signal -- the envelope is still well-formed and machine-readable.
    For `-ListInstalled`, all installations are listed as notFound.
    For `-DetectLatest`, `installation` is null.

JSON error envelope:

    {
      "ok": false,
      "command": "listInstalled",
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
