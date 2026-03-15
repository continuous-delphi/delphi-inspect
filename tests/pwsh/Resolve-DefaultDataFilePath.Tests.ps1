#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.7.0' }
<#
.SYNOPSIS
  Tests for Resolve-DefaultDataFilePath in delphi-inspect.ps1

.DESCRIPTION
  Covers: path construction from a given script location.

  Context 1 - Pure construction (no filesystem access):
    Verifies the returned path ends with the canonical data file name.
    Verifies the returned path contains the spec submodule directory name.

  Context 2 - Real repository layout:
    Verifies the resolved path exists on disk.
    Requires delphi-compiler-versions to be present as a submodule.
#>

# PESTER 5 SCOPING RULES - this file demonstrates the required pattern:
#
#   Rule 1: Dot-source both TestHelpers.ps1 and the script under test inside
#   BeforeAll, not at the top level of the file.  Pester 5 isolates the run
#   phase from the discovery phase entirely -- top-level dot-sources reach
#   discovery scope only and are invisible to BeforeAll and It blocks.
#
#   Rule 2: Use $script: scope for all variables shared across It blocks.

Describe 'Resolve-DefaultDataFilePath' {

  BeforeAll {
    . "$PSScriptRoot/TestHelpers.ps1"
    $script:scriptUnderTest = Get-ScriptUnderTestPath
    . $script:scriptUnderTest
  }

  Context 'Given a script path in a standard source/pwsh layout' {

    BeforeAll {
      $fakeRepo              = Join-Path ([System.IO.Path]::GetTempPath()) 'delphi-inspect-test-repo'
      $fakeScriptDir         = Join-Path $fakeRepo 'source' 'pwsh'
      $script:fakeScriptPath = Join-Path $fakeScriptDir 'delphi-inspect.ps1'
      # Create a placeholder file so the guard's Test-Path check passes.
      $null = New-Item -ItemType Directory -Path $fakeScriptDir -Force
      $null = New-Item -ItemType File -Path $script:fakeScriptPath -Force
    }

    AfterAll {
      if (Test-Path -LiteralPath $script:fakeScriptPath) {
        Remove-Item -LiteralPath $script:fakeScriptPath -Force
      }
    }

    It 'returns a path ending with the canonical data file name' {
      $result = Resolve-DefaultDataFilePath -ScriptPath $script:fakeScriptPath
      $result | Should -Match ([regex]::Escape('delphi-compiler-versions.json'))
    }

    It 'returns a path containing the spec submodule directory name' {
      $result = Resolve-DefaultDataFilePath -ScriptPath $script:fakeScriptPath
      $result | Should -Match ([regex]::Escape('delphi-compiler-versions'))
    }

  }

  Context 'Given the real repository layout' {

    It 'resolves to a path that exists on disk' {
      # Arrange
      # Use the actual script path so the traversal resolves against the real repo.
      # Requires delphi-compiler-versions to be present as a submodule.

      # Act
      $result = Resolve-DefaultDataFilePath -ScriptPath $script:scriptUnderTest
      $result = [System.IO.Path]::GetFullPath($result)

      # Assert
      $result | Should -Exist
    }

  }

}
