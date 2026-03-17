# TestHelpers.ps1
# Shared setup for all delphi-inspect Pester tests.
#
# Dot-source this file at the top of each *.Tests.ps1:
#   . "$PSScriptRoot/TestHelpers.ps1"
#
# Provides (run scope -- usable inside BeforeAll / It blocks):
#   Get-ScriptUnderTestPath    - returns absolute path to delphi-inspect.ps1
#   Get-MinFixturePath         - returns absolute path to the minimal fixture JSON
#   Get-ResolveFixturePath     - returns absolute path to the resolve fixture JSON
#   Get-DetectFixturePath      - returns absolute path to the listInstalled fixture JSON
#   Get-RegistryErrorShimPath  - returns absolute path to detect-registry-error-shim.ps1
#   Invoke-ToolProcess         - runs delphi-inspect.ps1 as a child process and
#                                returns [pscustomobject]@{ ExitCode; StdOut; StdErr }
#                                Optional -Shell parameter selects the host
#                                executable (default: 'pwsh').
#
# PESTER 5 SCOPING NOTE:
#   Pester 5 isolates the run phase from the discovery phase entirely.
#   Both variables and functions defined by a top-level dot-source are
#   visible only during discovery and are invisible to BeforeAll and It
#   blocks.  Dot-source this file inside the Describe-level BeforeAll so
#   that its helper functions are available throughout the run phase:
#
#     Describe 'MyFunction' {
#       BeforeAll {
#         . "$PSScriptRoot/TestHelpers.ps1"
#         $script:scriptUnderTest = Get-ScriptUnderTestPath
#         . $script:scriptUnderTest
#       }
#     }
#
#   This file intentionally does NOT dot-source delphi-inspect.ps1.
#   That dot-source must happen in the test file's own BeforeAll so that
#   the loaded functions land in the correct scope for It blocks.

function Get-ScriptUnderTestPath {
  $path = Join-Path $PSScriptRoot '..' '..' 'source' 'delphi-inspect.ps1'
  return [System.IO.Path]::GetFullPath($path)
}

function Get-MinFixturePath {
  $path = Join-Path $PSScriptRoot 'fixtures' 'delphi-compiler-versions.min.json'
  return [System.IO.Path]::GetFullPath($path)
}

function Get-ResolveFixturePath {
  $path = Join-Path $PSScriptRoot 'fixtures' 'delphi-compiler-versions.resolve.json'
  return [System.IO.Path]::GetFullPath($path)
}

function Get-DetectFixturePath {
  $path = Join-Path $PSScriptRoot 'fixtures' 'delphi-compiler-versions.listknown.json'
  return [System.IO.Path]::GetFullPath($path)
}

function Get-RegistryErrorShimPath {
  $path = Join-Path $PSScriptRoot 'fixtures' 'detect-registry-error-shim.ps1'
  return [System.IO.Path]::GetFullPath($path)
}

function Invoke-ToolProcess {
  param(
    [Parameter(Mandatory=$true)][string]$ScriptPath,
    [Parameter()][string[]]$Arguments = @(),
    [Parameter()][string]$Shell = 'pwsh',
    [Parameter()][string]$ExecutionPolicy = ''
  )

  $shellArgs = @('-NoProfile', '-NonInteractive')
  if ($ExecutionPolicy) { $shellArgs += @('-ExecutionPolicy', $ExecutionPolicy) }
  $shellArgs += @('-File', $ScriptPath)

  $psi = [System.Diagnostics.ProcessStartInfo]::new()
  $psi.FileName = $Shell
  foreach ($a in $shellArgs + $Arguments) {
    [void]$psi.ArgumentList.Add($a)
  }
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError  = $true
  $psi.UseShellExecute        = $false

  $p = [System.Diagnostics.Process]::new()
  $p.StartInfo = $psi
  [void]$p.Start()

  $stdoutTask = $p.StandardOutput.ReadToEndAsync()
  $stderrTask = $p.StandardError.ReadToEndAsync()
  $p.WaitForExit()
  $stdout = $stdoutTask.GetAwaiter().GetResult()
  $stderr = $stderrTask.GetAwaiter().GetResult()

  [pscustomobject]@{
    ExitCode = $p.ExitCode
    StdOut   = ($stdout -split '\r?\n' | Where-Object { $_ -ne '' })
    StdErr   = ($stderr -split '\r?\n' | Where-Object { $_ -ne '' })
  }
}
