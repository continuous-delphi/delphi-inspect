#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.7.0' }
<#
.SYNOPSIS
  Tests for Write-JsonError in delphi-toolchain-inspect.ps1

.DESCRIPTION
  Covers: JSON error envelope shape emitted by Write-JsonError.

  Context 1 - code=3 and a dataset error message:
    ok=false, error.code=3, error.message matches, tool fields correct.

  Context 2 - code=1 and an unexpected error message:
    error.code=1, command field matches.
#>

# PESTER 5 SCOPING RULES apply here -- see Resolve-DefaultDataFilePath.Tests.ps1
# for the canonical explanation.  Dot-source TestHelpers.ps1 and the script
# under test inside BeforeAll, not at the top level of the file.

Describe 'Write-JsonError' {

  BeforeAll {
    . "$PSScriptRoot/TestHelpers.ps1"
    $script:scriptUnderTest = Get-ScriptUnderTestPath
    . $script:scriptUnderTest
  }

  Context 'Given code=3 and a dataset error message' {

    BeforeAll {
      $script:json = Write-JsonError -ToolVersion '0.1.0' -Command 'version' -Code 3 `
                       -Message 'Data file not found: /tmp/x.json' | ConvertFrom-Json
    }

    It 'ok is false' {
      $script:json.ok | Should -Be $false
    }

    It 'error.code is 3' {
      $script:json.error.code | Should -Be 3
    }

    It 'error.message contains the supplied message' {
      $script:json.error.message | Should -Match 'Data file not found'
    }

    It 'tool.name is delphi-toolchain-inspect' {
      $script:json.tool.name | Should -Be 'delphi-toolchain-inspect'
    }

    It 'tool.impl is pwsh' {
      $script:json.tool.impl | Should -Be 'pwsh'
    }

    It 'tool.version is 0.1.0' {
      $script:json.tool.version | Should -Be '0.1.0'
    }

  }

  Context 'Given code=1 and an unexpected error message' {

    BeforeAll {
      $script:json = Write-JsonError -ToolVersion '0.1.0' -Command 'resolve' -Code 1 `
                       -Message 'Something unexpected' | ConvertFrom-Json
    }

    It 'error.code is 1' {
      $script:json.error.code | Should -Be 1
    }

    It 'command field is resolve' {
      $script:json.command | Should -Be 'resolve'
    }

  }

}
