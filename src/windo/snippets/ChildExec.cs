using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace WindoRunner
{
    public static class ChildExec
    {
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr CreateJobObject(IntPtr jobAttributes, string name);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool TerminateJobObject(IntPtr job, uint exitCode);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetInformationJobObject(
            IntPtr job,
            JobObjectInfoClass infoClass,
            ref JobObjectExtendedLimitInformation info,
            uint infoLength);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CloseHandle(IntPtr handle);

        private const uint JobObjectLimitKillOnJobClose = 0x00002000;

        private enum JobObjectInfoClass
        {
            ExtendedLimitInformation = 9
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct JobObjectBasicLimitInformation
        {
            public long PerProcessUserTimeLimit;
            public long PerJobUserTimeLimit;
            public uint LimitFlags;
            public UIntPtr MinimumWorkingSetSize;
            public UIntPtr MaximumWorkingSetSize;
            public uint ActiveProcessLimit;
            public UIntPtr Affinity;
            public uint PriorityClass;
            public uint SchedulingClass;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct IoCounters
        {
            public ulong ReadOperationCount;
            public ulong WriteOperationCount;
            public ulong OtherOperationCount;
            public ulong ReadTransferCount;
            public ulong WriteTransferCount;
            public ulong OtherTransferCount;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct JobObjectExtendedLimitInformation
        {
            public JobObjectBasicLimitInformation BasicLimitInformation;
            public IoCounters IoInfo;
            public UIntPtr ProcessMemoryLimit;
            public UIntPtr JobMemoryLimit;
            public UIntPtr PeakProcessMemoryUsed;
            public UIntPtr PeakJobMemoryUsed;
        }

        private static bool IsWindows()
        {
            var platform = Environment.OSVersion.Platform;
            return platform == PlatformID.Win32NT ||
                   platform == PlatformID.Win32S ||
                   platform == PlatformID.Win32Windows ||
                   platform == PlatformID.WinCE;
        }

        private static IntPtr TryAssignJob(Process process)
        {
            if (!IsWindows()) return IntPtr.Zero;
            IntPtr job = IntPtr.Zero;
            try
            {
                job = CreateJobObject(IntPtr.Zero, null);
                if (job == IntPtr.Zero)
                {
                    return IntPtr.Zero;
                }
                var limits = new JobObjectExtendedLimitInformation();
                limits.BasicLimitInformation.LimitFlags = JobObjectLimitKillOnJobClose;
                if (!SetInformationJobObject(
                        job,
                        JobObjectInfoClass.ExtendedLimitInformation,
                        ref limits,
                        (uint)Marshal.SizeOf(typeof(JobObjectExtendedLimitInformation))) ||
                    !AssignProcessToJobObject(job, process.Handle))
                {
                    CloseHandle(job);
                    return IntPtr.Zero;
                }
                return job;
            }
            catch
            {
                if (job != IntPtr.Zero) CloseHandle(job);
                return IntPtr.Zero;
            }
        }

        private static void TerminateProcessTree(Process process, IntPtr job)
        {
            bool jobTerminated = false;
            if (job != IntPtr.Zero)
            {
                try { jobTerminated = TerminateJobObject(job, 1); } catch { }
            }

            // Windows PowerShell 5.1 lacks Process.Kill(bool). If assignment
            // to a Job Object was blocked by an existing job policy, taskkill
            // provides a bounded native process-tree fallback.
            if (!jobTerminated && IsWindows())
            {
                try
                {
                    if (!process.HasExited)
                    {
                        var taskKill = new ProcessStartInfo();
                        taskKill.FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "taskkill.exe");
                        taskKill.Arguments = "/PID " + process.Id + " /T /F";
                        taskKill.UseShellExecute = false;
                        taskKill.CreateNoWindow = true;
                        taskKill.RedirectStandardOutput = true;
                        taskKill.RedirectStandardError = true;
                        using (var killer = Process.Start(taskKill))
                        {
                            if (killer != null) killer.WaitForExit(10000);
                        }
                    }
                }
                catch { }
            }

            try
            {
                if (!process.HasExited)
                {
                    var treeKill = typeof(Process).GetMethod("Kill", new[] { typeof(bool) });
                    if (treeKill != null)
                        treeKill.Invoke(process, new object[] { true });
                    else
                        process.Kill();
                }
            }
            catch
            {
                try { if (!process.HasExited) process.Kill(); } catch { }
            }
        }

        private static bool WaitForReaders(Task<string> stdoutTask, Task<string> stderrTask, int timeoutMs)
        {
            try { return Task.WaitAll(new Task[] { stdoutTask, stderrTask }, timeoutMs); }
            catch { return stdoutTask.IsCompleted && stderrTask.IsCompleted; }
        }

        private sealed class CaptureState
        {
            public volatile bool LimitReached;
            public volatile bool StreamSinkFailed;
        }

        private static string CompletedReaderResult(Task<string> task)
        {
            if (!task.IsCompleted || task.IsCanceled || task.IsFaulted) return "";
            try { return task.Result ?? ""; } catch { return ""; }
        }

        private static string ResolveWorkingDirectory(string requestedPath)
        {
            var candidates = new[]
            {
                requestedPath,
                Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                Path.GetTempPath()
            };
            foreach (var candidate in candidates)
            {
                if (string.IsNullOrWhiteSpace(candidate) || !Path.IsPathRooted(candidate))
                    continue;
                try
                {
                    var fullPath = Path.GetFullPath(candidate);
                    if (Directory.Exists(fullPath))
                        return fullPath;
                }
                catch { }
            }
            throw new DirectoryNotFoundException("No safe child-process working directory is available.");
        }

        private static StreamWriter OpenStreamSink(string path)
        {
            if (string.IsNullOrWhiteSpace(path)) return null;
            if (!Path.IsPathRooted(path))
                throw new ArgumentException("Inline stream path must be absolute.", "path");
            var fullPath = Path.GetFullPath(path);
            var parent = Path.GetDirectoryName(fullPath);
            if (string.IsNullOrWhiteSpace(parent))
                throw new ArgumentException("Inline stream path has no parent directory.", "path");
            Directory.CreateDirectory(parent);
            var stream = new FileStream(fullPath, FileMode.Create, FileAccess.Write, FileShare.ReadWrite | FileShare.Delete);
            return new StreamWriter(stream, new UTF8Encoding(false)) { AutoFlush = true };
        }

        private static string ReadStreamToMax(
            StreamReader reader,
            int maxChars,
            CaptureState state,
            StreamWriter sink)
        {
            var buffer = new char[8192];
            var captured = new StringBuilder();
            int total = 0;
            try
            {
                while (total < maxChars)
                {
                    int count = reader.Read(buffer, 0, Math.Min(buffer.Length, maxChars - total));
                    if (count <= 0) break;
                    captured.Append(buffer, 0, count);
                    total += count;

                    if (sink != null)
                    {
                        try
                        {
                            sink.Write(buffer, 0, count);
                        }
                        catch
                        {
                            state.StreamSinkFailed = true;
                            try { sink.Dispose(); } catch { }
                            sink = null;
                        }
                    }
                }
            }
            catch
            {
                // Preserve captured output and let the bounded process/reader
                // cleanup path decide the final execution result.
            }
            finally
            {
                if (sink != null)
                {
                    try { sink.Dispose(); } catch { }
                }
            }

            if (total >= maxChars)
                state.LimitReached = true;
            return captured.ToString();
        }

        private static bool IsCancellationRequested(string cancelPath)
        {
            if (string.IsNullOrWhiteSpace(cancelPath)) return false;
            try
            {
                if (!Path.IsPathRooted(cancelPath)) return false;
                return File.Exists(Path.GetFullPath(cancelPath));
            }
            catch
            {
                return false;
            }
        }

        private static string BuildGatedScript(string scriptText, string gateName)
        {
            var safeGateName = (gateName ?? "").Replace("'", "''");
            return "$windoGate=[System.Threading.EventWaitHandle]::OpenExisting('" + safeGateName + "');" +
                   "try{if(-not $windoGate.WaitOne(30000)){exit 124}}finally{$windoGate.Dispose()};" +
                   Environment.NewLine + (scriptText ?? "");
        }

        private static void RunPowerShellCore(
            string executablePath,
            string scriptText,
            string workingDirectory,
            int timeoutMs,
            int maxCharsPerStream,
            string stdoutStreamPath,
            string stderrStreamPath,
            string cancelPath,
            out string stdout,
            out string stderr,
            out bool timedOut,
            out bool truncated,
            out bool cancelled,
            out bool streamSinkFailed,
            out int exitCode)
        {
            timedOut = false;
            truncated = false;
            cancelled = false;
            streamSinkFailed = false;
            exitCode = 1;
            stdout = "";
            stderr = "";
            if (string.IsNullOrWhiteSpace(executablePath))
                executablePath = "powershell.exe";
            EventWaitHandle startGate = null;
            string commandText = scriptText ?? "";
            if (IsWindows())
            {
                var gateName = "Local\\WindoRunner-" + Guid.NewGuid().ToString("N");
                bool createdNew;
                startGate = new EventWaitHandle(false, EventResetMode.ManualReset, gateName, out createdNew);
                if (!createdNew)
                {
                    startGate.Dispose();
                    throw new InvalidOperationException("Unable to create a unique child-process start gate.");
                }
                commandText = BuildGatedScript(commandText, gateName);
            }
            var encodedCommand = Convert.ToBase64String(Encoding.Unicode.GetBytes(commandText));
            var psi = new ProcessStartInfo();
            psi.FileName = executablePath;
            psi.Arguments = "-NoProfile -NonInteractive -NoLogo -EncodedCommand " + encodedCommand;
            if (psi.Arguments.Length > 32000)
                throw new ArgumentException("The gated PowerShell command exceeds the Windows process command-line limit.", "scriptText");
            psi.WorkingDirectory = ResolveWorkingDirectory(workingDirectory);
            psi.RedirectStandardOutput = true;
            psi.RedirectStandardError = true;
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            Process p = null;
            IntPtr job = IntPtr.Zero;
            bool disposeProcessSynchronously = true;
            StreamWriter stdoutSink = null;
            StreamWriter stderrSink = null;
            bool sinksOwnedByReaders = false;
            try
            {
                // Open the live stream channels before the child starts. An
                // invalid stream path therefore fails closed without allowing
                // elevated user code to execute.
                stdoutSink = OpenStreamSink(stdoutStreamPath);
                stderrSink = OpenStreamSink(stderrStreamPath);
                if (IsCancellationRequested(cancelPath))
                {
                    cancelled = true;
                    exitCode = 130;
                    return;
                }

                p = Process.Start(psi);
                if (p == null)
                    throw new InvalidOperationException("The PowerShell child process did not start.");

                if (IsWindows())
                {
                    job = TryAssignJob(p);
                    if (job == IntPtr.Zero)
                    {
                        try { if (!p.HasExited) p.Kill(); } catch { }
                        throw new InvalidOperationException("Unable to establish child-process job containment; command was not executed.");
                    }
                    startGate.Set();
                    startGate.Dispose();
                    startGate = null;
                }

                try
                {
                    var captureState = new CaptureState();
                    var tOut = Task.Run(() => ReadStreamToMax(p.StandardOutput, maxCharsPerStream, captureState, stdoutSink));
                    var tErr = Task.Run(() => ReadStreamToMax(p.StandardError, maxCharsPerStream, captureState, stderrSink));
                    sinksOwnedByReaders = true;
                    var wait = Stopwatch.StartNew();
                    bool finished = false;
                    while (!finished && wait.ElapsedMilliseconds < timeoutMs && !captureState.LimitReached && !cancelled)
                    {
                        if (IsCancellationRequested(cancelPath))
                        {
                            cancelled = true;
                            break;
                        }
                        int remaining = timeoutMs - (int)Math.Min(timeoutMs, wait.ElapsedMilliseconds);
                        finished = p.WaitForExit(Math.Max(1, Math.Min(remaining, 100)));
                    }
                    if (cancelled && !finished)
                    {
                        TerminateProcessTree(p, job);
                        try { p.WaitForExit(15000); } catch { }
                        finished = true;
                    }
                    else if (captureState.LimitReached && !finished)
                    {
                        truncated = true;
                        TerminateProcessTree(p, job);
                        try { p.WaitForExit(15000); } catch { }
                        finished = true;
                    }
                    else if (!finished)
                    {
                        timedOut = true;
                        TerminateProcessTree(p, job);
                        try { p.WaitForExit(15000); } catch { }
                    }

                    // A descendant can inherit redirected handles after the
                    // direct child exits. Never block indefinitely waiting for
                    // those handles: terminate the assigned job/tree, close
                    // the readers, and allow only a bounded final drain.
                    if (!WaitForReaders(tOut, tErr, 5000))
                    {
                        if (!cancelled) timedOut = true;
                        TerminateProcessTree(p, job);
                        // Closing a StreamReader concurrently with a blocked
                        // synchronous Read can itself block. Kill-on-close is
                        // the bounded Windows primitive, so release the job
                        // before the final drain and never close readers here.
                        if (job != IntPtr.Zero)
                        {
                            CloseHandle(job);
                            job = IntPtr.Zero;
                        }
                        if (!WaitForReaders(tOut, tErr, 2000))
                        {
                            disposeProcessSynchronously = false;
                            var processToDispose = p;
                            Task.WhenAll(tOut, tErr).ContinueWith(
                                ignored => { try { processToDispose.Dispose(); } catch { } },
                                TaskScheduler.Default);
                        }
                    }
                    stdout = CompletedReaderResult(tOut);
                    stderr = CompletedReaderResult(tErr);
                    streamSinkFailed = captureState.StreamSinkFailed;
                    if (stdout.Length >= maxCharsPerStream || stderr.Length >= maxCharsPerStream)
                        truncated = true;
                    try
                    {
                        exitCode = p.HasExited ? p.ExitCode : -1;
                    }
                    catch
                    {
                        exitCode = -1;
                    }
                    if (cancelled)
                        exitCode = 130;
                    else if (timedOut)
                        exitCode = -1;
                }
                finally
                {
                    if (job != IntPtr.Zero) CloseHandle(job);
                    job = IntPtr.Zero;
                }
            }
            finally
            {
                if (startGate != null) startGate.Dispose();
                if (job != IntPtr.Zero) CloseHandle(job);
                if (!sinksOwnedByReaders)
                {
                    if (stdoutSink != null) { try { stdoutSink.Dispose(); } catch { } }
                    if (stderrSink != null) { try { stderrSink.Dispose(); } catch { } }
                }
                if (p != null && disposeProcessSynchronously) p.Dispose();
            }
        }

        public static void RunPowerShellStreaming(
            string executablePath,
            string scriptText,
            string workingDirectory,
            int timeoutMs,
            int maxCharsPerStream,
            string stdoutStreamPath,
            string stderrStreamPath,
            string cancelPath,
            out string stdout,
            out string stderr,
            out bool timedOut,
            out bool truncated,
            out bool cancelled,
            out bool streamSinkFailed,
            out int exitCode)
        {
            RunPowerShellCore(
                executablePath, scriptText, workingDirectory, timeoutMs, maxCharsPerStream,
                stdoutStreamPath, stderrStreamPath, cancelPath,
                out stdout, out stderr, out timedOut, out truncated,
                out cancelled, out streamSinkFailed, out exitCode);
        }

        // Backward-compatible streaming entry point created before explicit
        // cancellation and stream-health reporting were added.
        public static void RunPowerShellStreaming(
            string executablePath,
            string scriptText,
            string workingDirectory,
            int timeoutMs,
            int maxCharsPerStream,
            string stdoutStreamPath,
            string stderrStreamPath,
            out string stdout,
            out string stderr,
            out bool timedOut,
            out bool truncated,
            out int exitCode)
        {
            bool cancelled;
            bool streamSinkFailed;
            RunPowerShellCore(
                executablePath, scriptText, workingDirectory, timeoutMs, maxCharsPerStream,
                stdoutStreamPath, stderrStreamPath, null,
                out stdout, out stderr, out timedOut, out truncated,
                out cancelled, out streamSinkFailed, out exitCode);
        }

        public static void RunPowerShell(
            string executablePath,
            string scriptText,
            string workingDirectory,
            int timeoutMs,
            int maxCharsPerStream,
            out string stdout,
            out string stderr,
            out bool timedOut,
            out bool truncated,
            out int exitCode)
        {
            bool cancelled;
            bool streamSinkFailed;
            RunPowerShellCore(
                executablePath, scriptText, workingDirectory, timeoutMs, maxCharsPerStream,
                null, null, null,
                out stdout, out stderr, out timedOut, out truncated,
                out cancelled, out streamSinkFailed, out exitCode);
        }

        // Backward-compatible overload for callers created before working
        // directory propagation was added.
        public static void RunPowerShell(
            string executablePath,
            string scriptText,
            int timeoutMs,
            int maxCharsPerStream,
            out string stdout,
            out string stderr,
            out bool timedOut,
            out bool truncated,
            out int exitCode)
        {
            RunPowerShell(
                executablePath,
                scriptText,
                Environment.CurrentDirectory,
                timeoutMs,
                maxCharsPerStream,
                out stdout,
                out stderr,
                out timedOut,
                out truncated,
                out exitCode);
        }

        // Backward-compatible entry point for already-installed runner helpers.
        public static void RunCmd(
            string scriptText,
            int timeoutMs,
            int maxCharsPerStream,
            out string stdout,
            out string stderr,
            out bool timedOut,
            out bool truncated,
            out int exitCode)
        {
            RunPowerShell(
                "powershell.exe",
                scriptText,
                Environment.CurrentDirectory,
                timeoutMs,
                maxCharsPerStream,
                out stdout,
                out stderr,
                out timedOut,
                out truncated,
                out exitCode);
        }
    }
}
