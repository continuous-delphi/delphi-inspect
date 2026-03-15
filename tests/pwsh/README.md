# delphi-inspect Tests

## Running the tests

### To run all tests

From the repository root (or any directory -- the script is location-independent):

```powershell
./tests/run-tests.ps1
```

This sets execution policy to `Bypass` for the process, imports Pester 5.7+,
loads `PesterConfig.psd1`, and runs all test suites under `tests/pwsh/` with
`Detailed` output and NUnit XML results written to `tests/pwsh/results/`.

---

### To run a single suite during development

From the root directory:

```powershell
Invoke-Pester ./tests/pwsh/Write-VersionInfo.Tests.ps1 -Output Detailed
```

---

## Test suites

### Resolve-DefaultDataFilePath (3 tests)

- Returns a path ending with the canonical data file name
- Returns a path containing the spec submodule directory name
- Resolves to a path that exists on disk
  *(requires submodule -- see [Submodule initialization](#submodule-initialization))*

### Import-JsonData (6 tests)

- Returns parsed object with correct schemaVersion
- Returns parsed object with correct dataVersion
- Returns parsed object with correct meta.generatedUtcDate
- Returns parsed object with empty compilers list
- Throws with "Data file not found" for a missing path
- Throws with "Failed to parse JSON" for malformed JSON

### Write-VersionInfo (22 tests)

- First output line exactly matches tool header format contract
- Output includes a line with the dataVersion value
- Output includes a line with the schemaVersion value
- Output includes a generated line when meta.generatedUtcDate is set
- Output has exactly four lines when all fields populated
- Output has exactly three lines when meta is null
- Output does not include a generated line when meta is null
- Output has exactly three lines when generatedUtcDate is empty
- Output does not include a generated line when generatedUtcDate is empty
- Output has exactly three lines when generatedUtcDate is whitespace-only
- Output does not include a generated line when generatedUtcDate is whitespace-only
- Output has exactly three lines when generatedUtcDate is null within a non-null meta
- Output does not include a generated line when generatedUtcDate is null within a non-null meta
- `-Format json`: output is a single item that parses as valid JSON
- `-Format json`: ok is true
- `-Format json`: command is "version"
- `-Format json`: result.schemaVersion matches the dataset value
- `-Format json`: result.dataVersion matches the dataset value
- `-Format json`: result.generatedUtcDate matches the dataset value
- `-Format json` with null meta: output parses as valid JSON
- `-Format json` with null meta: result.generatedUtcDate is null

### Resolve-VersionEntry (16 tests)

Lookup priority per entry: `verDefine` (short-circuits), then `productName`,
then `aliases` array.  All comparisons are case-insensitive.

- Returns the matching entry for the canonical verDefine string
- Returns the matching entry for a short alias (e.g., D7)
- Returns the matching entry by productName (e.g., "Delphi 7")
- productName match is case-insensitive
- Returns the matching entry for an alias that contains a space
- Resolves lower-case verDefine string case-insensitively
- Resolves lower-case short alias case-insensitively
- Resolves upper-case short alias case-insensitively
- Returns null for an unknown alias
- Returns null for an empty string
- Returns the matching entry for a verDefine string in the second dataset entry

### Write-ResolveOutput (16 tests)

- Output includes verDefine, productName, compilerVersion, packageVersion, regKeyRelativePath, and aliases lines when all fields are populated
- Output has exactly six lines when all fields are populated
- Output has exactly six lines for a standard entry (VER150)
- Aliases line contains all aliases as a comma-separated list
- `-Format json`: output is a single item that parses as valid JSON
- `-Format json`: ok is true
- `-Format json`: command is "resolve"
- `-Format json`: result.verDefine matches the entry value
- `-Format json`: result.regKeyRelativePath matches the entry value
- `-Format json`: result.aliases contains all aliases
- `-Format json`: result does not contain a bds_reg_version property

### Write-ListKnownOutput (17 tests)

- Text format, all fields populated: VER150 and VER370 entry lines present; VER150 line contains compilerVersion and productName values; total line count is exactly 2
- `-Format json`, all fields populated: output is a single item that parses as valid JSON; ok is true; command is "listKnown"; result.schemaVersion, result.dataVersion, result.generatedUtcDate match dataset values; result.versions has 2 entries; first entry has verDefine, productName, regKeyRelativePath, aliases, and notes fields

### Test-EnvOptionsLibraryPath (9 tests)

Tests XML parsing of EnvOptions.proj for Delphi library path detection.
Uses temporary XML files created per-Context; all cleaned up in AfterAll.

- Win32: returns true when DelphiLibraryPath is present and non-empty; does not throw
- Win64: returns true when DelphiLibraryPathWin64 is present and non-empty
- Win32: returns false when DelphiLibraryPath node is absent
- Win32: returns false when DelphiLibraryPath is empty
- Returns false (and does not throw) when the file does not exist
- Returns false (and does not throw) when the file contains malformed XML

### Get-DccReadiness (37 tests)

Tests DCC installation readiness for all states.
Uses `Mock Get-RegistryRootDir` and `Mock Test-Path`; mocks are scoped per Context.

For `Should -Invoke` assertions, the function under test is called inside the `It`
body because Pester 5 only counts calls made during the current test run (not
calls from an enclosing `BeforeAll`).

- notApplicable when DCC not in supportedBuildSystems: readiness, registryFound=$null,
  component fields $null, Get-RegistryRootDir not called (vacuous -- BeforeAll calls
  do not count per-test; behavioral tests cover this path)
- notApplicable when Platform not in supportedPlatforms: readiness, registryFound=$null
- notFound when regKeyRelativePath is null: readiness, registryFound=$false, fields $null
- notFound when registry returns null: readiness, registryFound=$false, fields $null
- ready (Win32): readiness/registryFound/rootDirExists/compilerFound/cfgFound all true;
  dcc32.exe and dcc32.cfg paths verified via Should -Invoke ParameterFilter
- ready (Win64): readiness=ready; dcc64.exe and dcc64.cfg paths verified
- partialInstall when rootDirExists=false: readiness, registryFound=true, rootDirExists=false
- partialInstall when compilerFound=false: readiness, compilerFound=false, cfgFound=true
- partialInstall when cfgFound=false: readiness, cfgFound=false, compilerFound=true

### Get-MSBuildReadiness (31 tests)

Tests MSBuild installation readiness for all states.
Uses `Mock Get-RegistryRootDir`, `Mock Test-Path`, and `Mock Test-EnvOptionsLibraryPath`.

- notApplicable when MSBuild not in supportedBuildSystems: readiness, registryFound=$null
- notApplicable when Platform not in supportedPlatforms: readiness, registryFound=$null
- notFound when regKeyRelativePath is null: readiness, registryFound=$false
- notFound when registry returns null: readiness, registryFound=$false, fields $null
- ready (Win32): all boolean fields true; rsvars.bat path verified via Should -Invoke
- partialInstall when rootDirExists=false: readiness, rootDirExists=false
- partialInstall when rsvarsFound=false: readiness, rsvarsFound=false, envOptionsFound=true
- partialInstall when envOptionsFound=false: readiness, envOptionsFound=false,
  envOptionsHasLibraryPath=$null, Test-EnvOptionsLibraryPath not called
- partialInstall when envOptionsHasLibraryPath=false: readiness, field=false
- bdsVersion extracted from regKeyRelativePath leaf: EnvOptions.proj path contains
  version component (37.0) from VER370's registry key

### Write-ListInstalledOutput (32 tests)

Tests text and JSON output formatting.
Uses in-memory pscustomobject arrays -- no mocking required.

- Text, DCC, all notFound/notApplicable: exactly one line "No installations found"
- Text, DCC, one ready entry: header line, all DCC field lines, no MSBuild-specific lines
- Text, DCC, two entries: two header lines present, blank separator between blocks
- Text, DCC, mixed: notFound and notApplicable entries suppressed; only ready appears
- Text, MSBuild, null envOptionsHasLibraryPath: shows "null" string; no DCC-specific lines
- JSON, DCC mode: ok=true/command=listInstalled/result.platform+buildSystem+installations;
  notApplicable entry has registryFound=null; notFound entry has registryFound=false
- JSON, MSBuild mode: result.buildSystem=MSBuild; MSBuild-specific fields present;
  notApplicable entry has registryFound=null

### delphi-inspect.ps1 subprocess integration (107 tests)

Invokes the script as a child process via `Invoke-ToolProcess`; validates exit
codes, stdout, and stderr.  Covers the dispatch block that the dot-source guard
skips during unit tests.

- No action switches + valid `-DataFile`: exit 0, tool header, all four output lines, clean stderr
- `-Version` switch + valid `-DataFile`: exit 0, tool header, all four output lines, clean stderr
- `-DataFile` pointing to a missing path: exit 3, no stdout, stderr contains "Data file not found"
- `-DataFile` pointing to malformed JSON: exit 3, no stdout, stderr contains "Failed to parse JSON"
- No `-DataFile`, submodule initialized: exit 0, tool header, four output lines
  *(requires submodule -- see [Submodule initialization](#submodule-initialization))*
- `-Resolve -Name VER150`: exit 0, verDefine/productName/compilerVersion/aliases lines, clean stderr
- `-Resolve -Name D7` (short alias): exit 0, verDefine line shows VER150
- `-Resolve D7` (positional `-Name`): exit 0, verDefine line shows VER150
- `-Resolve -Name ver150` (lower-case): exit 0, verDefine line shows VER150
- `-Resolve -Name` for an unknown alias: exit 4, no stdout, stderr contains "Alias not found"
- `-Resolve` without `-Name`: exit 1 (PowerShell parameter binding failure), no stdout, stderr references mandatory Name parameter
- Multiple action switches (`-Version -Resolve`): exit 1 (PowerShell parameter binding failure), no stdout, stderr references parameter set resolution failure
- `-Resolve -Name VER370` (all fields): exit 0, exactly six stdout lines, clean stderr
- `-Version -Format json`: exit 0, stdout parses as JSON, ok=true/command=version, result contains schemaVersion/dataVersion/generatedUtcDate, clean stderr
- `-Resolve -Name VER150 -Format json`: exit 0, stdout parses as JSON, ok=true/command=resolve, result.verDefine=VER150, result.aliases contains D7, clean stderr
- `-DataFile` missing path `-Format json`: exit 3, stdout parses as JSON error envelope, ok=false/error.code=3/"Data file not found" in message, clean stderr
- `-Resolve` unknown alias `-Format json`: exit 4, stdout parses as JSON error envelope, ok=false/error.code=4/"Alias not found" in message, clean stderr
- `-ListKnown` + valid `-DataFile`: exit 0, exactly 2 stdout lines, VER150 entry line present, clean stderr
- `-ListKnown -Format json` + valid `-DataFile`: exit 0, stdout parses as JSON, ok=true/command=listKnown, result.versions non-empty, clean stderr
- `-Format yaml` (invalid value): exit 1 (parameter binder rejects ValidateSet value), no stdout, stderr present
- `-ListInstalled -Platform Win32 -BuildSystem DCC` (text): exit 6, stdout is "No installations found", clean stderr
- `-ListInstalled -Platform Win32 -BuildSystem DCC -Format json`: exit 6, JSON ok=true/command=listInstalled,
  result.platform=Win32/buildSystem=DCC, 3 installations; VER999 (MSBuild-only) has
  readiness=notApplicable/registryFound=null; VER150 has readiness=notFound/registryFound=false; clean stderr
- `-ListInstalled -Platform Win32 -BuildSystem MSBuild -Format json`: exit 6, JSON ok=true/command=listInstalled,
  result.buildSystem=MSBuild, clean stderr
- `-ListInstalled` without `-Platform`: exit 1 (parameter binding), no stdout, stderr present
- `-ListInstalled` without `-BuildSystem`: exit 1 (parameter binding), no stdout, stderr present

The error text for the binder-failure cases is produced by PowerShell's parameter
binder, not by the script.  The exact phrasing is version-dependent; the tests
match stable substrings ("Name" and "parameter set") rather than full strings.

---

## Standards for new PowerShell test files

### File header

Every test file must begin with:

```powershell
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.7.0' }
<#
.SYNOPSIS
  Tests for <FunctionName> in delphi-inspect.ps1

.DESCRIPTION
  Covers: <brief description of what is tested>

  Context 1 - <description>:
    <what is verified>
  ...
#>
```

### Pester 5 scoping rules

Pester 5 isolates the run phase (BeforeAll, It, AfterAll) from the discovery
phase entirely -- both variables and functions defined by a top-level dot-source
are invisible to `BeforeAll` and `It` blocks.  Two rules follow from this:

**Rule 1: Dot-source `TestHelpers.ps1` and the script under test inside the
Describe-level `BeforeAll`, not at the top level of the file.**

The Describe-level `BeforeAll` runs once before all nested blocks, so anything
dot-sourced there is available to every `Context` and `It` within that
`Describe`.  The correct pattern:

```powershell
Describe 'MyFunction' {
  BeforeAll {
    . "$PSScriptRoot/TestHelpers.ps1"
    $script:scriptUnderTest = Get-ScriptUnderTestPath
    . $script:scriptUnderTest

    $script:fixturePath = Get-MinFixturePath
  }
  ...
}
```

`Get-ScriptUnderTestPath` and `Get-MinFixturePath` are helper functions
defined in `TestHelpers.ps1` that return fully-resolved absolute paths.
Using functions rather than the plain `$ScriptUnderTest` / `$MinFixturePath`
variables lets all path logic stay in one place.

**Rule 2: Use `$script:` scope for all variables shared across `It` blocks.**

Variables assigned in `BeforeAll` must use the `$script:` prefix to be
visible inside `It` blocks within the same `Describe` or `Context`.

### Dot-source guard in delphi-inspect.ps1

The script under test contains a dot-source guard at the top:

```powershell
if ($MyInvocation.InvocationName -eq '.') { return }
```

When the script is dot-sourced (as in tests), this guard fires and the script
body does not execute -- only the function definitions are loaded into scope.
This is intentional and is what makes the script safely testable without
triggering live API calls or file I/O at load time.

Do not remove this guard.

### Pipeline results and Set-StrictMode

Under `Set-StrictMode -Version Latest`, calling `.Count` (or any property)
on `$null` throws a runtime error.  Pipeline cmdlets such as `Where-Object`,
`Select-Object`, and `ForEach-Object` return `$null` -- not an empty array --
when no items match.  This means the following pattern silently breaks under
strict mode:

```powershell
# Throws if Where-Object matches nothing: "The property 'Count' cannot
# be found on this object."
$n = ($collection | Where-Object { $_.foo -eq 'bar' }).Count
```

Always wrap pipeline output in `@()` when you need array semantics:

```powershell
# Safe: @() guarantees an array even when the pipeline is empty
$n = @($collection | Where-Object { $_.foo -eq 'bar' }).Count
```

This applies in production code and in test helpers alike.  Any use of
`.Count`, `.Length`, or indexed access on pipeline output must be guarded
with `@()`.

### Encoding

All test files and fixture files must be UTF-8 without BOM.

When writing temp files in tests, use `-Encoding UTF8NoBOM` with
`Set-Content`, not `-Encoding UTF8`. On some .NET versions `UTF8` emits a
BOM which can cause unexpected behavior in parsers and APIs.

```powershell
# Correct
Set-Content -LiteralPath $path -Value $content -Encoding UTF8NoBOM

# Avoid -- may emit BOM
Set-Content -LiteralPath $path -Value $content -Encoding UTF8
```

### Fixture files

Shared fixture files live in `tests/pwsh/fixtures/`. The minimal fixture
`delphi-compiler-versions.min.json` contains a structurally valid but
minimal dataset suitable for most parsing tests.

Ephemeral files created for specific test cases (malformed JSON, missing
paths, etc.) should use `[System.IO.Path]::GetTempPath()` and must be
cleaned up in `AfterAll`.

### Assertion style

- Use `Should -HaveCount` for collection length assertions; use `Should -Not -BeNullOrEmpty`
  to assert a collection is non-empty
- For output line content, prefer `-match 'label\s+value'` over exact string
  matching so that padding changes do not produce cryptic failures
- Reserve exact `Should -Be` matching for format contracts (e.g. the tool
  header line) where the precise string is the thing being tested
- For negative presence assertions, anchor the pattern: `-match '^label\s'`
  to avoid false passes from partial word matches

### Submodule initialization

Two tests require the `delphi-compiler-versions` submodule to be
initialized: the filesystem existence test in `Resolve-DefaultDataFilePath`
and the no-`-DataFile` context in the subprocess integration suite.  If
either fails with "path does not exist", run:

```powershell
git submodule update --init
```

from the repo root.

### Auto Discovery

Reminder that test files are auto-discovered by Pester.
Any file matching `*.Tests.ps1` under `tests/pwsh/` will be picked up
automatically when `run-tests.ps1` is executed.
No registration or explicit listing is required.
