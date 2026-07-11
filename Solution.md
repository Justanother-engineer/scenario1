# Scenario 01 — RMM: MITRE ATT&CK Coverage (Flow Order)

This document lists every MITRE ATT&CK technique exercised by the scenario, in the order they fire during a run. Each entry includes: the technique ID, name, what it does in this scenario, and the code reference (`file:line`) where it is implemented.

The chain is built so the SOC team can identify each phase by its Sysmon/Winlogbeat signal. See `idea.md` §"SOC Detection Signals" for the EID-by-EID mapping.

---

## Tactic: Initial Access

### T1219 — Remote Access Software
- **What:** Operator opens a RustDesk remote shell on the target.
- **Where:** Out-of-band; outside the scenario's code.
- **Detection:** Sysmon EID 1 — `rustdesk.exe` process creation; RustDesk-specific binary path.

---

## Tactic: Execution

### T1059.001 — Command and Scripting Interpreter: PowerShell (download cradle)
- **What:** Operator pastes the one-liner that fetches `loader.ps1` from GitHub and pipes it to `iex`.
- **Where:** Operator shell, then `loader.ps1:1-21` (the elevation gate).
- **Detection:** Sysmon EID 1 — `powershell.exe` with `Net.WebClient.DownloadString`; command-line contains `IEX`.

### T1105 — Ingress Tool Transfer
- **What:** `loader.ps1` downloads `stage.dll` from `github.com/Justanother-engineer/scenario1` to `C:\ProgramData\Microsoft\Crypto\RSA\S-1-5-18\stage.dll`.
- **Where:** `loader.ps1:55-68` (`Invoke-WebRequest`).
- **Detection:** Sysmon EID 3 (network) + EID 11 (file create) — outbound TLS to GitHub, file create in `Crypto\RSA\S-1-5-18`.

### T1059.001 (cont.) — PowerShell: masqueraded payload
- **What:** `loader.ps1` copies `powershell.exe` to `C:\ProgramData\Microsoft\Windows\Caches\svchost.exe`. The scheduled task will later run this binary as `svchost.exe` to execute the registry-staged C# payload.
- **Where:** `loader.ps1:70-82` (masquerade copy).
- **Detection:** Sysmon EID 11 — `svchost.exe` created under `Caches\`, not `System32\`.

### T1027 — Obfuscated Files or Information
- **What:** `spoof.cs` is base64-embedded inside `loader.ps1`; `stage.c`'s shellcode is XOR-encoded (`XOR_KEY = 0xAA`) with an in-place decoder stub.
- **Where:** `loader.ps1:86-88` (base64 decode); `stage.c:157-225` (`BuildAPCShellcode`).
- **Detection:** Static — strings of the C# source are not visible without base64 decode; shellcode bytes are not the plaintext `LoadLibraryA` shim.

### T1112 — Modify Registry
- **What:** `loader.ps1` writes the C# source (wrapped in PS to call `Add-Type` then `[Spoof]::Go()`) to `HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\App`.
- **Where:** `loader.ps1:85-118` (`Set-ItemProperty`).
- **Detection:** Sysmon EID 13 — `App` value modified under `HKLM\...\Explorer`.

### T1059.001 (cont.) — PowerShell: SYSTEM context via Scheduled Task
- **What:** `Register-ScheduledTask` creates `SecHealthSvc` running the masqueraded PS as `SYSTEM` with `-EncodedCommand` to `iex(gp ...).App`. Task is then immediately triggered.
- **Where:** `loader.ps1:120-144` (`Register-ScheduledTask`, `Start-ScheduledTask`).
- **Detection:** Winlogbeat 4698 (scheduled task created) + Sysmon EID 1 (masqueraded `svchost.exe` at `Caches\svchost.exe`).

### T1059.001 (cont.) — PowerShell: C# compile + execute
- **What:** In the SYSTEM context, the registry payload runs `Add-Type` on the embedded C# source then calls `[Spoof]::Go()`.
- **Where:** The C# wrapper PS code in `loader.ps1:91-107` (embedded in registry); C# source itself in `spoof.cs`.
- **Detection:** Sysmon EID 7 — `CSharp` code loaded into a PowerShell process.

### T1218.010 — Signed Binary Proxy Execution: Regsvr32
- **What:** The C# `Spoof::Go()` creates `regsvr32.exe` in `CREATE_SUSPENDED` state.
- **Where:** `spoof.cs` — `CreateProcessW` with `regsvr32.exe` + spoofed cmdline.
- **Detection:** Sysmon EID 1 — `regsvr32.exe` spawned by `svchost.exe` (the masquerade); unusual parent chain.

---

## Tactic: Defense Evasion

### T1055.012 — Process Injection: Process Hollowing (used for Process Argument Spoofing)
- **What:** Before resuming `regsvr32.exe`, the C# code walks the suspended process's PEB → `ProcessParameters` → `RTL_USER_PROCESS_PARAMETERS.CommandLine` and overwrites the `Buffer` to point at `C:\ProgramData\Microsoft\Crypto\RSA\S-1-5-18\stage.dll`. The kernel-side `EdrReadCmdline` (used by Sysmon EID 1) captured the spoofed buffer at `CreateProcessW` time; the process itself reads the PEB *after* the overwrite and acts on the real path.
- **Where:** `spoof.cs:174-204` (PEB walk + `WriteProcessMemory`).
- **Detection:** Sysmon EID 10 — `OpenProcess(PROCESS_VM_WRITE)` on `regsvr32.exe`; cross-process handle from a SYSTEM-context `svchost.exe` masquerade. The `regsvr32.exe` cmdline visible in EID 1 will show `mshtml.dll` (the spoof), not `stage.dll`.

### T1036.003 — Masquerading: Rename
- **What:** `powershell.exe` is copied to `C:\ProgramData\Microsoft\Windows\Caches\svchost.exe` and executed under that name (see T1059.001 masquerade step).
- **Where:** `loader.ps1:70-82`.
- **Detection:** Image path mismatch in EID 1 — `svchost.exe` not in `C:\Windows\System32\`.

### T1055.004 — Process Injection: Asynchronous Procedure Call
- **What:** `stage.dll`'s `DllRegisterServer` finds every `svchost.exe` in `System32\`, allocates RWX memory in each, writes XOR-obfuscated shellcode (`LoadLibraryA("…stage.dll")`), and queues a `QueueUserAPC` on every thread of every target. Multi-PID fan-out ensures at least one target's threads enter alertable state quickly.
- **Where:** `stage.c:131-164` (`FindAllProcessPIDs`), `stage.c:178-237` (`DllRegisterServer` loop), `stage.c:244-281` (`InjectAPCToProcess`).
- **Detection:** Sysmon EID 10 — `OpenThread(THREAD_SET_CONTEXT)` + `VirtualAllocEx(PAGE_EXECUTE_READWRITE)` on every `svchost.exe` in a tight loop. EID 7 — `stage.dll` image load inside a real `svchost.exe`.

### T1078 — Valid Accounts (SYSTEM)
- **What:** Once the masqueraded PowerShell runs as SYSTEM (via the scheduled task), the injected shellcode executes `LoadLibraryA` on `stage.dll` in the same SYSTEM context. The loaded `DllMain` then runs the `WorkerThread` in that SYSTEM svchost.
- **Where:** Implicit — chain is SYSTEM throughout after the scheduled-task handoff.
- **Detection:** Winlogbeat 4672/4624 — special privileges assigned at logon (SYSTEM).

---

## Tactic: Persistence

### T1547.001 — Boot or Logon Autostart Execution: Registry Run Keys
- **What:** `InstallPersistence` writes `rundll32.exe C:\ProgramData\Microsoft\Crypto\RSA\S-1-5-18\stage.dll,DllRegisterServer` to `HKLM\Software\Microsoft\Windows\CurrentVersion\Run\WindowsSecHealth`.
- **Where:** `stage.c:762-781` (`InstallPersistence`).
- **Detection:** Sysmon EID 13 — `Run\WindowsSecHealth` value created.

### T1053.005 — Scheduled Task/Job: Scheduled Task (logon trigger)
- **What:** `InstallPersistence` spawns `schtasks /create /tn "SecHealthSvc2" /ru SYSTEM /tr "rundll32 ... stage.dll" /sc onlogon /f`.
- **Where:** `stage.c:783-797`.
- **Detection:** Winlogbeat 4698 — `SecHealthSvc2` task created with `Microsoft\Windows\…` or root path; on subsequent user logon, 106 (task created) + 140 (task updated) + 200 (task launched) events.

---

## Tactic: Credential Access

### T1003.001 — OS Credential Dumping: LSASS Memory
- **What:** `DumpLSASS` finds `lsass.exe` via `CreateToolhelp32Snapshot`, enables `SeDebugPrivilege`, opens the process, calls `PssCaptureSnapshot` to capture its memory, and writes the dump to `C:\ProgramData\Microsoft\Crypto\RSA\MachineKeys\~adf.bin`.
- **Where:** `stage.c:288-321` (`DumpLSASS`).
- **Detection:** Sysmon EID 10 — `OpenProcess(PROCESS_VM_READ)` on `lsass.exe` from `svchost.exe`; EID 11 — `~adf.bin` created.

### T1003.002 — OS Credential Dumping: Security Account Manager
- **What:** `DumpSAM` spawns `reg save HKLM\SAM C:\Windows\Temp\~s1.tmp` and `reg save HKLM\SYSTEM C:\Windows\Temp\~s2.tmp`, waits for each to exit.
- **Where:** `stage.c:335-369` (`DumpSAM` via `RunAndCapture`).
- **Detection:** Sysmon EID 1 — `reg.exe save` spawned by `svchost.exe`; EID 11 — `~s1.tmp`/`~s2.tmp` in `C:\Windows\Temp\`.

### T1217 — Browser Information Discovery
- **What:** `StealBrowserCreds` enumerates Edge + Chrome `Login Data` SQLite via `SHGetFolderPathW` + `FindFirstFileW`, copies each to `C:\ProgramData\Microsoft\Crypto\RSA\MachineKeys\~br<random>.tmp`, then opens the copy with the `sqlite3.dll` API to extract credentials (not actually decrypted in this scenario, but the SQLite query runs).
- **Where:** `stage.c:375-418` (`StealBrowserCreds`).
- **Detection:** Sysmon EID 11 — `~br*.tmp` file copies in `MachineKeys\`.

### T1555.003 — Credentials from Password Stores: Credentials from Web Browsers
- **What:** Same code path as T1217; the copy + read pattern is what makes the technique dual-homed (info discovery + credential theft).
- **Where:** `stage.c:375-418` (same).
- **Detection:** As above + Sysmon EID 10 (sqlite open from `svchost.exe`).

### T1115 — Clipboard Data
- **What:** `MonitorClipboard` polls every 5s for 30s via `OpenClipboard` + `GetClipboardData(CF_TEXT)`, writes content to `C:\ProgramData\Microsoft\Network\~clip.tmp` when it changes. The file is touched on entry to guarantee the artifact exists even when the clipboard is empty.
- **Where:** `stage.c:422-455` (`MonitorClipboard`).
- **Detection:** Sysmon EID 10 — repeated `OpenClipboard` from `svchost.exe` (6x, 5s intervals); EID 11 — `~clip.tmp` created.

---

## Tactic: Discovery

### T1082 — System Information Discovery
- **What:** `DoRecon` runs `systeminfo` and `whoami /all` via `RunAndCapture` (pipe + `CreateProcessW`); also calls `GetUserNameExW(NameSamCompatible)` for the SAM-compatible username.
- **Where:** `stage.c:495-585` (`DoRecon`).
- **Detection:** Sysmon EID 1 — `systeminfo.exe` and `whoami.exe` spawned by `svchost.exe`.

### T1083 — File and Directory Discovery
- **What:** `StealBrowserCreds` calls `FindFirstFileW` / `FindNextFileW` against `…\User Data\Default\Login Data` paths to enumerate browser profiles.
- **Where:** `stage.c:375-418`.
- **Detection:** Sysmon EID 11 — the resulting `~br*.tmp` file creates imply the enumeration succeeded; the directory traversal itself is harder to detect without file auditing.

### T1057 — Process Discovery
- **What:** `DoRecon` runs `tasklist /v` and pipes output to `~df.tmp`.
- **Where:** `stage.c:495-585`.
- **Detection:** Sysmon EID 1 — `tasklist.exe` spawned by `svchost.exe`.

### T1016 — System Network Configuration Discovery
- **What:** `DoRecon` calls `GetAdaptersInfo` to dump IP / mask / gateway for each adapter.
- **Where:** `stage.c:528-547`.
- **Detection:** No direct Sysmon signal; the resulting text lands in `~df.tmp` so a post-hoc EID 11 on that file is the trail.

### T1046 — Network Service Discovery
- **What:** `DoSMBRecon` calls `NetServerEnum(SV_TYPE_ALL)` to enumerate all domain/workgroup servers, then socket-connects to TCP/445 with a 3s timeout to confirm reachability, and `NetShareEnum` per host to list shares.
- **Where:** `stage.c:591-682` (`DoSMBRecon`).
- **Detection:** Sysmon EID 3 — `svchost.exe` connecting to port 445 on multiple remote IPs; EID 5140/5145 — SMB share enumeration events on the network.

### T1018 — Remote System Discovery
- **What:** Same code path as T1046; `NetServerEnum` itself is the remote-system discovery primitive.
- **Where:** `stage.c:591-682`.
- **Detection:** As above.

### T1135 — Network Share Discovery
- **What:** `NetShareEnum` per discovered host writes share names to `C:\ProgramData\Microsoft\Network\~net.tmp`.
- **Where:** `stage.c:591-682`.
- **Detection:** EID 5140/5145 on the target; the file create EID 11 in `~net.tmp`.

### T1087 — Account Discovery
- **What:** `whoami /all` and `GetUserNameExW` enumerate the current user and group memberships.
- **Where:** `stage.c:495-585`.
- **Detection:** Subsumed by the EID 1 on `whoami.exe`.

### T1124 — System Time Discovery
- **What:** Implicit — `GetTickCount` is called during `RunAndCapture` waits; not a primary technique in this scenario but logs timestamp-prefixed entries.
- **Where:** Various `LogMessage` calls.
- **Detection:** None direct.

---

## Tactic: Collection

### T1074.001 — Data Staged: Local Data Staging
- **What:** All exfiltratable artifacts are written to a per-technique subdirectory before any "send" step:
  - `C:\ProgramData\Microsoft\Crypto\RSA\MachineKeys\~adf.bin` (LSASS)
  - `C:\Windows\Temp\~s1.tmp`, `~s2.tmp` (SAM, SYSTEM)
  - `C:\ProgramData\Microsoft\Network\~df.tmp` (recon text)
  - `C:\ProgramData\Microsoft\Network\~net.tmp` (SMB text)
  - `C:\ProgramData\Microsoft\Network\~clip.tmp` (clipboard)
  - `C:\ProgramData\Microsoft\Crypto\RSA\MachineKeys\~br<r>.tmp` (browser creds)
- **Where:** All `stage.c` writers (`DumpLSASS`, `DumpSAM`, `StealBrowserCreds`, `DoRecon`, `DoSMBRecon`, `MonitorClipboard`).
- **Detection:** EID 11 — burst of file creates in `MachineKeys\`, `Temp\`, and `Network\` within seconds of each other.

---

## Tactic: Command and Control

### T1071.001 — Application Layer Protocol: Web Protocols
- **What:** `Beacon` calls `WinHttpOpen` + `WinHttpConnect(github.com, INTERNET_DEFAULT_HTTPS_PORT)` then issues 5 GETs with 10s `Sleep` between them, simulating beaconing to a benign destination.
- **Where:** `stage.c:799-839` (`Beacon`).
- **Detection:** Sysmon EID 3 — `svchost.exe` → `github.com:443` (5x, 10s apart). The User-Agent is `Mozilla/5.0` — a strong tell for a binary masquerading as a browser.

---

## Tactic: Impact / Defense Evasion (Cleanup)

### T1070.004 — Indicator Removal: File Deletion
- **What:** After the operator runs `cleanup.ps1`, all 10 scattered artifact files are removed; `loader.log` is removed.
- **Where:** `cleanup.ps1:31-49`.
- **Detection:** EID 23 (`FileDelete`) on each of the paths; useful as a "you missed cleanup" forensic signal.

### T1070.002 — Indicator Removal: Clear Linux or Mac Logs (mapped: Clear Windows Event Logs via the chain)
- **What:** Not exercised — the scenario leaves Winlogbeat forwarding intact so the SOC can review.

### T1531 — Account Access Removal
- **What:** `cleanup.ps1` calls `net user SupportUser /delete` to remove the persistence-supporting admin account.
- **Where:** `cleanup.ps1:70-72`.
- **Detection:** Winlogbeat 4726 — user account deleted; 4732 (counterpart to the create event during the run).

### T1562.001 — Impair Defenses: Disable or Modify Tools (Firewall re-enable)
- **What:** `cleanup.ps1` re-enables all firewall profiles via `netsh advfirewall set allprofiles state on`. The scenario's attack phase disables via COM first, falling back to `netsh` if the COM call fails (`stage.c:702-732`).
- **Where:** `cleanup.ps1:74-76`; `stage.c:685-732` (`DisableFirewall`).
- **Detection:** Winlogbeat 4946/4947 (firewall rule change); Sysmon EID 12/13 (registry changes under `MpsSvc`).

---

## Tactic: Defense Evasion (Anti-forensics)

### T1116 — Code Signing (proxy via Microsoft binaries)
- **What:** Every process spawned during the chain is Microsoft-signed: `regsvr32.exe`, `reg.exe`, `cmd.exe`, `net.exe`, `netsh.exe`. The actual payload (`stage.dll`) is unsigned, but it runs *inside* a Microsoft-signed process (`svchost.exe`).
- **Where:** Implicit across `stage.c` `CreateProcessW` calls.
- **Detection:** Authenticode audit — `stage.dll` in `C:\ProgramData\…\stage.dll` has no signature; the parent chain is signed.

### T1564.003 — Hide Artifacts: Hidden Window
- **What:** All child processes (reg.exe, cmd.exe, net.exe) are created with `CREATE_NO_WINDOW`; pipe handles are not inherited to the console.
- **Where:** `stage.c:471`, `stage.c:725`, the new fallback paths in `CreateAdminAccount`.
- **Detection:** Sysmon EID 1 — child processes of `svchost.exe` with no `CreateSuspended`/`CreateNoWindow` flag mismatch if audited; the absence of a visible window is a behavioral tell.

---

## Summary — coverage at a glance

| Tactic | Techniques |
|---|---|
| Initial Access | T1219 |
| Execution | T1059.001, T1105, T1027, T1112, T1218.010 |
| Persistence | T1547.001, T1053.005 |
| Privilege Escalation | T1055.012 (spoof), T1055.004 (APC), T1078 (SYSTEM) |
| Defense Evasion | T1036.003, T1070.004, T1070.002 (covered by cleanup), T1116, T1564.003 |
| Credential Access | T1003.001, T1003.002, T1217, T1555.003, T1115 |
| Discovery | T1082, T1083, T1057, T1016, T1046, T1018, T1135, T1087, T1124 |
| Collection | T1074.001 |
| Command and Control | T1071.001 |
| Impact / Cleanup | T1531, T1562.001 |

**22 distinct techniques across 10 tactics.** Every technique maps to at least one Sysmon EID or Winlogbeat channel — see `idea.md` §"SOC Detection Signals" for the per-EID table.
