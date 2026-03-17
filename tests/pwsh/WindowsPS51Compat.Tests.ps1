#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.7.0' }
<#
.SYNOPSIS
  Windows PowerShell 5.1 compatibility tests for delphi-inspect.ps1.

.DESCRIPTION
  Verifies that delphi-inspect.ps1 can be launched under powershell.exe
  (Windows PowerShell 5.1) and produces correct exit codes.
  All tests in this file skip automatically on platforms where
  powershell.exe is absent (e.g. Linux CI runners).

  The test suite itself continues to require pwsh 7+ (see run-tests.ps1);
  these tests only invoke the script-under-test via powershell.exe.

  Scenarios tested (all supply -DataFile pointing to a non-existent path so
  the script reaches the data-loading code and exits 3 without touching the
  registry or filesystem beyond what is already absent):
    Default/Version mode -- exits 3 when the data file is missing.
    ListInstalled mode   -- exits 3 when the data file is missing.
    DetectLatest mode    -- exits 3 when the data file is missing.
    Resolve mode         -- exits 3 when the data file is missing.

  Each scenario exercises a distinct PS parameter set, verifying that all
  four parameter sets bind correctly under PS 5.1 and that the script body
  executes without hitting PS 6+-only syntax.

.NOTES
  Get-Command is NOT used to locate powershell.exe.  The Invoke-RsvarsEnvironment
  unit test in companion build scripts applies fake environment variables
  (including a truncated PATH) to the live process, which can remove
  C:\Windows\System32\WindowsPowerShell\v1.0 from PATH and break Get-Command
  resolution for external commands.  Instead, powershell.exe is located via
  its well-known fixed path under $env:SystemRoot.  On Linux/macOS
  $env:SystemRoot is absent so Test-Path returns $false and all tests skip cleanly.

  $skipTests is a discovery-time local variable captured by -Skip:.
  $script:winPS51Exe is set in BeforeAll (run time) so it is visible in
  It and Context BeforeAll blocks.

  -ExecutionPolicy Bypass is passed to powershell.exe because the machine's
  default execution policy may not permit running unsigned scripts.
#>

Describe 'Windows PowerShell 5.1 compatibility' {

  # Evaluated at Pester discovery time -- captured by -Skip: on each It.
  # Uses Test-Path (filesystem) rather than Get-Command (PATH-dependent) to
  # locate powershell.exe safely regardless of prior process PATH changes.
  $ps51Path  = if ($env:SystemRoot) {
    [System.IO.Path]::Combine($env:SystemRoot, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe')
  } else { $null }
  $skipTests = -not ($ps51Path -and (Test-Path -LiteralPath $ps51Path))

  BeforeAll {
    . "$PSScriptRoot/TestHelpers.ps1"
    $script:scriptPath = Get-ScriptUnderTestPath

    # Absent data file used by all scenarios; guaranteed not to exist.
    # Defined here (run time) so $script: scope is visible in Context BeforeAll blocks.
    $script:absentDataFile = 'C:\DoesNotExist\99999\delphi-compiler-versions.json'

    $script:winPS51Exe = $null
    $sysRoot = $env:SystemRoot
    if ($sysRoot) {
      $candidate = [System.IO.Path]::Combine($sysRoot, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe')
      if (Test-Path -LiteralPath $candidate) { $script:winPS51Exe = $candidate }
    }
  }

  It 'powershell.exe (Windows PowerShell 5.1) is present on this machine' -Skip:$skipTests {
    $script:winPS51Exe | Should -Not -BeNullOrEmpty
  }

  Context 'Version mode -- exits 3 when data file is missing' {

    BeforeAll {
      if (-not $script:winPS51Exe) { return }
      $script:result = Invoke-ToolProcess `
        -Shell           $script:winPS51Exe `
        -ExecutionPolicy 'Bypass' `
        -ScriptPath      $script:scriptPath `
        -Arguments       @('-Version', '-DataFile', $script:absentDataFile)
    }

    It 'exit code is 3' -Skip:$skipTests {
      $script:result.ExitCode | Should -Be 3
    }

    It 'stderr mentions data file not found' -Skip:$skipTests {
      $script:result.StdErr -join ' ' | Should -Match 'Data file not found'
    }

  }

  Context 'ListInstalled mode -- exits 3 when data file is missing' {

    BeforeAll {
      if (-not $script:winPS51Exe) { return }
      $script:result = Invoke-ToolProcess `
        -Shell           $script:winPS51Exe `
        -ExecutionPolicy 'Bypass' `
        -ScriptPath      $script:scriptPath `
        -Arguments       @('-ListInstalled', '-Platform', 'Win32', '-BuildSystem', 'MSBuild', '-DataFile', $script:absentDataFile)
    }

    It 'exit code is 3' -Skip:$skipTests {
      $script:result.ExitCode | Should -Be 3
    }

    It 'stderr mentions data file not found' -Skip:$skipTests {
      $script:result.StdErr -join ' ' | Should -Match 'Data file not found'
    }

  }

  Context 'DetectLatest mode -- exits 3 when data file is missing' {

    BeforeAll {
      if (-not $script:winPS51Exe) { return }
      $script:result = Invoke-ToolProcess `
        -Shell           $script:winPS51Exe `
        -ExecutionPolicy 'Bypass' `
        -ScriptPath      $script:scriptPath `
        -Arguments       @('-DetectLatest', '-Platform', 'Win32', '-BuildSystem', 'MSBuild', '-DataFile', $script:absentDataFile)
    }

    It 'exit code is 3' -Skip:$skipTests {
      $script:result.ExitCode | Should -Be 3
    }

    It 'stderr mentions data file not found' -Skip:$skipTests {
      $script:result.StdErr -join ' ' | Should -Match 'Data file not found'
    }

  }

  Context 'Resolve mode -- exits 3 when data file is missing' {

    BeforeAll {
      if (-not $script:winPS51Exe) { return }
      $script:result = Invoke-ToolProcess `
        -Shell           $script:winPS51Exe `
        -ExecutionPolicy 'Bypass' `
        -ScriptPath      $script:scriptPath `
        -Arguments       @('-Resolve', '-Name', 'xyz', '-DataFile', $script:absentDataFile)
    }

    It 'exit code is 3' -Skip:$skipTests {
      $script:result.ExitCode | Should -Be 3
    }

    It 'stderr mentions data file not found' -Skip:$skipTests {
      $script:result.StdErr -join ' ' | Should -Match 'Data file not found'
    }

  }

}
