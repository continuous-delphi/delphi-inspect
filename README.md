 # delphi-inspect

![delphi-inspect logo](https://continuous-delphi.github.io/assets/logos/delphi-inspect-480x270.png)

[![CI](https://github.com/continuous-delphi/delphi-inspect/actions/workflows/ci.yml/badge.svg)](https://github.com/continuous-delphi/delphi-inspect/actions/workflows/ci.yml)
![Status](https://img.shields.io/badge/status-incubator-orange)
![License](https://img.shields.io/github/license/continuous-delphi/delphi-inspect.svg)
![Delphi](https://img.shields.io/badge/delphi-red)
![PowerShell](https://img.shields.io/badge/powershell-blue)
![Continuous Delphi](https://img.shields.io/badge/org-continuous--delphi-red)

Deterministic Delphi toolchain discovery and normalization for Delphi systems.

## TLDR;

```powershell
# Object mode (default) -- returns PowerShell objects; pipe, filter, or assign directly
$ver  = pwsh delphi-inspect.ps1 -Version
$d7   = pwsh delphi-inspect.ps1 -Resolve D7
$all  = pwsh delphi-inspect.ps1 -ListKnown
$inst = pwsh delphi-inspect.ps1 -ListInstalled -Platform Win32 -BuildSystem DCC -Readiness all
$best = pwsh delphi-inspect.ps1 -DetectLatest

# Text format -- human-readable output
pwsh delphi-inspect.ps1
pwsh delphi-inspect.ps1 -Version -Format text
pwsh delphi-inspect.ps1 -Resolve D7 -Format text
pwsh delphi-inspect.ps1 -Resolve -Name D7 -Format text
pwsh delphi-inspect.ps1 -Resolve "Delphi 11" -Format text
pwsh delphi-inspect.ps1 -ListKnown -Format text
pwsh delphi-inspect.ps1 -ListInstalled -Platform Win32 -BuildSystem DCC -Format text
pwsh delphi-inspect.ps1 -ListInstalled -Platform Win32 -BuildSystem DCC -Readiness all -Format text
pwsh delphi-inspect.ps1 -DetectLatest -Format text
pwsh delphi-inspect.ps1 -DetectLatest -Platform Win64 -BuildSystem DCC -Format text

# JSON format -- machine envelope for CI pipelines
pwsh delphi-inspect.ps1 -Resolve D7 -Format json
pwsh delphi-inspect.ps1 -ListKnown -Format json
pwsh delphi-inspect.ps1 -ListInstalled -Platform Win32 -BuildSystem MSBuild -Readiness all -Format json
pwsh delphi-inspect.ps1 -DetectLatest -Platform Win64 -BuildSystem DCC -Format json
```

## Philosophy

`Continuous Delphi` meets Delphi developers where they are.

Whether you are building manually on a desktop PC, running FinalBuilder scripts on a cloned
server, or ready to adopt (or have already adopted) GitHub Actions, the tools here work at your level today without
requiring you to change everything at once.

The goal is _not_ to replace your workflow - the goal is to _incrementally enhance_ it.

## PowerShell Compatibility

Runs on the widely available Windows PowerShell 5.1 (`powershell.exe`)
and the newer PowerShell 7+ (`pwsh`).

Note: the test suite requires `pwsh`.

## Commands

| Command           | Description                                      |
|-------------------|--------------------------------------------------|
| `Version`         | Print tool version and dataset metadata          |
| `ListKnown`       | List all known Delphi versions from the dataset  |
| `ListInstalled`   | List all Delphi versions with readiness state    |
| `DetectLatest`    | Return the single highest-versioned ready install |
| `Resolve`         | Resolve an alias or VER### to a canonical entry  |

See [docs/commands.md](docs/commands.md) for full command reference including switches,
output formats, exit codes, and any functionality differences between implementations.

### Output formats

`-Format` controls the output mode.  Valid values:

- `object` (default) -- emits PowerShell objects to the pipeline.  Pipe,
  filter, or assign directly.  No text formatting is applied.
- `text` -- human-readable formatted output, one record per line or block.
- `json` -- machine envelope with `ok`/`command`/`tool`/`result` structure.
  Suitable for CI pipelines and non-PowerShell consumers.

### Machine output

Property names in `result` match the dataset field names exactly.

Success (`-Version`):

```json
{
  "ok": true,
  "command": "version",
  "tool": {
    "name": "delphi-inspect",
    "version": "X.Y.Z"
  },
  "result": {
    "schemaVersion": "1.0.0",
    "dataVersion": "0.1.0",
    "generatedUtcDate": "YYYY-MM-DD"
  }
}
```

Success (`-Resolve`):

```json
{
  "ok": true,
  "command": "resolve",
  "tool": {
    "name": "delphi-inspect",
    "version": "X.Y.Z"
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
```

All `result` fields are always present in JSON output; optional fields that are
absent in the dataset appear as `null` rather than being omitted.

Error:

```json
{
  "ok": false,
  "command": "version",
  "tool": {
    "name": "delphi-inspect",
    "version": "X.Y.Z"
  },
  "error": {
    "code": 3,
    "message": "Data file not found: ..."
  }
}
```

## Dataset

The implementations consumes the canonical dataset from
[delphi-compiler-versions](https://github.com/continuous-delphi/delphi-compiler-versions).
The JSON dataset is the single source of truth.

_todo_

The `gen/` folder produces a standalone `pwsh` script with the dataset embedded as a
PowerShell `here-string`.

Artifacts support the same three-tier dataset resolution priority. A newer
`delphi-compiler-versions.json` file found will take precedence over
the embedded data without regenerating or recompiling.


## Maturity

This repository is currently `incubator`. It will graduate to `stable` once:

- The command contract is considered frozen.
- At least one downstream consumer exists.

Until graduation, breaking changes may occur.

![continuous-delphi logo](https://continuous-delphi.github.io/assets/logos/continuous-delphi-480x270.png)

## Part of the Continuous Delphi Organization

This repository follows the Continuous Delphi organization taxonomy. See
[cd-meta-org](https://github.com/continuous-delphi/cd-meta-org) for navigation and governance.

- `docs/org-taxonomy.md` -- naming and tagging conventions
- `docs/versioning-policy.md` -- release and versioning rules
- `docs/repo-lifecycle.md` -- lifecycle states and graduation criteria
