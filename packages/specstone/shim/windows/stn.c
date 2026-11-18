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

/* Takes Ctrl+C and Ctrl+Break so this process lives on while the target, in the
 * same console, gets the event and decides. The ignore flag of
 * SetConsoleCtrlHandler(NULL, TRUE) would pass to the target, so it is not used. */
static BOOL WINAPI take_console_event(DWORD type)
{
    return type == CTRL_C_EVENT || type == CTRL_BREAK_EVENT;
}

/* Returns a job object that ends its processes when its last handle closes and
 * lets their children break away, or NULL when none can be made. */
static HANDLE make_job(void)
{
    HANDLE job = CreateJobObjectW(NULL, NULL);
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits;

    if (job == NULL) {
        return NULL;
    }
    ZeroMemory(&limits, sizeof(limits));
    limits.BasicLimitInformation.LimitFlags =
        JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE | JOB_OBJECT_LIMIT_SILENT_BREAKAWAY_OK;
    if (!SetInformationJobObject(job, JobObjectExtendedLimitInformation, &limits,
                                 sizeof(limits))) {
        CloseHandle(job);
        return NULL;
    }
    return job;
}

/* Puts the suspended process in the job, when there is one, then lets it run.
 * A job that refuses it (an outer job that forbids nesting) leaves it unjobbed,
 * since running beats refusing. Returns FALSE when the process cannot resume. */
static BOOL release_into_job(const PROCESS_INFORMATION *process, HANDLE job)
{
    if (job != NULL) {
        (void)AssignProcessToJobObject(job, process->hProcess);
    }
    return ResumeThread(process->hThread) != (DWORD)-1;
}

/* Starts program with the raw tail and waits for it, in this console and with
 * this process's standard handles and environment. The program is in a job
 * object from its first instruction, so it ends when this process does. Returns
 * the exit status of the program, all 32 bits. When it cannot start, sets
 * start_failure to the system error and returns 1. */
static DWORD start_and_wait(const wchar_t *program, const wchar_t *tail)
{
    const wchar_t *separator = (*tail != L'\0') ? L" " : L"";
    const wchar_t *parts[5];
    wchar_t *command_line;
    STARTUPINFOW startup;
    PROCESS_INFORMATION process;
    DWORD status = 1;
    HANDLE job;
    BOOL started;

    parts[0] = L"\"";
    parts[1] = program;
    parts[2] = L"\"";
    parts[3] = separator;
    parts[4] = tail;
    command_line = join(parts, 5);
    if (command_line == NULL) {
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

    job = make_job();
    started = CreateProcessW(program, command_line, NULL, NULL, TRUE,
                             CREATE_UNICODE_ENVIRONMENT | CREATE_SUSPENDED, NULL, NULL,
                             &startup, &process);
    if (!started) {
        start_failure = GetLastError();
    } else if (!release_into_job(&process, job)) {
        start_failure = GetLastError();
        TerminateProcess(process.hProcess, 1);
        CloseHandle(process.hThread);
        CloseHandle(process.hProcess);
    } else {
        CloseHandle(process.hThread);
        WaitForSingleObject(process.hProcess, INFINITE);
        if (!GetExitCodeProcess(process.hProcess, &status)) {
            status = 1;
        }
        CloseHandle(process.hProcess);
    }
    if (job != NULL) {
        CloseHandle(job);
    }
    release(command_line);
    return status;
}

/* Runs program with the raw tail of this process's command line and returns its
 * exit status; prints the reason and returns 1 when it cannot start. */
static int run_program(const wchar_t *program)
{
    DWORD status = start_and_wait(program, after_program_name(GetCommandLineW()));

    if (start_failure != 0) {
        report_failure(L"cannot start", program, start_failure);
        return 1;
    }
    return (int)status;
}

int wmain(void)
{
    wchar_t own[PATH_CAPACITY];
    wchar_t *slash;
    const wchar_t *parts[2];
    wchar_t *target;
    DWORD length = GetModuleFileNameW(NULL, own, PATH_CAPACITY);
    int status;

    SetConsoleCtrlHandler(take_console_event, TRUE);
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
    status = run_program(target);
    release(target);
    return status;
}
