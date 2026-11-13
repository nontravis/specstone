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
    # A lookup that finds nothing, such as Get-Command claude with no claude on
    # the PATH, searches every module folder too, so module search is off from
    # here: every cmdlet below comes from these modules or the core.
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

    # Returns $true when the strings $First and $Second hold the same characters.
    # -ceq compares by culture rules, which on Windows PowerShell 5.1 skip a NUL
    # or a soft hyphen, so it can match a text that differs.
    function Test-SameText([string]$First, [string]$Second) {
        return [string]::Equals($First, $Second, [StringComparison]::Ordinal)
    }

    # Returns the text of the JSON string $Raw (the characters between its
    # quotes) as install.sh reads it: \" and \\ decode, and any other escape
    # stays as typed, so no escaped value equals a plain one.
    function ConvertFrom-JsonString([string]$Raw) {
        return [regex]::Replace($Raw, '\\.', [System.Text.RegularExpressions.MatchEvaluator]{
            param($escape)
            if ($escape.Value -ceq '\"') {
                return '"'
            }
            if ($escape.Value -ceq '\\') {
                return '\'
            }
            return $escape.Value
        })
    }

    # Records that the object being read holds the key $Key once more, with the
    # kind of the latest value and, for a string, its text.
    function Add-JsonField($Fields, [string]$Key, [bool]$IsString, [string]$Text) {
        if ($Fields.ContainsKey($Key)) {
            $field = $Fields[$Key]
            $field.Count = $field.Count + 1
            $field.IsString = $IsString
            $field.Text = $Text
        } else {
            $Fields[$Key] = [pscustomobject]@{ Count = 1; IsString = $IsString; Text = $Text }
        }
    }

    # Returns what Add-JsonField recorded for the key $Key, or $null.
    function Get-JsonField($Fields, [string]$Key) {
        if ($Fields.ContainsKey($Key)) {
            return $Fields[$Key]
        }
        return $null
    }

    # Returns $true when the key $Key appears once in $Fields, holds a string,
    # and that string is $Text.
    function Test-FieldText($Fields, [string]$Key, [string]$Text) {
        $field = Get-JsonField $Fields $Key
        return ($null -ne $field) -and ($field.Count -eq 1) -and $field.IsString -and (Test-SameText $field.Text $Text)
    }

    # Returns the string value of the key $Key in the marketplace entry
    # $Entry, or '' when it is missing, repeated, or not a string.
    function Get-EntryText($Entry, [string]$Key) {
        $field = Get-JsonField $Entry $Key
        if ($null -ne $field -and $field.Count -eq 1 -and $field.IsString) {
            return $field.Text
        }
        return ''
    }

    # Returns $true when no key of $Fields appears twice. get_Values() because
    # a JSON key named Values would shadow the property.
    function Test-UniqueKeys($Fields) {
        foreach ($field in $Fields.get_Values()) {
            if ($field.Count -ne 1) {
                return $false
            }
        }
        return $true
    }

    # Reads the claude list reply $Reply with a strict JSON grammar walk that
    # knows strings and nesting, so a quote, brace, or key name inside a value
    # never counts, and returns Entry and Installed. It accepts and refuses what
    # install.sh's json_scan does: it throws when the reply is not read for
    # sure (not well-formed, text around the JSON, a key written with an
    # escape at an entry's own depth, a top level that is not an array, or a
    # string with a raw control character, U+0000 to U+001F). Mode
    # `marketplaces`: Entry holds the keys of the one object named
    # "specstone" (or $null), and the walk throws for
    # two such objects, a repeated key in it, a repeated name anywhere, or a
    # source that is not one string. Mode `plugins`: Installed is $true when
    # an object holds the id specstone@specstone and the scope user, and the
    # walk throws for a repeated id or scope. No other parser reads the reply,
    # so no parser can disagree with the walk about a key or a value.
    function Read-ClaudeList([string]$Reply, [string]$Mode) {
        $tokens = [regex]::new('\G(?:(?<space>[ \t\r\n]+)|(?<string>"(?:[^"\\\x00-\x1f]|\\[^\x00-\x1f])*")|(?<mark>[{}\[\]:,])|(?<literal>true|false|null|-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][-+]?[0-9]+)?))')
        $kind = [System.Collections.Generic.List[string]]::new()
        $state = [System.Collections.Generic.List[string]]::new()
        $keys = [System.Collections.Generic.List[string]]::new()
        $kind.Add('top')
        $state.Add('val')
        $keys.Add('')
        $depth = 0
        $fields = $null
        $entry = $null
        $entryCount = 0
        $installed = $false
        $at = 0
        while ($at -lt $Reply.Length) {
            $token = $tokens.Match($Reply, $at)
            if (-not $token.Success) {
                throw 'a character that JSON does not allow here'
            }
            $at += $token.Length
            if ($token.Groups['space'].Success) {
                continue
            }
            $isString = $false
            $valueText = ''
            $opens = ''
            if ($token.Groups['string'].Success) {
                $raw = $token.Value.Substring(1, $token.Length - 2)
                if ($kind[$depth] -ceq '{' -and ($state[$depth] -ceq 'k0' -or $state[$depth] -ceq 'key')) {
                    if ($depth -eq 2 -and $raw.Contains('\')) {
                        throw 'a key written with an escape'
                    }
                    $keys[$depth] = $raw
                    $state[$depth] = 'colon'
                    continue
                }
                $isString = $true
                $valueText = ConvertFrom-JsonString $raw
            } elseif (-not $token.Groups['literal'].Success) {
                $mark = $token.Value
                if ($mark -ceq '}' -or $mark -ceq ']') {
                    $expected = '['
                    if ($mark -ceq '}') {
                        $expected = '{'
                    }
                    if ($depth -lt 1 -or $kind[$depth] -cne $expected) {
                        throw 'a closing mark that closes nothing'
                    }
                    if ($state[$depth] -cne 'next' -and $state[$depth] -cne 'k0' -and $state[$depth] -cne 'v0') {
                        throw 'a closing mark where a value is due'
                    }
                    if ($mark -ceq '}' -and $depth -eq 2) {
                        if ($Mode -ceq 'marketplaces') {
                            $nameField = Get-JsonField $fields 'name'
                            if ($null -ne $nameField -and $nameField.Count -gt 1) {
                                throw 'a repeated name'
                            }
                            if (Test-FieldText $fields 'name' 'specstone') {
                                $sourceField = Get-JsonField $fields 'source'
                                if (-not (Test-UniqueKeys $fields) -or $null -eq $sourceField -or $sourceField.Count -ne 1 -or -not $sourceField.IsString) {
                                    throw 'a specstone entry that is not read for sure'
                                }
                                $entryCount++
                                $entry = $fields
                            }
                        } else {
                            $idField = Get-JsonField $fields 'id'
                            $scopeField = Get-JsonField $fields 'scope'
                            if (($null -ne $idField -and $idField.Count -gt 1) -or ($null -ne $scopeField -and $scopeField.Count -gt 1)) {
                                throw 'a repeated id or scope'
                            }
                            if ((Test-FieldText $fields 'id' 'specstone@specstone') -and (Test-FieldText $fields 'scope' 'user')) {
                                $installed = $true
                            }
                        }
                    }
                    $kind.RemoveAt($depth)
                    $state.RemoveAt($depth)
                    $keys.RemoveAt($depth)
                    $depth--
                    $state[$depth] = 'next'
                    continue
                }
                if ($mark -ceq ',') {
                    if ($depth -lt 1 -or $state[$depth] -cne 'next') {
                        throw 'a comma where none is due'
                    }
                    $state[$depth] = 'val'
                    if ($kind[$depth] -ceq '{') {
                        $state[$depth] = 'key'
                    }
                    continue
                }
                if ($mark -ceq ':') {
                    if ($kind[$depth] -cne '{' -or $state[$depth] -cne 'colon') {
                        throw 'a colon where none is due'
                    }
                    $state[$depth] = 'val'
                    continue
                }
                $opens = $mark
            }
            if ($state[$depth] -cne 'val' -and $state[$depth] -cne 'v0') {
                throw 'a value where none is due'
            }
            if ($depth -eq 0 -and $opens -cne '[') {
                throw 'a top level that is not an array'
            }
            if ($depth -eq 2 -and $kind[$depth] -ceq '{') {
                Add-JsonField $fields $keys[$depth] $isString $valueText
            }
            if ($opens.Length -eq 0) {
                $state[$depth] = 'next'
                continue
            }
            $depth++
            $kind.Add($opens)
            $state.Add('v0')
            $keys.Add('')
            if ($opens -ceq '{') {
                $state[$depth] = 'k0'
                if ($depth -eq 2) {
                    $fields = [System.Collections.Generic.Dictionary[string, object]]::new()
                }
            }
        }
        if ($depth -ne 0 -or $state[0] -cne 'next') {
            throw 'a reply that ends before its list does'
        }
        if ($entryCount -gt 1) {
            throw 'two entries named specstone'
        }
        return [pscustomobject]@{ Entry = $entry; Installed = $installed }
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

    # Runs a claude list command and reads its reply per Read-ClaudeList with
    # $Mode; returns what it read, or $null after naming the failure or the
    # reply that was not read for sure.
    function Get-ClaudeList([string]$Claude, [string[]]$Arguments, [string]$Wanted, [string]$Mode) {
        $result = Invoke-Claude $Claude $Arguments $false
        if ($null -eq $result) {
            return $null
        }
        try {
            return Read-ClaudeList (@($result.Output) -join "`n") $Mode
        } catch {
            Write-UnreadableReply $Arguments $Wanted
            return $null
        }
    }

    # Returns $true when the marketplace entry $Entry is the one this script
    # adds: source github, repo exactly nontravis/specstone, each written
    # without an escape. Any other entry is the Owner's own.
    function Test-OfficialEntry($Entry) {
        return (Test-FieldText $Entry 'source' 'github') -and (Test-FieldText $Entry 'repo' 'nontravis/specstone')
    }

    # Returns the url $Url without the userinfo (user or user:token) before
    # the host.
    function Remove-UrlUserinfo([string]$Url) {
        $schemeEnd = $Url.IndexOf('://', [StringComparison]::Ordinal)
        if ($schemeEnd -lt 0) {
            return $Url
        }
        $rest = $Url.Substring($schemeEnd + 3)
        $authorityEnd = $rest.IndexOfAny([char[]]'/?#')
        if ($authorityEnd -lt 0) {
            $authorityEnd = $rest.Length
        }
        $authority = $rest.Substring(0, $authorityEnd)
        $hostName = $authority.Substring($authority.LastIndexOf([char]'@') + 1)
        return $Url.Substring(0, $schemeEnd) + '://' + $hostName + $rest.Substring($authorityEnd)
    }

    # Returns where the marketplace entry $Entry comes from, read from the key
    # its source type names (a url without its userinfo), else 'an unknown
    # source'.
    function Get-EntrySource($Entry) {
        $source = Get-EntryText $Entry 'source'
        $key = ''
        if (Test-SameText $source 'github') {
            $key = 'repo'
        } elseif ((Test-SameText $source 'git') -or (Test-SameText $source 'url')) {
            $key = 'url'
        } elseif ((Test-SameText $source 'directory') -or (Test-SameText $source 'file')) {
            $key = 'path'
        }
        $found = ''
        if ($key.Length -gt 0) {
            $found = Get-EntryText $Entry $key
        }
        if ($found.Length -eq 0) {
            return 'an unknown source'
        }
        if ($key -ceq 'url') {
            $found = Remove-UrlUserinfo $found
        }
        return Get-PrintableText $found
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
        $marketplaces = Get-ClaudeList $claude @('plugin', 'marketplace', 'list', '--json') $wanted 'marketplaces'
        if ($null -eq $marketplaces) {
            return
        }
        $plugins = Get-ClaudeList $claude @('plugin', 'list', '--json') $wanted 'plugins'
        if ($null -eq $plugins) {
            return
        }
        $entry = $marketplaces.Entry
        $isInstalled = $plugins.Installed
        if ($null -eq $entry) {
            $added = Invoke-Claude $claude @('plugin', 'marketplace', 'add', $wanted) $true
            if ($null -eq $added) {
                return
            }
        } elseif (-not (Test-OfficialEntry $entry)) {
            Write-Host "specstone: marketplace specstone comes from $(Get-EntrySource $entry), not nontravis/specstone; left as it is"
            Write-PluginCommands $wanted
        } elseif (-not (Test-SameText (Get-EntryText $entry 'ref') $wantedRef)) {
            if (-not (Move-Marketplace $claude $wanted)) {
                return
            }
            $isInstalled = $false
        }
        if (-not $isInstalled) {
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

    # Prints one line naming the first `stn` on the cut $env:Path other than
    # in $BinFolder, as bin\stn.cmd walks it (run_cli_or_yield E03, E08-E10):
    # an entry that reads as $BinFolder, or holds stn.cmd and specstone.exe,
    # is skipped; a `stn` is a file named stn.exe, .cmd, .bat, .com, or .ps1,
    # tried in that order. The notice never changes the run's exit status.
    function Write-OtherStnNotice([string]$BinFolder) {
        $own = Get-FolderIdentity $BinFolder
        foreach ($entry in @(Split-PathText (Get-EnvText 'Path'))) {
            try {
                if ([string]::Equals((Get-FolderIdentity $entry), $own, [StringComparison]::OrdinalIgnoreCase)) {
                    continue
                }
                $folder = [IO.Path]::GetFullPath($entry)
                if ((Test-Path -LiteralPath (Join-Path $folder 'stn.cmd')) -and (Test-Path -LiteralPath (Join-Path $folder 'specstone.exe'))) {
                    continue
                }
                # Name the folder as the PATH spells it: GetFullPath may expand 8.3 names.
                $shown = $entry.TrimEnd('\', '/')
                foreach ($extension in 'exe', 'cmd', 'bat', 'com', 'ps1') {
                    if (Test-Path -LiteralPath (Join-Path $folder "stn.$extension") -PathType Leaf) {
                        Write-Host "specstone: another stn is at $shown\stn.$extension; type specstone to run the CLI"
                        return
                    }
                }
            } catch {
                # an entry the OS cannot read holds no stn that the shim could run
            }
        }
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
        if ($oldVersion.Length -gt 0 -and (Test-SameText $oldVersion $newVersion)) {
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
        Write-OtherStnNotice (Join-Path $installDir 'bin')
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
