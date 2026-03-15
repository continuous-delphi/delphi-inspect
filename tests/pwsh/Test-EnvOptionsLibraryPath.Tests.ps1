#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.7.0' }
<#
.SYNOPSIS
  Tests for Test-EnvOptionsLibraryPath in delphi-inspect.ps1

.DESCRIPTION
  Covers: XML parsing of EnvOptions.proj to detect Delphi library path properties.

  Context 1 - Win32, DelphiLibraryPath present and non-empty:
    Returns true, does not throw.

  Context 2 - Win64, DelphiLibraryPath present and non-empty (in a Win64 PropertyGroup):
    Returns true.

  Context 3 - Win32, DelphiLibraryPath node missing:
    Returns false.

  Context 4 - Win32, DelphiLibraryPath present but empty:
    Returns false.

  Context 5 - File does not exist:
    Returns false, does not throw.

  Context 6 - File contains malformed XML:
    Returns false, does not throw.
#>

Describe 'Test-EnvOptionsLibraryPath' {

  BeforeAll {
    . "$PSScriptRoot/TestHelpers.ps1"
    $script:scriptUnderTest = Get-ScriptUnderTestPath
    . $script:scriptUnderTest

    $script:tmp = [System.IO.Path]::GetTempPath()
  }

  Context 'Win32 - DelphiLibraryPath present and non-empty' {

    BeforeAll {
      $script:xmlPath = Join-Path $script:tmp 'envopts-win32-nonempty.proj'
      Set-Content -LiteralPath $script:xmlPath -Encoding UTF8NoBOM -Value @'
<?xml version="1.0"?>
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup>
    <DelphiLibraryPath>C:\Embarcadero\Studio\7.0\lib\win32\release</DelphiLibraryPath>
  </PropertyGroup>
</Project>
'@
    }

    AfterAll {
      if (Test-Path -LiteralPath $script:xmlPath) { Remove-Item -LiteralPath $script:xmlPath -Force }
    }

    It 'returns true' {
      Test-EnvOptionsLibraryPath -Path $script:xmlPath -Platform 'Win32' | Should -Be $true
    }

    It 'does not throw' {
      { Test-EnvOptionsLibraryPath -Path $script:xmlPath -Platform 'Win32' } | Should -Not -Throw
    }

  }

  Context 'Win64 - DelphiLibraryPath present and non-empty' {

    BeforeAll {
      # RAD Studio stores library paths as 'DelphiLibraryPath' for all platforms.
      # The Win64 PropertyGroup uses a Condition attribute to scope it; the element
      # name is identical to Win32.
      $script:xmlPath = Join-Path $script:tmp 'envopts-win64-nonempty.proj'
      Set-Content -LiteralPath $script:xmlPath -Encoding UTF8NoBOM -Value @'
<?xml version="1.0"?>
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup Condition="'$(Platform)'=='Win64'">
    <DelphiLibraryPath>C:\Embarcadero\Studio\37.0\lib\win64\release</DelphiLibraryPath>
  </PropertyGroup>
</Project>
'@
    }

    AfterAll {
      if (Test-Path -LiteralPath $script:xmlPath) { Remove-Item -LiteralPath $script:xmlPath -Force }
    }

    It 'returns true for Win64 with non-empty DelphiLibraryPath' {
      Test-EnvOptionsLibraryPath -Path $script:xmlPath -Platform 'Win64' | Should -Be $true
    }

  }

  Context 'Win32 - DelphiLibraryPath node missing from XML' {

    BeforeAll {
      $script:xmlPath = Join-Path $script:tmp 'envopts-win32-missing.proj'
      Set-Content -LiteralPath $script:xmlPath -Encoding UTF8NoBOM -Value @'
<?xml version="1.0"?>
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup>
    <SomeOtherProperty>value</SomeOtherProperty>
  </PropertyGroup>
</Project>
'@
    }

    AfterAll {
      if (Test-Path -LiteralPath $script:xmlPath) { Remove-Item -LiteralPath $script:xmlPath -Force }
    }

    It 'returns false when DelphiLibraryPath is absent' {
      Test-EnvOptionsLibraryPath -Path $script:xmlPath -Platform 'Win32' | Should -Be $false
    }

  }

  Context 'Win32 - DelphiLibraryPath present but empty' {

    BeforeAll {
      $script:xmlPath = Join-Path $script:tmp 'envopts-win32-empty.proj'
      Set-Content -LiteralPath $script:xmlPath -Encoding UTF8NoBOM -Value @'
<?xml version="1.0"?>
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup>
    <DelphiLibraryPath></DelphiLibraryPath>
  </PropertyGroup>
</Project>
'@
    }

    AfterAll {
      if (Test-Path -LiteralPath $script:xmlPath) { Remove-Item -LiteralPath $script:xmlPath -Force }
    }

    It 'returns false when DelphiLibraryPath is empty' {
      Test-EnvOptionsLibraryPath -Path $script:xmlPath -Platform 'Win32' | Should -Be $false
    }

  }

  Context 'File does not exist' {

    BeforeAll {
      $script:missingPath = Join-Path $script:tmp 'envopts-nonexistent-xyzzy.proj'
    }

    It 'returns false' {
      Test-EnvOptionsLibraryPath -Path $script:missingPath -Platform 'Win32' | Should -Be $false
    }

    It 'does not throw' {
      { Test-EnvOptionsLibraryPath -Path $script:missingPath -Platform 'Win32' } | Should -Not -Throw
    }

  }

  Context 'File contains malformed XML' {

    BeforeAll {
      $script:xmlPath = Join-Path $script:tmp 'envopts-malformed.proj'
      Set-Content -LiteralPath $script:xmlPath -Value '< not valid xml >' -Encoding UTF8NoBOM
    }

    AfterAll {
      if (Test-Path -LiteralPath $script:xmlPath) { Remove-Item -LiteralPath $script:xmlPath -Force }
    }

    It 'returns false for malformed XML' {
      Test-EnvOptionsLibraryPath -Path $script:xmlPath -Platform 'Win32' | Should -Be $false
    }

    It 'does not throw for malformed XML' {
      { Test-EnvOptionsLibraryPath -Path $script:xmlPath -Platform 'Win32' } | Should -Not -Throw
    }

  }

}
