#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.7.0' }
<#
.SYNOPSIS
  Tests for Write-VersionInfo in cd-ci-toolchain.ps1

.DESCRIPTION
  Covers: output lines produced for various data shapes.

  Value-presence assertions use array -match filtering so that a future
  padding tweak does not produce a cryptic string-mismatch failure.
  The one exception is the first output line, which is tested as an exact
  string because it is the canonical format contract for the tool header.

  Context 1 - Fully populated data object:
    Verifies the tool-name-and-version line, dataVersion, schemaVersion, and
    generated lines are all present, and that the total line count is 4.

  Context 2 - Data object with null meta:
    Verifies the generated line is absent and total line count is 3.

  Context 3 - Data object with an empty generatedUtcDate:
    Verifies the generated line is absent and total line count is 3.

  Context 4 - Data object with a whitespace-only generatedUtcDate:
    Verifies the generated line is absent and total line count is 3.
    (The implementation uses IsNullOrWhiteSpace, so '   ' must be suppressed
    the same way as '' and $null.)

  Context 5 - Data object with a null generatedUtcDate within a non-null meta:
    Verifies the generated line is absent and total line count is 3.
    (meta is non-null, so the first guard passes; generatedUtcDate is null,
    so the second guard fails and $generated stays null.)

  Context 6 - -Format json, all fields populated:
    Verifies the output is a single item that parses as valid JSON, ok is $true,
    command is 'version', and result contains schemaVersion, dataVersion, and
    generatedUtcDate with the expected values.

  Context 7 - -Format json, meta is null:
    Verifies the output parses as valid JSON and result.generatedUtcDate is null.
#>

# PESTER 5 SCOPING RULES apply here -- see Resolve-DefaultDataFilePath.Tests.ps1
# for the canonical explanation.  Dot-source TestHelpers.ps1 and the script
# under test inside BeforeAll, not at the top level of the file.

Describe 'Write-VersionInfo' {

  BeforeAll {
    . "$PSScriptRoot/TestHelpers.ps1"
    $script:scriptUnderTest = Get-ScriptUnderTestPath
    . $script:scriptUnderTest
  }

  Context 'Given a data object with all fields populated' {

    BeforeAll {
      $script:data = [pscustomobject]@{
        schemaVersion = '1.0.0'
        dataVersion   = '0.1.0'
        meta          = [pscustomobject]@{ generatedUtcDate = '2026-01-01' }
      }
      $script:output = Write-VersionInfo -ToolVersion '0.1.0' -Data $script:data
    }

    # Exact match: this line is the format contract for the tool header.
    It 'first output line identifies the tool and version' {
      $script:output[0] | Should -Be 'cd-ci-toolchain 0.1.0'
    }

    # Array -match returns elements that satisfy the pattern, so these pass
    # regardless of how many spaces separate the label from the value.
    It 'output includes a line with the dataVersion value' {
      ($script:output -match 'dataVersion\s+0\.1\.0') | Should -Not -BeNullOrEmpty
    }

    It 'output includes a line with the schemaVersion value' {
      ($script:output -match 'schemaVersion\s+1\.0\.0') | Should -Not -BeNullOrEmpty
    }

    It 'output includes a generated line when meta.generatedUtcDate is set' {
      ($script:output -match 'generated\s+2026-01-01') | Should -Not -BeNullOrEmpty
    }

    It 'output has exactly four lines' {
      $script:output | Should -HaveCount 4
    }

  }

  Context 'Given a data object with null meta' {

    BeforeAll {
      $script:data = [pscustomobject]@{
        schemaVersion = '1.0.0'
        dataVersion   = '0.1.0'
        meta          = $null
      }
      $script:output = Write-VersionInfo -ToolVersion '0.1.0' -Data $script:data
    }

    It 'output has exactly three lines' {
      $script:output | Should -HaveCount 3
    }

    It 'output does not include a generated line' {
      ($script:output -match '^generated\s') | Should -BeNullOrEmpty
    }

  }

  Context 'Given a data object with an empty generatedUtcDate' {

    BeforeAll {
      $script:data = [pscustomobject]@{
        schemaVersion = '1.0.0'
        dataVersion   = '0.1.0'
        meta          = [pscustomobject]@{ generatedUtcDate = '' }
      }
      $script:output = Write-VersionInfo -ToolVersion '0.1.0' -Data $script:data
    }

    It 'output has exactly three lines' {
      $script:output | Should -HaveCount 3
    }

    It 'output does not include a generated line' {
      ($script:output -match '^generated\s') | Should -BeNullOrEmpty
    }

  }

  Context 'Given a data object with a whitespace-only generatedUtcDate' {

    BeforeAll {
      $script:data = [pscustomobject]@{
        schemaVersion = '1.0.0'
        dataVersion   = '0.1.0'
        meta          = [pscustomobject]@{ generatedUtcDate = '   ' }
      }
      $script:output = Write-VersionInfo -ToolVersion '0.1.0' -Data $script:data
    }

    It 'output has exactly three lines' {
      $script:output | Should -HaveCount 3
    }

    It 'output does not include a generated line' {
      ($script:output -match '^generated\s') | Should -BeNullOrEmpty
    }

  }

  Context 'Given a data object with a null generatedUtcDate within a non-null meta' {

    BeforeAll {
      $script:data = [pscustomobject]@{
        schemaVersion = '1.0.0'
        dataVersion   = '0.1.0'
        meta          = [pscustomobject]@{ generatedUtcDate = $null }
      }
      $script:output = Write-VersionInfo -ToolVersion '0.1.0' -Data $script:data
    }

    It 'output has exactly three lines' {
      $script:output | Should -HaveCount 3
    }

    It 'output does not include a generated line' {
      ($script:output -match '^generated\s') | Should -BeNullOrEmpty
    }

  }

  Context 'Given -Format json and all fields are populated' {

    BeforeAll {
      $script:data = [pscustomobject]@{
        schemaVersion = '1.0.0'
        dataVersion   = '0.1.0'
        meta          = [pscustomobject]@{ generatedUtcDate = '2026-01-01' }
      }
      $script:output = Write-VersionInfo -ToolVersion '0.1.0' -Data $script:data -Format 'json'
      $script:json   = $script:output | ConvertFrom-Json
    }

    It 'output is a single item' {
      $script:output | Should -HaveCount 1
    }

    It 'output parses as valid JSON' {
      { $script:output | ConvertFrom-Json } | Should -Not -Throw
    }

    It 'ok is true' {
      $script:json.ok | Should -Be $true
    }

    It 'command is version' {
      $script:json.command | Should -Be 'version'
    }

    It 'result.schemaVersion matches the dataset value' {
      $script:json.result.schemaVersion | Should -Be '1.0.0'
    }

    It 'result.dataVersion matches the dataset value' {
      $script:json.result.dataVersion | Should -Be '0.1.0'
    }

    It 'result.generatedUtcDate matches the dataset value' {
      $script:json.result.generatedUtcDate | Should -Be '2026-01-01'
    }

  }

  Context 'Given -Format json and meta is null' {

    BeforeAll {
      $script:data = [pscustomobject]@{
        schemaVersion = '1.0.0'
        dataVersion   = '0.1.0'
        meta          = $null
      }
      $script:output = Write-VersionInfo -ToolVersion '0.1.0' -Data $script:data -Format 'json'
      $script:json   = $script:output | ConvertFrom-Json
    }

    It 'output parses as valid JSON' {
      { $script:output | ConvertFrom-Json } | Should -Not -Throw
    }

    It 'result.generatedUtcDate is null' {
      $script:json.result.generatedUtcDate | Should -Be $null
    }

  }

}
