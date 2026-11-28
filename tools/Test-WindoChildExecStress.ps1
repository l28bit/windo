# Isolated, bounded stress certification of the canonical shipping executor.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'This certification requires Windows.'
}
$root = Split-Path $PSScriptRoot -Parent
$source = [IO.File]::ReadAllText((Join-Path $root 'src/windo/snippets/ChildExec.cs'))
$payload = ([IO.File]::ReadAllText((Join-Path $root 'tools/ChildExec.b64.txt')) -replace '\s','')
if ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) -cne $source) {
    throw 'Shipping payload differs from maintained ChildExec source.'
}
if ('WindoRunner.ChildExec' -as [type]) {
    throw 'Stress certification requires a fresh PowerShell process.'
}
$harness = @'
namespace WindoRunner
{
    public static class ChildExecStressFixture
    {
        public static string Run(string host, string root)
        {
            // Two waves, four overlapping children each. Exercise the actual
            // shared executor in one process, not four isolated test hosts.
            for (int wave = 0; wave < 2; wave++)
            {
                var tasks = new Task[4];
                for (int slot = 0; slot < tasks.Length; slot++)
                {
                    int id = wave * tasks.Length + slot;
                    tasks[slot] = Task.Run(() =>
                    {
                        string dir = Path.Combine(root, "case-" + id);
                        Directory.CreateDirectory(dir);
                        string token = "WINDO-STRESS-" + id;
                        int expectedExit = 20 + id;
                        string script = "[Console]::Out.Write('" + token +
                            "|'+(Get-Location).Path);[Console]::Error.Write('" +
                            token + "-ERR');exit " + expectedExit;
                        string stdout, stderr;
                        bool timedOut, truncated;
                        int exitCode;
                        ChildExec.RunPowerShell(host, script, dir, 30000, 65536,
                            out stdout, out stderr, out timedOut, out truncated, out exitCode);
                        if (timedOut || truncated || exitCode != expectedExit ||
                            stdout != token + "|" + dir || stderr != token + "-ERR")
                            throw new InvalidOperationException(
                                "Case " + id + " failed: exit=" + exitCode +
                                " timeout=" + timedOut + " truncated=" + truncated +
                                " stdout=" + stdout + " stderr=" + stderr);
                    });
                }
                if (!Task.WaitAll(tasks, 90000))
                    throw new TimeoutException("Concurrent ChildExec wave exceeded its bound.");
            }
            // Establish a warmed-up process handle baseline. The .NET runtime
            // can retain a small number of worker-thread and diagnostic handles.
            int baseline = GetHandleCount();
            for (int wave = 0; wave < 2; wave++)
            {
                var mixed = new Task[4];
                for (int slot = 0; slot < mixed.Length; slot++)
                {
                    int id = wave * mixed.Length + slot;
                    mixed[slot] = Task.Factory.StartNew(() => RunMixed(host, root, id),
                        CancellationToken.None, TaskCreationOptions.LongRunning,
                        TaskScheduler.Default);
                }
                if (!Task.WaitAll(mixed, 90000))
                    throw new TimeoutException("Mixed-failure wave exceeded its bound.");
            }
            // Reuse the same process after timeout and output-cap termination.
            // A fresh request must not inherit either failure or stale output.
            for (int id = 0; id < 8; id++)
            {
                string token = "WINDO-RECOVERY-" + id;
                string stdout, stderr;
                bool timedOut, truncated;
                int exitCode;
                ChildExec.RunPowerShell(host, "[Console]::Out.Write('" + token + "');exit 0",
                    root, 30000, 65536, out stdout, out stderr, out timedOut, out truncated, out exitCode);
                if (stdout != token || stderr != "" || timedOut || truncated || exitCode != 0)
                    throw new InvalidOperationException("Recovery request " + id + " failed.");
            }
            int final = GetHandleCount();
            // This is a gross retained-handle regression guard, not proof of
            // zero leaks. Allow bounded CLR/runtime variation after warm-up.
            if (final - baseline > 24)
                throw new InvalidOperationException("Retained process handle growth exceeded 24: " +
                    baseline + " -> " + final);
            return "PASS: 24 commands; 8 concurrent normal, 8 concurrent mixed, 8 recovery. " +
                "Retained handles after warm-up: " + baseline + " -> " + final + ".";
        }

        private static int GetHandleCount()
        {
            GC.Collect();
            GC.WaitForPendingFinalizers();
            GC.Collect();
            using (var process = Process.GetCurrentProcess())
            {
                process.Refresh();
                return process.HandleCount;
            }
        }

        private static void RunMixed(string host, string root, int id)
        {
            string dir = Path.Combine(root, "mixed-" + id);
            Directory.CreateDirectory(dir);
            string token = "WINDO-MIXED-" + id;
            int mode = id % 4;
            int cap = mode == 1 ? 4096 : 65536;
            int timeout = mode == 0 ? 12000 : 30000;
            string script;
            if (mode == 0)
                script = "[Console]::Out.Write('" + token + "');Start-Sleep -Seconds 90";
            else if (mode == 1)
                script = "[Console]::Error.Write(('X' * 1000000));Start-Sleep -Seconds 90";
            else
                script = "[Console]::Out.Write('" + token + "');[Console]::Error.Write('" +
                    token + "-ERR');exit " + (30 + id);
            string stdout, stderr;
            bool timedOut, truncated;
            int exitCode;
            ChildExec.RunPowerShell(host, script, dir, timeout, cap,
                out stdout, out stderr, out timedOut, out truncated, out exitCode);
            bool valid;
            if (mode == 0)
                valid = timedOut && !truncated && exitCode == -1 && stdout == token && stderr == "";
            else if (mode == 1)
                valid = truncated && !timedOut && stdout == "" && stderr == new string('X', cap);
            else
                valid = !timedOut && !truncated && exitCode == 30 + id &&
                    stdout == token && stderr == token + "-ERR";
            if (!valid)
                throw new InvalidOperationException("Mixed case " + id + " failed: exit=" + exitCode +
                    " timeout=" + timedOut + " truncated=" + truncated +
                    " stdout length=" + stdout.Length + " stderr length=" + stderr.Length);

        }
    }
}
'@
Add-Type -TypeDefinition ($source + [Environment]::NewLine + $harness) -Language CSharp
$hostPath = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('windo-stress-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixtureRoot)
try {
    [WindoRunner.ChildExecStressFixture]::Run([string]$hostPath, [string]$fixtureRoot) | Write-Host
} finally {
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}
