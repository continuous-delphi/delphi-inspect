#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.7.0' }
<#
.SYNOPSIS
  Tests for Get-DccReadiness in delphi-inspect.ps1

.DESCRIPTION
  Covers: DCC readiness checks for all states.

  Context 1 - notApplicable: DCC not in supportedBuildSystems:
    readiness=notApplicable, registryFound=$null, all component fields $null,
    Get-RegistryRootDir never called.

  Context 2 - notApplicable: Platform not in supportedPlatforms:
    readiness=notApplicable, registryFound=$null, Get-RegistryRootDir never called.

  Context 3 - notFound: regKeyRelativePath is null:
    readiness=notFound, registryFound=$false, component fields $null.

  Context 4 - notFound: registry returns null (no installation):
    readiness=notFound, registryFound=$false, component fields $null.

  Context 5 - ready: all components present (Win32):
    readiness=ready, all booleans true, dcc32.exe and dcc32.cfg checked.

  Context 6 - ready: all components present (Win64):
    readiness=ready, dcc64.exe and dcc64.cfg checked.

  Context 7 - partialInstall: rootDirExists=false:
    readiness=partialInstall, registryFound=true, rootDirExists=false.

  Context 8 - partialInstall: compilerFound=false:
    readiness=partialInstall, compilerFound=false, cfgFound=true.

  Context 9 - partialInstall: cfgFound=false:
    readiness=partialInstall, cfgFound=false, compilerFound=true.
#>

Describe 'Get-DccReadiness' {

  BeforeAll {
    . "$PSScriptRoot/TestHelpers.ps1"
    $script:scriptUnderTest = Get-ScriptUnderTestPath
    . $script:scriptUnderTest

    $script:listInstalledFixturePath = Get-DetectFixturePath
    $script:data = Import-JsonData -Path $script:listInstalledFixturePath

    # VER150: DCC+Win32 only
    $script:entryDccWin32    = $script:data.versions[0]
    # VER999: MSBuild+Win32 only -- DCC is notApplicable
    $script:entryMSBuildOnly = $script:data.versions[1]
    # VER998: DCC+MSBuild, Win32+Win64
    $script:entryBoth        = $script:data.versions[2]

    # Synthetic entry with no regKeyRelativePath (covers early-return path)
    $script:entryNoRegKey = [pscustomobject]@{
      verDefine             = 'VER000'
      productName           = 'Delphi No RegKey'
      regKeyRelativePath    = $null
      supportedBuildSystems = @('DCC')
      supportedPlatforms    = @('Win32')
    }
  }

  Context 'notApplicable - DCC not in supportedBuildSystems' {

    BeforeAll {
      Mock Get-RegistryRootDir { return $null }
      $script:result = Get-DccReadiness -Entry $script:entryMSBuildOnly -Platform 'Win32'
    }

    It 'readiness is notApplicable' {
      $script:result.readiness | Should -Be 'notApplicable'
    }

    It 'registryFound is null' {
      $script:result.registryFound | Should -BeNull
    }

    It 'rootDirExists is null' {
      $script:result.rootDirExists | Should -BeNull
    }

    It 'compilerFound is null' {
      $script:result.compilerFound | Should -BeNull
    }

    It 'cfgFound is null' {
      $script:result.cfgFound | Should -BeNull
    }

    It 'Get-RegistryRootDir was not called' {
      Should -Invoke Get-RegistryRootDir -Times 0 -Exactly
    }

  }

  Context 'notApplicable - Platform not in supportedPlatforms' {

    BeforeAll {
      Mock Get-RegistryRootDir { return $null }
      # VER150 supports only Win32; requesting Win64 fires notApplicable
      $script:result = Get-DccReadiness -Entry $script:entryDccWin32 -Platform 'Win64'
    }

    It 'readiness is notApplicable' {
      $script:result.readiness | Should -Be 'notApplicable'
    }

    It 'registryFound is null' {
      $script:result.registryFound | Should -BeNull
    }

    It 'Get-RegistryRootDir was not called' {
      Should -Invoke Get-RegistryRootDir -Times 0 -Exactly
    }

  }

  Context 'notFound - regKeyRelativePath is null' {

    BeforeAll {
      Mock Get-RegistryRootDir { return $null }
      $script:result = Get-DccReadiness -Entry $script:entryNoRegKey -Platform 'Win32'
    }

    It 'readiness is notFound' {
      $script:result.readiness | Should -Be 'notFound'
    }

    It 'registryFound is false' {
      $script:result.registryFound | Should -Be $false
    }

    It 'component fields are null' {
      $script:result.rootDirExists | Should -BeNull
      $script:result.compilerFound | Should -BeNull
      $script:result.cfgFound      | Should -BeNull
    }

  }

  Context 'notFound - registry returns null (no installation)' {

    BeforeAll {
      Mock Get-RegistryRootDir { return $null }
      $script:result = Get-DccReadiness -Entry $script:entryDccWin32 -Platform 'Win32'
    }

    It 'readiness is notFound' {
      $script:result.readiness | Should -Be 'notFound'
    }

    It 'registryFound is false' {
      $script:result.registryFound | Should -Be $false
    }

    It 'rootDirExists is null' {
      $script:result.rootDirExists | Should -BeNull
    }

    It 'compilerFound is null' {
      $script:result.compilerFound | Should -BeNull
    }

    It 'cfgFound is null' {
      $script:result.cfgFound | Should -BeNull
    }

  }

  Context 'ready - all components present (Win32)' {

    BeforeAll {
      Mock Get-RegistryRootDir { return 'C:\Fake\Delphi7' }
      Mock Test-Path { return $true }
      $script:result = Get-DccReadiness -Entry $script:entryDccWin32 -Platform 'Win32'
    }

    It 'readiness is ready' {
      $script:result.readiness | Should -Be 'ready'
    }

    It 'registryFound is true' {
      $script:result.registryFound | Should -Be $true
    }

    It 'rootDir is the value returned by Get-RegistryRootDir' {
      $script:result.rootDir | Should -Be 'C:\Fake\Delphi7'
    }

    It 'rootDirExists is true' {
      $script:result.rootDirExists | Should -Be $true
    }

    It 'compilerFound is true' {
      $script:result.compilerFound | Should -Be $true
    }

    It 'cfgFound is true' {
      $script:result.cfgFound | Should -Be $true
    }

    It 'checks dcc32.exe for Win32' {
      # Call inside the It so Pester 5 tracks it in this test's call history
      Get-DccReadiness -Entry $script:entryDccWin32 -Platform 'Win32' | Out-Null
      Should -Invoke Test-Path -ParameterFilter { $LiteralPath -match 'dcc32\.exe' }
    }

    It 'checks dcc32.cfg for Win32' {
      # Call inside the It so Pester 5 tracks it in this test's call history
      Get-DccReadiness -Entry $script:entryDccWin32 -Platform 'Win32' | Out-Null
      Should -Invoke Test-Path -ParameterFilter { $LiteralPath -match 'dcc32\.cfg' }
    }

  }

  Context 'ready - all components present (Win64)' {

    BeforeAll {
      Mock Get-RegistryRootDir { return 'C:\Fake\Delphi13' }
      Mock Test-Path { return $true }
      $script:result = Get-DccReadiness -Entry $script:entryBoth -Platform 'Win64'
    }

    It 'readiness is ready' {
      $script:result.readiness | Should -Be 'ready'
    }

    It 'checks dcc64.exe for Win64' {
      # Call inside the It so Pester 5 tracks it in this test's call history
      Get-DccReadiness -Entry $script:entryBoth -Platform 'Win64' | Out-Null
      Should -Invoke Test-Path -ParameterFilter { $LiteralPath -match 'dcc64\.exe' }
    }

    It 'checks dcc64.cfg for Win64' {
      # Call inside the It so Pester 5 tracks it in this test's call history
      Get-DccReadiness -Entry $script:entryBoth -Platform 'Win64' | Out-Null
      Should -Invoke Test-Path -ParameterFilter { $LiteralPath -match 'dcc64\.cfg' }
    }

  }

  Context 'partialInstall - rootDirExists is false (all Test-Path return false)' {

    BeforeAll {
      Mock Get-RegistryRootDir { return 'C:\Fake\Delphi7' }
      Mock Test-Path { return $false }
      $script:result = Get-DccReadiness -Entry $script:entryDccWin32 -Platform 'Win32'
    }

    It 'readiness is partialInstall' {
      $script:result.readiness | Should -Be 'partialInstall'
    }

    It 'registryFound is true' {
      $script:result.registryFound | Should -Be $true
    }

    It 'rootDir is the value returned by Get-RegistryRootDir' {
      $script:result.rootDir | Should -Be 'C:\Fake\Delphi7'
    }

    It 'rootDirExists is false' {
      $script:result.rootDirExists | Should -Be $false
    }

  }

  Context 'partialInstall - compilerFound is false, others true' {

    BeforeAll {
      Mock Get-RegistryRootDir { return 'C:\Fake\Delphi7' }
      Mock Test-Path -ParameterFilter { $LiteralPath -match 'dcc32\.exe' } { return $false }
      Mock Test-Path { return $true }
      $script:result = Get-DccReadiness -Entry $script:entryDccWin32 -Platform 'Win32'
    }

    It 'readiness is partialInstall' {
      $script:result.readiness | Should -Be 'partialInstall'
    }

    It 'compilerFound is false' {
      $script:result.compilerFound | Should -Be $false
    }

    It 'cfgFound is true' {
      $script:result.cfgFound | Should -Be $true
    }

    It 'rootDirExists is true' {
      $script:result.rootDirExists | Should -Be $true
    }

  }

  Context 'partialInstall - cfgFound is false, others true' {

    BeforeAll {
      Mock Get-RegistryRootDir { return 'C:\Fake\Delphi7' }
      Mock Test-Path -ParameterFilter { $LiteralPath -match 'dcc32\.cfg' } { return $false }
      Mock Test-Path { return $true }
      $script:result = Get-DccReadiness -Entry $script:entryDccWin32 -Platform 'Win32'
    }

    It 'readiness is partialInstall' {
      $script:result.readiness | Should -Be 'partialInstall'
    }

    It 'cfgFound is false' {
      $script:result.cfgFound | Should -Be $false
    }

    It 'compilerFound is true' {
      $script:result.compilerFound | Should -Be $true
    }

  }

}
