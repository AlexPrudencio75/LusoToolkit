// A job contains only the portable process and its normal descendants.
// The host owns the non-inherited job handle. If the host dies, Windows kills the job.
using System;
using System.Collections;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

namespace LusoToolkit {
    public sealed class PortableProcess : IDisposable {
        [StructLayout(LayoutKind.Sequential)] struct BasicLimits {
            public long UserTime, JobTime;
            public uint Flags;
            public UIntPtr MinWorkingSet, MaxWorkingSet;
            public uint ActiveProcessLimit;
            public UIntPtr Affinity;
            public uint Priority, Scheduling;
        }
        [StructLayout(LayoutKind.Sequential)] struct IoCounters { public ulong A, B, C, D, E, F; }
        [StructLayout(LayoutKind.Sequential)] struct ExtendedLimits {
            public BasicLimits Basic;
            public IoCounters Io;
            public UIntPtr ProcessMemory, JobMemory, PeakProcessMemory, PeakJobMemory;
        }
        [StructLayout(LayoutKind.Sequential)] struct Accounting {
            public long A, B, C, D;
            public uint Faults, Total, Active, Terminated;
        }
        [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct Startup {
            public uint cb;
            public string reserved, desktop, title;
            public uint x, y, xSize, ySize, xChars, yChars, fill, flags;
            public ushort show, reservedBytes;
            public IntPtr reservedPtr, input, output, error;
        }
        [StructLayout(LayoutKind.Sequential)] struct ProcessInfo { public IntPtr process, thread; public uint pid, tid; }
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr CreateJobObject(IntPtr attributes, string name);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool SetInformationJobObject(IntPtr job, int kind, ref ExtendedLimits info, uint length);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool QueryInformationJobObject(IntPtr job, int kind, out Accounting info, uint length, IntPtr returned);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool TerminateJobObject(IntPtr job, uint code);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool TerminateProcess(IntPtr process, uint code);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool CreateProcessW(string application, StringBuilder command, IntPtr processAttributes, IntPtr threadAttributes, bool inherit, uint flags, IntPtr environment, string directory, ref Startup startup, out ProcessInfo process);
        [DllImport("kernel32.dll", SetLastError=true)] static extern uint ResumeThread(IntPtr thread);
        [DllImport("kernel32.dll")] static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);
        [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
        IntPtr job = IntPtr.Zero, process = IntPtr.Zero;
        public int ProcessId { get; private set; }
        public uint ActiveProcesses {
            get {
                if (job == IntPtr.Zero) return 0;
                Accounting info;
                if (!QueryInformationJobObject(job, 1, out info, (uint)Marshal.SizeOf(typeof(Accounting)), IntPtr.Zero)) throw new Win32Exception(Marshal.GetLastWin32Error());
                return info.Active;
            }
        }
        public PortableProcess(string executable, string workingDirectory, string temporaryDirectory) {
            IntPtr environment = IntPtr.Zero;
            ProcessInfo pi = new ProcessInfo();
            try {
                job = CreateJobObject(IntPtr.Zero, null);
                if (job == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
                ExtendedLimits limits = new ExtendedLimits();
                limits.Basic.Flags = 0x2000; // JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE; no breakaway flags.
                if (!SetInformationJobObject(job, 9, ref limits, (uint)Marshal.SizeOf(typeof(ExtendedLimits)))) throw new Win32Exception(Marshal.GetLastWin32Error());
                // Environment changes belong to this child, never the user's persistent profile.
                SortedDictionary<string,string> variables = new SortedDictionary<string,string>(StringComparer.OrdinalIgnoreCase);
                foreach (DictionaryEntry entry in Environment.GetEnvironmentVariables()) variables[(string)entry.Key] = (string)entry.Value;
                variables["TEMP"] = variables["TMP"] = temporaryDirectory;
                variables["APPDATA"] = Path.Combine(temporaryDirectory, "Roaming");
                variables["LOCALAPPDATA"] = Path.Combine(temporaryDirectory, "Local");
                Directory.CreateDirectory(variables["APPDATA"]);
                Directory.CreateDirectory(variables["LOCALAPPDATA"]);
                StringBuilder block = new StringBuilder();
                foreach (KeyValuePair<string,string> entry in variables) block.Append(entry.Key).Append('=').Append(entry.Value).Append('\0');
                block.Append('\0');
                environment = Marshal.StringToHGlobalUni(block.ToString());
                Startup startup = new Startup();
                startup.cb = (uint)Marshal.SizeOf(typeof(Startup)); startup.flags = 1; startup.show = 1;
                // Suspended first: no code executes before containment succeeds.
                if (!CreateProcessW(executable, new StringBuilder("\"" + executable + "\""), IntPtr.Zero, IntPtr.Zero, false,
                    0x4 | 0x400 | 0x10, environment, workingDirectory, ref startup, out pi)) throw new Win32Exception(Marshal.GetLastWin32Error());
                if (!AssignProcessToJobObject(job, pi.process)) throw new Win32Exception(Marshal.GetLastWin32Error());
                if (ResumeThread(pi.thread) == UInt32.MaxValue) throw new Win32Exception(Marshal.GetLastWin32Error());
                ProcessId = (int)pi.pid; process = pi.process; pi.process = IntPtr.Zero;
            } catch {
                if (pi.process != IntPtr.Zero) TerminateProcess(pi.process, 1);
                Dispose();
                throw;
            } finally {
                if (pi.thread != IntPtr.Zero) CloseHandle(pi.thread);
                if (pi.process != IntPtr.Zero) CloseHandle(pi.process);
                if (environment != IntPtr.Zero) Marshal.FreeHGlobal(environment);
            }
        }
        public void RequestClose() {
            if (process == IntPtr.Zero || WaitForSingleObject(process, 0) != 258) return;
            try { using (Process p = Process.GetProcessById(ProcessId)) { p.CloseMainWindow(); } } catch (InvalidOperationException) { }
        }
        public void Stop() {
            if (job != IntPtr.Zero && !TerminateJobObject(job, 0)) throw new Win32Exception(Marshal.GetLastWin32Error());
        }
        public void Dispose() {
            // Closing this last, non-inherited handle terminates any remaining owned processes.
            if (job != IntPtr.Zero) { CloseHandle(job); job = IntPtr.Zero; }
            if (process != IntPtr.Zero) { CloseHandle(process); process = IntPtr.Zero; }
            GC.SuppressFinalize(this);
        }
        ~PortableProcess() { Dispose(); }
    }
}
