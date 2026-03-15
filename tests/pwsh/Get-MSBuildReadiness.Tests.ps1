#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.7.0' }
<#
.SYNOPSIS
  Tests for Get-MSBuildReadiness in delphi-inspect.ps1

.DESCRIPTION
  Covers: MSBuild readiness checks for all states.

  Context 1 - notApplicable: MSBuild not in supportedBuildSystems:
    readiness=notApplicable, registryFound=$null, Get-RegistryRootDir never called.

  Context 2 - notApplicable: Platform not in supportedPlatforms:
    readiness=notApplicable, registryFound=$null.

  Context 3 - notFound: regKeyRelativePath is null:
    readiness=notFound, registryFound=$false.

  Context 4 - notFound: registry returns null (no installation):
    readiness=notFound, registryFound=$false, component fields $null.

  Context 5 - ready: all components found (Win32):
    readiness=ready, all booleans true, rsvars.bat checked.

  Context 6 - partialInstall: rootDirExists=false:
    readiness=partialInstall.

  Context 7 - partialInstall: rsvarsFound=false:
    readiness=partialInstall, rsvarsFound=false, envOptionsFound=true.

  Context 8 - partialInstall: envOptionsFound=false:
    readiness=partialInstall, envOptionsHasLibraryPath=$null,
    Test-EnvOptionsLibraryPath never called.

  Context 9 - partialInstall: envOptionsHasLibraryPath=false:
    readiness=partialInstall, envOptionsHasLibraryPath=false.

  Context 10 - bdsVersion extracted from regKeyRelativePath leaf:
    EnvOptions.proj path uses the version component from the registry key.
#>

Describe 'Get-MSBuildReadiness' {

  BeforeAll {
    . "$PSScriptRoot/TestHelpers.ps1"
    $script:scriptUnderTest = Get-ScriptUnderTestPath
    . $script:scriptUnderTest

    $script:listInstalledFixturePath = Get-DetectFixturePath
    $script:data = Import-JsonData -Path $script:listInstalledFixturePath

    # VER150: DCC+Win32 only -- MSBuild is notApplicable
    $script:entryDccOnly      = $script:data.versions[0]
    # VER999: MSBuild+Win32 only
    $script:entryMSBuildWin32 = $script:data.versions[1]
    # VER980: DCC+MSBuild, Win32+Win64; regKeyRelativePath ends in 98.0
    $script:entryBoth         = $script:data.versions[2]

    # Synthetic entry with no regKeyRelativePath
    $script:entryNoRegKey = [pscustomobject]@{
      verDefine             = 'VER000'
      productName           = 'Delphi No RegKey'
      regKeyRelativePath    = $null
      supportedBuildSystems = @('MSBuild')
      supportedPlatforms    = @('Win32')
    }
  }

  Context 'notApplicable - MSBuild not in supportedBuildSystems' {

    BeforeAll {
      Mock Get-RegistryRootDir { return $null }
      $script:result = Get-MSBuildReadiness -Entry $script:entryDccOnly -Platform 'Win32'
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

    It 'Get-RegistryRootDir was not called' {
      Should -Invoke Get-RegistryRootDir -Times 0 -Exactly
    }

  }

  Context 'notApplicable - Platform not in supportedPlatforms' {

    BeforeAll {
      Mock Get-RegistryRootDir { return $null }
      # VER999 supports only Win32; requesting Win64 fires notApplicable
      $script:result = Get-MSBuildReadiness -Entry $script:entryMSBuildWin32 -Platform 'Win64'
    }

    It 'readiness is notApplicable' {
      $script:result.readiness | Should -Be 'notApplicable'
    }

    It 'registryFound is null' {
      $script:result.registryFound | Should -BeNull
    }

  }

  Context 'notFound - regKeyRelativePath is null' {

    BeforeAll {
      Mock Get-RegistryRootDir { return $null }
      $script:result = Get-MSBuildReadiness -Entry $script:entryNoRegKey -Platform 'Win32'
    }

    It 'readiness is notFound' {
      $script:result.readiness | Should -Be 'notFound'
    }

    It 'registryFound is false' {
      $script:result.registryFound | Should -Be $false
    }

  }

  Context 'notFound - registry returns null (no installation)' {

    BeforeAll {
      Mock Get-RegistryRootDir { return $null }
      $script:result = Get-MSBuildReadiness -Entry $script:entryBoth -Platform 'Win32'
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

  }

  Context 'ready - all components found (Win32)' {

    BeforeAll {
      Mock Get-RegistryRootDir { return 'C:\Fake\Delphi13' }
      Mock Test-Path { return $true }
      Mock Test-EnvOptionsLibraryPath { return $true }
      $script:result = Get-MSBuildReadiness -Entry $script:entryBoth -Platform 'Win32'
    }

    It 'readiness is ready' {
      $script:result.readiness | Should -Be 'ready'
    }

    It 'registryFound is true' {
      $script:result.registryFound | Should -Be $true
    }

    It 'rootDir is the value returned by Get-RegistryRootDir' {
      $script:result.rootDir | Should -Be 'C:\Fake\Delphi13'
    }

    It 'rsvarsPath is the bin\rsvars.bat path under rootDir' {
      $script:result.rsvarsPath | Should -Be 'C:\Fake\Delphi13\bin\rsvars.bat'
    }

    It 'rootDirExists is true' {
      $script:result.rootDirExists | Should -Be $true
    }

    It 'rsvarsFound is true' {
      $script:result.rsvarsFound | Should -Be $true
    }

    It 'envOptionsFound is true' {
      $script:result.envOptionsFound | Should -Be $true
    }

    It 'envOptionsHasLibraryPath is true' {
      $script:result.envOptionsHasLibraryPath | Should -Be $true
    }

    It 'checks rsvars.bat' {
      # Call inside the It so Pester 5 tracks it in this test's call history
      Get-MSBuildReadiness -Entry $script:entryBoth -Platform 'Win32' | Out-Null
      Should -Invoke Test-Path -ParameterFilter { $LiteralPath -match 'rsvars\.bat' }
    }

  }

  Context 'partialInstall - rootDirExists is false' {

    BeforeAll {
      Mock Get-RegistryRootDir { return 'C:\Fake\Delphi13' }
      Mock Test-Path { return $false }
      Mock Test-EnvOptionsLibraryPath { return $true }
      $script:result = Get-MSBuildReadiness -Entry $script:entryBoth -Platform 'Win32'
    }

    It 'readiness is partialInstall' {
      $script:result.readiness | Should -Be 'partialInstall'
    }

    It 'rootDir is the value returned by Get-RegistryRootDir' {
      $script:result.rootDir | Should -Be 'C:\Fake\Delphi13'
    }

    It 'rsvarsPath is the bin\rsvars.bat path under rootDir' {
      $script:result.rsvarsPath | Should -Be 'C:\Fake\Delphi13\bin\rsvars.bat'
    }

    It 'rootDirExists is false' {
      $script:result.rootDirExists | Should -Be $false
    }

  }

  Context 'partialInstall - rsvarsFound is false, others true' {

    BeforeAll {
      Mock Get-RegistryRootDir { return 'C:\Fake\Delphi13' }
      Mock Test-Path -ParameterFilter { $LiteralPath -match 'rsvars\.bat' } { return $false }
      Mock Test-Path { return $true }
      Mock Test-EnvOptionsLibraryPath { return $true }
      $script:result = Get-MSBuildReadiness -Entry $script:entryBoth -Platform 'Win32'
    }

    It 'readiness is partialInstall' {
      $script:result.readiness | Should -Be 'partialInstall'
    }

    It 'rsvarsFound is false' {
      $script:result.rsvarsFound | Should -Be $false
    }

    It 'envOptionsFound is true' {
      $script:result.envOptionsFound | Should -Be $true
    }

  }

  Context 'partialInstall - envOptionsFound is false' {

    BeforeAll {
      Mock Get-RegistryRootDir { return 'C:\Fake\Delphi13' }
      Mock Test-Path -ParameterFilter { $LiteralPath -match 'EnvOptions\.proj' } { return $false }
      Mock Test-Path { return $true }
      Mock Test-EnvOptionsLibraryPath { return $true }
      $script:result = Get-MSBuildReadiness -Entry $script:entryBoth -Platform 'Win32'
    }

    It 'readiness is partialInstall' {
      $script:result.readiness | Should -Be 'partialInstall'
    }

    It 'envOptionsFound is false' {
      $script:result.envOptionsFound | Should -Be $false
    }

    It 'envOptionsHasLibraryPath is null when envOptionsFound is false' {
      $script:result.envOptionsHasLibraryPath | Should -BeNull
    }

    It 'Test-EnvOptionsLibraryPath was not called' {
      Should -Invoke Test-EnvOptionsLibraryPath -Times 0 -Exactly
    }

  }

  Context 'partialInstall - envOptionsHasLibraryPath is false' {

    BeforeAll {
      Mock Get-RegistryRootDir { return 'C:\Fake\Delphi13' }
      Mock Test-Path { return $true }
      Mock Test-EnvOptionsLibraryPath { return $false }
      $script:result = Get-MSBuildReadiness -Entry $script:entryBoth -Platform 'Win32'
    }

    It 'readiness is partialInstall' {
      $script:result.readiness | Should -Be 'partialInstall'
    }

    It 'envOptionsHasLibraryPath is false' {
      $script:result.envOptionsHasLibraryPath | Should -Be $false
    }

  }

  Context 'bdsVersion extracted from regKeyRelativePath leaf' {

    BeforeAll {
      Mock Get-RegistryRootDir { return 'C:\Fake\Delphi13' }
      Mock Test-Path { return $true }
      Mock Test-EnvOptionsLibraryPath { return $true }
      $script:result = Get-MSBuildReadiness -Entry $script:entryBoth -Platform 'Win32'
    }

    It 'EnvOptions.proj path contains the bdsVersion leaf (98.0) from regKeyRelativePath' {
      # Call inside the It so Pester 5 tracks it in this test's call history
      # VER980 regKeyRelativePath ends in 98.0; the constructed path must include it
      Get-MSBuildReadiness -Entry $script:entryBoth -Platform 'Win32' | Out-Null
      Should -Invoke Test-Path -ParameterFilter {
        $LiteralPath -match '98\.0' -and $LiteralPath -match 'EnvOptions\.proj'
      }
    }

  }

}
