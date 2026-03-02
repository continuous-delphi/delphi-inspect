#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.7.0' }
<#
.SYNOPSIS
  Tests for Get-RegistryRootDir in delphi-toolchain-inspect.ps1

.DESCRIPTION
  Covers: registry lookup behavior of Get-RegistryRootDir for absent paths.

  Context 1 - Registry path absent in both hives:
    Returns null for a guaranteed-absent subkey without throwing.

  Context 2 - Path with a leading backslash:
    TrimStart handles the leading backslash; still returns null without throwing.

  NOTE: The CurrentUser-before-LocalMachine fallback and the whitespace-RootDir
  fallback cannot be tested without mocking static .NET methods
  ([Microsoft.Win32.RegistryKey]::OpenBaseKey).  Those paths are exercised
  structurally through Get-DccReadiness and Get-MSBuildReadiness mocking.
#>

# PESTER 5 SCOPING RULES apply here -- see Resolve-DefaultDataFilePath.Tests.ps1
# for the canonical explanation.  Dot-source TestHelpers.ps1 and the script
# under test inside BeforeAll, not at the top level of the file.

Describe 'Get-RegistryRootDir' {

  BeforeAll {
    . "$PSScriptRoot/TestHelpers.ps1"
    $script:scriptUnderTest = Get-ScriptUnderTestPath
    . $script:scriptUnderTest
  }

  Context 'Given a registry path that does not exist in either hive' {

    It 'returns null without throwing' {
      $result = Get-RegistryRootDir -RelativePath 'Software\DelphiToolchainInspectTest-NonExistent-00000000'
      $result | Should -BeNull
    }

  }

  Context 'Given a registry path with a leading backslash' {

    It 'returns null without throwing (TrimStart handles leading backslash)' {
      $result = Get-RegistryRootDir -RelativePath '\Software\DelphiToolchainInspectTest-NonExistent-00000000'
      $result | Should -BeNull
    }

  }

}
