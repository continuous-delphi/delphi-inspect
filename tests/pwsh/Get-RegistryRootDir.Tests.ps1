#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.7.0' }
<#
.SYNOPSIS
  Tests for Get-RegistryRootDir in delphi-inspect.ps1

.DESCRIPTION
  Covers: registry lookup behavior of Get-RegistryRootDir for absent paths
  and for a key written to HKCU.

  Context 1 - Registry path absent in both hives:
    Returns null for a guaranteed-absent subkey without throwing.

  Context 2 - Path with a leading backslash:
    TrimStart handles the leading backslash; still returns null without throwing.

  Context 3 - Key present in HKCU with a valid RootDir value:
    Writes a real temp key to HKCU, calls the function, and verifies the
    RootDir value is returned.  This proves the HKCU hive is searched.
    Proof that HKCU takes priority over HKLM when both contain the same key
    would additionally require writing to HKLM, which needs elevation and is
    not done in a standard test environment.

  NOTE: The whitespace-only RootDir fallback and the HKCU-priority-over-HKLM
  ordering cannot be verified without HKLM write access (requires elevation)
  or mocking [Microsoft.Win32.RegistryKey]::OpenBaseKey.  Those paths are
  exercised structurally through Get-DccReadiness and Get-MSBuildReadiness
  mocking.
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

  Context 'Given a key in HKCU with a valid RootDir value' {

    BeforeAll {
      $script:hkcuKeyPath     = 'HKCU:\Software\DelphiToolchainInspectTest-HKCU-00000000'
      $script:hkcuRootDirVal  = 'C:\DelphiToolchainInspectTest-RootDir'
      $null = New-Item -Path $script:hkcuKeyPath -Force
      Set-ItemProperty -Path $script:hkcuKeyPath -Name 'RootDir' -Value $script:hkcuRootDirVal
    }

    AfterAll {
      Remove-Item -Path $script:hkcuKeyPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'returns the RootDir value from HKCU (proves HKCU hive is searched)' {
      $result = Get-RegistryRootDir -RelativePath 'Software\DelphiToolchainInspectTest-HKCU-00000000'
      $result | Should -Be $script:hkcuRootDirVal
    }

  }

}
