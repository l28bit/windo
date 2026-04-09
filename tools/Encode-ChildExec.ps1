$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$cs = Join-Path $root "src\windo\snippets\ChildExec.cs"
$b = [Convert]::ToBase64String([IO.File]::ReadAllBytes($cs))
$out = Join-Path $PSScriptRoot "ChildExec.b64.txt"
Set-Content -Path $out -Value $b -NoNewline
Write-Host "Wrote $out length=$($b.Length)"
