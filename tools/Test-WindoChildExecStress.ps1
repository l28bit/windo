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
            return "PASS: 8 independent commands in two four-way concurrent waves.";
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
