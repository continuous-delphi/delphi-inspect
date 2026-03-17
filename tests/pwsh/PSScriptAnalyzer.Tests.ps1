#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.7.0' }
#Requires -Modules @{ ModuleName='PSScriptAnalyzer'; ModuleVersion='1.21.0' }
<#
.SYNOPSIS
  PSScriptAnalyzer lint test for source/delphi-inspect.ps1

.DESCRIPTION
  Runs Invoke-ScriptAnalyzer against delphi-inspect.ps1 using the default
  rule set and asserts zero violations.  On failure each violation is listed
  with its rule name, severity, and line number.
#>

Describe 'PSScriptAnalyzer - delphi-inspect.ps1' {

  BeforeAll {
    . "$PSScriptRoot/TestHelpers.ps1"
    $script:scriptUnderTest = Get-ScriptUnderTestPath
    $script:violations = @(Invoke-ScriptAnalyzer -Path $script:scriptUnderTest)
  }

  It 'has no PSScriptAnalyzer violations' {
    $lines = $script:violations | ForEach-Object {
      "  [$($_.Severity)] $($_.RuleName) at line $($_.Line): $($_.Message)"
    }
    $because = if ($lines) { "`n" + ($lines -join [System.Environment]::NewLine) } else { '' }
    $script:violations | Should -BeNullOrEmpty -Because $because
  }

}
