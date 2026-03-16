#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.7.0' }
<#
.SYNOPSIS
  Tests for Write-DetectLatestOutput in delphi-inspect.ps1

.DESCRIPTION
  Covers: text and JSON output formatting for -DetectLatest results.
  No mocking required -- in-memory pscustomobject values are passed directly.

  Context 1 - Text, DCC, no ready installation:
    Emits exactly one line: "No ready installation found".

  Context 2 - Text, DCC, one ready entry:
    Header line, readiness/registryFound/rootDirExists/compilerFound/cfgFound lines.
    No MSBuild-specific lines.

  Context 3 - Text, MSBuild, one ready entry:
    Header line with MSBuild-specific fields; no DCC-specific lines.

  Context 4 - JSON, DCC, installation found:
    ok=true, command=detectLatest, result.platform/buildSystem/installation.
    installation has DCC-specific fields; readiness=ready.

  Context 5 - JSON, DCC, no installation found:
    ok=true, command=detectLatest, result.installation is null.

  Context 6 - JSON, MSBuild, installation found:
    result.buildSystem=MSBuild; MSBuild-specific fields present on installation.
#>

Describe 'Write-DetectLatestOutput' {

  BeforeAll {
    . "$PSScriptRoot/TestHelpers.ps1"
    $script:scriptUnderTest = Get-ScriptUnderTestPath
    . $script:scriptUnderTest

    $script:toolVersion = '0.1.0'

    # ---- DCC in-memory fixtures ----

    $script:readyDcc = [pscustomobject]@{
      verDefine     = 'VER370'
      productName   = 'Delphi 13 Florence'
      readiness     = 'ready'
      registryFound = $true
      rootDir       = 'C:\Fake\Delphi13'
      rootDirExists = $true
      compilerFound = $true
      cfgFound      = $true
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
  }

  Context 'Text, DCC, no ready installation' {

    BeforeAll {
      $script:out = Write-DetectLatestOutput `
        -Installation $null `
        -Platform 'Win32' -BuildSystem 'DCC' `
        -ToolVersion $script:toolVersion `
        -Format 'text'
    }

    It 'emits exactly one line' {
      $script:out | Should -HaveCount 1
    }

    It 'line is "No ready installation found"' {
      $script:out | Should -Be 'No ready installation found'
    }

  }

  Context 'Text, DCC, one ready entry' {

    BeforeAll {
      $script:out = Write-DetectLatestOutput `
        -Installation $script:readyDcc `
        -Platform 'Win32' -BuildSystem 'DCC' `
        -ToolVersion $script:toolVersion `
        -Format 'text'
    }

    It 'first line contains verDefine and productName' {
      $script:out[0] | Should -Match 'VER370\s+Delphi 13 Florence'
    }

    It 'includes a readiness line showing ready' {
      ($script:out -match 'readiness\s+ready') | Should -Not -BeNullOrEmpty
    }

    It 'includes a registryFound line showing true' {
      ($script:out -match 'registryFound\s+true') | Should -Not -BeNullOrEmpty
    }

    It 'includes a rootDir line with the path' {
      ($script:out -match 'rootDir\s+C:\\Fake\\Delphi13') | Should -Not -BeNullOrEmpty
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

  Context 'Text, MSBuild, one ready entry' {

    BeforeAll {
      $script:out = Write-DetectLatestOutput `
        -Installation $script:readyMSBuild `
        -Platform 'Win32' -BuildSystem 'MSBuild' `
        -ToolVersion $script:toolVersion `
        -Format 'text'
    }

    It 'first line contains verDefine and productName' {
      $script:out[0] | Should -Match 'VER370\s+Delphi 13 Florence'
    }

    It 'includes a rsvarsPath line with the path' {
      ($script:out -match 'rsvarsPath\s+C:\\Fake\\Delphi13\\bin\\rsvars\.bat') | Should -Not -BeNullOrEmpty
    }

    It 'includes a rsvarsFound line showing true' {
      ($script:out -match 'rsvarsFound\s+true') | Should -Not -BeNullOrEmpty
    }

    It 'includes a compilerFound line showing true' {
      ($script:out -match 'compilerFound\s+true') | Should -Not -BeNullOrEmpty
    }

    It 'includes an envOptionsFound line showing true' {
      ($script:out -match 'envOptionsFound\s+true') | Should -Not -BeNullOrEmpty
    }

    It 'includes an envOptionsHasLibraryPath line showing true' {
      ($script:out -match 'envOptionsHasLibraryPath\s+true') | Should -Not -BeNullOrEmpty
    }

    It 'does not include DCC-specific cfgFound line' {
      ($script:out -match '^\s+cfgFound') | Should -BeNullOrEmpty
    }

  }

  Context 'JSON, DCC, installation found' {

    BeforeAll {
      $rawOut = Write-DetectLatestOutput `
        -Installation $script:readyDcc `
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

    It 'command is detectLatest' {
      $script:json.command | Should -Be 'detectLatest'
    }

    It 'result.platform is Win32' {
      $script:json.result.platform | Should -Be 'Win32'
    }

    It 'result.buildSystem is DCC' {
      $script:json.result.buildSystem | Should -Be 'DCC'
    }

    It 'result.installation is not null' {
      $script:json.result.installation | Should -Not -BeNull
    }

    It 'result.installation.verDefine is VER370' {
      $script:json.result.installation.verDefine | Should -Be 'VER370'
    }

    It 'result.installation.readiness is ready' {
      $script:json.result.installation.readiness | Should -Be 'ready'
    }

    It 'result.installation.rootDir is the path' {
      $script:json.result.installation.rootDir | Should -Be 'C:\Fake\Delphi13'
    }

    It 'result.installation.compilerFound is true' {
      $script:json.result.installation.compilerFound | Should -Be $true
    }

    It 'result.installation.cfgFound is true' {
      $script:json.result.installation.cfgFound | Should -Be $true
    }

  }

  Context 'JSON, DCC, no installation found' {

    BeforeAll {
      $rawOut = Write-DetectLatestOutput `
        -Installation $null `
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

    It 'command is detectLatest' {
      $script:json.command | Should -Be 'detectLatest'
    }

    It 'result.installation is null' {
      $script:json.result.installation | Should -BeNull
    }

  }

  Context 'JSON, MSBuild, installation found' {

    BeforeAll {
      $rawOut = Write-DetectLatestOutput `
        -Installation $script:readyMSBuild `
        -Platform 'Win32' -BuildSystem 'MSBuild' `
        -ToolVersion $script:toolVersion -Format 'json'
      $script:json = ($rawOut -join "`n") | ConvertFrom-Json
    }

    It 'result.buildSystem is MSBuild' {
      $script:json.result.buildSystem | Should -Be 'MSBuild'
    }

    It 'result.installation.rsvarsPath is the path' {
      $script:json.result.installation.rsvarsPath | Should -Be 'C:\Fake\Delphi13\bin\rsvars.bat'
    }

    It 'result.installation.rsvarsFound is true' {
      $script:json.result.installation.rsvarsFound | Should -Be $true
    }

    It 'result.installation.compilerFound is true' {
      $script:json.result.installation.compilerFound | Should -Be $true
    }

    It 'result.installation.envOptionsFound is true' {
      $script:json.result.installation.envOptionsFound | Should -Be $true
    }

    It 'result.installation.envOptionsHasLibraryPath is true' {
      $script:json.result.installation.envOptionsHasLibraryPath | Should -Be $true
    }

  }

  Context 'Object format (default), installation found' {

    BeforeAll {
      $script:objOut = Write-DetectLatestOutput `
        -Installation $script:readyDcc `
        -Platform 'Win32' -BuildSystem 'DCC' `
        -ToolVersion $script:toolVersion
    }

    It 'emits the installation object' {
      $script:objOut | Should -Not -BeNullOrEmpty
    }

    It 'emitted object verDefine is VER370' {
      $script:objOut.verDefine | Should -Be 'VER370'
    }

    It 'emitted object readiness is ready' {
      $script:objOut.readiness | Should -Be 'ready'
    }

  }

  Context 'Object format (default), no installation found' {

    BeforeAll {
      $script:objOut = Write-DetectLatestOutput `
        -Installation $null `
        -Platform 'Win32' -BuildSystem 'DCC' `
        -ToolVersion $script:toolVersion
    }

    It 'emits nothing (empty pipeline)' {
      # Wrap in @() to handle null vs empty array under StrictMode
      @($script:objOut) | Should -HaveCount 0
    }

  }

}
