# Builds stn.exe for Windows x64 with MSVC and the static C runtime (/MT), its
# version resource stamped from -Version. Needs Visual Studio 2019 16.2 or later
# with the x64 C++ tools.
#
#   build.ps1 -OutFile <absolute path> -Version <MAJOR.MINOR.PATCH[-pre-release]>
#
# Exits 0 with the file written. Otherwise exits non-zero with one stderr line
# naming what is wrong, and writes no file.
param(
    [Parameter(Mandatory)][string]$OutFile,
    [Parameter(Mandatory)][string]$Version
)

$ErrorActionPreference = 'Stop'

# Each part of a four-part version resource number holds 16 bits.
$maxNumber = 65535

function Test-Version([string]$Text) {
    if ($Text -notmatch '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$') { return $false }
    foreach ($part in ($Text -replace '-.*$', '').Split('.')) {
        if ($part.Length -gt 5 -or [int]$part -gt $maxNumber) { return $false }
    }
    return $true
}

function Enter-MsvcShell {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere)) {
        throw "vswhere.exe not found at $vswhere"
    }
    $install = & $vswhere -latest -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath
    if (-not $install) {
        throw 'no Visual Studio with the x64 C++ tools found by vswhere.exe'
    }
    $install = @($install)[0]
    Import-Module (Join-Path $install 'Common7\Tools\Microsoft.VisualStudio.DevShell.dll')
    Enter-VsDevShell -VsInstallPath $install -SkipAutomaticLocation `
        -DevCmdArguments '-arch=x64 -host_arch=x64'
}

# Runs a tool and returns its exit status; its output goes to the host, not
# into the return value.
function Invoke-Tool([string]$Tool, [string[]]$Arguments) {
    & $Tool @Arguments | Out-Host
    return $LASTEXITCODE
}

function Write-VersionHeader([string]$Folder, [string]$Text) {
    $numbers = ($Text -replace '-.*$', '').Split('.') -join ','
    $header = "#define STN_VERSION_TEXT L`"$Text`"`r`n" +
        "#define STN_VERSION_NUMBERS $numbers,0`r`n"
    [IO.File]::WriteAllText("$Folder\stn_version.h", $header, [Text.Encoding]::ASCII)
}

$status = 0
$work = $null
try {
    if (-not (Test-Version $Version)) {
        throw "-Version '$Version' is not MAJOR.MINOR.PATCH with an optional -pre-release, each number at most $maxNumber"
    }
    $work = Join-Path ([IO.Path]::GetTempPath()) ('stn_build_' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $work | Out-Null
    Write-VersionHeader $work $Version
    Enter-MsvcShell

    $status = Invoke-Tool 'rc' @(
        '/nologo', '/I', $work, '/fo', "$work\stn.res", "$PSScriptRoot\stn.rc")
    if ($status -eq 0) {
        $status = Invoke-Tool 'cl' @(
            '/nologo', '/O2', '/MT', '/W4', '/WX', '/utf-8',
            '/DUNICODE', '/D_UNICODE',
            "$PSScriptRoot\stn.c", "$work\stn.res",
            "/Fe:$OutFile", "/Fo:$work\stn.obj",
            '/link', '/SUBSYSTEM:CONSOLE', 'kernel32.lib')
    }
} catch {
    [Console]::Error.WriteLine("build.ps1: $($_.Exception.Message)")
    $status = 1
} finally {
    if ($work -and (Test-Path -LiteralPath $work)) {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}
exit $status
