@echo off
rem Runs the Specstone CLI by its short name: the first other stn found on an
rem absolute PATH entry takes the run (with a loop guard added), else the
rem specstone.exe beside this shim does. Arguments, streams, environment, and
rem exit status pass through; the PATH is read, never rewritten.
rem Two scopes: the outer one ends with the batch, so the shell that typed stn
rem never holds the guard (run_cli_or_yield E11); the inner one holds the work
rem variables and ends on the run line, so the target gets the environment
rem the shim got, the guard alone added on a hand-off.
setlocal EnableExtensions DisableDelayedExpansion
setlocal
call :find_own_folder

rem A hand-off that came back here: run the CLI beside it at once
rem (run_cli_or_yield E01 backs the own-folder compare below).
if defined SPECSTONE_STN_GUARD goto run_own
if not defined PATH goto run_own

rem Split the PATH at each semicolon outside double quotes, the quotes dropped
rem and every other character kept literal, as cmd.exe reads a quoted entry
rem (after https://stackoverflow.com/a/7940444). Each special character gets
rem an escape, and a semicolon two; quotes stay doubled while a quoted set runs.
set "split=%PATH:"=""%"
set "split=%split:^=^^%"
set "split=%split:&=^&%"
set "split=%split:|=^|%"
set "split=%split:<=^<%"
set "split=%split:>=^>%"
set "split=%split:;=^;^;%"
rem An unquoted set drops the escapes outside the quotes only: a separator
rem becomes two plain semicolons, one inside quotes keeps its two escapes. A
rem question mark then marks the inner semicolon and a less-than sign each
rem separator, both characters no Windows path holds.
set split=%split:""="%
set "split=%split:"=""%"
set "split=%split:^;^;=?%"
set "split=%split:;;=<%"
rem An unquoted set behind one more quote drops the escapes left inside the
rem first quotes; then every quote goes.
set split="%split:""="%
set "split=%split:"=%"
set "target="
setlocal EnableDelayedExpansion
set "split=!split:?=;!"
for %%a in ("!split:<=" "!") do (
  if "!!"=="" endlocal
  if not defined target if %%a neq "" (
    set "entry=%%~a"
    call :visit
  )
)

if not defined target goto run_own
if /i "%target:~-4%"==".ps1" goto refuse
if /i "%target:~-4%"==".exe" goto run_target
if /i "%target:~-4%"==".com" goto run_target

rem Each run line expands its work variables before its endlocal drops them,
rem then sets the guard in the outer scope. A stn.cmd or stn.bat runs in a
rem child cmd.exe, so it never replaces this batch and the line still ends it.
endlocal & set "SPECSTONE_STN_GUARD=1" & "%ComSpec%" /d /v:off /s /c ^""%target%" %*^" & exit /b

:run_target
rem The run and the exit share one line: cmd.exe parses the whole line before
rem it runs, so it reads no later line of a stn.cmd that install.ps1 replaced
rem meanwhile (run_cli_or_yield E06).
endlocal & set "SPECSTONE_STN_GUARD=1" & "%target%" %* & exit /b

:run_own
endlocal & "%own%\specstone.exe" %* & exit /b

:refuse
rem A stn.ps1 first on the walk: start nothing, PowerShell included, so the
rem other tool keeps its name (run_cli_or_yield E10).
for %%F in ("%target%") do >&2 echo(another stn at %%~F; use specstone
exit /b 1

:find_own_folder
rem The batch's folder, read in a called label, is right even when cmd.exe
rem found the batch through PATH under a quoted name (as npm's cmd-shim does).
set "own=%~dp0"
set "own=%own:~0,-1%"
exit /b

:visit
rem Walk only an entry that starts with a drive root or \\ (run_cli_or_yield
rem E02); skip the shim's own folder, the trailing \ dropped and letter case
rem ignored, and any folder holding both stn.cmd and specstone.exe, which is
rem a Specstone install folder, the own one through a junction or symlink
rem included, since batch cannot resolve a link (E08).
if "%entry:~0,2%"=="\\" goto visit_absolute
if not "%entry:~1,1%"==":" exit /b
if "%entry:~2,1%"=="\" goto visit_absolute
if not "%entry:~2,1%"=="/" exit /b
:visit_absolute
for %%F in ("%entry%") do set "folder=%%~fF"
if "%folder:~-1%"=="\" set "folder=%folder:~0,-1%"
if /i "%folder%"=="%own%" exit /b
if exist "%folder%\stn.cmd" if exist "%folder%\specstone.exe" exit /b
if not exist "%folder%\stn.*" exit /b
for %%X in (exe cmd bat com ps1) do if not defined target (
  set "extension=%%X"
  call :probe
)
exit /b

:probe
rem A stn counts only as a file, never a folder (run_cli_or_yield E09).
set "attributes="
for %%F in ("%folder%\stn.%extension%") do set "attributes=%%~aF"
if not defined attributes exit /b
if /i "%attributes:~0,1%"=="d" exit /b
set "target=%folder%\stn.%extension%"
exit /b
