#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.7.0' }
<#
.SYNOPSIS
  Subprocess integration tests for delphi-toolchain-inspect.ps1

.DESCRIPTION
  Invokes the script as a child process via Invoke-ToolProcess and validates
  exit codes, stdout, and stderr.  These tests cover the main execution block
  (the dispatch layer) which the dot-source guard deliberately skips when
  loading for unit tests.

  Each Context spawns exactly one subprocess and shares the result
  ($script:run) across Its.

  Contexts 1-4 supply -DataFile explicitly so they run without the submodule.
  Context 5 omits -DataFile to exercise the default path resolution branch;
  it requires delphi-compiler-versions to be initialized
  (git submodule update --init).

  Context 1 - No action switches + valid -DataFile:
    Default behavior is Version.  Validates exit 0, all four stdout lines, and clean stderr.

  Context 2 - -Version switch + valid -DataFile:
    Explicit switch produces the same output as the default.  Validates all four stdout
    lines and clean stderr, confirming the switch reaches the same dispatch branch.

  Context 3 - -DataFile path does not exist:
    Exit 3, no stdout, stderr contains "Data file not found".

  Context 4 - -DataFile contains malformed JSON:
    Exit 3, no stdout, stderr contains "Failed to parse JSON".

  Context 5 - No -DataFile, submodule present:
    Exercises the Resolve-DefaultDataFilePath branch of the dispatch block
    end-to-end.  Exit 0, tool header present.

  Contexts 6-10 cover the -Resolve dispatch branch.  All supply -DataFile
  explicitly using the resolve fixture (delphi-compiler-versions.resolve.json).

  Context 6 - -Resolve -Name VER150 (resolve by canonical VER):
    Exit 0, verDefine line present, productName line present, clean stderr.

  Context 7 - -Resolve -Name D7 (resolve by short alias):
    Exit 0, ver line shows VER150.

  Context 7b - -Resolve D7 (positional -Name):
    Exit 0, ver line shows VER150.  Verifies Position=0 on -Name.

  Context 8 - -Resolve -Name ver150 (case-insensitive):
    Exit 0, ver line shows VER150.

  Context 9 - -Resolve -Name for an unknown alias:
    Exit 4, no stdout, stderr contains "Alias not found".

  Context 10 - -Resolve without -Name:
    Exit 1 (PowerShell parameter binding rejects the invocation before the
    script body runs), no stdout, stderr references the mandatory Name parameter.

  Context 11 - Multiple action switches (-Version -Resolve):
    Exit 1 (PowerShell parameter binding rejects the invocation before the
    script body runs), no stdout, stderr references parameter set resolution.

  Context 12 - -Resolve -Name VER370 (all fields in text mode):
    All six output lines present (verDefine, productName, compilerVersion,
    packageVersion, regKeyRelativePath, aliases).
    Fills the text-mode all-fields gap left by Contexts 6-8 which use VER150.

  Context 13 - -Version -Format json and a valid -DataFile:
    Exit 0, stdout is a single JSON envelope with ok=true, command='version',
    and result containing schemaVersion, dataVersion, generatedUtcDate.
    Clean stderr.

  Context 14 - -Resolve -Name VER150 -Format json and a valid -DataFile:
    Exit 0, stdout is a single JSON envelope with ok=true, command='resolve',
    result.verDefine=VER150, and result.aliases containing 'D7'.
    Clean stderr.

  Context 15 - -DataFile pointing to a missing path -Format json:
    Exit 3, stdout is a JSON error envelope (ok=false, error.code=3,
    error.message contains 'Data file not found').  Clean stderr.

  Context 16 - -Resolve for an unknown alias -Format json:
    Exit 4, stdout is a JSON error envelope (ok=false, error.code=4,
    error.message contains 'Alias not found').  Clean stderr.

  Context 17 - -Format yaml (invalid ValidateSet value):
    Exit 1 (PowerShell parameter binder rejects 'yaml' before the script body
    runs).  No stdout.  Stderr present.

  Context 18 - -ListKnown with valid -DataFile:
    Exit 0, exactly 2 stdout lines (one per entry), VER150 entry line present,
    clean stderr.

  Context 19 - -ListKnown -Format json with valid -DataFile:
    Exit 0, stdout parses as valid JSON, ok=true, command='listKnown',
    result.versions is non-empty.  Clean stderr.

  Contexts 20-24 cover the -ListInstalled dispatch branch.  All supply -DataFile
  explicitly using the listInstalled fixture (delphi-compiler-versions.listknown.json).
  The listInstalled fixture has 3 entries: VER150 (DCC/Win32), VER999 (MSBuild/Win32 synthetic),
  VER370 (DCC+MSBuild/Win32+Win64).  The test machine has no Delphi installed so all
  registry checks return notFound; VER999 is notApplicable for DCC builds.

  Context 20 - -ListInstalled -Platform Win32 -BuildSystem DCC (text mode):
    Exit 6 (no installations found), stdout is "No installations found", clean stderr.

  Context 21 - -ListInstalled -Platform Win32 -BuildSystem DCC -Format json:
    Exit 6, stdout parses as JSON, ok=true, command=listInstalled,
    result.platform=Win32/result.buildSystem=DCC, installations count matches listInstalled fixture,
    VER999 has registryFound=null (notApplicable), VER150/VER370 have registryFound=false.
    Clean stderr.

  Context 22 - -ListInstalled -Platform Win32 -BuildSystem MSBuild -Format json:
    Exit 6, stdout parses as JSON, ok=true, command=listInstalled,
    result.buildSystem=MSBuild, installations count matches listInstalled fixture.  VER150 (DCC-only) is
    notApplicable/registryFound=null; VER999 (MSBuild/Win32) is
    notFound/registryFound=false.  Clean stderr.

  Context 23 - -ListInstalled without -Platform:
    Exit 1 (PowerShell parameter binding rejects the invocation), no stdout, stderr present.

  Context 24 - -ListInstalled without -BuildSystem:
    Exit 1 (PowerShell parameter binding rejects the invocation), no stdout, stderr present.

  Context 25 - registry access failure, text mode (via detect-registry-error-shim.ps1):
    Exit 5, no stdout, stderr contains "Registry access failed".

  Context 26 - registry access failure, json mode (via detect-registry-error-shim.ps1):
    Exit 5, stdout parses as JSON, ok=false, error.code=5, error.message matches
    "Registry access failed".  Clean stderr.

  Contexts 27-30 cover the -DetectLatest dispatch branch.  All supply -DataFile
  explicitly using the listInstalled fixture.  The test machine has no Delphi
  installed so all registry checks return notFound; DetectLatest exits 6.

  Context 27 - -DetectLatest -Platform Win32 -BuildSystem DCC (text mode):
    Exit 6, stdout is "No ready installation found", clean stderr.

  Context 28 - -DetectLatest -Platform Win32 -BuildSystem DCC -Format json:
    Exit 6, stdout parses as JSON, ok=true, command=detectLatest,
    result.platform=Win32/result.buildSystem=DCC, result.installation=null.
    Clean stderr.

  Context 29 - -DetectLatest without -Platform:
    Exit 1 (PowerShell parameter binding rejects the invocation), no stdout, stderr present.

  Context 30 - -DetectLatest without -BuildSystem:
    Exit 1 (PowerShell parameter binding rejects the invocation), no stdout, stderr present.
#>

Describe 'delphi-toolchain-inspect.ps1 (subprocess)' {

  BeforeAll {
    . "$PSScriptRoot/TestHelpers.ps1"
    $script:scriptPath             = Get-ScriptUnderTestPath
    $script:fixturePath            = Get-MinFixturePath
    $script:resolveFixturePath     = Get-ResolveFixturePath
    $script:listInstalledFixturePath      = Get-DetectFixturePath
    $script:registryErrorShimPath  = Get-RegistryErrorShimPath

    $script:listInstalledFixtureVersionCount  = ((Get-Content -LiteralPath $script:listInstalledFixturePath -Raw |
        ConvertFrom-Json).versions | Measure-Object).Count
    $script:resolveFixtureVersionCount = ((Get-Content -LiteralPath $script:resolveFixturePath -Raw |
        ConvertFrom-Json).versions | Measure-Object).Count

    $script:badJsonPath = Join-Path ([System.IO.Path]::GetTempPath()) 'delphi-toolchain-inspect-integration-bad.json'
    Set-Content -LiteralPath $script:badJsonPath -Value '{ bad json' -Encoding UTF8NoBOM
  }

  AfterAll {
    if (Test-Path -LiteralPath $script:badJsonPath) {
      Remove-Item -LiteralPath $script:badJsonPath -Force
    }
  }

  Context 'Given no action switches and a valid -DataFile' {

    BeforeAll {
      $script:run = Invoke-ToolProcess -ScriptPath $script:scriptPath `
                                       -Arguments @('-DataFile', $script:fixturePath)
    }

    It 'exits with code 0' {
      $script:run.ExitCode | Should -Be 0
    }

    # Exact match: the first line is the canonical format contract for the tool header.
    It 'first stdout line is the tool header' {
      $script:run.StdOut[0] | Should -Be 'delphi-toolchain-inspect 0.1.0'
    }

    It 'stdout includes a line with the dataVersion value' {
      ($script:run.StdOut -match 'dataVersion\s+0\.1\.0') | Should -Not -BeNullOrEmpty
    }

    It 'stdout includes a line with the schemaVersion value' {
      ($script:run.StdOut -match 'schemaVersion\s+1\.0\.0') | Should -Not -BeNullOrEmpty
    }

    It 'stdout includes a generated line' {
      ($script:run.StdOut -match '^generated\s') | Should -Not -BeNullOrEmpty
    }

    It 'stdout has exactly four lines' {
      $script:run.StdOut | Should -HaveCount 4
    }

    It 'produces no stderr' {
      $script:run.StdErr | Should -BeNullOrEmpty
    }

  }

  Context 'Given -Version switch and a valid -DataFile' {

    BeforeAll {
      $script:run = Invoke-ToolProcess -ScriptPath $script:scriptPath `
                                       -Arguments @('-Version', '-DataFile', $script:fixturePath)
    }

    It 'exits with code 0' {
      $script:run.ExitCode | Should -Be 0
    }

    It 'first stdout line is the tool header' {
      $script:run.StdOut[0] | Should -Be 'delphi-toolchain-inspect 0.1.0'
    }

    It 'stdout includes a line with the dataVersion value' {
      ($script:run.StdOut -match 'dataVersion\s+0\.1\.0') | Should -Not -BeNullOrEmpty
    }

    It 'stdout includes a line with the schemaVersion value' {
      ($script:run.StdOut -match 'schemaVersion\s+1\.0\.0') | Should -Not -BeNullOrEmpty
    }

    It 'stdout includes a generated line' {
      ($script:run.StdOut -match '^generated\s') | Should -Not -BeNullOrEmpty
    }

    It 'stdout has exactly four lines' {
      $script:run.StdOut | Should -HaveCount 4
    }

    It 'produces no stderr' {
      $script:run.StdErr | Should -BeNullOrEmpty
    }

  }

  Context 'Given -DataFile pointing to a path that does not exist' {

    BeforeAll {
      $missingPath = Join-Path ([System.IO.Path]::GetTempPath()) 'delphi-toolchain-inspect-integration-missing.json'
      $script:run  = Invoke-ToolProcess -ScriptPath $script:scriptPath `
                                        -Arguments @('-DataFile', $missingPath)
    }

    It 'exits with code 3' {
      $script:run.ExitCode | Should -Be 3
    }

    It 'produces no stdout' {
      $script:run.StdOut | Should -BeNullOrEmpty
    }

    It 'emits at least one stderr line containing "Data file not found"' {
      $script:run.StdErr | Should -Not -BeNullOrEmpty
      ($script:run.StdErr -join "`n") | Should -Match 'Data file not found'
    }

  }

  Context 'Given -DataFile pointing to a file with malformed JSON' {

    BeforeAll {
      $script:run = Invoke-ToolProcess -ScriptPath $script:scriptPath `
                                       -Arguments @('-DataFile', $script:badJsonPath)
    }

    It 'exits with code 3' {
      $script:run.ExitCode | Should -Be 3
    }

    It 'produces no stdout' {
      $script:run.StdOut | Should -BeNullOrEmpty
    }

    It 'emits at least one stderr line containing "Failed to parse JSON"' {
      $script:run.StdErr | Should -Not -BeNullOrEmpty
      ($script:run.StdErr -join "`n") | Should -Match 'Failed to parse JSON'
    }

  }

  # Requires: git submodule update --init
  Context 'Given no -DataFile and the submodule is initialized' {

    BeforeAll {
      $script:run = Invoke-ToolProcess -ScriptPath $script:scriptPath
    }

    It 'exits with code 0' {
      $script:run.ExitCode | Should -Be 0
    }

    It 'first stdout line is the tool header' {
      $script:run.StdOut[0] | Should -Be 'delphi-toolchain-inspect 0.1.0'
    }

    It 'stdout has exactly four lines' {
      $script:run.StdOut | Should -HaveCount 4
    }

  }

  Context 'Given -Resolve -Name VER150 and a valid -DataFile' {

    BeforeAll {
      $script:run = Invoke-ToolProcess -ScriptPath $script:scriptPath `
                                       -Arguments @('-Resolve', '-Name', 'VER150', '-DataFile', $script:resolveFixturePath)
    }

    It 'exits with code 0' {
      $script:run.ExitCode | Should -Be 0
    }

    It 'stdout includes a verDefine line with the canonical VER value' {
      ($script:run.StdOut -match 'verDefine\s+VER150') | Should -Not -BeNullOrEmpty
    }

    It 'stdout includes a productName line' {
      ($script:run.StdOut -match 'productName\s+Delphi 7') | Should -Not -BeNullOrEmpty
    }

    It 'stdout includes a compilerVersion line' {
      ($script:run.StdOut -match 'compilerVersion\s+15\.0') | Should -Not -BeNullOrEmpty
    }

    It 'stdout includes an aliases line' {
      ($script:run.StdOut -match 'aliases\s+') | Should -Not -BeNullOrEmpty
    }

    It 'produces no stderr' {
      $script:run.StdErr | Should -BeNullOrEmpty
    }

  }

  Context 'Given -Resolve -Name D7 (short alias) and a valid -DataFile' {

    BeforeAll {
      $script:run = Invoke-ToolProcess -ScriptPath $script:scriptPath `
                                       -Arguments @('-Resolve', '-Name', 'D7', '-DataFile', $script:resolveFixturePath)
    }

    It 'exits with code 0' {
      $script:run.ExitCode | Should -Be 0
    }

    It 'verDefine line resolves to the canonical VER150' {
      ($script:run.StdOut -match 'verDefine\s+VER150') | Should -Not -BeNullOrEmpty
    }

  }

  Context 'Given -Resolve D7 (positional -Name) and a valid -DataFile' {

    BeforeAll {
      $script:run = Invoke-ToolProcess -ScriptPath $script:scriptPath `
                                       -Arguments @('-Resolve', 'D7', '-DataFile', $script:resolveFixturePath)
    }

    It 'exits with code 0' {
      $script:run.ExitCode | Should -Be 0
    }

    It 'verDefine line resolves to the canonical VER150' {
      ($script:run.StdOut -match 'verDefine\s+VER150') | Should -Not -BeNullOrEmpty
    }

  }

  Context 'Given -Resolve -Name ver150 (lower-case input) and a valid -DataFile' {

    BeforeAll {
      $script:run = Invoke-ToolProcess -ScriptPath $script:scriptPath `
                                       -Arguments @('-Resolve', '-Name', 'ver150', '-DataFile', $script:resolveFixturePath)
    }

    It 'exits with code 0' {
      $script:run.ExitCode | Should -Be 0
    }

    It 'verDefine line resolves to the canonical VER150' {
      ($script:run.StdOut -match 'verDefine\s+VER150') | Should -Not -BeNullOrEmpty
    }

  }

  Context 'Given -Resolve -Name for an alias not in the dataset' {

    BeforeAll {
      $script:run = Invoke-ToolProcess -ScriptPath $script:scriptPath `
                                       -Arguments @('-Resolve', '-Name', 'DelphiX', '-DataFile', $script:resolveFixturePath)
    }

    It 'exits with code 4' {
      $script:run.ExitCode | Should -Be 4
    }

    It 'produces no stdout' {
      $script:run.StdOut | Should -BeNullOrEmpty
    }

    It 'emits at least one stderr line containing "Alias not found"' {
      $script:run.StdErr | Should -Not -BeNullOrEmpty
      ($script:run.StdErr -join "`n") | Should -Match 'Alias not found'
    }

  }

  Context 'Given -Resolve without -Name' {

    BeforeAll {
      $script:run = Invoke-ToolProcess -ScriptPath $script:scriptPath `
                                       -Arguments @('-Resolve', '-DataFile', $script:resolveFixturePath)
    }

    It 'exits with code 1 (PowerShell parameter binding failure)' {
      $script:run.ExitCode | Should -Be 1
    }

    It 'produces no stdout' {
      $script:run.StdOut | Should -BeNullOrEmpty
    }

    It 'emits stderr referencing the mandatory Name parameter' {
      $script:run.StdErr | Should -Not -BeNullOrEmpty
      ($script:run.StdErr -join "`n") | Should -Match 'Name'
    }

  }

  Context 'Given multiple action switches (-Version and -Resolve)' {

    BeforeAll {
      $script:run = Invoke-ToolProcess -ScriptPath $script:scriptPath `
                                       -Arguments @('-Version', '-Resolve', '-DataFile', $script:fixturePath)
    }

    It 'exits with code 1 (PowerShell parameter binding failure)' {
      $script:run.ExitCode | Should -Be 1
    }

    It 'produces no stdout' {
      $script:run.StdOut | Should -BeNullOrEmpty
    }

    It 'emits stderr referencing parameter set resolution failure' {
      $script:run.StdErr | Should -Not -BeNullOrEmpty
      ($script:run.StdErr -join "`n") | Should -Match 'parameter set'
    }

  }

  Context 'Given -Resolve -Name VER370 and a valid -DataFile (all fields)' {

    BeforeAll {
      $script:run = Invoke-ToolProcess -ScriptPath $script:scriptPath `
                                       -Arguments @('-Resolve', '-Name', 'VER370', '-DataFile', $script:resolveFixturePath)
    }

    It 'exits with code 0' {
      $script:run.ExitCode | Should -Be 0
    }

    It 'stdout has exactly six lines' {
      $script:run.StdOut | Should -HaveCount 6
    }

    It 'produces no stderr' {
      $script:run.StdErr | Should -BeNullOrEmpty
    }

  }

  Context 'Given -Version -Format json and a valid -DataFile' {

    BeforeAll {
      $script:run  = Invoke-ToolProcess -ScriptPath $script:scriptPath `
                                        -Arguments @('-Version', '-Format', 'json', '-DataFile', $script:fixturePath)
      $script:json = ($script:run.StdOut -join "`n") | ConvertFrom-Json
    }

    It 'exits with code 0' {
      $script:run.ExitCode | Should -Be 0
    }

    It 'stdout parses as valid JSON' {
      { ($script:run.StdOut -join "`n") | ConvertFrom-Json } | Should -Not -Throw
    }

    It 'JSON ok is true and command is version' {
      $script:json.ok      | Should -Be $true
      $script:json.command | Should -Be 'version'
    }

    It 'JSON result.schemaVersion is present' {
      ($script:run.StdOut -join "`n") | Should -Match 'schemaVersion'
    }

    It 'JSON result.dataVersion is present' {
      ($script:run.StdOut -join "`n") | Should -Match 'dataVersion'
    }

    It 'JSON result.generatedUtcDate is not null' {
      $script:json.result.generatedUtcDate | Should -Not -BeNullOrEmpty
    }

    It 'produces no stderr' {
      $script:run.StdErr | Should -BeNullOrEmpty
    }

  }

  Context 'Given -Resolve -Name VER150 -Format json and a valid -DataFile' {

    BeforeAll {
      $script:run  = Invoke-ToolProcess -ScriptPath $script:scriptPath `
                                        -Arguments @('-Resolve', '-Name', 'VER150', '-Format', 'json', '-DataFile', $script:resolveFixturePath)
      $script:json = ($script:run.StdOut -join "`n") | ConvertFrom-Json
    }

    It 'exits with code 0' {
      $script:run.ExitCode | Should -Be 0
    }

    It 'stdout parses as valid JSON' {
      { ($script:run.StdOut -join "`n") | ConvertFrom-Json } | Should -Not -Throw
    }

    It 'JSON ok is true and command is resolve' {
      $script:json.ok      | Should -Be $true
      $script:json.command | Should -Be 'resolve'
    }

    It 'JSON result.verDefine is VER150' {
      $script:json.result.verDefine | Should -Be 'VER150'
    }

    It 'JSON result.aliases contains D7' {
      $script:json.result.aliases | Should -Contain 'D7'
    }

    It 'produces no stderr' {
      $script:run.StdErr | Should -BeNullOrEmpty
    }

  }

  Context 'Given -DataFile pointing to a missing path -Format json' {

    BeforeAll {
      $missingPath = Join-Path ([System.IO.Path]::GetTempPath()) 'delphi-toolchain-inspect-integration-missing-json.json'
      $script:run  = Invoke-ToolProcess -ScriptPath $script:scriptPath `
                                        -Arguments @('-Format', 'json', '-DataFile', $missingPath)
      $script:json = ($script:run.StdOut -join "`n") | ConvertFrom-Json
    }

    It 'exits with code 3' {
      $script:run.ExitCode | Should -Be 3
    }

    It 'stdout parses as valid JSON' {
      { ($script:run.StdOut -join "`n") | ConvertFrom-Json } | Should -Not -Throw
    }

    It 'JSON ok is false' {
      $script:json.ok | Should -Be $false
    }

    It 'JSON error.code is 3' {
      $script:json.error.code | Should -Be 3
    }

    It 'JSON error.message contains "Data file not found"' {
      $script:json.error.message | Should -Match 'Data file not found'
    }

    It 'produces no stderr' {
      $script:run.StdErr | Should -BeNullOrEmpty
    }

  }

  Context 'Given -Resolve for an unknown alias -Format json' {

    BeforeAll {
      $script:run  = Invoke-ToolProcess -ScriptPath $script:scriptPath `
                                        -Arguments @('-Resolve', '-Name', 'DelphiX', '-Format', 'json', '-DataFile', $script:resolveFixturePath)
      $script:json = ($script:run.StdOut -join "`n") | ConvertFrom-Json
    }

    It 'exits with code 4' {
      $script:run.ExitCode | Should -Be 4
    }

    It 'stdout parses as valid JSON' {
      { ($script:run.StdOut -join "`n") | ConvertFrom-Json } | Should -Not -Throw
    }

    It 'JSON ok is false' {
      $script:json.ok | Should -Be $false
    }

    It 'JSON error.code is 4' {
      $script:json.error.code | Should -Be 4
    }

    It 'JSON error.message contains "Alias not found"' {
      $script:json.error.message | Should -Match 'Alias not found'
    }

    It 'produces no stderr' {
      $script:run.StdErr | Should -BeNullOrEmpty
    }

  }

  Context 'Given -ListKnown and a valid -DataFile' {

    BeforeAll {
      $script:run = Invoke-ToolProcess -ScriptPath $script:scriptPath `
                                       -Arguments @('-ListKnown', '-DataFile', $script:resolveFixturePath)
    }

    It 'exits with code 0' {
      $script:run.ExitCode | Should -Be 0
    }

    It 'stdout has exactly one line per dataset entry' {
      $script:run.StdOut | Should -HaveCount $script:resolveFixtureVersionCount
    }

    It 'stdout includes an entry line for VER150' {
      ($script:run.StdOut -match 'VER150') | Should -Not -BeNullOrEmpty
    }

    It 'produces no stderr' {
      $script:run.StdErr | Should -BeNullOrEmpty
    }

  }

  Context 'Given -ListKnown -Format json and a valid -DataFile' {

    BeforeAll {
      $script:run  = Invoke-ToolProcess -ScriptPath $script:scriptPath `
                                        -Arguments @('-ListKnown', '-Format', 'json', '-DataFile', $script:resolveFixturePath)
      $script:json = ($script:run.StdOut -join "`n") | ConvertFrom-Json
    }

    It 'exits with code 0' {
      $script:run.ExitCode | Should -Be 0
    }

    It 'stdout parses as valid JSON' {
      { ($script:run.StdOut -join "`n") | ConvertFrom-Json } | Should -Not -Throw
    }

    It 'JSON ok is true and command is listKnown' {
      $script:json.ok      | Should -Be $true
      $script:json.command | Should -Be 'listKnown'
    }

    It 'JSON result.versions is a non-empty array' {
      $script:json.result.versions | Should -Not -BeNullOrEmpty
    }

    It 'produces no stderr' {
      $script:run.StdErr | Should -BeNullOrEmpty
    }

  }

  Context 'Given -ListInstalled -Platform Win32 -BuildSystem DCC (text mode, no installations)' {

    BeforeAll {
      $script:run = Invoke-ToolProcess -ScriptPath $script:scriptPath `
                                       -Arguments @('-ListInstalled', '-Platform', 'Win32', '-BuildSystem', 'DCC', '-DataFile', $script:listInstalledFixturePath)
    }

    It 'exits with code 6 (no installations found)' {
      $script:run.ExitCode | Should -Be 6
    }

    It 'stdout has exactly one line' {
      $script:run.StdOut | Should -HaveCount 1
    }

    It 'stdout line is "No installations found"' {
      # StdOut may be a scalar string (single line) -- pipe directly rather than indexing
      $script:run.StdOut | Should -Be 'No installations found'
    }

    It 'produces no stderr' {
      $script:run.StdErr | Should -BeNullOrEmpty
    }

  }

  Context 'Given -ListInstalled -Platform Win32 -BuildSystem DCC -Format json' {

    BeforeAll {
      $script:run  = Invoke-ToolProcess -ScriptPath $script:scriptPath `
                                        -Arguments @('-ListInstalled', '-Platform', 'Win32', '-BuildSystem', 'DCC', '-Format', 'json', '-DataFile', $script:listInstalledFixturePath)
      $script:json = ($script:run.StdOut -join "`n") | ConvertFrom-Json
    }

    It 'exits with code 6' {
      $script:run.ExitCode | Should -Be 6
    }

    It 'stdout parses as valid JSON' {
      { ($script:run.StdOut -join "`n") | ConvertFrom-Json } | Should -Not -Throw
    }

    It 'JSON ok is true and command is listInstalled' {
      $script:json.ok      | Should -Be $true
      $script:json.command | Should -Be 'listInstalled'
    }

    It 'JSON result.platform is Win32' {
      $script:json.result.platform | Should -Be 'Win32'
    }

    It 'JSON result.buildSystem is DCC' {
      $script:json.result.buildSystem | Should -Be 'DCC'
    }

    It 'JSON result.installations has one entry per listInstalled fixture entry' {
      $script:json.result.installations | Should -HaveCount $script:listInstalledFixtureVersionCount
    }

    It 'VER999 (MSBuild-only) entry has readiness=notApplicable and registryFound=null' {
      # @() forces empty array -- Where-Object returns $null under StrictMode when no matches
      $entry = @($script:json.result.installations | Where-Object { $_.verDefine -eq 'VER999' })[0]
      $entry | Should -Not -BeNull
      $entry.readiness     | Should -Be 'notApplicable'
      $entry.registryFound | Should -BeNull
    }

    It 'VER150 (DCC/Win32) entry has readiness=notFound and registryFound=false' {
      $entry = @($script:json.result.installations | Where-Object { $_.verDefine -eq 'VER150' })[0]
      $entry | Should -Not -BeNull
      $entry.readiness     | Should -Be 'notFound'
      $entry.registryFound | Should -Be $false
    }

    It 'produces no stderr' {
      $script:run.StdErr | Should -BeNullOrEmpty
    }

  }

  Context 'Given -ListInstalled -Platform Win32 -BuildSystem MSBuild -Format json' {

    BeforeAll {
      $script:run  = Invoke-ToolProcess -ScriptPath $script:scriptPath `
                                        -Arguments @('-ListInstalled', '-Platform', 'Win32', '-BuildSystem', 'MSBuild', '-Format', 'json', '-DataFile', $script:listInstalledFixturePath)
      $script:json = ($script:run.StdOut -join "`n") | ConvertFrom-Json
    }

    It 'exits with code 6' {
      $script:run.ExitCode | Should -Be 6
    }

    It 'stdout parses as valid JSON' {
      { ($script:run.StdOut -join "`n") | ConvertFrom-Json } | Should -Not -Throw
    }

    It 'JSON ok is true and command is listInstalled' {
      $script:json.ok      | Should -Be $true
      $script:json.command | Should -Be 'listInstalled'
    }

    It 'JSON result.buildSystem is MSBuild' {
      $script:json.result.buildSystem | Should -Be 'MSBuild'
    }

    It 'JSON result.installations has one entry per listInstalled fixture entry' {
      $script:json.result.installations | Should -HaveCount $script:listInstalledFixtureVersionCount
    }

    It 'VER150 (DCC-only) entry has readiness=notApplicable and registryFound=null' {
      # MSBuild not in VER150.supportedBuildSystems -> notApplicable; registry never checked
      # @() forces empty array -- Where-Object returns $null under StrictMode when no matches
      $entry = @($script:json.result.installations | Where-Object { $_.verDefine -eq 'VER150' })[0]
      $entry | Should -Not -BeNull
      $entry.readiness     | Should -Be 'notApplicable'
      $entry.registryFound | Should -BeNull
    }

    It 'VER999 (MSBuild/Win32) entry has readiness=notFound and registryFound=false' {
      # MSBuild+Win32 supported; no Delphi installed on test machine -> notFound
      $entry = @($script:json.result.installations | Where-Object { $_.verDefine -eq 'VER999' })[0]
      $entry | Should -Not -BeNull
      $entry.readiness     | Should -Be 'notFound'
      $entry.registryFound | Should -Be $false
    }

    It 'produces no stderr' {
      $script:run.StdErr | Should -BeNullOrEmpty
    }

  }

  Context 'Given -ListInstalled without -Platform' {

    BeforeAll {
      $script:run = Invoke-ToolProcess -ScriptPath $script:scriptPath `
                                       -Arguments @('-ListInstalled', '-BuildSystem', 'DCC', '-DataFile', $script:listInstalledFixturePath)
    }

    It 'exits with code 1 (PowerShell parameter binding failure)' {
      $script:run.ExitCode | Should -Be 1
    }

    It 'produces no stdout' {
      $script:run.StdOut | Should -BeNullOrEmpty
    }

    It 'emits stderr' {
      $script:run.StdErr | Should -Not -BeNullOrEmpty
    }

  }

  Context 'Given -ListInstalled without -BuildSystem' {

    BeforeAll {
      $script:run = Invoke-ToolProcess -ScriptPath $script:scriptPath `
                                       -Arguments @('-ListInstalled', '-Platform', 'Win32', '-DataFile', $script:listInstalledFixturePath)
    }

    It 'exits with code 1 (PowerShell parameter binding failure)' {
      $script:run.ExitCode | Should -Be 1
    }

    It 'produces no stdout' {
      $script:run.StdOut | Should -BeNullOrEmpty
    }

    It 'emits stderr' {
      $script:run.StdErr | Should -Not -BeNullOrEmpty
    }

  }

  Context 'Given -Format yaml (invalid ValidateSet value)' {

    BeforeAll {
      $script:run = Invoke-ToolProcess -ScriptPath $script:scriptPath `
                                       -Arguments @('-Version', '-Format', 'yaml', '-DataFile', $script:fixturePath)
    }

    It 'exits with code 1 (PowerShell parameter binding failure)' {
      $script:run.ExitCode | Should -Be 1
    }

    It 'produces no stdout' {
      $script:run.StdOut | Should -BeNullOrEmpty
    }

    It 'emits stderr' {
      $script:run.StdErr | Should -Not -BeNullOrEmpty
    }

  }

  Context 'Given -DetectLatest -Platform Win32 -BuildSystem DCC (text mode, no installations)' {

    BeforeAll {
      $script:run = Invoke-ToolProcess -ScriptPath $script:scriptPath `
                                       -Arguments @('-DetectLatest', '-Platform', 'Win32', '-BuildSystem', 'DCC', '-DataFile', $script:listInstalledFixturePath)
    }

    It 'exits with code 6 (no ready installation found)' {
      $script:run.ExitCode | Should -Be 6
    }

    It 'stdout has exactly one line' {
      $script:run.StdOut | Should -HaveCount 1
    }

    It 'stdout line is "No ready installation found"' {
      $script:run.StdOut | Should -Be 'No ready installation found'
    }

    It 'produces no stderr' {
      $script:run.StdErr | Should -BeNullOrEmpty
    }

  }

  Context 'Given -DetectLatest -Platform Win32 -BuildSystem DCC -Format json (no installations)' {

    BeforeAll {
      $script:run  = Invoke-ToolProcess -ScriptPath $script:scriptPath `
                                        -Arguments @('-DetectLatest', '-Platform', 'Win32', '-BuildSystem', 'DCC', '-Format', 'json', '-DataFile', $script:listInstalledFixturePath)
      $script:json = ($script:run.StdOut -join "`n") | ConvertFrom-Json
    }

    It 'exits with code 6' {
      $script:run.ExitCode | Should -Be 6
    }

    It 'stdout parses as valid JSON' {
      { ($script:run.StdOut -join "`n") | ConvertFrom-Json } | Should -Not -Throw
    }

    It 'JSON ok is true and command is detectLatest' {
      $script:json.ok      | Should -Be $true
      $script:json.command | Should -Be 'detectLatest'
    }

    It 'JSON result.platform is Win32' {
      $script:json.result.platform | Should -Be 'Win32'
    }

    It 'JSON result.buildSystem is DCC' {
      $script:json.result.buildSystem | Should -Be 'DCC'
    }

    It 'JSON result.installation is null' {
      $script:json.result.installation | Should -BeNull
    }

    It 'produces no stderr' {
      $script:run.StdErr | Should -BeNullOrEmpty
    }

  }

  Context 'Given -DetectLatest without -Platform' {

    BeforeAll {
      $script:run = Invoke-ToolProcess -ScriptPath $script:scriptPath `
                                       -Arguments @('-DetectLatest', '-BuildSystem', 'DCC', '-DataFile', $script:listInstalledFixturePath)
    }

    It 'exits with code 1 (PowerShell parameter binding failure)' {
      $script:run.ExitCode | Should -Be 1
    }

    It 'produces no stdout' {
      $script:run.StdOut | Should -BeNullOrEmpty
    }

    It 'emits stderr' {
      $script:run.StdErr | Should -Not -BeNullOrEmpty
    }

  }

  Context 'Given -DetectLatest without -BuildSystem' {

    BeforeAll {
      $script:run = Invoke-ToolProcess -ScriptPath $script:scriptPath `
                                       -Arguments @('-DetectLatest', '-Platform', 'Win32', '-DataFile', $script:listInstalledFixturePath)
    }

    It 'exits with code 1 (PowerShell parameter binding failure)' {
      $script:run.ExitCode | Should -Be 1
    }

    It 'produces no stdout' {
      $script:run.StdOut | Should -BeNullOrEmpty
    }

    It 'emits stderr' {
      $script:run.StdErr | Should -Not -BeNullOrEmpty
    }

  }

  Context 'Given a registry access failure in text mode (shim)' {

    BeforeAll {
      $script:run = Invoke-ToolProcess -ScriptPath $script:registryErrorShimPath `
                                       -Arguments @('-DataFile', $script:listInstalledFixturePath, '-Platform', 'Win32', '-BuildSystem', 'DCC')
    }

    It 'exits with code 5 (registry error)' {
      $script:run.ExitCode | Should -Be 5
    }

    It 'produces no stdout' {
      $script:run.StdOut | Should -BeNullOrEmpty
    }

    It 'emits at least one stderr line containing "Registry access failed"' {
      $script:run.StdErr | Should -Not -BeNullOrEmpty
      ($script:run.StdErr -join "`n") | Should -Match 'Registry access failed'
    }

  }

  Context 'Given a registry access failure in json mode (shim)' {

    BeforeAll {
      $script:run  = Invoke-ToolProcess -ScriptPath $script:registryErrorShimPath `
                                        -Arguments @('-DataFile', $script:listInstalledFixturePath, '-Platform', 'Win32', '-BuildSystem', 'DCC', '-Format', 'json')
      $script:json = ($script:run.StdOut -join "`n") | ConvertFrom-Json
    }

    It 'exits with code 5 (registry error)' {
      $script:run.ExitCode | Should -Be 5
    }

    It 'stdout parses as valid JSON' {
      { ($script:run.StdOut -join "`n") | ConvertFrom-Json } | Should -Not -Throw
    }

    It 'JSON ok is false' {
      $script:json.ok | Should -Be $false
    }

    It 'JSON error.code is 5' {
      $script:json.error.code | Should -Be 5
    }

    It 'JSON error.message contains "Registry access failed"' {
      $script:json.error.message | Should -Match 'Registry access failed'
    }

    It 'produces no stderr' {
      $script:run.StdErr | Should -BeNullOrEmpty
    }

  }

}
