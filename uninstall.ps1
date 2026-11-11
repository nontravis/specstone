# Removes the Specstone CLI from ~\.specstone and its user PATH entry (Windows PowerShell 5.1):
#   irm https://raw.githubusercontent.com/nontravis/specstone/main/uninstall.ps1 | iex
# Personal packs, ~\.specstone itself, and every project's .specstone stay. The
# whole body sits in one & { } block. A truncated stream does not parse, so it
# runs nothing, and the strict mode and error preference set inside the block
# never reach the caller's session. A refusal throws; it never calls exit, which
# would close the caller's window under iex.
# Keep this file ASCII: Windows PowerShell 5.1 reads a file with no BOM as ANSI.
& {
    Set-StrictMode -Version 3
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'

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

    # Loads the Win32 calls this script needs, once per session.
    function Initialize-Native {
        if ($null -eq ('SpecstoneUninstall.NativeMethods' -as [type])) {
            Add-Type -Namespace SpecstoneUninstall -Name NativeMethods -MemberDefinition ('[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)] ' + 'public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult); ' + '[DllImport("kernel32.dll", CharSet = CharSet.Unicode)] ' + 'public static extern uint GetLongPathName(string lpszShortPath, System.Text.StringBuilder lpszLongPath, uint cchBuffer);')
        }
    }

    # Returns $Path with any 8.3 short name spelled out, so a process path and
    # the install folder compare equal whichever spelling each one carries. A
    # short name holds a ~, so a path without one is returned as it is.
    function Get-LongPath([string]$Path) {
        if ($Path.IndexOf('~') -lt 0) {
            return $Path
        }
        try {
            Initialize-Native
            $buffer = New-Object System.Text.StringBuilder -ArgumentList 32768
            $length = [SpecstoneUninstall.NativeMethods]::GetLongPathName($Path, $buffer, 32768)
            if ($length -gt 0 -and $length -lt 32768) {
                return $buffer.ToString()
            }
        } catch {
            # no long form to find; compare the path as it is
        }
        return $Path
    }

    # Tells running programs that the user environment changed, as the Windows
    # settings dialog does; without it only new sessions of Explorer see it.
    function Send-EnvironmentChange {
        Initialize-Native
        $result = [UIntPtr]::Zero
        # HWND_BROADCAST, WM_SETTINGCHANGE, SMTO_ABORTIFHUNG, 5 s
        [void][SpecstoneUninstall.NativeMethods]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$result)
    }

    # Returns the first line of the exception message in $ErrorRecord.
    function Get-FirstMessageLine($ErrorRecord) {
        return (([string]$ErrorRecord.Exception.Message) -split '\r?\n')[0]
    }

    # Returns the files under the folders $Folders that another program holds
    # open. Each file is opened for exclusive read and write; only a sharing or
    # lock violation counts as held, so a read-only file is not mistaken for a
    # running program and the removal reports it by itself.
    function Get-LockedFile([string[]]$Folders) {
        $locked = New-Object System.Collections.ArrayList
        foreach ($folder in $Folders) {
            foreach ($file in @(Get-ChildItem -LiteralPath $folder -Recurse -File -Force)) {
                $stream = $null
                try {
                    $stream = [System.IO.File]::Open($file.FullName, 'Open', 'ReadWrite', 'None')
                } catch {
                    # Open() wraps the failure in a MethodInvocationException.
                    $cause = $_.Exception.GetBaseException()
                    $code = $cause.HResult -band 0xFFFF
                    if ($cause -is [System.IO.IOException] -and ($code -eq 32 -or $code -eq 33)) {
                        [void]$locked.Add($file.FullName)
                    }
                } finally {
                    if ($null -ne $stream) {
                        $stream.Dispose()
                    }
                }
            }
        }
        return $locked.ToArray()
    }

    # Returns the folder of $Roots that holds the path $Path, or ''.
    function Find-Root([string]$Path, $Roots) {
        $long = Get-LongPath $Path
        foreach ($root in $Roots) {
            if ($long.StartsWith($root.Prefix, [StringComparison]::OrdinalIgnoreCase)) {
                return $root.Shown
            }
        }
        return ''
    }

    # Returns the folder of $Roots that holds the executable $Exe of $Process,
    # else a loaded module of it, or '' when none does. The modules are read
    # only when the executable is elsewhere; a process this user may not
    # inspect has no readable Modules and counts as outside.
    function Find-RunningFrom($Process, [string]$Exe, $Roots) {
        if ($Exe.Length -gt 0) {
            $from = Find-Root $Exe $Roots
            if ($from.Length -gt 0) {
                return $from
            }
        }
        try {
            foreach ($module in @($Process.Modules)) {
                $from = Find-Root ([string]$module.FileName) $Roots
                if ($from.Length -gt 0) {
                    return $from
                }
            }
        } catch {
            # no access to this process's modules
        }
        return ''
    }

    # Returns a table of process id to executable path from WMI, which reports
    # the path of a 64-bit process to a 32-bit PowerShell too. A failure gives
    # an empty table, and the modules then carry the match.
    function Get-ExecutablePath {
        $paths = @{}
        try {
            foreach ($item in @(Get-CimInstance -ClassName Win32_Process)) {
                if ($null -ne $item.ExecutablePath) {
                    $paths[[int]$item.ProcessId] = [string]$item.ExecutablePath
                }
            }
        } catch {
            # fall back to the loaded modules
        }
        return $paths
    }

    # Returns the message that refuses the uninstall: one line per process that
    # runs from $Folders, else one line naming the first held file.
    function Get-RefusalMessage([string[]]$Folders, [string[]]$Locked) {
        $roots = @(foreach ($folder in $Folders) {
            [pscustomobject]@{ Shown = $folder; Prefix = (Get-LongPath $folder).TrimEnd('\') + '\' }
        })
        $lines = New-Object System.Collections.ArrayList
        $executables = Get-ExecutablePath
        foreach ($process in @(Get-Process -ErrorAction SilentlyContinue)) {
            $exe = ''
            if ($executables.ContainsKey([int]$process.Id)) {
                $exe = $executables[[int]$process.Id]
            }
            $from = Find-RunningFrom $process $exe $roots
            if ($from.Length -gt 0) {
                [void]$lines.Add("specstone: cannot uninstall while $($process.ProcessName) (PID $($process.Id)) runs from $from; stop it and run the uninstall line again")
            }
        }
        if ($lines.Count -eq 0) {
            [void]$lines.Add("specstone: cannot uninstall while $($Locked[0]) is in use by another program; stop it and run the uninstall line again")
        }
        return ($lines.ToArray() -join "`n")
    }

    # Deletes the folder $Folder when it is there, and says so. Returns 'none',
    # 'removed', or 'failed'; a failure is named on stderr and the rest goes on.
    function Remove-Folder([string]$Folder) {
        if (-not (Test-Path -LiteralPath $Folder)) {
            return 'none'
        }
        try {
            Remove-Item -LiteralPath $Folder -Recurse -Force
            if (Test-Path -LiteralPath $Folder) {
                throw 'it is still there'
            }
        } catch {
            [Console]::Error.WriteLine("specstone: could not remove ${Folder}: $(Get-FirstMessageLine $_)")
            return 'failed'
        }
        Write-Host "Removed $Folder"
        return 'removed'
    }

    # Removes every user PATH item that names $Folder, ignoring case, a trailing
    # backslash, and %VAR% spelling as the install does, and keeps every other
    # item as it was. The Path is read from the registry unexpanded and written
    # back with its kind, so the owner's %VAR% items stay as they are. Returns
    # 'none', 'removed', or 'failed'.
    function Remove-UserPathEntry([string]$Folder) {
        $key = $null
        try {
            $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
            if (@($key.GetValueNames()) -notcontains 'Path') {
                return 'none'
            }
            $current = [string]$key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            $kind = $key.GetValueKind('Path')
            # Leave a Path of another kind (a multi-string, say) untouched.
            if ($kind -ne [Microsoft.Win32.RegistryValueKind]::String -and $kind -ne [Microsoft.Win32.RegistryValueKind]::ExpandString) {
                if ($current.IndexOf($Folder, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
                    return 'none'
                }
                [Console]::Error.WriteLine("specstone: the user PATH has an unexpected type ($kind) and is left as it is: remove $Folder from it yourself")
                return 'failed'
            }
            $wanted = [Environment]::ExpandEnvironmentVariables($Folder).TrimEnd('\')
            $kept = New-Object System.Collections.ArrayList
            $dropped = 0
            foreach ($entry in $current.Split(';')) {
                if ([Environment]::ExpandEnvironmentVariables($entry.Trim()).TrimEnd('\') -ieq $wanted) {
                    $dropped++
                } else {
                    [void]$kept.Add($entry)
                }
            }
            if ($dropped -eq 0) {
                return 'none'
            }
            $key.SetValue('Path', ($kept.ToArray() -join ';'), $kind)
        } catch {
            [Console]::Error.WriteLine("specstone: could not write the user PATH: remove $Folder from it yourself")
            return 'failed'
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
        Write-Host "Removed $Folder from the user PATH"
        return 'removed'
    }

    $homeDir = Get-EnvText 'HOME'
    if ($homeDir.Length -eq 0) {
        $homeDir = Get-EnvText 'USERPROFILE'
    }
    if ($homeDir.Length -eq 0) {
        throw 'specstone: no home folder: HOME and USERPROFILE are unset'
    }
    $installDir = Join-Path $homeDir '.specstone'
    $binDir = Join-Path $installDir 'bin'
    $libDir = Join-Path $installDir 'lib'

    # Nothing above this line starts a program. From here every program is
    # searched on absolute PATH entries only; the finally below puts the
    # caller's PATH back, as the block runs in the caller's session.
    $savedPath = Get-EnvText 'Path'
    $env:Path = Get-AbsolutePathText $savedPath
    try {
        # Check every file before any delete, so a refusal leaves the install whole.
        $present = @(foreach ($folder in @($binDir, $libDir)) {
            if (Test-Path -LiteralPath $folder) {
                $folder
            }
        })
        $locked = @(Get-LockedFile $present)
        if ($locked.Count -gt 0) {
            throw (Get-RefusalMessage $present $locked)
        }

        $results = @((Remove-Folder $binDir), (Remove-Folder $libDir), (Remove-UserPathEntry $binDir))
        $failed = $results -contains 'failed'
        if (-not $failed -and -not ($results -contains 'removed')) {
            Write-Host 'specstone: nothing to remove'
        }
        Write-Host 'claude plugin uninstall specstone@specstone'
        if ($failed) {
            throw 'specstone: the uninstall is incomplete; the lines above name what stays'
        }
    } finally {
        $env:Path = $savedPath
    }
}
