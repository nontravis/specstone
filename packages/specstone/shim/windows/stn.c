/*
 * stn.exe: the Windows short name for specstone. It runs the specstone.exe
 * beside it with the raw tail of its own command line, so cmd.exe never parses
 * the arguments on the way, and exits with that program's status.
 *
 * Built by build.ps1 with MSVC and the static C runtime.
 */
#include <windows.h>
#include <wchar.h>

#define PATH_CAPACITY 32768
#define TARGET_NAME L"specstone.exe"
#define FALLBACK_CMD L"\\System32\\cmd.exe"

/* Set by start_and_wait to the system error of a program it could not start. */
static DWORD start_failure = 0;

/* Returns the command line past its program name: the name runs to the closing
 * quote when it opens with one, else to the first space or tab, as the C runtime
 * reads it; the spaces and tabs after it are dropped, the rest stays as typed. */
static const wchar_t *after_program_name(const wchar_t *line)
{
    if (*line == L'"') {
        line++;
        while (*line != L'\0' && *line != L'"') {
            line++;
        }
        if (*line == L'"') {
            line++;
        }
    } else {
        while (*line != L'\0' && *line != L' ' && *line != L'\t') {
            line++;
        }
    }
    while (*line == L' ' || *line == L'\t') {
        line++;
    }
    return line;
}

/* Returns the parts joined into one new string, or NULL when memory is out. */
static wchar_t *join(const wchar_t *const *parts, size_t count)
{
    size_t total = 1;
    size_t at = 0;
    size_t i;
    wchar_t *text;

    for (i = 0; i < count; i++) {
        total += wcslen(parts[i]);
    }
    text = (wchar_t *)HeapAlloc(GetProcessHeap(), 0, total * sizeof(wchar_t));
    if (text == NULL) {
        return NULL;
    }
    for (i = 0; i < count; i++) {
        size_t length = wcslen(parts[i]);
        wmemcpy(text + at, parts[i], length);
        at += length;
    }
    text[at] = L'\0';
    return text;
}

static void release(wchar_t *text)
{
    if (text != NULL) {
        HeapFree(GetProcessHeap(), 0, text);
    }
}

/* Writes text to stderr: UTF-16 to a console, UTF-8 bytes to a pipe or file. */
static void write_stderr(const wchar_t *text)
{
    HANDLE handle = GetStdHandle(STD_ERROR_HANDLE);
    DWORD mode;
    DWORD written;
    int length = (int)wcslen(text);
    int size;
    char *bytes;

    if (handle == NULL || handle == INVALID_HANDLE_VALUE) {
        return;
    }
    if (GetConsoleMode(handle, &mode)) {
        WriteConsoleW(handle, text, (DWORD)length, &written, NULL);
        return;
    }
    size = WideCharToMultiByte(CP_UTF8, 0, text, length, NULL, 0, NULL, NULL);
    if (size <= 0) {
        return;
    }
    bytes = (char *)HeapAlloc(GetProcessHeap(), 0, (SIZE_T)size);
    if (bytes == NULL) {
        return;
    }
    if (WideCharToMultiByte(CP_UTF8, 0, text, length, bytes, size, NULL, NULL) > 0) {
        WriteFile(handle, bytes, (DWORD)size, &written, NULL);
    }
    HeapFree(GetProcessHeap(), 0, bytes);
}

/* Prints "stn: <what> <subject>: <the system's reason for error>" on stderr. */
static void report_failure(const wchar_t *what, const wchar_t *subject, DWORD error)
{
    wchar_t *reason = NULL;
    DWORD length = FormatMessageW(
        FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM
            | FORMAT_MESSAGE_IGNORE_INSERTS,
        NULL, error, 0, (LPWSTR)&reason, 0, NULL);
    const wchar_t *parts[7];
    wchar_t *line;

    while (length > 0 && (reason[length - 1] == L'\r' || reason[length - 1] == L'\n'
                          || reason[length - 1] == L' ')) {
        length--;
    }
    if (reason != NULL) {
        reason[length] = L'\0';
    }
    parts[0] = L"stn: ";
    parts[1] = what;
    parts[2] = L" ";
    parts[3] = subject;
    parts[4] = L": ";
    parts[5] = (reason != NULL && length > 0) ? reason : L"unknown error";
    parts[6] = L"\r\n";
    line = join(parts, 7);
    if (line != NULL) {
        write_stderr(line);
        release(line);
    }
    if (reason != NULL) {
        LocalFree(reason);
    }
}

/* Returns the handle as a child may inherit it; it is none when stn.exe has
 * none, as for a process started without that stream. */
static HANDLE inheritable_std_handle(DWORD which)
{
    HANDLE handle = GetStdHandle(which);

    if (handle != NULL && handle != INVALID_HANDLE_VALUE) {
        SetHandleInformation(handle, HANDLE_FLAG_INHERIT, HANDLE_FLAG_INHERIT);
    }
    return handle;
}

/* Returns the cmd.exe that ComSpec names, else the one under SystemRoot. */
static wchar_t *find_cmd(void)
{
    wchar_t buffer[PATH_CAPACITY];
    const wchar_t *parts[2];
    DWORD length = GetEnvironmentVariableW(L"ComSpec", buffer, PATH_CAPACITY);

    if (length > 0 && length < PATH_CAPACITY) {
        parts[0] = buffer;
        return join(parts, 1);
    }
    length = GetEnvironmentVariableW(L"SystemRoot", buffer, PATH_CAPACITY);
    if (length == 0 || length >= PATH_CAPACITY) {
        return NULL;
    }
    parts[0] = buffer;
    parts[1] = FALLBACK_CMD;
    return join(parts, 2);
}

/* Starts program with the raw tail and waits for it, in this console and with
 * this process's standard handles and environment; through_cmd starts it as
 * `cmd.exe /d /s /c` does a batch file. Returns the exit status of the program,
 * all 32 bits. When it cannot start, sets start_failure to the system error
 * and returns 1. */
static DWORD start_and_wait(const wchar_t *program, const wchar_t *tail, BOOL through_cmd)
{
    const wchar_t *separator = (*tail != L'\0') ? L" " : L"";
    const wchar_t *plain[5];
    const wchar_t *wrapped[8];
    wchar_t *cmd = NULL;
    wchar_t *command_line;
    STARTUPINFOW startup;
    PROCESS_INFORMATION process;
    DWORD status = 1;
    BOOL started;

    if (through_cmd) {
        cmd = find_cmd();
        if (cmd == NULL) {
            start_failure = ERROR_FILE_NOT_FOUND;
            return 1;
        }
        wrapped[0] = L"\"";
        wrapped[1] = cmd;
        wrapped[2] = L"\" /d /s /c \"\"";
        wrapped[3] = program;
        wrapped[4] = L"\"";
        wrapped[5] = separator;
        wrapped[6] = tail;
        wrapped[7] = L"\"";
        command_line = join(wrapped, 8);
    } else {
        plain[0] = L"\"";
        plain[1] = program;
        plain[2] = L"\"";
        plain[3] = separator;
        plain[4] = tail;
        command_line = join(plain, 5);
    }
    if (command_line == NULL) {
        release(cmd);
        start_failure = ERROR_OUTOFMEMORY;
        return 1;
    }

    ZeroMemory(&startup, sizeof(startup));
    startup.cb = sizeof(startup);
    startup.dwFlags = STARTF_USESTDHANDLES;
    startup.hStdInput = inheritable_std_handle(STD_INPUT_HANDLE);
    startup.hStdOutput = inheritable_std_handle(STD_OUTPUT_HANDLE);
    startup.hStdError = inheritable_std_handle(STD_ERROR_HANDLE);
    ZeroMemory(&process, sizeof(process));

    started = CreateProcessW(through_cmd ? cmd : program, command_line, NULL, NULL,
                             TRUE, CREATE_UNICODE_ENVIRONMENT, NULL, NULL,
                             &startup, &process);
    if (!started) {
        start_failure = GetLastError();
    } else {
        CloseHandle(process.hThread);
        WaitForSingleObject(process.hProcess, INFINITE);
        if (!GetExitCodeProcess(process.hProcess, &status)) {
            status = 1;
        }
        CloseHandle(process.hProcess);
    }
    release(command_line);
    release(cmd);
    return status;
}

int wmain(void)
{
    wchar_t own[PATH_CAPACITY];
    wchar_t *slash;
    const wchar_t *parts[2];
    wchar_t *target;
    DWORD length = GetModuleFileNameW(NULL, own, PATH_CAPACITY);
    DWORD status;

    if (length == 0 || length >= PATH_CAPACITY) {
        report_failure(L"cannot read the path of", L"stn.exe", GetLastError());
        return 1;
    }
    slash = wcsrchr(own, L'\\');
    if (slash == NULL) {
        report_failure(L"cannot read the path of", L"stn.exe", ERROR_BAD_PATHNAME);
        return 1;
    }
    slash[1] = L'\0';
    parts[0] = own;
    parts[1] = TARGET_NAME;
    target = join(parts, 2);
    if (target == NULL) {
        report_failure(L"cannot start", TARGET_NAME, ERROR_OUTOFMEMORY);
        return 1;
    }

    status = start_and_wait(target, after_program_name(GetCommandLineW()), FALSE);
    if (start_failure != 0) {
        report_failure(L"cannot start", target, start_failure);
        release(target);
        return 1;
    }
    release(target);
    return (int)status;
}
