# Installs the Specstone CLI under ~\.specstone (Windows PowerShell 5.1):
#   irm https://raw.githubusercontent.com/nontravis/specstone/main/install.ps1 | iex
# A version, such as the pre-release 1.2.0-beta.1, installs from the script of
# its own tag:
#   iex "& {$(irm https://raw.githubusercontent.com/nontravis/specstone/vX.Y.Z/install.ps1)} -Version X.Y.Z"
# The whole body sits in one & { } block. A truncated stream does not parse, so
# it runs nothing, and the strict mode and error preference set inside the block
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

    # Returns the PATH text $Text with only its absolute entries: a drive root
    # such as C:\ or C:/, or a UNC path. It splits on each ';' outside double
    # quotes and drops the quotes, as cmd.exe does, so an empty, '.', or
    # relative entry (the current folder) is never searched.
    function Get-AbsolutePathText([string]$Text) {
        $kept = New-Object System.Collections.ArrayList
        $entry = New-Object System.Text.StringBuilder
        $isQuoted = $false
        foreach ($character in ($Text + ';').ToCharArray()) {
            if ($character -eq '"') {
                $isQuoted = -not $isQuoted
            } elseif ($character -eq ';' -and -not $isQuoted) {
                $item = $entry.ToString()
                if ($item -match '^([A-Za-z]:[\\/]|\\\\)') {
                    if ($item.Contains(';')) {
                        $item = '"' + $item + '"'
                    }
                    [void]$kept.Add($item)
                }
                [void]$entry.Clear()
            } else {
                [void]$entry.Append($character)
            }
        }
        return ($kept.ToArray() -join ';')
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
    # each stderr line into an ErrorRecord, whose ToString() is the line itself,
    # without the NativeCommandError decoration that a 2> file would hold. With
    # $Live the stdout shows on the host as it arrives; otherwise it is returned
    # as Output. Decodes the program's output as UTF-8 (the console encoding
    # is the OEM code page) and restores the console encoding afterwards.
    # Returns Status, Output, and the stderr lines as Errors.
    function Invoke-Native([string]$File, [string[]]$Arguments, [bool]$Live) {
        $ErrorActionPreference = 'Continue'
        $global:LASTEXITCODE = 0
        $output = New-Object System.Collections.ArrayList
        $errors = New-Object System.Collections.ArrayList
        $savedEncoding = $null
        try {
            $savedEncoding = [Console]::OutputEncoding
            [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
        } catch {
            $savedEncoding = $null
        }
        try {
            & $File @Arguments 2>&1 | ForEach-Object {
                if ($_ -is [System.Management.Automation.ErrorRecord]) {
                    [void]$errors.Add($_.ToString())
                } elseif ($Live) {
                    Write-Host ([string]$_)
                } else {
                    [void]$output.Add([string]$_)
                }
            }
            $status = $global:LASTEXITCODE
        } catch {
            $status = 1
            [void]$errors.Add($_.Exception.GetBaseException().Message)
        } finally {
            if ($null -ne $savedEncoding) {
                try { [Console]::OutputEncoding = $savedEncoding } catch { }
            }
        }
        return [pscustomobject]@{ Status = $status; Output = $output.ToArray(); Errors = $errors.ToArray() }
    }

    # Returns the first non-blank line of $Lines, or ''.
    function Get-FirstLine($Lines) {
        foreach ($line in @($Lines)) {
            $text = ([string]$line).Trim()
            if ($text.Length -gt 0) {
                return $text
            }
        }
        return ''
    }

    # Prints that the claude command with $Arguments failed: the first non-blank
    # stderr line, else the first non-blank stdout line, else `exit <status>`.
    function Write-ClaudeFailure([string[]]$Arguments, $Result) {
        $reason = Get-FirstLine $Result.Errors
        if ($reason.Length -eq 0) {
            $reason = Get-FirstLine $Result.Output
        }
        if ($reason.Length -eq 0) {
            $reason = "exit $($Result.Status)"
        }
        [Console]::Error.WriteLine("specstone: claude $($Arguments -join ' ') failed: $reason; run it by hand")
    }

    # Runs claude with $Arguments. Returns the result, or $null after naming the
    # failed command. A live run keeps its stderr for the host after a success.
    function Invoke-Claude([string]$Claude, [string[]]$Arguments, [bool]$Live) {
        $result = Invoke-Native $Claude $Arguments $Live
        if ($result.Status -ne 0) {
            Write-ClaudeFailure $Arguments $result
            return $null
        }
        if ($Live) {
            foreach ($line in @($result.Errors)) {
                [Console]::Error.WriteLine($line)
            }
        }
        return $result
    }

    # Returns $true when $Value is the string $Text. -ceq alone would filter an
    # array or compare a number by its text.
    function Test-ExactText($Value, [string]$Text) {
        return ($Value -is [string]) -and ($Value -ceq $Text)
    }

    # Returns $true when the JSON list text $Text is read for sure: a top-level
    # array that holds no array directly, no key written with an escape, and no
    # key repeated in an object of the list (ignoring case, as a property lookup
    # does); ConvertFrom-Json would hide each. It reads the strings and nesting,
    # so a quote or brace inside a value never counts. Well-formedness is
    # ConvertFrom-Json's to judge.
    function Test-JsonKeysPlain([string]$Text) {
        if ($Text -cnotmatch '\A\s*\[') {
            return $false
        }
        $open = New-Object System.Collections.ArrayList
        $previous = ''
        foreach ($token in [regex]::Matches($Text, '"(?:[^"\\]|\\.)*"|[{}\[\]:]')) {
            $current = $token.Value
            if ($current -ceq '[') {
                if ($open.Count -eq 1) {
                    return $false
                }
                [void]$open.Add('[')
            } elseif ($current -ceq '{') {
                [void]$open.Add([System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase))
            } elseif ($current -ceq '}' -or $current -ceq ']') {
                if ($open.Count -eq 0) {
                    return $false
                }
                $open.RemoveAt($open.Count - 1)
            } elseif ($current -ceq ':') {
                $key = $previous.Substring(1, $previous.Length - 2)
                if ($key.Contains('\')) {
                    return $false
                }
                if ($open.Count -eq 2 -and -not $open[1].Add($key)) {
                    return $false
                }
            }
            $previous = $current
        }
        return $true
    }

    # Returns $true when $Item is an object ConvertFrom-Json read from a JSON
    # object, not a string, a number, or an array.
    function Test-JsonObject($Item) {
        return ($null -ne $Item) -and ($Item.PSObject.TypeNames[0] -ceq 'System.Management.Automation.PSCustomObject')
    }

    # Returns the objects of the JSON list in $Lines, whichever way
    # ConvertFrom-Json hands an array back (Windows PowerShell 5.1 does not
    # unroll it). Throws when the list is not read for sure: empty, not JSON,
    # text around the JSON, a key that Test-JsonKeysPlain refuses, or an item
    # that is not an object.
    function ConvertFrom-JsonList([string[]]$Lines) {
        $text = (@($Lines) -join "`n").Trim()
        if (-not (Test-JsonKeysPlain $text)) {
            throw 'the list is not read for sure'
        }
        $parsed = $text | ConvertFrom-Json
        if ($null -eq $parsed) {
            return @()
        }
        $items = @($parsed | ForEach-Object { $_ })
        foreach ($item in $items) {
            if (-not (Test-JsonObject $item)) {
                throw 'an item of the list is not an object'
            }
        }
        return $items
    }

    # Returns the property $Name of $Item, or $null when it has none. The key
    # must match in case: a property lookup alone ignores it.
    function Get-Property($Item, [string]$Name) {
        if ($null -eq $Item) {
            return $null
        }
        $property = $Item.PSObject.Properties[$Name]
        if ($null -eq $property -or $property.Name -cne $Name) {
            return $null
        }
        return $property.Value
    }

    # Prints the remove, add, and install commands for the marketplace source $Wanted.
    function Write-PluginCommands([string]$Wanted) {
        Write-Host '  claude plugin marketplace remove specstone'
        Write-Host "  claude plugin marketplace add $Wanted"
        Write-Host '  claude plugin install specstone@specstone'
    }

    # Prints the commands of Write-PluginCommands under a line saying who runs them.
    function Write-ManualPluginCommands([string]$Wanted) {
        Write-Host 'To add the Specstone plugin to Claude Code, run (the first command only when a marketplace specstone already exists):'
        Write-PluginCommands $Wanted
    }

    # Names the claude list command with $Arguments whose reply was not read
    # for sure, then prints the commands for the source $Wanted.
    function Write-UnreadableReply([string[]]$Arguments, [string]$Wanted) {
        [Console]::Error.WriteLine("specstone: claude $($Arguments -join ' ') failed: its reply could not be read; run it by hand")
        Write-ManualPluginCommands $Wanted
    }

    # Runs a claude list command; returns its objects as one array, or $null
    # after naming the failure or the reply that was not read for sure.
    function Get-ClaudeList([string]$Claude, [string[]]$Arguments, [string]$Wanted) {
        $result = Invoke-Claude $Claude $Arguments $false
        if ($null -eq $result) {
            return $null
        }
        try {
            return , @(ConvertFrom-JsonList $result.Output)
        } catch {
            Write-UnreadableReply $Arguments $Wanted
            return $null
        }
    }

    # Returns $true when the marketplace entry $Entry is the one this script
    # adds: source github, repo exactly nontravis/specstone. Any other entry
    # is the Owner's own.
    function Test-OfficialEntry($Entry) {
        return (Test-ExactText (Get-Property $Entry 'source') 'github') -and (Test-ExactText (Get-Property $Entry 'repo') 'nontravis/specstone')
    }

    # Returns where the marketplace entry $Entry comes from, read from the key
    # its source type names, else 'an unknown source'.
    function Get-EntrySource($Entry) {
        $source = Get-Property $Entry 'source'
        $key = ''
        if (Test-ExactText $source 'github') {
            $key = 'repo'
        } elseif ((Test-ExactText $source 'git') -or (Test-ExactText $source 'url')) {
            $key = 'url'
        } elseif ((Test-ExactText $source 'directory') -or (Test-ExactText $source 'file')) {
            $key = 'path'
        }
        $found = $null
        if ($key.Length -gt 0) {
            $found = Get-Property $Entry $key
        }
        if ($found -is [string] -and $found.Length -gt 0) {
            return Get-PrintableText $found
        }
        return 'an unknown source'
    }

    # Moves marketplace specstone to the source $Wanted. The remove also
    # uninstalls the plugin. Returns $false after naming the command that failed.
    function Move-Marketplace([string]$Claude, [string]$Wanted) {
        $removed = Invoke-Claude $Claude @('plugin', 'marketplace', 'remove', 'specstone') $true
        if ($null -eq $removed) {
            return $false
        }
        $added = Invoke-Claude $Claude @('plugin', 'marketplace', 'add', $Wanted) $true
        if ($null -eq $added) {
            return $false
        }
        Write-Host "specstone: marketplace specstone re-added from $Wanted"
        return $true
    }

    # Returns $true when one entry of the plugin list $Plugins holds both the id
    # specstone@specstone and the scope user; project and local installs from
    # other projects never count.
    function Test-PluginInstalledForUser($Plugins) {
        foreach ($item in $Plugins) {
            if ((Test-ExactText (Get-Property $item 'id') 'specstone@specstone') -and (Test-ExactText (Get-Property $item 'scope') 'user')) {
                return $true
            }
        }
        return $false
    }

    # Puts marketplace specstone at the wanted source and installs the plugin
    # through claude, skipping what is there, or prints the commands when claude
    # is not on the PATH. A marketplace from another source stays, and a list
    # reply that is not read for sure stops the step like a failed list. Never
    # fails the script: the CLI install stands.
    function Install-Plugin {
        $wanted = 'nontravis/specstone'
        $wantedRef = ''
        if ($Version.Length -gt 0) {
            $wanted = "$wanted#v$Version"
            $wantedRef = "v$Version"
        }
        $found = Get-Command claude -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -eq $found) {
            Write-ManualPluginCommands $wanted
            return
        }
        $claude = $found.Source
        $listMarketplaces = @('plugin', 'marketplace', 'list', '--json')
        $marketplaces = Get-ClaudeList $claude $listMarketplaces $wanted
        if ($null -eq $marketplaces) {
            return
        }
        $entries = @($marketplaces | Where-Object { Test-ExactText (Get-Property $_ 'name') 'specstone' })
        $entry = $null
        if ($entries.Count -eq 1) {
            $entry = $entries[0]
        }
        if ($entries.Count -gt 1 -or ($null -ne $entry -and (Get-Property $entry 'source') -isnot [string])) {
            Write-UnreadableReply $listMarketplaces $wanted
            return
        }
        $plugins = Get-ClaudeList $claude @('plugin', 'list', '--json') $wanted
        if ($null -eq $plugins) {
            return
        }
        if ($null -eq $entry) {
            $added = Invoke-Claude $claude @('plugin', 'marketplace', 'add', $wanted) $true
            if ($null -eq $added) {
                return
            }
        } else {
            if (-not (Test-OfficialEntry $entry)) {
                Write-Host "specstone: marketplace specstone comes from $(Get-EntrySource $entry), not nontravis/specstone; left as it is"
                Write-PluginCommands $wanted
            } else {
                $ref = Get-Property $entry 'ref'
                if ($ref -isnot [string]) {
                    $ref = ''
                }
                if ($ref -cne $wantedRef) {
                    if (-not (Move-Marketplace $claude $wanted)) {
                        return
                    }
                    $plugins = @()
                }
            }
        }
        if (-not (Test-PluginInstalledForUser $plugins)) {
            $installed = Invoke-Claude $claude @('plugin', 'install', 'specstone@specstone') $true
            if ($null -eq $installed) {
                return
            }
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

    # Puts the archive's lib\ and bin\ into $InstallDir, bin last. Each existing
    # file is renamed to <name>.old first, so a running specstone.exe can be
    # replaced; a failure puts every renamed file back and removes what it copied.
    function Install-Files([string]$InstallDir) {
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
    # Nothing above this line starts a program. From here every program, claude
    # included, is searched on absolute PATH entries only. cmd.exe also tries
    # the current folder before PATH, for the bare `node` that claude.cmd runs;
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

        $probe = Invoke-Native (Join-Path $unpack 'bin\specstone.exe') @('--version') $false
        if ($probe.Status -ne 0) {
            throw "specstone: the downloaded specstone does not run (exit $($probe.Status)); the install is unchanged"
        }
        $newVersion = (@($probe.Output) -join "`n").Trim()

        Remove-OldLeftovers $installDir
        $oldVersion = ''
        $oldBinary = Join-Path $installDir 'bin\specstone.exe'
        if (Test-Path -LiteralPath $oldBinary) {
            $oldProbe = Invoke-Native $oldBinary @('--version') $false
            if ($oldProbe.Status -eq 0) {
                $oldVersion = (@($oldProbe.Output) -join "`n").Trim()
            }
        }
        if ($oldVersion.Length -gt 0 -and $oldVersion -ceq $newVersion) {
            if ($Version.Length -gt 0) {
                Write-Host "specstone $newVersion is already installed"
            } else {
                Write-Host "specstone $newVersion is already the latest release"
            }
        } else {
            Install-Files $installDir
            Write-Host "specstone $newVersion installed in $installDir\bin"
        }

        Add-UserPathEntry (Join-Path $installDir 'bin')
        Install-Plugin
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
