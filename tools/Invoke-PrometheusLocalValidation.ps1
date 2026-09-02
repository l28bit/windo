[CmdletBinding()]
param(
    [ValidateSet('PreSign','Full')]
    [string]$Mode = 'PreSign',

    [switch]$Worker,

    [string]$WorkerLabel = ''
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$ScriptPath = $MyInvocation.MyCommand.Path

function Write-PrometheusSection {
    param([string]$Text)
    Write-Host ''
    Write-Host ('=== {0} ===' -f $Text) -ForegroundColor Cyan
}

function Get-PrometheusPublishedHash {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][ValidateSet('SHA256','SHA384','SHA512')][string]$Algorithm
    )

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $text = $strictUtf8.GetString($bytes)
    $publishedBytes = $utf8NoBom.GetBytes($text.Replace("`r`n", "`n"))

    switch ($Algorithm) {
        'SHA256' { $hash = [System.Security.Cryptography.SHA256]::Create() }
        'SHA384' { $hash = [System.Security.Cryptography.SHA384]::Create() }
        'SHA512' { $hash = [System.Security.Cryptography.SHA512]::Create() }
    }

    try {
        $digest = $hash.ComputeHash($publishedBytes)
        return (-join ($digest | ForEach-Object { $_.ToString('X2') }))
    }
    finally {
        $hash.Dispose()
    }
}

function Get-PrometheusManifest {
    param([Parameter(Mandatory = $true)][string]$Path)

    $manifest = @{}
    foreach ($line in ([System.IO.File]::ReadAllText($Path) -split "`r?`n")) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#')) { continue }
        if ($trimmed -match '^(?<key>[^=]+?)=(?<value>.*)$') {
            $manifest[$matches.key] = $matches.value.Trim()
        }
    }
    return $manifest
}

function Test-PrometheusParseGate {
    $files = @(
        'bootstrap.ps1',
        'windo_install.ps1',
        'windo_runner.ps1',
        'windo_uninstall.ps1',
        'tools/Test-WindoLogic.ps1',
        'tools/Validate-Windo.ps1',
        'tools/Test-WindoReservedVariables.ps1',
        'tools/Invoke-PrometheusLocalValidation.ps1',
        'tools/Invoke-PrometheusLocalStage.ps1',
        'tools/Prometheus-RepairGeneratedArtifacts.ps1'
    )

    foreach ($relative in $files) {
        $path = Join-Path $RepoRoot $relative
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Missing required file: $relative"
        }
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile(
            (Resolve-Path -LiteralPath $path),
            [ref]$tokens,
            [ref]$errors
        )
        if ($errors.Count -gt 0) {
            foreach ($parseError in $errors) {
                Write-Host ('PARSE FAIL {0}:{1}:{2} {3}' -f $relative, $parseError.Extent.StartLineNumber, $parseError.Extent.StartColumnNumber, $parseError.Message) -ForegroundColor Red
            }
            throw "PowerShell parse gate failed: $relative"
        }
    }

    Write-Host 'PASS: release entry points and local Prometheus tools parse.' -ForegroundColor Green
}

function Get-PrometheusRunnerChildExecPayload {
    param([Parameter(Mandatory = $true)][string]$Text)

    $anchor = '$cs = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('
    $anchorIndex = $Text.IndexOf($anchor, [StringComparison]::OrdinalIgnoreCase)
    if ($anchorIndex -lt 0) { throw 'Standalone runner ChildExec assignment anchor could not be located.' }
    $secondAnchor = $Text.IndexOf($anchor, $anchorIndex + $anchor.Length, [StringComparison]::OrdinalIgnoreCase)
    if ($secondAnchor -ge 0) { throw 'Standalone runner contains multiple ChildExec assignment anchors.' }

    $openQuote = $Text.IndexOf([char]39, $anchorIndex + $anchor.Length)
    if ($openQuote -lt 0) { throw 'Standalone runner ChildExec opening quote could not be located.' }
    $closeQuote = $Text.IndexOf([char]39, $openQuote + 1)
    if ($closeQuote -lt 0) { throw 'Standalone runner ChildExec closing quote could not be located.' }

    $payload = ($Text.Substring($openQuote + 1, $closeQuote - $openQuote - 1) -replace '\s', '')
    if ($payload.Length -lt 10000 -or $payload -match '[^A-Za-z0-9+/=]') {
        throw 'Standalone runner ChildExec payload is malformed.'
    }
    return $payload
}

function Test-PrometheusChildExecParity {
    $sourcePath = Join-Path $RepoRoot 'src\windo\snippets\ChildExec.cs'
    $payloadPath = Join-Path $RepoRoot 'tools\ChildExec.b64.txt'
    $runnerPath = Join-Path $RepoRoot 'windo_runner.ps1'
    $installerPath = Join-Path $RepoRoot 'windo_install.ps1'

    foreach ($path in @($sourcePath, $payloadPath, $runnerPath, $installerPath)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing parity input: $path" }
    }

    $source = [System.IO.File]::ReadAllText($sourcePath)
    $payload = ([System.IO.File]::ReadAllText($payloadPath) -replace '\s', '')
    $decoded = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload))
    if ($source -cne $decoded) {
        throw 'ChildExec.cs and tools/ChildExec.b64.txt are not byte-equivalent.'
    }

    $runnerText = [System.IO.File]::ReadAllText($runnerPath)
    $runnerPayload = Get-PrometheusRunnerChildExecPayload -Text $runnerText
    if ($runnerPayload -cne $payload) {
        throw 'Standalone runner embedded ChildExec payload differs from tools/ChildExec.b64.txt.'
    }

    $installerText = [System.IO.File]::ReadAllText($installerPath)
    $runnerBlockPattern = '(?ms)^\$RunnerContent = @''\r?\n(?<runner>.*?)^''@\r?\nWrite-Utf8NoBomFile -Path \$RunnerPath -Content \$RunnerContent'
    $runnerBlockMatch = [regex]::Match($installerText, $runnerBlockPattern)
    if (-not $runnerBlockMatch.Success) {
        throw 'Installer RunnerContent block could not be located.'
    }
    $embeddedRunner = $runnerBlockMatch.Groups['runner'].Value.TrimEnd("`r", "`n")
    if ($embeddedRunner -cne $runnerText.TrimEnd("`r", "`n")) {
        throw 'Installer embedded RunnerContent differs from standalone windo_runner.ps1.'
    }

    Write-Host 'PASS: ChildExec source, Base64 payload, standalone runner, and installer runner are synchronized.' -ForegroundColor Green
}

function Test-PrometheusInstallerEncoding {
    $installerPath = Join-Path $RepoRoot 'windo_install.ps1'
    $bytes = [System.IO.File]::ReadAllBytes($installerPath)
    $hasUtf8Bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    if (-not $hasUtf8Bom) {
        throw 'windo_install.ps1 does not have the UTF-8 BOM required for Windows PowerShell 5.1-safe non-ASCII parsing.'
    }
    Write-Host 'PASS: installer encoding is explicit UTF-8 with BOM.' -ForegroundColor Green
}

function Test-PrometheusReleaseHashes {
    $manifestPath = Join-Path $RepoRoot 'checksums\installer.sha256'
    $installerPath = Join-Path $RepoRoot 'windo_install.ps1'
    $uninstallerPath = Join-Path $RepoRoot 'windo_uninstall.ps1'

    foreach ($path in @($manifestPath, $installerPath, $uninstallerPath)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing release hash input: $path" }
    }

    $manifest = Get-PrometheusManifest -Path $manifestPath
    if (-not $manifest.ContainsKey('schemaVersion') -or [string]$manifest.schemaVersion -cne '2') {
        throw 'Checksum manifest schemaVersion must be 2.'
    }
    if (-not $manifest.ContainsKey('releaseBranch') -or [string]$manifest.releaseBranch -cne 'jonex/windo-production-ready') {
        throw 'Checksum manifest releaseBranch must be jonex/windo-production-ready.'
    }

    $specs = @(
        @{ Key = 'installerSha256'; Path = $installerPath; Algorithm = 'SHA256' },
        @{ Key = 'installerSha384'; Path = $installerPath; Algorithm = 'SHA384' },
        @{ Key = 'installerSha512'; Path = $installerPath; Algorithm = 'SHA512' },
        @{ Key = 'uninstallerSha256'; Path = $uninstallerPath; Algorithm = 'SHA256' },
        @{ Key = 'uninstallerSha384'; Path = $uninstallerPath; Algorithm = 'SHA384' },
        @{ Key = 'uninstallerSha512'; Path = $uninstallerPath; Algorithm = 'SHA512' }
    )

    foreach ($spec in $specs) {
        $key = [string]$spec.Key
        if (-not $manifest.ContainsKey($key)) { throw "Checksum manifest is missing $key." }
        $expected = [string]$manifest[$key]
        $actual = Get-PrometheusPublishedHash -Path ([string]$spec.Path) -Algorithm ([string]$spec.Algorithm)
        if ($actual -cne $expected) {
            throw "$key does not match the current release artifact. expected=$expected actual=$actual"
        }
    }

    Write-Host 'PASS: installer and uninstaller checksum manifest hashes match current artifacts.' -ForegroundColor Green
}

function Test-PrometheusReleaseTrustRoot {
    $installerPath = Join-Path $RepoRoot 'windo_install.ps1'
    $publicKeyPath = Join-Path $RepoRoot 'keys\windo-release-public.rsa.xml'
    $installerText = [System.IO.File]::ReadAllText($installerPath)
    $match = [regex]::Match($installerText, '(?m)^\$WindoReleasePublicKeyB64\s*=\s*"(?<b64>[A-Za-z0-9+/=]+)"\s*$')
    if (-not $match.Success) { throw 'Installer embedded release public key was not found.' }
    $embedded = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($match.Groups['b64'].Value)).Trim()
    $committed = [System.IO.File]::ReadAllText($publicKeyPath).Trim()
    if ($embedded -cne $committed) { throw 'Installer embedded release public key differs from keys/windo-release-public.rsa.xml.' }
    Write-Host 'PASS: installer trust root matches committed public release key.' -ForegroundColor Green
}

function Test-PrometheusSignatureGate {
    $verifier = Join-Path $RepoRoot 'tools\Test-WindoChecksumSignature.ps1'
    if (-not (Test-Path -LiteralPath $verifier -PathType Leaf)) { throw 'Missing checksum signature verifier.' }

    try {
        & $verifier | Out-Null
        Write-Host 'PASS: checksum manifest signature is valid.' -ForegroundColor Green
    }
    catch {
        if ($Mode -eq 'Full') {
            throw ('Checksum manifest signature validation failed: {0}' -f $_.Exception.Message)
        }
        Write-Host 'PENDING: checksum manifest signature is not valid for the current manifest. This is allowed in PreSign mode only.' -ForegroundColor Yellow
    }
}

function Invoke-PrometheusWorker {
    Write-PrometheusSection ("$WorkerLabel / $Mode")
    Write-Host ('PowerShell: {0}' -f $PSVersionTable.PSVersion)
    Write-Host ('Repo:       {0}' -f $RepoRoot)

    Test-PrometheusParseGate

    & (Join-Path $RepoRoot 'tools\Test-WindoReservedVariables.ps1')
    $reservedVariableGatePassed = $?
    if (-not $reservedVariableGatePassed) { throw 'Reserved-variable regression test failed.' }

    & (Join-Path $RepoRoot 'tools\Test-WindoLogic.ps1')
    $logicGatePassed = $?
    if (-not $logicGatePassed) { throw 'WINDO logic suite failed.' }

    Test-PrometheusChildExecParity
    Test-PrometheusInstallerEncoding
    Test-PrometheusReleaseHashes
    Test-PrometheusReleaseTrustRoot
    Test-PrometheusSignatureGate

    Write-Host ('PASS: {0} local Prometheus {1} gate completed.' -f $WorkerLabel, $Mode) -ForegroundColor Green
}

if ($Worker) {
    try {
        Invoke-PrometheusWorker
        exit 0
    }
    catch {
        Write-Host ('FAIL: {0}: {1}' -f $WorkerLabel, $_.Exception.Message) -ForegroundColor Red
        exit 1
    }
}

$branch = ''
try {
    $branchOutput = @(& git -C $RepoRoot rev-parse --abbrev-ref HEAD 2>$null)
    if ($LASTEXITCODE -eq 0) { $branch = (($branchOutput | ForEach-Object { [string]$_ }) -join '').Trim() }
}
catch {}
if ($branch -and $branch -ne 'jonex/windo-production-ready') {
    throw "Local Prometheus validation must run from jonex/windo-production-ready. Current branch: $branch"
}

$hosts = New-Object 'System.Collections.Generic.List[object]'
$ps51 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $ps51 -PathType Leaf)) {
    throw "Windows PowerShell 5.1 host was not found at $ps51"
}
$hosts.Add([pscustomobject]@{ Label = 'Windows PowerShell 5.1'; Path = $ps51 })

$pwshCommand = Get-Command pwsh.exe -ErrorAction SilentlyContinue
if ($null -eq $pwshCommand) {
    throw 'PowerShell 7 (pwsh.exe) is required for the Prometheus dual-host gate.'
}
$hosts.Add([pscustomobject]@{ Label = 'PowerShell 7'; Path = $pwshCommand.Source })

$logRoot = Join-Path $env:TEMP 'WINDO-Prometheus'
if (-not (Test-Path -LiteralPath $logRoot)) { New-Item -ItemType Directory -Path $logRoot -Force | Out-Null }
$logPath = Join-Path $logRoot ('prometheus-local-validation-{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$allOutput = New-Object 'System.Collections.Generic.List[string]'
$failedHosts = New-Object 'System.Collections.Generic.List[string]'

foreach ($hostInfo in $hosts) {
    Write-PrometheusSection $hostInfo.Label
    $arguments = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $ScriptPath,
        '-Worker',
        '-Mode', $Mode,
        '-WorkerLabel', $hostInfo.Label
    )

    $hostOutput = @(& $hostInfo.Path @arguments 2>&1)
    $exitCode = $LASTEXITCODE
    foreach ($line in $hostOutput) {
        $text = [string]$line
        $allOutput.Add(('[{0}] {1}' -f $hostInfo.Label, $text))
        Write-Host $text
    }
    if ($exitCode -ne 0) { $failedHosts.Add($hostInfo.Label) }
}

[System.IO.File]::WriteAllLines($logPath, $allOutput.ToArray(), (New-Object System.Text.UTF8Encoding($false)))
Write-Host ''
Write-Host ('Validation log: {0}' -f $logPath) -ForegroundColor DarkGray

if ($failedHosts.Count -gt 0) {
    Write-Host ('PROMETHEUS LOCAL GATE: FAIL ({0})' -f ($failedHosts -join ', ')) -ForegroundColor Red
    exit 1
}

if ($Mode -eq 'PreSign') {
    Write-Host 'PROMETHEUS LOCAL GATE: PRE-SIGN PASS' -ForegroundColor Green
    Write-Host 'If the signature is the only PENDING item, the branch is ready for the owner signing step.' -ForegroundColor Cyan
}
else {
    Write-Host 'PROMETHEUS LOCAL GATE: FULL PASS' -ForegroundColor Green
}
exit 0
