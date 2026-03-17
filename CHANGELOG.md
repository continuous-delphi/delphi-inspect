# Changelog

All notable changes to this project after it's initial release
will be documented in this file.

---

## [0.5.0] - 2026-03-17

- Add new `Locate` command
  [#25](https://github.com/continuous-delphi/delphi-inspect/issues/25)

- Ensure `PowerShell 5.1` compatibility for the delphi-inspect.ps1 script
  (Tests remain the newer `pwsh`)  
  [#23](https://github.com/continuous-delphi/delphi-inspect/issues/23)

- PSScriptAnalyzer added to tests for linting PowerShell scripting
  
- Expanded platforms to support full list:
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
[#2](https://github.com/continuous-delphi/delphi-toolchain-inspect/issues/2)

- Name changed from overly-formal `delphi-toolchain-inspect` to
`delphi-inspect`  Future tools will follow the sample simple naming format
[#15](https://github.com/continuous-delphi/delphi-toolchain-inspect/issues/15)

- Default output format changed to Objects, user can still request `-Format Text` or
`-Format JSON`. 
[#14](https://github.com/continuous-delphi/delphi-toolchain-inspect/issues/14)

- Add new command `-DetectLatest` with a single return value in text/json formats
Add `rootDir` and `rsvarsPath` to result
Default platform parameter to `Win32`, default build parameter to `MSBuild`
[#6](https://github.com/continuous-delphi/delphi-toolchain-inspect/issues/6)

- New CI workflow `ci.yml` that `runs-on: windows-latest` to auto-run tests
[#5](https://github.com/continuous-delphi/delphi-toolchain-inspect/issues/5)

<br />
<br />

## `delphi-inspect` - a developer tool from Continuous Delphi

![continuous-delphi logo](https://continuous-delphi.github.io/assets/logos/continuous-delphi-480x270.png)

https://github.com/continuous-delphi
