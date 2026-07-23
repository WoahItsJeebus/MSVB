local M = {}

local ffi_ok, ffi = pcall(require, "ffi")
if not ffi_ok or type(ffi) ~= "table" then
    M.available = false
    M.error = "LuaJIT FFI is unavailable"
    return M
end

if ffi.os ~= "Windows" then
    M.available = false
    M.error = "Windows process APIs are unavailable on this platform"
    return M
end

local declarations_ok, declarations_error = pcall(ffi.cdef, [[
typedef void *VLB_HANDLE;
typedef void *VLB_HKEY;
typedef unsigned char VLB_BYTE;
typedef unsigned short VLB_WORD;
typedef unsigned short VLB_WCHAR;
typedef unsigned long VLB_DWORD;
typedef long VLB_LONG;
typedef int VLB_BOOL;
typedef unsigned long long VLB_ULONGLONG;

typedef struct VLB_SECURITY_ATTRIBUTES {
    VLB_DWORD nLength;
    void *lpSecurityDescriptor;
    VLB_BOOL bInheritHandle;
} VLB_SECURITY_ATTRIBUTES;

typedef struct VLB_STARTUPINFOW {
    VLB_DWORD cb;
    VLB_WCHAR *lpReserved;
    VLB_WCHAR *lpDesktop;
    VLB_WCHAR *lpTitle;
    VLB_DWORD dwX;
    VLB_DWORD dwY;
    VLB_DWORD dwXSize;
    VLB_DWORD dwYSize;
    VLB_DWORD dwXCountChars;
    VLB_DWORD dwYCountChars;
    VLB_DWORD dwFillAttribute;
    VLB_DWORD dwFlags;
    VLB_WORD wShowWindow;
    VLB_WORD cbReserved2;
    VLB_BYTE *lpReserved2;
    VLB_HANDLE hStdInput;
    VLB_HANDLE hStdOutput;
    VLB_HANDLE hStdError;
} VLB_STARTUPINFOW;

typedef struct VLB_PROCESS_INFORMATION {
    VLB_HANDLE hProcess;
    VLB_HANDLE hThread;
    VLB_DWORD dwProcessId;
    VLB_DWORD dwThreadId;
} VLB_PROCESS_INFORMATION;

typedef struct VLB_PROCESSENTRY32W {
    VLB_DWORD dwSize;
    VLB_DWORD cntUsage;
    VLB_DWORD th32ProcessID;
    uintptr_t th32DefaultHeapID;
    VLB_DWORD th32ModuleID;
    VLB_DWORD cntThreads;
    VLB_DWORD th32ParentProcessID;
    long pcPriClassBase;
    VLB_DWORD dwFlags;
    VLB_WCHAR szExeFile[260];
} VLB_PROCESSENTRY32W;

typedef struct VLB_FILETIME {
    VLB_DWORD dwLowDateTime;
    VLB_DWORD dwHighDateTime;
} VLB_FILETIME;

VLB_BOOL __stdcall CreatePipe(
    VLB_HANDLE *hReadPipe,
    VLB_HANDLE *hWritePipe,
    VLB_SECURITY_ATTRIBUTES *lpPipeAttributes,
    VLB_DWORD nSize
);
VLB_BOOL __stdcall SetHandleInformation(VLB_HANDLE hObject, VLB_DWORD dwMask, VLB_DWORD dwFlags);
VLB_BOOL __stdcall CreateProcessW(
    const VLB_WCHAR *lpApplicationName,
    VLB_WCHAR *lpCommandLine,
    VLB_SECURITY_ATTRIBUTES *lpProcessAttributes,
    VLB_SECURITY_ATTRIBUTES *lpThreadAttributes,
    VLB_BOOL bInheritHandles,
    VLB_DWORD dwCreationFlags,
    void *lpEnvironment,
    const VLB_WCHAR *lpCurrentDirectory,
    VLB_STARTUPINFOW *lpStartupInfo,
    VLB_PROCESS_INFORMATION *lpProcessInformation
);
VLB_DWORD __stdcall WaitForSingleObject(VLB_HANDLE hHandle, VLB_DWORD dwMilliseconds);
VLB_BOOL __stdcall PeekNamedPipe(
    VLB_HANDLE hNamedPipe,
    void *lpBuffer,
    VLB_DWORD nBufferSize,
    VLB_DWORD *lpBytesRead,
    VLB_DWORD *lpTotalBytesAvail,
    VLB_DWORD *lpBytesLeftThisMessage
);
VLB_BOOL __stdcall ReadFile(
    VLB_HANDLE hFile,
    void *lpBuffer,
    VLB_DWORD nNumberOfBytesToRead,
    VLB_DWORD *lpNumberOfBytesRead,
    void *lpOverlapped
);
VLB_BOOL __stdcall GetExitCodeProcess(VLB_HANDLE hProcess, VLB_DWORD *lpExitCode);
VLB_BOOL __stdcall TerminateProcess(VLB_HANDLE hProcess, unsigned int uExitCode);
VLB_BOOL __stdcall CloseHandle(VLB_HANDLE hObject);
VLB_DWORD __stdcall GetLastError(void);
VLB_ULONGLONG __stdcall GetTickCount64(void);
int __stdcall MultiByteToWideChar(
    unsigned int CodePage,
    VLB_DWORD dwFlags,
    const char *lpMultiByteStr,
    int cbMultiByte,
    VLB_WCHAR *lpWideCharStr,
    int cchWideChar
);
int __stdcall WideCharToMultiByte(
    unsigned int CodePage,
    VLB_DWORD dwFlags,
    const VLB_WCHAR *lpWideCharStr,
    int cchWideChar,
    char *lpMultiByteStr,
    int cbMultiByte,
    const char *lpDefaultChar,
    VLB_BOOL *lpUsedDefaultChar
);
VLB_DWORD __stdcall ExpandEnvironmentStringsW(
    const VLB_WCHAR *lpSrc,
    VLB_WCHAR *lpDst,
    VLB_DWORD nSize
);
VLB_HANDLE __stdcall CreateToolhelp32Snapshot(VLB_DWORD dwFlags, VLB_DWORD th32ProcessID);
VLB_BOOL __stdcall Process32FirstW(VLB_HANDLE hSnapshot, VLB_PROCESSENTRY32W *lppe);
VLB_BOOL __stdcall Process32NextW(VLB_HANDLE hSnapshot, VLB_PROCESSENTRY32W *lppe);

VLB_LONG __stdcall RegOpenKeyExW(
    VLB_HKEY hKey,
    const VLB_WCHAR *lpSubKey,
    VLB_DWORD ulOptions,
    VLB_DWORD samDesired,
    VLB_HKEY *phkResult
);
VLB_LONG __stdcall RegEnumKeyExW(
    VLB_HKEY hKey,
    VLB_DWORD dwIndex,
    VLB_WCHAR *lpName,
    VLB_DWORD *lpcchName,
    VLB_DWORD *lpReserved,
    VLB_WCHAR *lpClass,
    VLB_DWORD *lpcchClass,
    VLB_FILETIME *lpftLastWriteTime
);
VLB_LONG __stdcall RegQueryValueExW(
    VLB_HKEY hKey,
    const VLB_WCHAR *lpValueName,
    VLB_DWORD *lpReserved,
    VLB_DWORD *lpType,
    VLB_BYTE *lpData,
    VLB_DWORD *lpcbData
);
VLB_LONG __stdcall RegCloseKey(VLB_HKEY hKey);
]])

if not declarations_ok then
    M.available = false
    M.error = "Windows FFI declarations failed: " .. tostring(declarations_error)
    return M
end

local kernel32_ok, kernel32 = pcall(ffi.load, "kernel32")
local advapi32_ok, advapi32 = pcall(ffi.load, "advapi32")
if not kernel32_ok or not advapi32_ok then
    M.available = false
    M.error = "Windows system libraries could not be loaded"
    return M
end

M.available = true

local CP_UTF8 = 65001
local CREATE_NO_WINDOW = 0x08000000
local HANDLE_FLAG_INHERIT = 0x00000001
local STARTF_USESTDHANDLES = 0x00000100
local WAIT_OBJECT_0 = 0x00000000
local WAIT_TIMEOUT = 0x00000102
local WAIT_FAILED = 0xFFFFFFFF
local TH32CS_SNAPPROCESS = 0x00000002

local ERROR_SUCCESS = 0
local ERROR_NO_MORE_ITEMS = 259
local KEY_READ = 0x00020019
local KEY_WOW64_64KEY = 0x00000100
local KEY_WOW64_32KEY = 0x00000200
local REG_SZ = 1
local REG_EXPAND_SZ = 2

local HKEY_CURRENT_USER = ffi.cast("VLB_HKEY", ffi.cast("intptr_t", -2147483647))
local HKEY_LOCAL_MACHINE = ffi.cast("VLB_HKEY", ffi.cast("intptr_t", -2147483646))
local INVALID_HANDLE_VALUE = ffi.cast("VLB_HANDLE", ffi.cast("intptr_t", -1))

local function last_error()
    return tonumber(kernel32.GetLastError())
end

local function close_handle(handle)
    if handle ~= nil and handle ~= ffi.NULL and handle ~= INVALID_HANDLE_VALUE then
        kernel32.CloseHandle(handle)
    end
end

local function utf8_to_wide(value)
    if type(value) ~= "string" then
        return nil, "value is not a string"
    end

    local required = kernel32.MultiByteToWideChar(CP_UTF8, 0, value, #value, nil, 0)
    if required == 0 and #value > 0 then
        return nil, "UTF-8 conversion failed with Windows error " .. tostring(last_error())
    end

    local buffer = ffi.new("VLB_WCHAR[?]", required + 1)
    if required > 0 then
        local converted = kernel32.MultiByteToWideChar(CP_UTF8, 0, value, #value, buffer, required)
        if converted ~= required then
            return nil, "UTF-8 conversion failed with Windows error " .. tostring(last_error())
        end
    end
    buffer[required] = 0
    return buffer
end

local function wide_to_utf8(value, length)
    if value == nil or value == ffi.NULL or length <= 0 then
        return ""
    end

    local required = kernel32.WideCharToMultiByte(
        CP_UTF8,
        0,
        value,
        length,
        nil,
        0,
        nil,
        nil
    )
    if required <= 0 then
        return nil
    end

    local buffer = ffi.new("char[?]", required)
    local converted = kernel32.WideCharToMultiByte(
        CP_UTF8,
        0,
        value,
        length,
        buffer,
        required,
        nil,
        nil
    )
    if converted ~= required then
        return nil
    end
    return ffi.string(buffer, required)
end

local function expand_environment(value)
    local source = utf8_to_wide(value)
    if source == nil then
        return value
    end

    local required = kernel32.ExpandEnvironmentStringsW(source, nil, 0)
    if required == 0 or required > 32768 then
        return value
    end

    local buffer = ffi.new("VLB_WCHAR[?]", required)
    if kernel32.ExpandEnvironmentStringsW(source, buffer, required) == 0 then
        return value
    end

    return wide_to_utf8(buffer, required - 1) or value
end

local function quote_windows_argument(value)
    if value == "" then
        return '""'
    end

    if not value:find('[%s"]') then
        return value
    end

    local output = { '"' }
    local backslashes = 0
    for index = 1, #value do
        local character = value:sub(index, index)
        if character == "\\" then
            backslashes = backslashes + 1
        elseif character == '"' then
            output[#output + 1] = string.rep("\\", backslashes * 2 + 1)
            output[#output + 1] = '"'
            backslashes = 0
        else
            if backslashes > 0 then
                output[#output + 1] = string.rep("\\", backslashes)
                backslashes = 0
            end
            output[#output + 1] = character
        end
    end

    if backslashes > 0 then
        output[#output + 1] = string.rep("\\", backslashes * 2)
    end
    output[#output + 1] = '"'
    return table.concat(output)
end

local function create_pipe(parent_end)
    local security = ffi.new("VLB_SECURITY_ATTRIBUTES")
    security.nLength = ffi.sizeof(security)
    security.lpSecurityDescriptor = nil
    security.bInheritHandle = 1

    local read_handle = ffi.new("VLB_HANDLE[1]")
    local write_handle = ffi.new("VLB_HANDLE[1]")
    if kernel32.CreatePipe(read_handle, write_handle, security, 0) == 0 then
        return nil, nil, "CreatePipe failed with Windows error " .. tostring(last_error())
    end

    local parent_handle = parent_end == "write" and write_handle[0] or read_handle[0]
    if kernel32.SetHandleInformation(parent_handle, HANDLE_FLAG_INHERIT, 0) == 0 then
        close_handle(read_handle[0])
        close_handle(write_handle[0])
        return nil, nil, "SetHandleInformation failed with Windows error " .. tostring(last_error())
    end

    return read_handle[0], write_handle[0]
end

local function drain_pipe(handle, chunks, captured_bytes, total_bytes, maximum_bytes)
    local buffer = ffi.new("uint8_t[8192]")
    local available = ffi.new("VLB_DWORD[1]")
    local bytes_read = ffi.new("VLB_DWORD[1]")

    while true do
        available[0] = 0
        if kernel32.PeekNamedPipe(handle, nil, 0, nil, available, nil) == 0 then
            break
        end

        local count = tonumber(available[0])
        if count <= 0 then
            break
        end

        count = math.min(count, 8192)
        bytes_read[0] = 0
        if kernel32.ReadFile(handle, buffer, count, bytes_read, nil) == 0 then
            break
        end

        local read_count = tonumber(bytes_read[0])
        if read_count <= 0 then
            break
        end

        local data = ffi.string(buffer, read_count)
        total_bytes = total_bytes + read_count
        local remaining = maximum_bytes - captured_bytes
        if remaining > 0 then
            local kept = math.min(remaining, read_count)
            chunks[#chunks + 1] = data:sub(1, kept)
            captured_bytes = captured_bytes + kept
        end
    end

    return captured_bytes, total_bytes
end

function M.run_process(executable, arguments, options)
    options = options or {}
    arguments = arguments or {}

    if type(executable) ~= "string" or executable == "" then
        return {
            started = false,
            error = "Executable path is empty",
        }
    end

    local timeout_ms = tonumber(options.timeout_ms) or 10000
    timeout_ms = math.max(100, math.min(timeout_ms, 120000))
    local maximum_bytes = tonumber(options.maximum_output_bytes) or (1024 * 1024)
    maximum_bytes = math.max(4096, math.min(maximum_bytes, 4 * 1024 * 1024))

    local command_parts = { quote_windows_argument(executable) }
    for _, argument in ipairs(arguments) do
        if type(argument) ~= "string" then
            return {
                started = false,
                error = "Process arguments must be strings",
            }
        end
        command_parts[#command_parts + 1] = quote_windows_argument(argument)
    end

    local executable_wide, executable_error = utf8_to_wide(executable)
    if executable_wide == nil then
        return {
            started = false,
            error = executable_error,
        }
    end

    local command_wide, command_error = utf8_to_wide(table.concat(command_parts, " "))
    if command_wide == nil then
        return {
            started = false,
            error = command_error,
        }
    end

    local stdout_read, stdout_write, stdout_error = create_pipe("read")
    if stdout_read == nil then
        return {
            started = false,
            error = stdout_error,
        }
    end

    local stderr_read, stderr_write, stderr_error = create_pipe("read")
    if stderr_read == nil then
        close_handle(stdout_read)
        close_handle(stdout_write)
        return {
            started = false,
            error = stderr_error,
        }
    end

    local stdin_read, stdin_write, stdin_error = create_pipe("write")
    if stdin_read == nil then
        close_handle(stdout_read)
        close_handle(stdout_write)
        close_handle(stderr_read)
        close_handle(stderr_write)
        return {
            started = false,
            error = stdin_error,
        }
    end

    local startup = ffi.new("VLB_STARTUPINFOW")
    startup.cb = ffi.sizeof(startup)
    startup.dwFlags = STARTF_USESTDHANDLES
    startup.hStdInput = stdin_read
    startup.hStdOutput = stdout_write
    startup.hStdError = stderr_write

    local process_info = ffi.new("VLB_PROCESS_INFORMATION")
    local started_at = tonumber(kernel32.GetTickCount64())
    local created = kernel32.CreateProcessW(
        executable_wide,
        command_wide,
        nil,
        nil,
        1,
        CREATE_NO_WINDOW,
        nil,
        nil,
        startup,
        process_info
    )

    close_handle(stdout_write)
    close_handle(stderr_write)
    close_handle(stdin_read)
    close_handle(stdin_write)

    if created == 0 then
        local error_code = last_error()
        close_handle(stdout_read)
        close_handle(stderr_read)
        return {
            started = false,
            errorCode = error_code,
            error = "CreateProcessW failed with Windows error " .. tostring(error_code),
        }
    end

    close_handle(process_info.hThread)

    local stdout_chunks = {}
    local stderr_chunks = {}
    local stdout_captured = 0
    local stderr_captured = 0
    local stdout_total = 0
    local stderr_total = 0
    local timed_out = false
    local termination_failed = false
    local wait_error
    local wait_result = WAIT_TIMEOUT

    while wait_result == WAIT_TIMEOUT do
        stdout_captured, stdout_total = drain_pipe(
            stdout_read,
            stdout_chunks,
            stdout_captured,
            stdout_total,
            maximum_bytes
        )
        stderr_captured, stderr_total = drain_pipe(
            stderr_read,
            stderr_chunks,
            stderr_captured,
            stderr_total,
            maximum_bytes
        )

        local elapsed = tonumber(kernel32.GetTickCount64()) - started_at
        if elapsed >= timeout_ms then
            timed_out = true
            termination_failed = kernel32.TerminateProcess(process_info.hProcess, 124) == 0
            kernel32.WaitForSingleObject(process_info.hProcess, 1000)
            break
        end

        wait_result = tonumber(kernel32.WaitForSingleObject(process_info.hProcess, 20))
        if wait_result == WAIT_FAILED then
            wait_error = last_error()
        end
    end

    stdout_captured, stdout_total = drain_pipe(
        stdout_read,
        stdout_chunks,
        stdout_captured,
        stdout_total,
        maximum_bytes
    )
    stderr_captured, stderr_total = drain_pipe(
        stderr_read,
        stderr_chunks,
        stderr_captured,
        stderr_total,
        maximum_bytes
    )

    local exit_code_value = ffi.new("VLB_DWORD[1]")
    local exit_code
    if kernel32.GetExitCodeProcess(process_info.hProcess, exit_code_value) ~= 0 then
        exit_code = tonumber(exit_code_value[0])
    end

    local duration_ms = tonumber(kernel32.GetTickCount64()) - started_at
    close_handle(process_info.hProcess)
    close_handle(stdout_read)
    close_handle(stderr_read)

    local process_error
    if termination_failed then
        process_error = "The process timed out but Windows could not terminate it"
    elseif wait_result == WAIT_FAILED then
        process_error = "Waiting for the process failed with Windows error " .. tostring(wait_error)
    end

    return {
        started = true,
        timedOut = timed_out,
        error = process_error,
        exitCode = exit_code,
        durationMs = duration_ms,
        stdout = table.concat(stdout_chunks),
        stderr = table.concat(stderr_chunks),
        stdoutBytes = stdout_total,
        stderrBytes = stderr_total,
        stdoutTruncated = stdout_total > stdout_captured,
        stderrTruncated = stderr_total > stderr_captured,
    }
end

function M.is_process_running(executable_name)
    if type(executable_name) ~= "string" or executable_name == "" then
        return false
    end

    local snapshot = kernel32.CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0)
    if snapshot == nil or snapshot == ffi.NULL or snapshot == INVALID_HANDLE_VALUE then
        return false
    end

    local entry = ffi.new("VLB_PROCESSENTRY32W")
    entry.dwSize = ffi.sizeof(entry)
    local found = false
    local has_entry = kernel32.Process32FirstW(snapshot, entry) ~= 0
    local expected = executable_name:lower()

    while has_entry do
        local length = 0
        while length < 260 and entry.szExeFile[length] ~= 0 do
            length = length + 1
        end
        local name = wide_to_utf8(entry.szExeFile, length)
        if type(name) == "string" and name:lower() == expected then
            found = true
            break
        end
        has_entry = kernel32.Process32NextW(snapshot, entry) ~= 0
    end

    close_handle(snapshot)
    return found
end

local function query_registry_string(key, value_name)
    local value_name_wide = utf8_to_wide(value_name)
    if value_name_wide == nil then
        return nil
    end

    local value_type = ffi.new("VLB_DWORD[1]")
    local size = ffi.new("VLB_DWORD[1]")
    local status = advapi32.RegQueryValueExW(
        key,
        value_name_wide,
        nil,
        value_type,
        nil,
        size
    )
    if status ~= ERROR_SUCCESS then
        return nil
    end

    local byte_count = tonumber(size[0])
    local registry_type = tonumber(value_type[0])
    if byte_count <= 2 or byte_count > 65536 or
        (registry_type ~= REG_SZ and registry_type ~= REG_EXPAND_SZ) then
        return nil
    end

    local buffer = ffi.new("VLB_BYTE[?]", byte_count)
    status = advapi32.RegQueryValueExW(
        key,
        value_name_wide,
        nil,
        value_type,
        buffer,
        size
    )
    if status ~= ERROR_SUCCESS then
        return nil
    end

    local character_count = math.floor(tonumber(size[0]) / 2)
    local wide_buffer = ffi.cast("VLB_WCHAR *", buffer)
    while character_count > 0 and wide_buffer[character_count - 1] == 0 do
        character_count = character_count - 1
    end

    local value = wide_to_utf8(wide_buffer, character_count)
    if type(value) ~= "string" then
        return nil
    end
    if registry_type == REG_EXPAND_SZ then
        value = expand_environment(value)
    end
    return value
end

local function read_registry_string(root, subkey_path, value_name, access)
    local subkey_path_wide = utf8_to_wide(subkey_path)
    if subkey_path_wide == nil then
        return nil
    end

    local key = ffi.new("VLB_HKEY[1]")
    local status = advapi32.RegOpenKeyExW(
        root,
        subkey_path_wide,
        0,
        access,
        key
    )
    if status ~= ERROR_SUCCESS then
        return nil
    end

    local value = query_registry_string(key[0], value_name)
    advapi32.RegCloseKey(key[0])
    return value
end

function M.get_steam_install_path()
    local candidates = {
        {
            root = HKEY_CURRENT_USER,
            path = "SOFTWARE\\Valve\\Steam",
            value = "SteamPath",
            access = KEY_READ + KEY_WOW64_64KEY,
        },
        {
            root = HKEY_LOCAL_MACHINE,
            path = "SOFTWARE\\Valve\\Steam",
            value = "InstallPath",
            access = KEY_READ + KEY_WOW64_32KEY,
        },
        {
            root = HKEY_LOCAL_MACHINE,
            path = "SOFTWARE\\Valve\\Steam",
            value = "InstallPath",
            access = KEY_READ + KEY_WOW64_64KEY,
        },
    }

    for _, candidate in ipairs(candidates) do
        local value = read_registry_string(
            candidate.root,
            candidate.path,
            candidate.value,
            candidate.access
        )
        if type(value) == "string" and value ~= "" then
            return value
        end
    end
    return nil
end

local function enumerate_uninstall_root(root, access)
    local uninstall_path = utf8_to_wide("SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall")
    if uninstall_path == nil then
        return {}
    end

    local uninstall_key = ffi.new("VLB_HKEY[1]")
    local status = advapi32.RegOpenKeyExW(root, uninstall_path, 0, access, uninstall_key)
    if status ~= ERROR_SUCCESS then
        return {}
    end

    local results = {}
    local index = 0
    while index < 8192 do
        local name_buffer = ffi.new("VLB_WCHAR[512]")
        local name_length = ffi.new("VLB_DWORD[1]", 511)
        status = advapi32.RegEnumKeyExW(
            uninstall_key[0],
            index,
            name_buffer,
            name_length,
            nil,
            nil,
            nil,
            nil
        )
        if status == ERROR_NO_MORE_ITEMS then
            break
        end

        if status == ERROR_SUCCESS then
            local subkey_name = wide_to_utf8(name_buffer, tonumber(name_length[0]))
            if type(subkey_name) == "string" then
                local subkey_name_wide = utf8_to_wide(subkey_name)
                local subkey = ffi.new("VLB_HKEY[1]")
                if subkey_name_wide ~= nil and
                    advapi32.RegOpenKeyExW(
                        uninstall_key[0],
                        subkey_name_wide,
                        0,
                        access,
                        subkey
                    ) == ERROR_SUCCESS then
                    local display_name = query_registry_string(subkey[0], "DisplayName")
                    if type(display_name) == "string" and
                        display_name:lower():find("vortex", 1, true) ~= nil then
                        results[#results + 1] = {
                            displayName = display_name,
                            displayVersion = query_registry_string(subkey[0], "DisplayVersion"),
                            installLocation = query_registry_string(subkey[0], "InstallLocation"),
                            displayIcon = query_registry_string(subkey[0], "DisplayIcon"),
                            uninstallString = query_registry_string(subkey[0], "UninstallString"),
                        }
                    end
                    advapi32.RegCloseKey(subkey[0])
                end
            end
        end

        index = index + 1
    end

    advapi32.RegCloseKey(uninstall_key[0])
    return results
end

function M.get_vortex_uninstall_entries()
    local results = {}
    local seen = {}
    local roots = {
        { root = HKEY_CURRENT_USER, access = KEY_READ + KEY_WOW64_64KEY },
        { root = HKEY_CURRENT_USER, access = KEY_READ + KEY_WOW64_32KEY },
        { root = HKEY_LOCAL_MACHINE, access = KEY_READ + KEY_WOW64_64KEY },
        { root = HKEY_LOCAL_MACHINE, access = KEY_READ + KEY_WOW64_32KEY },
    }

    for _, descriptor in ipairs(roots) do
        for _, entry in ipairs(enumerate_uninstall_root(descriptor.root, descriptor.access)) do
            local identity = table.concat({
                entry.displayName or "",
                entry.displayVersion or "",
                entry.installLocation or "",
                entry.displayIcon or "",
            }, "\0"):lower()
            if not seen[identity] then
                seen[identity] = true
                results[#results + 1] = entry
            end
        end
    end

    return results
end

return M
