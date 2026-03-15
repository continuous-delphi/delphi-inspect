#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.7.0' }
<#
.SYNOPSIS
  Tests for Resolve-VersionEntry in delphi-inspect.ps1

.DESCRIPTION
  Covers: alias lookup logic across the versions array.

  Uses delphi-compiler-versions.resolve.json, which contains two entries:
    VER150 (Delphi 7)  -- aliases: VER150, Delphi7, D7
    VER370 (Delphi 13 Florence) -- aliases: VER370, Delphi13, Delphi 13 Florence, D13

  Context 1 - Match by canonical VER string:
    Verifies that the entry is found and the correct ver is returned.

  Context 2 - Match by short alias:
    Verifies that a non-VER alias (D7) resolves to the correct entry.

  Context 3 - Match by productName:
    Verifies that a productName string resolves to the correct entry.

  Context 4 - Match by alias with embedded space:
    Verifies that "Delphi 13 Florence" resolves to the VER370 entry.

  Context 5 - Case-insensitive match:
    Verifies that lower-case input ("ver150", "d7") resolves correctly.

  Context 6 - No match returns null:
    Verifies that an unknown alias causes the function to return null.

  Context 7 - Match against the second entry:
    Verifies that the scan reaches entries beyond the first.
#>

# PESTER 5 SCOPING RULES apply here -- see Resolve-DefaultDataFilePath.Tests.ps1
# for the canonical explanation.  Dot-source TestHelpers.ps1 and the script
# under test inside BeforeAll, not at the top level of the file.

Describe 'Resolve-VersionEntry' {

  BeforeAll {
    . "$PSScriptRoot/TestHelpers.ps1"
    $script:scriptUnderTest = Get-ScriptUnderTestPath
    . $script:scriptUnderTest

    $script:data = Import-JsonData -Path (Get-ResolveFixturePath)
  }

  Context 'Given the canonical VER string for the first entry' {

    It 'returns the matching entry' {
      $result = Resolve-VersionEntry -Name 'VER150' -Data $script:data
      $result | Should -Not -BeNull
    }

    It 'returned entry has the correct verDefine' {
      $result = Resolve-VersionEntry -Name 'VER150' -Data $script:data
      $result.verDefine | Should -Be 'VER150'
    }

  }

  Context 'Given a short alias for the first entry' {

    It 'returns the matching entry' {
      $result = Resolve-VersionEntry -Name 'D7' -Data $script:data
      $result | Should -Not -BeNull
    }

    It 'returned entry has the correct verDefine' {
      $result = Resolve-VersionEntry -Name 'D7' -Data $script:data
      $result.verDefine | Should -Be 'VER150'
    }

  }

  Context 'Given the productName for the first entry' {

    It 'returns the matching entry' {
      $result = Resolve-VersionEntry -Name 'Delphi 7' -Data $script:data
      $result | Should -Not -BeNull
    }

    It 'returned entry has the correct verDefine' {
      $result = Resolve-VersionEntry -Name 'Delphi 7' -Data $script:data
      $result.verDefine | Should -Be 'VER150'
    }

    It 'productName match is case-insensitive' {
      $result = Resolve-VersionEntry -Name 'delphi 7' -Data $script:data
      $result.verDefine | Should -Be 'VER150'
    }

  }

  Context 'Given an alias that contains a space' {

    It 'returns the matching entry' {
      $result = Resolve-VersionEntry -Name 'Delphi 13 Florence' -Data $script:data
      $result | Should -Not -BeNull
    }

    It 'returned entry has the correct verDefine' {
      $result = Resolve-VersionEntry -Name 'Delphi 13 Florence' -Data $script:data
      $result.verDefine | Should -Be 'VER370'
    }

  }

  Context 'Given input in a different case' {

    It 'resolves lower-case VER string to the correct entry' {
      $result = Resolve-VersionEntry -Name 'ver150' -Data $script:data
      $result.verDefine | Should -Be 'VER150'
    }

    It 'resolves lower-case short alias to the correct entry' {
      $result = Resolve-VersionEntry -Name 'd7' -Data $script:data
      $result.verDefine | Should -Be 'VER150'
    }

    It 'resolves upper-case short alias to the correct entry' {
      $result = Resolve-VersionEntry -Name 'D7' -Data $script:data
      $result.verDefine | Should -Be 'VER150'
    }

  }

  Context 'Given an alias that does not exist in the dataset' {

    It 'returns null' {
      $result = Resolve-VersionEntry -Name 'UnknownAlias' -Data $script:data
      $result | Should -BeNull
    }

    It 'returns null for an empty string' {
      $result = Resolve-VersionEntry -Name '' -Data $script:data
      $result | Should -BeNull
    }

  }

  Context 'Given the canonical VER string for the second entry' {

    It 'returns the matching entry' {
      $result = Resolve-VersionEntry -Name 'VER370' -Data $script:data
      $result | Should -Not -BeNull
    }

    It 'returned entry has the correct verDefine' {
      $result = Resolve-VersionEntry -Name 'VER370' -Data $script:data
      $result.verDefine | Should -Be 'VER370'
    }

  }

}
