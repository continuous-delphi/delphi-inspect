#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.7.0' }
<#
.SYNOPSIS
  Tests for Write-ListInstalledOutput in delphi-inspect.ps1

.DESCRIPTION
  Covers: text and JSON output formatting for -ListInstalled results.
  No mocking required -- in-memory pscustomobject arrays are passed directly.

  Context 1 - Text, DCC, all entries notFound or notApplicable:
    Emits exactly one line: "No installations found".

  Context 2 - Text, DCC, one ready entry:
    Header line, readiness/registryFound/rootDirExists/compilerFound/cfgFound lines.
    No MSBuild-specific lines.

  Context 3 - Text, DCC, two entries (blank-line separator):
    Two header lines present; at least one blank separator between blocks.

  Context 4 - Text, DCC, notFound and notApplicable entries suppressed:
    Only ready/partialInstall entries appear in text output.

  Context 5 - Text, MSBuild, partialInstall with null envOptionsHasLibraryPath:
    Shows "null" for envOptionsHasLibraryPath; no DCC-specific lines.

  Context 6 - JSON, DCC mode:
    ok=true, command=listInstalled, result.platform/buildSystem/installations.
    notApplicable entry has registryFound=null; notFound entry has registryFound=false.

  Context 7 - JSON, MSBuild mode:
    result.buildSystem=MSBuild; MSBuild-specific fields present on entries.
    notApplicable entry has registryFound=null.
#>

Describe 'Write-ListInstalledOutput' {

  BeforeAll {
    . "$PSScriptRoot/TestHelpers.ps1"
    $script:scriptUnderTest = Get-ScriptUnderTestPath
    . $script:scriptUnderTest

    $script:toolVersion = '0.1.0'

    # ---- DCC in-memory fixtures ----

    $script:readyDcc = [pscustomobject]@{
      verDefine     = 'VER150'
      productName   = 'Delphi 7'
      readiness     = 'ready'
      registryFound = $true
      rootDir       = 'C:\Fake\Delphi7'
      rootDirExists = $true
      compilerFound = $true
      cfgFound      = $true
    }

    $script:partialDcc = [pscustomobject]@{
      verDefine     = 'VER370'
      productName   = 'Delphi 13 Florence'
      readiness     = 'partialInstall'
      registryFound = $true
      rootDir       = 'C:\Fake\Delphi13'
      rootDirExists = $true
      compilerFound = $false
      cfgFound      = $true
    }

    $script:notFoundDcc = [pscustomobject]@{
      verDefine     = 'VER000'
      productName   = 'Delphi Ghost'
      readiness     = 'notFound'
      registryFound = $false
      rootDir       = $null
      rootDirExists = $null
      compilerFound = $null
      cfgFound      = $null
    }

    $script:notApplicableDcc = [pscustomobject]@{
      verDefine     = 'VER999'
      productName   = 'Delphi Synthetic'
      readiness     = 'notApplicable'
      registryFound = $null
      rootDir       = $null
      rootDirExists = $null
      compilerFound = $null
      cfgFound      = $null
    }

    # ---- MSBuild in-memory fixtures ----

    $script:readyMSBuild = [pscustomobject]@{
      verDefine                = 'VER370'
      productName              = 'Delphi 13 Florence'
      readiness                = 'ready'
      registryFound            = $true
      rootDir                  = 'C:\Fake\Delphi13'
      rsvarsPath               = 'C:\Fake\Delphi13\bin\rsvars.bat'
      rootDirExists            = $true
      rsvarsFound              = $true
      compilerFound            = $true
      envOptionsFound          = $true
      envOptionsHasLibraryPath = $true
    }

    $script:partialMSBuildNoEnvOpts = [pscustomobject]@{
      verDefine                = 'VER370'
      productName              = 'Delphi 13 Florence'
      readiness                = 'partialInstall'
      registryFound            = $true
      rootDir                  = 'C:\Fake\Delphi13'
      rsvarsPath               = 'C:\Fake\Delphi13\bin\rsvars.bat'
      rootDirExists            = $true
      rsvarsFound              = $true
      compilerFound            = $true
      envOptionsFound          = $false
      envOptionsHasLibraryPath = $null
    }

    $script:notFoundMSBuild = [pscustomobject]@{
      verDefine                = 'VER999'
      productName              = 'Delphi Synthetic'
      readiness                = 'notFound'
      registryFound            = $false
      rootDir                  = $null
      rsvarsPath               = $null
      rootDirExists            = $null
      rsvarsFound              = $null
      compilerFound            = $null
      envOptionsFound          = $null
      envOptionsHasLibraryPath = $null
    }

    $script:notApplicableMSBuild = [pscustomobject]@{
      verDefine                = 'VER150'
      productName              = 'Delphi 7'
      readiness                = 'notApplicable'
      registryFound            = $null
      rootDir                  = $null
      rsvarsPath               = $null
      rootDirExists            = $null
      rsvarsFound              = $null
      compilerFound            = $null
      envOptionsFound          = $null
      envOptionsHasLibraryPath = $null
    }
  }

  Context 'Text, DCC, empty Installations array' {

    BeforeAll {
      $script:out = Write-ListInstalledOutput `
        -Installations @() `
        -Platform 'Win32' -BuildSystem 'DCC' `
        -ToolVersion $script:toolVersion `
        -Format 'text'
    }

    It 'emits exactly one line' {
      $script:out | Should -HaveCount 1
    }

    It 'line is "No installations found"' {
      $script:out | Should -Be 'No installations found'
    }

  }

  Context 'Text, DCC, one ready entry' {

    BeforeAll {
      $script:out = Write-ListInstalledOutput `
        -Installations @($script:readyDcc) `
        -Platform 'Win32' -BuildSystem 'DCC' `
        -ToolVersion $script:toolVersion `
        -Format 'text'
    }

    It 'first line contains verDefine and productName' {
      $script:out[0] | Should -Match 'VER150\s+Delphi 7'
    }

    It 'includes a readiness line showing ready' {
      ($script:out -match 'readiness\s+ready') | Should -Not -BeNullOrEmpty
    }

    It 'includes a registryFound line showing true' {
      ($script:out -match 'registryFound\s+true') | Should -Not -BeNullOrEmpty
    }

    It 'includes a rootDirExists line showing true' {
      ($script:out -match 'rootDirExists\s+true') | Should -Not -BeNullOrEmpty
    }

    It 'includes a compilerFound line showing true' {
      ($script:out -match 'compilerFound\s+true') | Should -Not -BeNullOrEmpty
    }

    It 'includes a cfgFound line showing true' {
      ($script:out -match 'cfgFound\s+true') | Should -Not -BeNullOrEmpty
    }

    It 'does not include MSBuild-specific rsvarsFound line' {
      ($script:out -match '^\s+rsvarsFound') | Should -BeNullOrEmpty
    }

    It 'does not include MSBuild-specific envOptionsFound line' {
      ($script:out -match '^\s+envOptionsFound') | Should -BeNullOrEmpty
    }

  }

  Context 'Text, DCC, two entries separated by a blank line' {

    BeforeAll {
      $script:out = Write-ListInstalledOutput `
        -Installations @($script:readyDcc, $script:partialDcc) `
        -Platform 'Win32' -BuildSystem 'DCC' `
        -ToolVersion $script:toolVersion `
        -Format 'text'
    }

    It 'blank separator line is positioned between the two header lines' {
      # @() forces empty array -- Where-Object returns $null under StrictMode when no matches
      $headerIdx = @(0..($script:out.Count - 1) | Where-Object { $script:out[$_] -match '^VER' })
      $blankIdx  = @(0..($script:out.Count - 1) | Where-Object { $script:out[$_] -eq '' })
      $headerIdx | Should -HaveCount 2
      $blankIdx  | Should -Not -BeNullOrEmpty
      $blankIdx[0] | Should -BeGreaterThan $headerIdx[0]
      $blankIdx[0] | Should -BeLessThan    $headerIdx[1]
    }

  }

  Context 'Text, DCC, all received entries emitted (no internal filter)' {

    BeforeAll {
      $script:out = Write-ListInstalledOutput `
        -Installations @($script:notFoundDcc, $script:readyDcc, $script:notApplicableDcc) `
        -Platform 'Win32' -BuildSystem 'DCC' `
        -ToolVersion $script:toolVersion `
        -Format 'text'
    }

    It 'ready entry VER150 appears in output' {
      ($script:out -match 'VER150') | Should -Not -BeNullOrEmpty
    }

    It 'notFound entry VER000 also appears in output (no internal filter)' {
      ($script:out -match 'VER000') | Should -Not -BeNullOrEmpty
    }

    It 'notApplicable entry VER999 also appears in output (no internal filter)' {
      ($script:out -match 'VER999') | Should -Not -BeNullOrEmpty
    }

  }

  Context 'Text, MSBuild, partialInstall with null envOptionsHasLibraryPath' {

    BeforeAll {
      $script:out = Write-ListInstalledOutput `
        -Installations @($script:partialMSBuildNoEnvOpts) `
        -Platform 'Win32' -BuildSystem 'MSBuild' `
        -ToolVersion $script:toolVersion `
        -Format 'text'
    }

    It 'includes a rsvarsFound line' {
      ($script:out -match 'rsvarsFound\s+true') | Should -Not -BeNullOrEmpty
    }

    It 'includes a compilerFound line showing true' {
      ($script:out -match 'compilerFound\s+true') | Should -Not -BeNullOrEmpty
    }

    It 'includes an envOptionsFound line showing false' {
      ($script:out -match 'envOptionsFound\s+false') | Should -Not -BeNullOrEmpty
    }

    It 'includes envOptionsHasLibraryPath line showing null' {
      ($script:out -match 'envOptionsHasLibraryPath\s+null') | Should -Not -BeNullOrEmpty
    }

    It 'does not include DCC-specific cfgFound line' {
      ($script:out -match '^\s+cfgFound') | Should -BeNullOrEmpty
    }

  }

  Context 'JSON, DCC mode - structure and readiness distinctions' {

    BeforeAll {
      $rawOut = Write-ListInstalledOutput `
        -Installations @($script:readyDcc, $script:notFoundDcc, $script:notApplicableDcc) `
        -Platform 'Win32' -BuildSystem 'DCC' `
        -ToolVersion $script:toolVersion -Format 'json'
      $script:json = ($rawOut -join "`n") | ConvertFrom-Json
    }

    It 'output parses as valid JSON' {
      { ($rawOut -join "`n") | ConvertFrom-Json } | Should -Not -Throw
    }

    It 'ok is true' {
      $script:json.ok | Should -Be $true
    }

    It 'command is listInstalled' {
      $script:json.command | Should -Be 'listInstalled'
    }

    It 'result.platform is Win32' {
      $script:json.result.platform | Should -Be 'Win32'
    }

    It 'result.buildSystem is DCC' {
      $script:json.result.buildSystem | Should -Be 'DCC'
    }

    It 'result.installations has 3 entries (one per in-memory input)' {
      # Count matches the 3 pscustomobjects passed to the function above.
      $script:json.result.installations | Should -HaveCount 3
    }

    It 'ready entry has compilerFound field' {
      $entry = @($script:json.result.installations | Where-Object { $_.readiness -eq 'ready' })[0]
      $entry | Should -Not -BeNull
      $entry.compilerFound | Should -Be $true
    }

    It 'ready entry has rootDir field' {
      $entry = @($script:json.result.installations | Where-Object { $_.readiness -eq 'ready' })[0]
      $entry.rootDir | Should -Be 'C:\Fake\Delphi7'
    }

    It 'notApplicable entry has registryFound=null and rootDir=null' {
      $entry = @($script:json.result.installations | Where-Object { $_.readiness -eq 'notApplicable' })[0]
      $entry | Should -Not -BeNull
      $entry.registryFound | Should -BeNull
      $entry.rootDir       | Should -BeNull
    }

    It 'notFound entry has registryFound=false and rootDir=null' {
      $entry = @($script:json.result.installations | Where-Object { $_.readiness -eq 'notFound' })[0]
      $entry | Should -Not -BeNull
      $entry.registryFound | Should -Be $false
      $entry.rootDir       | Should -BeNull
    }

  }

  Context 'JSON, MSBuild mode - MSBuild-specific fields' {

    BeforeAll {
      $rawOut = Write-ListInstalledOutput `
        -Installations @($script:readyMSBuild, $script:notApplicableMSBuild) `
        -Platform 'Win32' -BuildSystem 'MSBuild' `
        -ToolVersion $script:toolVersion -Format 'json'
      $script:json = ($rawOut -join "`n") | ConvertFrom-Json
    }

    It 'result.buildSystem is MSBuild' {
      $script:json.result.buildSystem | Should -Be 'MSBuild'
    }

    It 'ready MSBuild entry has rootDir field' {
      $entry = @($script:json.result.installations | Where-Object { $_.readiness -eq 'ready' })[0]
      $entry.rootDir | Should -Be 'C:\Fake\Delphi13'
    }

    It 'ready MSBuild entry has rsvarsPath field' {
      $entry = @($script:json.result.installations | Where-Object { $_.readiness -eq 'ready' })[0]
      $entry.rsvarsPath | Should -Be 'C:\Fake\Delphi13\bin\rsvars.bat'
    }

    It 'ready MSBuild entry has rsvarsFound field' {
      $entry = @($script:json.result.installations | Where-Object { $_.readiness -eq 'ready' })[0]
      $entry.rsvarsFound | Should -Be $true
    }

    It 'ready MSBuild entry has compilerFound field' {
      $entry = @($script:json.result.installations | Where-Object { $_.readiness -eq 'ready' })[0]
      $entry.compilerFound | Should -Be $true
    }

    It 'ready MSBuild entry has envOptionsFound field' {
      $entry = @($script:json.result.installations | Where-Object { $_.readiness -eq 'ready' })[0]
      $entry.envOptionsFound | Should -Be $true
    }

    It 'ready MSBuild entry has envOptionsHasLibraryPath field' {
      $entry = @($script:json.result.installations | Where-Object { $_.readiness -eq 'ready' })[0]
      $entry.envOptionsHasLibraryPath | Should -Be $true
    }

    It 'notApplicable MSBuild entry has registryFound=null' {
      $entry = @($script:json.result.installations | Where-Object { $_.readiness -eq 'notApplicable' })[0]
      $entry.registryFound | Should -BeNull
    }

  }

  Context 'Object format (default), emits all received entries as objects (no internal filter)' {

    BeforeAll {
      $script:objOut = @(Write-ListInstalledOutput `
        -Installations @($script:readyDcc, $script:notFoundDcc, $script:notApplicableDcc) `
        -Platform 'Win32' -BuildSystem 'DCC' `
        -ToolVersion $script:toolVersion)
    }

    It 'emits all three received entries' {
      $script:objOut | Should -HaveCount 3
    }

    It 'each entry is the original pscustomobject (passthrough)' {
      $script:objOut[0].verDefine | Should -Be 'VER150'
      $script:objOut[1].verDefine | Should -Be 'VER000'
      $script:objOut[2].verDefine | Should -Be 'VER999'
    }

    It 'readiness values are preserved on emitted objects' {
      $script:objOut[0].readiness | Should -Be 'ready'
      $script:objOut[1].readiness | Should -Be 'notFound'
      $script:objOut[2].readiness | Should -Be 'notApplicable'
    }

  }

  Context 'Object format (default), emits nothing when Installations is empty' {

    BeforeAll {
      $script:objOut = @(Write-ListInstalledOutput `
        -Installations @() `
        -Platform 'Win32' -BuildSystem 'DCC' `
        -ToolVersion $script:toolVersion)
    }

    It 'emits nothing (empty pipeline)' {
      $script:objOut | Should -HaveCount 0
    }

  }

}
