# cd-ci-toolchain Command Reference

This document describes the command-line interface for
`cd-ci-toolchain.ps1`.

------------------------------------------------------------------------

# Overview

`cd-ci-toolchain` provides three primary actions:

-   `-Version` --- Display tool and dataset metadata
-   `-Resolve` --- Resolve a Delphi alias or VER### constant to
    canonical version data
-   `-ListKnown` --- List all known Delphi versions from the dataset

By default, invoking the script with **no switches** performs the
`-Version` action.

------------------------------------------------------------------------

# Usage

    pwsh ./source/pwsh/cd-ci-toolchain.ps1 [action] [options]

------------------------------------------------------------------------

# Actions

## -Version

Display tool version and dataset metadata.

### Examples

    pwsh cd-ci-toolchain.ps1
    pwsh cd-ci-toolchain.ps1 -Version
    pwsh cd-ci-toolchain.ps1 -Version -Format json

### Output (text format, default)

Labels are left-padded to a fixed column width.

    cd-ci-toolchain 0.1.0
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
        "name": "cd-ci-toolchain",
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

    pwsh cd-ci-toolchain.ps1 -Resolve D7
    pwsh cd-ci-toolchain.ps1 -Resolve "Delphi 11"
    pwsh cd-ci-toolchain.ps1 -Resolve -Name VER150
    pwsh cd-ci-toolchain.ps1 -Resolve VER350 -Format json

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
        "name": "cd-ci-toolchain",
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

    pwsh cd-ci-toolchain.ps1 -ListKnown
    pwsh cd-ci-toolchain.ps1 -ListKnown -Format json
    pwsh cd-ci-toolchain.ps1 -ListKnown -DataFile ./data/custom.json

### Output (text format, default)

One line per entry in fixed-width columns: verDefine (12), compilerVersion (10),
packageVersion (6), productName (trailing).

    VER150      15.0      70    Delphi 7
    VER370      37.0      370   Delphi 13 Florence

### Output (json format)

    {
      "ok": true,
      "command": "listKnown",
      "tool": {
        "name": "cd-ci-toolchain",
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

`generatedUtcDate` is always present in JSON output; it is `null` when absent
from the dataset.  All version entry fields are always present regardless of
null status.

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

------------------------------------------------------------------------

# Parameter Rules

-   `-Version`, `-Resolve`, and `-ListKnown` are mutually exclusive
    (enforced by PowerShell parameter sets; exit code 1 if more than one
    is supplied).
-   With no action switch, the default action is `-Version`.
-   `-Resolve` requires `-Name`; it may be supplied positionally.
-   `-Format` applies to `-Version`, `-Resolve`, and `-ListKnown`.
-   Parameter binding errors are handled by PowerShell (exit code 1).

------------------------------------------------------------------------

# Exit Codes

  Code   Meaning
  ------ -----------------------------------------------------------------
  0      Success
  1      PowerShell parameter binding error or unexpected internal error
  2      Reserved (script-body argument validation; not currently used)
  3      Dataset missing or unreadable
  4      Alias not found (-Resolve only)

------------------------------------------------------------------------

# Error Behavior

## Text format (default)

-   On success: stdout contains output, stderr is empty.
-   On dataset errors (exit 3): stderr contains the error message,
    stdout is empty.
-   On unknown alias (exit 4): stderr contains "Alias not found",
    stdout is empty.
-   On parameter binding errors (exit 1): PowerShell emits its own
    error text to stderr, stdout is empty.

## JSON format (-Format json)

-   On success: stdout contains the JSON success envelope, stderr is
    empty.
-   On dataset errors (exit 3) or unknown alias (exit 4): stdout
    contains a JSON error envelope, stderr is empty.
-   On parameter binding errors (exit 1): PowerShell emits its own
    error text to stderr before the script body runs; no JSON envelope
    is produced.

JSON error envelope:

    {
      "ok": false,
      "command": "version",
      "tool": { ... },
      "error": {
        "code": 3,
        "message": "Data file not found: ..."
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
