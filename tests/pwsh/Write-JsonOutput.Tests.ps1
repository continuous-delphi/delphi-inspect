#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.7.0' }
<#
.SYNOPSIS
  Tests for Write-JsonOutput in delphi-toolchain-inspect.ps1

.DESCRIPTION
  Covers: JSON serialization behavior of Write-JsonOutput.

  Context 1 - Simple flat object:
    Output is a single string with no embedded newlines that parses back correctly.

  Context 2 - Nested object (depth > 1):
    Nesting is preserved (-Depth 10 reaches deep properties).

  Context 3 - Object with a null property:
    Null property is present in the output (not silently omitted).
#>

# PESTER 5 SCOPING RULES apply here -- see Resolve-DefaultDataFilePath.Tests.ps1
# for the canonical explanation.  Dot-source TestHelpers.ps1 and the script
# under test inside BeforeAll, not at the top level of the file.

Describe 'Write-JsonOutput' {

  BeforeAll {
    . "$PSScriptRoot/TestHelpers.ps1"
    $script:scriptUnderTest = Get-ScriptUnderTestPath
    . $script:scriptUnderTest
  }

  Context 'Given a simple flat object' {

    BeforeAll {
      $obj = [pscustomobject]@{ name = 'test'; value = 42 }
      $script:result = Write-JsonOutput $obj
    }

    It 'returns a single string' {
      $script:result | Should -BeOfType [string]
    }

    It 'output has no embedded newlines (single-line compact JSON)' {
      $script:result | Should -Not -Match "`n"
    }

    It 'parses back to an object with the correct name property' {
      ($script:result | ConvertFrom-Json).name | Should -Be 'test'
    }

    It 'parses back to an object with the correct value property' {
      ($script:result | ConvertFrom-Json).value | Should -Be 42
    }

  }

  Context 'Given an object with nested properties (depth > 1)' {

    BeforeAll {
      $obj = [pscustomobject]@{
        outer = [pscustomobject]@{
          inner = [pscustomobject]@{ leaf = 'deep' }
        }
      }
      $script:result = Write-JsonOutput $obj
    }

    It 'parses back and preserves the nested leaf value' {
      ($script:result | ConvertFrom-Json).outer.inner.leaf | Should -Be 'deep'
    }

  }

  Context 'Given an object with a null property' {

    BeforeAll {
      $obj = [pscustomobject]@{ present = 'yes'; absent = $null }
      $script:result = Write-JsonOutput $obj
    }

    It 'parses back and the null property is present (not omitted)' {
      $parsed = $script:result | ConvertFrom-Json
      $parsed.PSObject.Properties.Name | Should -Contain 'absent'
    }

    It 'parses back and the null property value is null' {
      ($script:result | ConvertFrom-Json).absent | Should -BeNull
    }

  }

}
