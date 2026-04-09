using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading.Tasks;

namespace WindoRunner
{
    public static class ChildExec
    {
        public static string ReadStreamToMax(StreamReader r, int maxChars, Process p)
        {
            var sb = new StringBuilder();
            var buf = new char[8192];
            int total = 0;
            while (total < maxChars)
            {
                int n = r.Read(buf, 0, Math.Min(buf.Length, maxChars - total));
                if (n <= 0) break;
                sb.Append(buf, 0, n);
                total += n;
            }
            if (total >= maxChars)
            {
                try { if (!p.HasExited) p.Kill(); } catch { }
                try { p.WaitForExit(15000); } catch { }
            }
            return sb.ToString();
        }

        public static void RunCmd(
            string arguments,
            int timeoutMs,
            int maxCharsPerStream,
            out string stdout,
            out string stderr,
            out bool timedOut,
            out bool truncated,
            out int exitCode)
        {
            timedOut = false;
            truncated = false;
            exitCode = 1;
            stdout = "";
            stderr = "";
            var psi = new ProcessStartInfo();
            psi.FileName = "cmd.exe";
            psi.Arguments = "/c " + arguments;
            psi.RedirectStandardOutput = true;
            psi.RedirectStandardError = true;
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            using (var p = Process.Start(psi))
            {
                var tOut = Task.Run(() => ReadStreamToMax(p.StandardOutput, maxCharsPerStream, p));
                var tErr = Task.Run(() => ReadStreamToMax(p.StandardError, maxCharsPerStream, p));
                bool finished = p.WaitForExit(timeoutMs);
                if (!finished)
                {
                    timedOut = true;
                    try { if (!p.HasExited) p.Kill(); } catch { }
                    try { p.WaitForExit(15000); } catch { }
                }
                stdout = tOut.Result;
                stderr = tErr.Result;
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
                if (timedOut)
                    exitCode = -1;
            }
        }
    }
}
