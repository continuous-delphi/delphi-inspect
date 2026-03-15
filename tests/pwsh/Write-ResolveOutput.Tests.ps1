#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.7.0' }
<#
.SYNOPSIS
  Tests for Write-ResolveOutput in delphi-inspect.ps1

.DESCRIPTION
  Covers: output lines produced for various entry shapes.

  The label column is 20 chars wide.  Value-presence assertions use array
  -match filtering so that a future padding tweak does not produce a cryptic
  string-mismatch failure.

  Context 1 - Entry with all optional fields populated (VER370):
    Verifies all six lines are present -- verDefine, productName, compilerVersion,
    packageVersion, regKeyRelativePath, aliases -- and that
    the total line count is 6.

  Context 2 - Entry (VER150):
    Verifies the standard fields produce a total line count of 6.

  Context 3 - Aliases are comma-joined on one line:
    Verifies that multiple aliases appear as a comma-separated list.

  Context 4 - -Format json, all optional fields populated (VER370):
    Verifies the output is a single item that parses as valid JSON, ok is $true,
    command is 'resolve', and result contains verDefine and regKeyRelativePath.

  Context 5 - -Format json, VER150 entry:
    Verifies that result.verDefine is correct and that bds_reg_version is not
    present in the result object.
#>

# PESTER 5 SCOPING RULES apply here -- see Resolve-DefaultDataFilePath.Tests.ps1
# for the canonical explanation.  Dot-source TestHelpers.ps1 and the script
# under test inside BeforeAll, not at the top level of the file.

Describe 'Write-ResolveOutput' {

  BeforeAll {
    . "$PSScriptRoot/TestHelpers.ps1"
    $script:scriptUnderTest = Get-ScriptUnderTestPath
    . $script:scriptUnderTest
  }

  Context 'Given an entry with all optional fields populated' {

    BeforeAll {
      $script:entry = [pscustomobject]@{
        verDefine          = 'VER370'
        productName        = 'Delphi 13 Florence'
        compilerVersion    = '37.0'
        packageVersion     = '370'
        regKeyRelativePath = '\Software\Embarcadero\BDS\37.0'
        aliases            = @('VER370', 'Delphi13', 'Delphi 13 Florence', 'D13')
      }
      $script:output = Write-ResolveOutput -Entry $script:entry -Format 'text'
    }

    It 'output includes a line with the verDefine value' {
      ($script:output -match 'verDefine\s+VER370') | Should -Not -BeNullOrEmpty
    }

    It 'output includes a line with the productName value' {
      ($script:output -match 'productName\s+Delphi 13 Florence') | Should -Not -BeNullOrEmpty
    }

    It 'output includes a line with the compilerVersion value' {
      ($script:output -match 'compilerVersion\s+37\.0') | Should -Not -BeNullOrEmpty
    }

    It 'output includes a line with the packageVersion value' {
      ($script:output -match 'packageVersion\s+370') | Should -Not -BeNullOrEmpty
    }

    It 'output includes a line with the regKeyRelativePath value' {
      ($script:output -match 'regKeyRelativePath\s+') | Should -Not -BeNullOrEmpty
    }

    It 'output includes a line with the aliases value' {
      ($script:output -match 'aliases\s+') | Should -Not -BeNullOrEmpty
    }

    It 'output has exactly six lines' {
      $script:output | Should -HaveCount 6
    }

  }

  Context 'Given an entry for VER150' {

    BeforeAll {
      $script:entry = [pscustomobject]@{
        verDefine          = 'VER150'
        productName        = 'Delphi 7'
        compilerVersion    = '15.0'
        packageVersion     = '70'
        regKeyRelativePath = '\Software\Borland\Delphi\7.0'
        aliases            = @('VER150', 'Delphi7', 'D7')
      }
      $script:output = Write-ResolveOutput -Entry $script:entry -Format 'text'
    }

    It 'output has exactly six lines' {
      $script:output | Should -HaveCount 6
    }

  }

  Context 'Given an entry with multiple aliases' {

    BeforeAll {
      $script:entry = [pscustomobject]@{
        verDefine          = 'VER150'
        productName        = 'Delphi 7'
        compilerVersion    = '15.0'
        packageVersion     = '70'
        regKeyRelativePath = '\Software\Borland\Delphi\7.0'
        aliases            = @('VER150', 'Delphi7', 'D7')
      }
      $script:output = Write-ResolveOutput -Entry $script:entry -Format 'text'
    }

    It 'aliases line contains all aliases comma-separated' {
      ($script:output -match 'aliases\s+VER150, Delphi7, D7') | Should -Not -BeNullOrEmpty
    }

  }

  Context 'Given -Format json and all optional fields are populated' {

    BeforeAll {
      $script:entry = [pscustomobject]@{
        verDefine          = 'VER370'
        productName        = 'Delphi 13 Florence'
        compilerVersion    = '37.0'
        packageVersion     = '370'
        regKeyRelativePath = '\Software\Embarcadero\BDS\37.0'
        aliases            = @('VER370', 'Delphi13', 'Delphi 13 Florence', 'D13')
      }
      $script:output = Write-ResolveOutput -Entry $script:entry -ToolVersion '0.1.0' -Format 'json'
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

    It 'command is resolve' {
      $script:json.command | Should -Be 'resolve'
    }

    It 'result.verDefine matches the entry value' {
      $script:json.result.verDefine | Should -Be 'VER370'
    }

    It 'result.regKeyRelativePath matches the entry value' {
      $script:json.result.regKeyRelativePath | Should -Be '\Software\Embarcadero\BDS\37.0'
    }

    It 'result.aliases contains all four aliases' {
      $script:json.result.aliases | Should -HaveCount 4
    }

  }

  Context 'Given -Format json and the VER150 entry' {

    BeforeAll {
      $script:entry = [pscustomobject]@{
        verDefine          = 'VER150'
        productName        = 'Delphi 7'
        compilerVersion    = '15.0'
        packageVersion     = '70'
        regKeyRelativePath = '\Software\Borland\Delphi\7.0'
        aliases            = @('VER150', 'Delphi7', 'D7')
      }
      $script:output = Write-ResolveOutput -Entry $script:entry -ToolVersion '0.1.0' -Format 'json'
      $script:json   = $script:output | ConvertFrom-Json
    }

    It 'result.verDefine is VER150' {
      $script:json.result.verDefine | Should -Be 'VER150'
    }

    It 'result does not contain a bds_reg_version property' {
      $script:json.result.PSObject.Properties['bds_reg_version'] | Should -BeNullOrEmpty
    }

  }

  Context 'Given object format (default) and VER370 entry' {

    BeforeAll {
      $script:entry = [pscustomobject]@{
        verDefine          = 'VER370'
        productName        = 'Delphi 13 Florence'
        compilerVersion    = '37.0'
        packageVersion     = '370'
        regKeyRelativePath = '\Software\Embarcadero\BDS\37.0'
        aliases            = @('VER370', 'Delphi13', 'Delphi 13 Florence', 'D13')
      }
      $script:output = Write-ResolveOutput -Entry $script:entry
    }

    It 'emits one pscustomobject' {
      $script:output | Should -HaveCount 1
    }

    It 'has verDefine property with correct value' {
      $script:output.verDefine | Should -Be 'VER370'
    }

    It 'has productName property with correct value' {
      $script:output.productName | Should -Be 'Delphi 13 Florence'
    }

    It 'has compilerVersion property with correct value' {
      $script:output.compilerVersion | Should -Be '37.0'
    }

    It 'has packageVersion property with correct value' {
      $script:output.packageVersion | Should -Be '370'
    }

    It 'has regKeyRelativePath property with correct value' {
      $script:output.regKeyRelativePath | Should -Be '\Software\Embarcadero\BDS\37.0'
    }

    It 'has aliases property with all four entries' {
      $script:output.aliases | Should -HaveCount 4
    }

  }

}
