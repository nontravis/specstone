/*
 * stn.exe: the Windows short name for specstone. It hands the run to the first
 * other stn on an absolute PATH entry, else runs the specstone.exe beside it,
 * with the raw tail of its own command line, so cmd.exe never parses the
 * arguments on the way, and exits with that program's status. A stn.ps1 found
 * first is refused, never run.
 *
 * Built by build.ps1 with MSVC and the static C runtime.
 */
#include <windows.h>
#include <wchar.h>

#define PATH_CAPACITY 32768
#define TARGET_NAME L"specstone.exe"
#define FALLBACK_CMD L"\\System32\\cmd.exe"
#define GUARD_NAME L"SPECSTONE_STN_GUARD"
#define OTHER_NAME_COUNT 5

typedef enum { STN_NONE, STN_PROGRAM, STN_BATCH, STN_PS1 } stn_kind;

/* The files a stn can be, in the order a folder is searched. */
static const struct {
    const wchar_t *name;
    stn_kind kind;
} other_names[OTHER_NAME_COUNT] = {
    {L"stn.exe", STN_PROGRAM}, {L"stn.cmd", STN_BATCH}, {L"stn.bat", STN_BATCH},
    {L"stn.com", STN_PROGRAM}, {L"stn.ps1", STN_PS1},
};

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

/* Returns whether the entry is absolute: a drive letter, `:`, then `\` or `/`,
 * or a leading `\\`. */
static BOOL is_absolute_entry(const wchar_t *entry)
{
    if (((entry[0] >= L'A' && entry[0] <= L'Z') || (entry[0] >= L'a' && entry[0] <= L'z'))
        && entry[1] == L':' && (entry[2] == L'\\' || entry[2] == L'/')) {
        return TRUE;
    }
    return entry[0] == L'\\' && entry[1] == L'\\';
}

/* Returns the cmd.exe that ComSpec names when it is an absolute path, else the
 * one under SystemRoot. */
static wchar_t *find_cmd(void)
{
    wchar_t buffer[PATH_CAPACITY];
    const wchar_t *parts[2];
    DWORD length = GetEnvironmentVariableW(L"ComSpec", buffer, PATH_CAPACITY);

    if (length > 0 && length < PATH_CAPACITY && is_absolute_entry(buffer)) {
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

/* Returns whether the path names a file, not a folder; a link counts by what it
 * is, and a path that cannot be read is none. */
static BOOL is_file(const wchar_t *path)
{
    DWORD attributes = GetFileAttributesW(path);

    return attributes != INVALID_FILE_ATTRIBUTES
           && (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

/* Writes folder, a separator when it has none, and name into out; returns
 * FALSE when they do not fit in cap characters. */
static BOOL join_entry(const wchar_t *folder, const wchar_t *name, wchar_t *out, DWORD cap)
{
    size_t folder_length = wcslen(folder);
    size_t name_length = wcslen(name);
    BOOL needs_separator = folder_length > 0 && folder[folder_length - 1] != L'\\'
                           && folder[folder_length - 1] != L'/';
    size_t at = folder_length;

    if (folder_length + 1 + name_length + 1 > (size_t)cap) {
        return FALSE;
    }
    wmemcpy(out, folder, folder_length);
    if (needs_separator) {
        out[at++] = L'\\';
    }
    wmemcpy(out + at, name, name_length + 1);
    return TRUE;
}

/* Writes the final path of folder, junctions and symlinks followed, without the
 * `\\?\` prefix; returns FALSE when the folder cannot be opened or read. */
static BOOL folder_final_path(const wchar_t *folder, wchar_t *out, DWORD cap)
{
    HANDLE handle = CreateFileW(folder, 0,
                                FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                                NULL, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, NULL);
    DWORD length;

    if (handle == INVALID_HANDLE_VALUE) {
        return FALSE;
    }
    length = GetFinalPathNameByHandleW(handle, out, cap,
                                       FILE_NAME_NORMALIZED | VOLUME_NAME_DOS);
    CloseHandle(handle);
    if (length == 0 || length >= cap) {
        return FALSE;
    }
    if (wcsncmp(out, L"\\\\?\\UNC\\", 8) == 0) {
        wmemmove(out + 2, out + 8, wcslen(out + 8) + 1);
    } else if (wcsncmp(out, L"\\\\?\\", 4) == 0) {
        wmemmove(out, out + 4, wcslen(out + 4) + 1);
    }
    return TRUE;
}

/* Returns whether the folder holds both stn.exe and specstone.exe, a Specstone
 * install folder, never another tool's stn. */
static BOOL holds_install_pair(const wchar_t *folder)
{
    wchar_t file[PATH_CAPACITY];

    return join_entry(folder, L"stn.exe", file, PATH_CAPACITY) && is_file(file)
           && join_entry(folder, TARGET_NAME, file, PATH_CAPACITY) && is_file(file);
}

/* Copies the PATH entry at text into out, quotes dropped and a `;` inside quotes
 * kept; returns where the next entry starts, or NULL after the last. */
static const wchar_t *read_entry(const wchar_t *text, wchar_t *out)
{
    BOOL quoted = FALSE;

    while (*text != L'\0' && (quoted || *text != L';')) {
        if (*text == L'"') {
            quoted = !quoted;
        } else {
            *out++ = *text;
        }
        text++;
    }
    *out = L'\0';
    return (*text == L';') ? text + 1 : NULL;
}

/* Returns the kind of the first stn in the entry, its path in found, or
 * STN_NONE for an entry that is relative, the own folder, an install folder,
 * unreadable, or holds none. */
static stn_kind stn_in_entry(const wchar_t *entry, const wchar_t *own_final,
                             wchar_t *found, DWORD cap)
{
    wchar_t entry_final[PATH_CAPACITY];
    int i;

    if (!is_absolute_entry(entry)) {
        return STN_NONE;
    }
    if (own_final[0] != L'\0' && folder_final_path(entry, entry_final, PATH_CAPACITY)
        && CompareStringOrdinal(entry_final, -1, own_final, -1, TRUE) == CSTR_EQUAL) {
        return STN_NONE;
    }
    if (holds_install_pair(entry)) {
        return STN_NONE;
    }
    for (i = 0; i < OTHER_NAME_COUNT; i++) {
        if (join_entry(entry, other_names[i].name, found, cap) && is_file(found)) {
            return other_names[i].kind;
        }
    }
    return STN_NONE;
}

/* Walks PATH for the first stn outside the own folder, whose final path is
 * own_final (empty when unknown); writes its path to found. */
static stn_kind find_other_stn(const wchar_t *own_final, wchar_t *found, DWORD cap)
{
    DWORD size = GetEnvironmentVariableW(L"PATH", NULL, 0);
    wchar_t *path;
    wchar_t *entry;
    const wchar_t *at;
    stn_kind kind = STN_NONE;

    if (size == 0) {
        return STN_NONE;
    }
    path = (wchar_t *)HeapAlloc(GetProcessHeap(), 0, (SIZE_T)size * sizeof(wchar_t));
    entry = (wchar_t *)HeapAlloc(GetProcessHeap(), 0, (SIZE_T)size * sizeof(wchar_t));
    if (path != NULL && entry != NULL) {
        DWORD length = GetEnvironmentVariableW(L"PATH", path, size);

        at = (length > 0 && length < size) ? path : NULL;
        while (at != NULL && kind == STN_NONE) {
            at = read_entry(at, entry);
            kind = stn_in_entry(entry, own_final, found, cap);
        }
    }
    release(path);
    release(entry);
    return kind;
}

/* Returns whether the loop guard holds a value. */
static BOOL guard_is_set(void)
{
    wchar_t probe[1];

    return GetEnvironmentVariableW(GUARD_NAME, probe, 1) > 0;
}

/* Prints "another stn at <path>; use specstone" on stderr. */
static void refuse(const wchar_t *path)
{
    const wchar_t *parts[3];
    wchar_t *line;

    parts[0] = L"another stn at ";
    parts[1] = path;
    parts[2] = L"; use specstone\r\n";
    line = join(parts, 3);
    if (line != NULL) {
        write_stderr(line);
        release(line);
    }
}

/* Runs program with the raw tail of this process's command line and returns its
 * exit status; prints the reason and returns 1 when it cannot start. */
static int run_program(const wchar_t *program, BOOL through_cmd)
{
    DWORD status = start_and_wait(program, after_program_name(GetCommandLineW()), through_cmd);

    if (start_failure != 0) {
        report_failure(L"cannot start", program, start_failure);
        return 1;
    }
    return (int)status;
}

/* Sets the loop guard in this process, so the program started next and its
 * children hold it, then runs it. */
static int hand_off(const wchar_t *program, BOOL through_cmd)
{
    if (!SetEnvironmentVariableW(GUARD_NAME, L"1")) {
        report_failure(L"cannot set", GUARD_NAME, GetLastError());
        return 1;
    }
    return run_program(program, through_cmd);
}

int wmain(void)
{
    wchar_t own[PATH_CAPACITY];
    wchar_t own_final[PATH_CAPACITY];
    wchar_t found[PATH_CAPACITY];
    wchar_t *slash;
    const wchar_t *parts[2];
    wchar_t *target;
    stn_kind kind = STN_NONE;
    DWORD length = GetModuleFileNameW(NULL, own, PATH_CAPACITY);
    int status;

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
    if (!guard_is_set()) {
        if (!folder_final_path(own, own_final, PATH_CAPACITY)) {
            own_final[0] = L'\0';
        }
        kind = find_other_stn(own_final, found, PATH_CAPACITY);
    }
    switch (kind) {
    case STN_PS1:
        refuse(found);
        return 1;
    case STN_PROGRAM:
    case STN_BATCH:
        return hand_off(found, kind == STN_BATCH);
    case STN_NONE:
        break;
    }

    parts[0] = own;
    parts[1] = TARGET_NAME;
    target = join(parts, 2);
    if (target == NULL) {
        report_failure(L"cannot start", TARGET_NAME, ERROR_OUTOFMEMORY);
        return 1;
    }
    status = run_program(target, FALSE);
    release(target);
    return status;
}
