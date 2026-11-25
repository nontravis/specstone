# Installs the Specstone CLI under ~\.specstone (Windows PowerShell 5.1):
#   irm https://raw.githubusercontent.com/nontravis/specstone/main/install.ps1 | iex
# A version, such as the pre-release 1.2.0-beta.1, installs from the script of
# its own tag:
#   iex "& {$(irm https://raw.githubusercontent.com/nontravis/specstone/vX.Y.Z/install.ps1)} -Version 'X.Y.Z'"
# The whole body sits in one & { } block. A truncated stream does not parse, so
# it runs nothing, and the strict mode and the preferences set inside the block
# never reach the caller's session. A refusal throws; it never calls exit, which
# would close the caller's window under iex. Under irm | iex the param binds
# $Version in the caller's session, so the finally at the end removes it.
# Keep this file ASCII: Windows PowerShell 5.1 reads a file with no BOM as ANSI.
param([string]$Version = '')
try {
& {
    Set-StrictMode -Version 3
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'

    # Imports by name the modules this script calls cmdlets from. A cmdlet that
    # command lookup has to find makes a Windows PowerShell 5.1 with no module
    # analysis cache (a fresh profile, a CI runner) analyze every module folder
    # first, about 25 s; a module named here is loaded straight from its folder.
    # Module search is off from here: every cmdlet below comes from these
    # modules or the core. Get-Command still searches every module folder for a
    # name it does not find, such as git with no git on the PATH, so
    # Find-Program looks a program up instead.
    Import-Module -Name Microsoft.PowerShell.Management, Microsoft.PowerShell.Utility, Microsoft.PowerShell.Archive
    $PSModuleAutoLoadingPreference = 'None'

    $releaseUrl = 'https://github.com/nontravis/specstone/releases/latest/download'
    $supported = 'macOS arm64, macOS x64, Linux x64, Windows x64'
    $tmp = ''

    # Returns the environment variable $Name, or '' when it is unset.
    function Get-EnvText([string]$Name) {
        $value = [Environment]::GetEnvironmentVariable($Name)
        if ($null -eq $value) {
            return ''
        }
        return $value
    }

    # Returns the entries of the PATH text $Text. It splits on each ';' outside
    # double quotes and drops the quotes, as cmd.exe does, so a quoted entry
    # that holds a ';' stays one entry.
    function Split-PathText([string]$Text) {
        $items = New-Object System.Collections.ArrayList
        $entry = New-Object System.Text.StringBuilder
        $isQuoted = $false
        foreach ($character in ($Text + ';').ToCharArray()) {
            if ($character -eq '"') {
                $isQuoted = -not $isQuoted
            } elseif ($character -eq ';' -and -not $isQuoted) {
                [void]$items.Add($entry.ToString())
                [void]$entry.Clear()
            } else {
                [void]$entry.Append($character)
            }
        }
        return $items.ToArray()
    }

    # Returns the PATH text $Text with only its absolute entries: a drive root
    # such as C:\ or C:/, or a UNC path, so an empty, '.', or relative entry
    # (the current folder) is never searched. An entry that holds a ';' is
    # quoted again.
    function Get-AbsolutePathText([string]$Text) {
        $kept = New-Object System.Collections.ArrayList
        foreach ($item in @(Split-PathText $Text)) {
            if ($item -match '^([A-Za-z]:[\\/]|\\\\)') {
                if ($item.Contains(';')) {
                    $item = '"' + $item + '"'
                }
                [void]$kept.Add($item)
            }
        }
        return ($kept.ToArray() -join ';')
    }

    # Returns the full path of the first file named $Name plus a PATHEXT
    # extension on $env:Path, each entry in order and each extension in order
    # inside it, as cmd.exe finds a program; $null when there is none.
    function Find-Program([string]$Name) {
        $extensions = @((Get-EnvText 'PATHEXT').Split(';') | Where-Object { $_.Length -gt 0 })
        if ($extensions.Count -eq 0) {
            $extensions = @('.COM', '.EXE', '.BAT', '.CMD')
        }
        foreach ($entry in @(Split-PathText (Get-EnvText 'Path'))) {
            if ($entry.Length -eq 0) {
                continue
            }
            foreach ($extension in $extensions) {
                try {
                    $candidate = Join-Path $entry ($Name + $extension)
                    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                        return $candidate
                    }
                } catch {
                    # an entry the OS cannot read holds no program to run
                }
            }
        }
        return $null
    }

    # Returns the release target for this machine, or refuses before any download.
    function Get-Target {
        $arch = Get-EnvText 'PROCESSOR_ARCHITEW6432'
        if ($arch.Length -eq 0) {
            $arch = Get-EnvText 'PROCESSOR_ARCHITECTURE'
        }
        if ($arch -ne 'AMD64') {
            throw "specstone: unsupported machine Windows $arch; supported: $supported"
        }
        return 'windows-x64'
    }

    # Returns $true when $Text is MAJOR.MINOR.PATCH[-<pre-release>] in the form
    # of the CLI's Version. -cmatch with \A and \z and ASCII classes only: -match
    # ignores case, $ matches before a final line feed, and \d matches digits of
    # other scripts.
    function Test-Version([string]$Text) {
        $number = '(0|[1-9][0-9]*)'
        $identifier = '(0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)'
        return $Text -cmatch "\A$number\.$number\.$number(-$identifier(\.$identifier)*)?\z"
    }

    # Returns $Text with every character but printable ASCII as '?', so no
    # host encoding can turn a shown character into a control that moves the
    # cursor or rewrites the terminal.
    function Get-PrintableText([string]$Text) {
        return [regex]::Replace($Text, '[^\x20-\x7E]', '?')
    }

    # Downloads $Url to $Destination over TLS 1.2, which Windows PowerShell 5.1
    # may not offer by default, and puts the process-wide setting back after.
    function Save-Download([string]$Url, [string]$Destination) {
        $protocols = [Net.ServicePointManager]::SecurityProtocol
        try {
            [Net.ServicePointManager]::SecurityProtocol = $protocols -bor [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -UseBasicParsing -TimeoutSec 30 -Uri $Url -OutFile $Destination
        } finally {
            [Net.ServicePointManager]::SecurityProtocol = $protocols
        }
    }

    # Copies or downloads the file $Name from the archive folder or the release into $tmp.
    function Save-File([string]$Name) {
        $destination = Join-Path $tmp $Name
        $archiveDir = Get-EnvText 'SPECSTONE_ARCHIVE_DIR'
        try {
            if ($archiveDir.Length -gt 0) {
                Copy-Item -LiteralPath (Join-Path $archiveDir $Name) -Destination $destination
            } else {
                Save-Download "$releaseUrl/$Name" $destination
            }
        } catch {
            throw "specstone: download failed for $Name; the install is unchanged"
        }
    }

    # Returns the lower-case SHA-256 that SHA256SUMS lists for $Asset, or ''.
    function Get-ExpectedHash([string]$Asset) {
        foreach ($line in @(Get-Content -LiteralPath (Join-Path $tmp 'SHA256SUMS'))) {
            $fields = @(([string]$line).Trim() -split '\s+', 2)
            if ($fields.Count -eq 2 -and ($fields[1] -eq $Asset -or $fields[1] -eq "*$Asset")) {
                return $fields[0].ToLowerInvariant()
            }
        }
        return ''
    }

    # Downloads $Asset and SHA256SUMS into $tmp and checks the archive's hash.
    function Save-AndVerify([string]$Asset) {
        Save-File $Asset
        Save-File 'SHA256SUMS'
        $expected = Get-ExpectedHash $Asset
        $actual = (Get-FileHash -Algorithm SHA256 -ErrorAction Stop -LiteralPath (Join-Path $tmp $Asset)).Hash.ToLowerInvariant()
        if ($expected.Length -eq 0 -or $expected -ne $actual) {
            throw "specstone: checksum mismatch for $Asset; the install is unchanged"
        }
    }

    # Runs the program $File with $Arguments under 'Continue', so a line on its
    # stderr is not an error. Merging stderr into the output stream (2>&1) turns
    # each stderr line into an ErrorRecord, which is dropped, so Output holds
    # the stdout lines only. Decodes the program's output as UTF-8 (the console
    # encoding is the OEM code page) and restores the console encoding
    # afterwards. Returns Status and Output.
    function Invoke-Native([string]$File, [string[]]$Arguments) {
        $ErrorActionPreference = 'Continue'
        $global:LASTEXITCODE = 0
        $output = New-Object System.Collections.ArrayList
        $savedEncoding = $null
        try {
            $savedEncoding = [Console]::OutputEncoding
            [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
        } catch {
            $savedEncoding = $null
        }
        try {
            & $File @Arguments 2>&1 | ForEach-Object {
                if ($_ -isnot [System.Management.Automation.ErrorRecord]) {
                    [void]$output.Add([string]$_)
                }
            }
            $status = $global:LASTEXITCODE
        } catch {
            $status = 1
        } finally {
            if ($null -ne $savedEncoding) {
                try { [Console]::OutputEncoding = $savedEncoding } catch { }
            }
        }
        return [pscustomobject]@{ Status = $status; Output = $output.ToArray() }
    }

    # Returns $true when the strings $First and $Second hold the same characters.
    # -ceq compares by culture rules, which on Windows PowerShell 5.1 skip a NUL
    # or a soft hyphen, so it can match a text that differs.
    function Test-SameText([string]$First, [string]$Second) {
        return [string]::Equals($First, $Second, [StringComparison]::Ordinal)
    }

    # Returns $true when the `git --version` text $Text names git 2.25 or later;
    # a text that names no version, such as the empty output of a git that
    # failed, does not. The digit runs are bounded so no [int] cast overflows.
    function Test-GitFloor([string]$Text) {
        $found = [regex]::Match($Text, 'git version ([0-9]{1,6})\.([0-9]{1,6})')
        if (-not $found.Success) {
            return $false
        }
        $major = [int]$found.Groups[1].Value
        $minor = [int]$found.Groups[2].Value
        return ($major -gt 2) -or ($major -eq 2 -and $minor -ge 25)
    }

    # Prints one warning line when git 2.25 or later is missing. It only
    # prints: nothing is installed and the install's exit status stays.
    function Write-MissingPrerequisites {
        $gitCommand = 'winget install Git.Git'
        $gitText = ''
        $git = Find-Program 'git'
        if ($null -ne $git) {
            $probe = Invoke-Native $git @('--version')
            if ($probe.Status -eq 0) {
                $gitText = (@($probe.Output) -join "`n").Trim()
            }
        }
        if (-not (Test-GitFloor $gitText)) {
            Write-Host "specstone: git 2.25 or later is missing; install it with $gitCommand"
        }
    }

    # Tells running programs that the user environment changed, as the Windows
    # settings dialog does; without it only new sessions of Explorer see it.
    function Send-EnvironmentChange {
        if ($null -eq ('SpecstoneInstall.NativeMethods' -as [type])) {
            Add-Type -Namespace SpecstoneInstall -Name NativeMethods -MemberDefinition ('[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)] ' + 'public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);')
        }
        $result = [UIntPtr]::Zero
        # HWND_BROADCAST, WM_SETTINGCHANGE, SMTO_ABORTIFHUNG, 5 s
        [void][SpecstoneInstall.NativeMethods]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$result)
    }

    # Appends $Folder to the user PATH unless an entry already names it, ignoring
    # case, a trailing backslash, and %VAR% spelling, and says so. The Path is read from the
    # registry unexpanded and written back with its kind (ExpandString when it
    # was one or holds a %), so the owner's %VAR% entries stay as they are;
    # [Environment]::SetEnvironmentVariable would expand them for good.
    function Add-UserPathEntry([string]$Folder) {
        $key = $null
        try {
            $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
            $current = ''
            $kind = [Microsoft.Win32.RegistryValueKind]::String
            if (@($key.GetValueNames()) -contains 'Path') {
                $current = [string]$key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                $kind = $key.GetValueKind('Path')
            }
            # Leave a Path of another kind (a multi-string, say) untouched.
            if ($kind -ne [Microsoft.Win32.RegistryValueKind]::String -and $kind -ne [Microsoft.Win32.RegistryValueKind]::ExpandString) {
                [Console]::Error.WriteLine("specstone: the user PATH has an unexpected type ($kind) and is left as it is: add $Folder to it yourself")
                return
            }
            $wanted = [Environment]::ExpandEnvironmentVariables($Folder).TrimEnd('\')
            foreach ($entry in $current.Split(';')) {
                if ([Environment]::ExpandEnvironmentVariables($entry.Trim()).TrimEnd('\') -ieq $wanted) {
                    return
                }
            }
            $joined = $Folder
            if ($current.Trim().Length -gt 0) {
                $joined = $current.TrimEnd(';') + ';' + $Folder
            }
            if ($kind -eq [Microsoft.Win32.RegistryValueKind]::ExpandString -or $joined.Contains('%')) {
                $kind = [Microsoft.Win32.RegistryValueKind]::ExpandString
            } else {
                $kind = [Microsoft.Win32.RegistryValueKind]::String
            }
            $key.SetValue('Path', $joined, $kind)
        } catch {
            [Console]::Error.WriteLine("specstone: could not write the user PATH: add $Folder to it yourself")
            return
        } finally {
            if ($null -ne $key) {
                $key.Close()
            }
        }
        try {
            Send-EnvironmentChange
        } catch {
            # the PATH is written; programs already running pick it up on restart
        }
        Write-Host "Added $Folder to the user PATH. Open a new PowerShell window to use specstone."
    }

    # Returns the full path of the folder $Folder with a trailing '\' dropped
    # and a symlink or junction followed to its target, for a compare that
    # ignores spelling. A relative target leads from the link's parent folder.
    function Get-FolderIdentity([string]$Folder) {
        $full = [IO.Path]::GetFullPath($Folder)
        $item = Get-Item -LiteralPath $full -Force -ErrorAction SilentlyContinue
        # Strict mode throws on a property the item lacks; Target is a script
        # property of Windows PowerShell 5.0 and later.
        $targets = $null
        if ($null -ne $item -and $null -ne $item.PSObject.Properties['Target']) {
            $targets = $item.Target
        }
        if ($null -ne $targets) {
            foreach ($link in @($targets)) {
                if (-not [string]::IsNullOrEmpty($link)) {
                    $parent = [IO.Path]::GetDirectoryName($full.TrimEnd('\'))
                    $full = [IO.Path]::GetFullPath([IO.Path]::Combine($parent, $link))
                    break
                }
            }
        }
        return $full.TrimEnd('\')
    }

    # Returns the path of the first `stn` on $env:Path in an entry other than
    # $BinFolder, or $null when there is none. An entry that reads as
    # $BinFolder, or holds stn.exe and specstone.exe (a Specstone install), is
    # skipped; a `stn` is a file named stn.exe, .cmd, .bat, .com, or .ps1,
    # tried in that order inside an entry.
    function Find-OtherStn([string]$BinFolder) {
        $own = Get-FolderIdentity $BinFolder
        foreach ($entry in @(Split-PathText (Get-EnvText 'Path'))) {
            try {
                if ([string]::Equals((Get-FolderIdentity $entry), $own, [StringComparison]::OrdinalIgnoreCase)) {
                    continue
                }
                $folder = [IO.Path]::GetFullPath($entry)
                if ((Test-Path -LiteralPath (Join-Path $folder 'stn.exe') -PathType Leaf) -and (Test-Path -LiteralPath (Join-Path $folder 'specstone.exe') -PathType Leaf)) {
                    continue
                }
                # Name the folder as the PATH spells it: GetFullPath may expand 8.3 names.
                $shown = $entry.TrimEnd('\', '/')
                foreach ($extension in 'exe', 'cmd', 'bat', 'com', 'ps1') {
                    if (Test-Path -LiteralPath (Join-Path $folder "stn.$extension") -PathType Leaf) {
                        return "$shown\stn.$extension"
                    }
                }
            } catch {
                # an entry the OS cannot read holds no stn that the Owner could run
            }
        }
        return $null
    }

    # Prints one line naming the other stn at $Path, which the Owner then types
    # specstone in place of. It never changes the run's exit status.
    function Write-OtherStnNotice([string]$Path) {
        if ($Path.Length -eq 0) {
            return
        }
        Write-Host "specstone: another stn is at $Path; stn is not installed, type specstone to run the CLI"
    }

    # Deletes the *.old leftovers under bin\ and lib\ of $InstallDir. A file that
    # is still locked stays for the next run.
    function Remove-OldLeftovers([string]$InstallDir) {
        foreach ($name in 'bin', 'lib') {
            $folder = Join-Path $InstallDir $name
            if (-not (Test-Path -LiteralPath $folder)) {
                continue
            }
            $leftovers = @(Get-ChildItem -LiteralPath $folder -Recurse -File -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like '*.old' })
            foreach ($file in $leftovers) {
                try {
                    Remove-Item -LiteralPath $file.FullName -Force
                } catch {
                    # locked by a running process; the next run deletes it
                }
            }
        }
    }

    # Returns the first free name among "<Path>.old", "<Path>.2.old", ... A name
    # in use is a leftover that a running process still locks.
    function Get-OldName([string]$Path) {
        $candidate = "$Path.old"
        $number = 1
        while (Test-Path -LiteralPath $candidate) {
            $number++
            $candidate = "$Path.$number.old"
        }
        return $candidate
    }

    # Removes the stn.exe an earlier run placed in $BinFolder: a delete, else a
    # rename to <name>.old that a later run deletes. Returns the path when both
    # fail, else $null.
    function Remove-PlacedStn([string]$BinFolder) {
        $path = Join-Path $BinFolder 'stn.exe'
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            return $null
        }
        try {
            Remove-Item -LiteralPath $path -Force
            return $null
        } catch {
            # a running stn.exe holds the file; try the rename
        }
        try {
            Move-Item -LiteralPath $path -Destination (Get-OldName $path)
            return $null
        } catch {
            return $path
        }
    }

    # Puts the archive's lib\ and bin\ into $InstallDir, bin last, without the
    # archive's stn.exe when $SkipStn is set. Each existing file is renamed to
    # <name>.old first, so a running specstone.exe can be replaced; a failure
    # puts every renamed file back and removes what it copied.
    function Install-Files([string]$InstallDir, [switch]$SkipStn) {
        $renamed = New-Object System.Collections.ArrayList
        $copied = New-Object System.Collections.ArrayList
        $current = $InstallDir
        try {
            foreach ($name in 'lib', 'bin') {
                $source = (Get-Item -LiteralPath (Join-Path $unpack $name)).FullName
                $target = Join-Path $InstallDir $name
                $current = $target
                New-Item -ItemType Directory -Force -Path $target | Out-Null
                foreach ($file in @(Get-ChildItem -LiteralPath $target -Recurse -File -Force)) {
                    if ($file.Name -like '*.old') {
                        continue
                    }
                    $current = $file.FullName
                    $old = Get-OldName $file.FullName
                    Move-Item -LiteralPath $file.FullName -Destination $old
                    [void]$renamed.Add(@($file.FullName, $old))
                }
                foreach ($file in @(Get-ChildItem -LiteralPath $source -Recurse -File -Force)) {
                    $relative = $file.FullName.Substring($source.Length).TrimStart('\')
                    if ($SkipStn -and $name -eq 'bin' -and $relative -eq 'stn.exe') {
                        continue
                    }
                    $destination = Join-Path $target $relative
                    $current = $destination
                    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
                    Copy-Item -LiteralPath $file.FullName -Destination $destination
                    [void]$copied.Add($destination)
                }
            }
        } catch {
            foreach ($path in $copied) {
                Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
            }
            foreach ($pair in $renamed) {
                Move-Item -LiteralPath $pair[1] -Destination $pair[0] -Force -ErrorAction SilentlyContinue
            }
            throw "specstone: could not place ${current}: run the install again"
        }
    }

    $target = Get-Target
    if ($Version.Length -gt 0) {
        if (-not (Test-Version $Version)) {
            throw "specstone: $(Get-PrintableText $Version) is not a version of the form MAJOR.MINOR.PATCH[-<pre-release>]; the install is unchanged"
        }
        $releaseUrl = "https://github.com/nontravis/specstone/releases/download/v$Version"
    }
    $homeDir = Get-EnvText 'HOME'
    if ($homeDir.Length -eq 0) {
        $homeDir = Get-EnvText 'USERPROFILE'
    }
    if ($homeDir.Length -eq 0) {
        throw 'specstone: no home folder: HOME and USERPROFILE are unset'
    }
    $installDir = Join-Path $homeDir '.specstone'
    $asset = "specstone-$target.zip"

    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('specstone.' + [guid]::NewGuid().ToString('N'))
    $unpack = Join-Path $tmp 'unpack'
    # Nothing above this line starts a program. From here every program is
    # searched on absolute PATH entries only. cmd.exe also tries the current
    # folder before PATH, for a bare program name that a .cmd on the PATH runs;
    # only NoDefaultCurrentDirectoryInExePath stops that. The finally below
    # puts the caller's PATH and that variable back (it removes the variable
    # when it was unset), as the block runs in the caller's session.
    $savedPath = Get-EnvText 'Path'
    $savedNoCurrentFolder = [Environment]::GetEnvironmentVariable('NoDefaultCurrentDirectoryInExePath')
    $env:Path = Get-AbsolutePathText $savedPath
    [Environment]::SetEnvironmentVariable('NoDefaultCurrentDirectoryInExePath', '1')
    try {
        try {
            New-Item -ItemType Directory -Path $tmp | Out-Null
        } catch {
            throw "specstone: could not make a temporary folder in $([IO.Path]::GetTempPath()); the install is unchanged"
        }
        Save-AndVerify $asset
        try {
            Expand-Archive -LiteralPath (Join-Path $tmp $asset) -DestinationPath $unpack -Force -ErrorAction Stop
        } catch {
            throw "specstone: could not unpack $asset; the install is unchanged"
        }
        if (-not ((Test-Path -LiteralPath (Join-Path $unpack 'bin')) -and (Test-Path -LiteralPath (Join-Path $unpack 'lib')))) {
            throw "specstone: could not unpack $asset; the install is unchanged"
        }

        $probe = Invoke-Native (Join-Path $unpack 'bin\specstone.exe') @('--version')
        if ($probe.Status -ne 0) {
            throw "specstone: the downloaded specstone does not run (exit $($probe.Status)); the install is unchanged"
        }
        $newVersion = (@($probe.Output) -join "`n").Trim()

        $binFolder = Join-Path $installDir 'bin'
        $otherStn = Find-OtherStn $binFolder
        Remove-OldLeftovers $installDir
        $stnRemovalFailed = $null
        $oldVersion = ''
        $oldBinary = Join-Path $installDir 'bin\specstone.exe'
        if (Test-Path -LiteralPath $oldBinary) {
            $oldProbe = Invoke-Native $oldBinary @('--version')
            if ($oldProbe.Status -eq 0) {
                $oldVersion = (@($oldProbe.Output) -join "`n").Trim()
            }
        }
        if ($oldVersion.Length -gt 0 -and (Test-SameText $oldVersion $newVersion)) {
            if ($Version.Length -gt 0) {
                Write-Host "specstone $newVersion is already installed"
            } else {
                Write-Host "specstone $newVersion is already the latest release"
            }
            if ($null -ne $otherStn) {
                $stnRemovalFailed = Remove-PlacedStn $binFolder
            }
        } else {
            Install-Files $installDir -SkipStn:($null -ne $otherStn)
            Write-Host "specstone $newVersion installed in $installDir\bin"
        }

        Add-UserPathEntry $binFolder
        Write-OtherStnNotice $otherStn
        if ($null -ne $stnRemovalFailed) {
            [Console]::Error.WriteLine("specstone: could not remove ${stnRemovalFailed}: delete it yourself")
        }
        try {
            Write-MissingPrerequisites
        } catch {
            # a failed check never turns a finished install into a failure
            Write-Host "specstone: could not check prerequisites: $(Get-PrintableText $_.Exception.Message)"
        }
    } finally {
        $env:Path = $savedPath
        [Environment]::SetEnvironmentVariable('NoDefaultCurrentDirectoryInExePath', $savedNoCurrentFolder)
        try {
            Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        } catch {
            # the folder is in the system temp; Windows clears it later
        }
    }
}
} finally {
    Remove-Variable -Name Version -Scope Local -ErrorAction SilentlyContinue
}
