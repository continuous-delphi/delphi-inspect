#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.7.0' }
<#
.SYNOPSIS
  Tests for Import-JsonData in delphi-toolchain-inspect.ps1

.DESCRIPTION
  Covers: JSON file loading and parsing.

  Context 1 - Valid JSON file:
    Verifies the returned object has the correct schemaVersion, dataVersion,
    meta.generatedUtcDate, and versions properties.

  Context 2 - Missing file:
    Verifies the exception message contains "Data file not found".

  Context 3 - Malformed JSON:
    Verifies the exception message contains "Failed to parse JSON".
#>

# PESTER 5 SCOPING RULES apply here -- see Resolve-DefaultDataFilePath.Tests.ps1
# for the canonical explanation.  Dot-source TestHelpers.ps1 and the script
# under test inside BeforeAll, not at the top level of the file.

Describe 'Import-JsonData' {

  BeforeAll {
    . "$PSScriptRoot/TestHelpers.ps1"
    $script:scriptUnderTest = Get-ScriptUnderTestPath
    . $script:scriptUnderTest

    $script:fixturePath = Get-MinFixturePath
  }

  Context 'Given a valid JSON file' {

    BeforeAll {
      $script:result = Import-JsonData -Path $script:fixturePath
    }

    It 'returns a parsed object with the correct schemaVersion' {
      $script:result.schemaVersion | Should -Be '1.0.0'
    }

    It 'returns a parsed object with the correct dataVersion' {
      $script:result.dataVersion | Should -Be '0.1.0'
    }

    It 'returns a parsed object with the correct meta.generatedUtcDate' {
      $script:result.meta.generatedUtcDate | Should -Be '2026-01-01'
    }

    It 'returns a parsed object with an empty versions list' {
      $script:result.versions | Should -HaveCount 0
    }

  }

  Context 'Given a path that does not exist' {

    It 'throws with a message containing "Data file not found"' {
      $missingPath = Join-Path ([System.IO.Path]::GetTempPath()) 'delphi-toolchain-inspect-missing-xyz.json'
      { Import-JsonData -Path $missingPath } | Should -Throw -ExpectedMessage '*Data file not found*'
    }

  }

  Context 'Given a file with malformed JSON' {

    BeforeAll {
      $script:badJsonPath = Join-Path ([System.IO.Path]::GetTempPath()) 'delphi-toolchain-inspect-bad-json.json'
      Set-Content -LiteralPath $script:badJsonPath -Value '{ this is : not valid json' -Encoding UTF8NoBOM
    }

    AfterAll {
      if (Test-Path -LiteralPath $script:badJsonPath) {
        Remove-Item -LiteralPath $script:badJsonPath -Force
      }
    }

    It 'throws with a message containing "Failed to parse JSON"' {
      { Import-JsonData -Path $script:badJsonPath } | Should -Throw -ExpectedMessage '*Failed to parse JSON*'
    }

  }

}
