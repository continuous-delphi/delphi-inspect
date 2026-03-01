#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.7.0' }
<#
.SYNOPSIS
  Tests for Write-ListKnownOutput in cd-ci-toolchain.ps1

.DESCRIPTION
  Covers: per-entry lines for text format and JSON envelope output.
  Uses a two-entry dataset matching the resolve fixture schema.

  Context 1 - Text format, all fields populated:
    Verifies that both entry lines are present, each line leads with the
    verDefine value, and the total line count is exactly 2 (one per entry).

  Context 2 - -Format json, all fields populated:
    Verifies the output parses as valid JSON with ok=true and
    command='listKnown', that result contains schemaVersion, dataVersion, and
    generatedUtcDate, that result.versions has 2 entries, and that the first
    entry contains verDefine, productName, regKeyRelativePath, aliases, and
    notes fields.
#>

# PESTER 5 SCOPING RULES apply here -- see Resolve-DefaultDataFilePath.Tests.ps1
# for the canonical explanation.  Dot-source TestHelpers.ps1 and the script
# under test inside BeforeAll, not at the top level of the file.

Describe 'Write-ListKnownOutput' {

  BeforeAll {
    . "$PSScriptRoot/TestHelpers.ps1"
    $script:scriptUnderTest = Get-ScriptUnderTestPath
    . $script:scriptUnderTest

    # Build a two-entry dataset matching the resolve fixture schema.
    $script:data = [pscustomobject]@{
      schemaVersion = '1.0.0'
      dataVersion   = '0.1.0'
      meta          = [pscustomobject]@{ generatedUtcDate = '2026-01-01' }
      versions      = @(
        [pscustomobject]@{
          verDefine          = 'VER150'
          productName        = 'Delphi 7'
          compilerVersion    = '15.0'
          packageVersion     = '70'
          regKeyRelativePath = '\Software\Borland\Delphi\7.0'
          aliases            = @('VER150', 'Delphi7', 'D7')
          notes              = @()
        },
        [pscustomobject]@{
          verDefine          = 'VER370'
          productName        = 'Delphi 13 Florence'
          compilerVersion    = '37.0'
          packageVersion     = '370'
          regKeyRelativePath = '\Software\Embarcadero\BDS\37.0'
          aliases            = @('VER370', 'Delphi13', 'Delphi 13 Florence', 'D13')
          notes              = @()
        }
      )
    }
  }

  Context 'Given text format with all fields populated' {

    BeforeAll {
      $script:output = Write-ListKnownOutput -Data $script:data -ToolVersion '0.1.0'
    }

    It 'output includes an entry line for VER150' {
      ($script:output -match 'VER150') | Should -Not -BeNullOrEmpty
    }

    It 'output includes an entry line for VER370' {
      ($script:output -match 'VER370') | Should -Not -BeNullOrEmpty
    }

    It 'VER150 entry line contains compilerVersion and productName values' {
      ($script:output -match 'VER150.*15\.0.*Delphi 7') | Should -Not -BeNullOrEmpty
    }

    It 'output has exactly 2 lines' {
      $script:output | Should -HaveCount 2
    }

  }

  Context 'Given -Format json with all fields populated' {

    BeforeAll {
      $script:output = Write-ListKnownOutput -Data $script:data -ToolVersion '0.1.0' -Format 'json'
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

    It 'command is listKnown' {
      $script:json.command | Should -Be 'listKnown'
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

    It 'result.versions has 2 entries' {
      $script:json.result.versions | Should -HaveCount 2
    }

    It 'first entry verDefine is VER150' {
      $script:json.result.versions[0].verDefine | Should -Be 'VER150'
    }

    It 'first entry productName is Delphi 7' {
      $script:json.result.versions[0].productName | Should -Be 'Delphi 7'
    }

    It 'first entry regKeyRelativePath is present' {
      $script:json.result.versions[0].regKeyRelativePath | Should -Not -BeNullOrEmpty
    }

    It 'first entry aliases is present' {
      $script:json.result.versions[0].aliases | Should -Not -BeNullOrEmpty
    }

    It 'first entry notes is present' {
      $script:json.result.versions[0].PSObject.Properties['notes'] | Should -Not -BeNullOrEmpty
    }

  }

}
