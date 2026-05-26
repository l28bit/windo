$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$global:WINDO_EXIT_CODE = 0
$script:WindoBootstrapExpectedVersion = "8.5.1"

function Get-WindoEditionLabel {
    param([string]$Semver = $script:WindoBootstrapExpectedVersion)
    $parts = @($Semver.Split('.'))
    if ($parts.Count -ge 2) { return ("V{0}.{1}" -f $parts[0], $parts[1]) }
    return "V$Semver"
}

function Set-WindoBootstrapExitCode {
    param([int]$Code)
    $script:bootstrapExitCode = $Code
    $global:WINDO_EXIT_CODE = $Code
    try { $global:LASTEXITCODE = $Code } catch { }
}

function Test-WindoBootstrapProcessElevated {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $pr = [Security.Principal.WindowsPrincipal]$id
        return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Get-WindoBootstrapReleaseBranch {
    $raw = if ($null -ne $env:WINDO_TRACKING_BRANCH -and -not [string]::IsNullOrWhiteSpace($env:WINDO_TRACKING_BRANCH)) { [string]$env:WINDO_TRACKING_BRANCH } else { "Exodus" }
    $trimmed = $raw.Trim()
    $lower = $trimmed.ToLowerInvariant()
    if ($lower -in @('genesis', 'genisis', 'prometheus')) { return "Exodus" }
    if ($trimmed -notmatch '^[A-Za-z0-9._-]{1,64}$') { return "Exodus" }
    return $trimmed
}
$script:_windo_bootstrap_release_ref = $null

function Get-WindoBootstrapReleaseRef {
    if (-not [string]::IsNullOrWhiteSpace($env:WINDO_RELEASE_COMMIT)) {
        $envCommit = [string]$env:WINDO_RELEASE_COMMIT
        if ($envCommit -match '^[a-fA-F0-9]{40}$') {
            return $envCommit.ToLowerInvariant()
        }
        Write-WindoBootstrapStep -Status warn -Label "WINDO_RELEASE_COMMIT invalid" -Detail "Falling back to branch '$($env:WINDO_TRACKING_BRANCH)'." -Color Yellow
    }
    if ($null -ne $script:_windo_bootstrap_release_ref) { return $script:_windo_bootstrap_release_ref }

    $branch = Get-WindoBootstrapReleaseBranch
    try {
        $uri = "https://api.github.com/repos/l28bit/windo/commits/$branch"
        $resp = Invoke-WindoBootstrapWebRequest -Uri $uri -TimeoutSec 25 -UseBasicParsing
        $obj = $resp.Content | ConvertFrom-Json -ErrorAction Stop
        if ($obj.sha) {
            $script:_windo_bootstrap_release_ref = [string]$obj.sha
            return $script:_windo_bootstrap_release_ref
        }
    } catch {
        Write-WindoBootstrapStep -Status warn -Label "Release ref resolution failed" -Detail "Falling back to branch '$branch'." -Color Yellow
    }

    $script:_windo_bootstrap_release_ref = $branch
    return $branch
}

function ConvertFrom-WindoBootstrapBool {
    param([string]$Name, [bool]$Default = $false)
    $raw = [string](Get-Item -Path "Env:$Name" -ErrorAction SilentlyContinue).Value
    if ([string]::IsNullOrWhiteSpace($raw)) { return $Default }
    switch ($raw.Trim().ToLowerInvariant()) {
        '1' { return $true }
        'true' { return $true }
        'yes' { return $true }
        'on' { return $true }
        '0' { return $false }
        'false' { return $false }
        'no' { return $false }
        'off' { return $false }
        default { return $Default }
    }
}

function Invoke-WindoBootstrapWebRequest {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [int]$TimeoutSec = 25,
        [switch]$UseBasicParsing,
        [string]$OutFile
    )
    if ($null -ne $OutFile) {
        Invoke-WebRequest -Uri $Uri -UseBasicParsing:$UseBasicParsing -TimeoutSec $TimeoutSec -OutFile $OutFile -ErrorAction Stop
    } else {
        Invoke-WebRequest -Uri $Uri -UseBasicParsing:$UseBasicParsing -TimeoutSec $TimeoutSec -ErrorAction Stop
    }
}

function Invoke-WindoBootstrapRestMethod {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [int]$TimeoutSec = 35,
        [string]$OutFile
    )
    if ($null -ne $OutFile) {
        Invoke-RestMethod -Uri $Uri -OutFile $OutFile -TimeoutSec $TimeoutSec -ErrorAction Stop
    } else {
        Invoke-RestMethod -Uri $Uri -TimeoutSec $TimeoutSec -ErrorAction Stop
    }
}

function Start-WindoBootstrapProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string]$Verb = $null,
        [object]$ArgumentList = $null,
        [switch]$Wait,
        [switch]$PassThru,
        [string]$ErrorAction = "Stop"
    )
    $common = @{
        FilePath = $FilePath
        Wait = $Wait
        ErrorAction = $ErrorAction
        PassThru = $PassThru.IsPresent
    }
    if ([string]::IsNullOrWhiteSpace($Verb)) {
        if ($null -eq $ArgumentList) {
            return Start-Process @common
        }
        $common.ArgumentList = $ArgumentList
        return Start-Process @common
    }

    $common.Verb = $Verb
    if ($null -ne $ArgumentList) {
        $common.ArgumentList = $ArgumentList
    }
    return Start-Process @common
}

function Get-WindoBootstrapFileHash {
    param([Parameter(Mandatory = $true)][string]$Path)
    (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function _windo_bootstrap_is_retryable_web_error {
    param([System.Management.Automation.ErrorRecord]$ErrorRecord)
    if ($null -eq $ErrorRecord) { return $false }
    $m = $ErrorRecord.Exception.Message
    if ($m -match 'timeout|timed out|name resolution|Could not establish trust relationship|name not known|No such host|connection was aborted|The remote name could not be resolved') { return $true }
    $resp = $ErrorRecord.Exception.Response
    if ($null -ne $resp) {
        try {
            $code = [int]$resp.StatusCode
            return ($code -in @(429, 500, 502, 503, 504))
        } catch { }
    }
    return $false
}

function Get-WindoBootstrapRuntimeProfile {
    $platform = $null
    try { $platform = [System.Environment]::OSVersion.Platform } catch {}

    $osVersion = $null
    try { $osVersion = [System.Environment]::OSVersion.Version } catch {}

    $psVersion = $null
    try { $psVersion = [version]$PSVersionTable.PSVersion } catch {}

    $languageMode = "Unknown"
    try { $languageMode = $ExecutionContext.SessionState.LanguageMode.ToString() } catch {}

    return [pscustomobject]@{
        IsWindows = ($platform -eq [System.PlatformID]::Win32NT)
        IsWindows10OrLater = if ($null -ne $osVersion) { $osVersion.Major -ge 10 } else { $false }
        IsPowerShellSupported = if ($null -ne $psVersion) { $psVersion -ge [version]'5.1' } else { $false }
        PowerShellVersion = if ($null -ne $psVersion) { $psVersion.ToString() } else { "unknown" }
        LanguageMode = $languageMode
        SupportsBackgroundJobs = [bool](Get-Command Start-Job -ErrorAction SilentlyContinue)
        SupportsWebCmdlets = ($null -ne (Get-Command Invoke-WebRequest -ErrorAction SilentlyContinue)) -and ($null -ne (Get-Command Invoke-RestMethod -ErrorAction SilentlyContinue))
    }
}

function Test-WindoBootstrapHostCompatibility {
    $profile = Get-WindoBootstrapRuntimeProfile

    Write-WindoBootstrapStep -Status run -Label "Runtime compatibility" -Detail "PS $($profile.PowerShellVersion) on Windows $($profile.IsWindows10OrLater)"

    if (-not $profile.IsWindows) {
        throw "WINDO bootstrap requires Windows."
    }
    if (-not $profile.IsWindows10OrLater) {
        throw "WINDO bootstrap requires Windows 10 or newer."
    }
    if (-not $profile.IsPowerShellSupported) {
        throw "WINDO bootstrap requires PowerShell 5.1+."
    }
    if (-not $profile.SupportsWebCmdlets) {
        throw "Required web cmdlets are unavailable in this session."
    }

    $script:WindoBootstrapSupportsBackgroundJobs = $profile.SupportsBackgroundJobs
    if (-not $script:WindoBootstrapSupportsBackgroundJobs) {
        Write-WindoBootstrapStep -Status warn -Label "Background jobs unavailable" -Detail "Falling back to inline download without spinner."
    }

    if ($profile.LanguageMode -ne "FullLanguage") {
        Write-WindoBootstrapStep -Status warn -Label "Constrained host detected" -Detail "Dynamic language mode is not FullLanguage; some advanced tooling paths may be restricted."
    } else {
        Write-WindoBootstrapStep -Status ok -Label "Language mode" -Detail "FullLanguage" -Color Green
    }

    return $profile
}

function Get-WindoBootstrapManifestValue([string]$Text, [string]$Key) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    if ([string]::IsNullOrWhiteSpace($Key)) { return $null }

    $want = $Key.Trim()
    foreach ($line in ($Text -split "`r?`n")) {
        $trim = [string]$line.Trim()
        if ([string]::IsNullOrWhiteSpace($trim) -or $trim.StartsWith("#")) { continue }
        $equal = $trim.IndexOf("=")
        if ($equal -lt 0) { continue }
        $name = $trim.Substring(0, $equal).Trim()
        if ($name -ieq $want) {
            $raw = $trim.Substring($equal + 1).Trim()
            if ([string]::IsNullOrWhiteSpace($raw)) { return $null }

            $hashIndex = $raw.IndexOf("#")
            if ($hashIndex -ge 0) { $raw = $raw.Substring(0, $hashIndex).Trim() }
            if ([string]::IsNullOrWhiteSpace($raw)) { return $null }

            $len = $raw.Length
            if ($len -ge 2 -and (($raw[0] -eq '"' -and $raw[$len - 1] -eq '"') -or ($raw[0] -eq "'" -and $raw[$len - 1] -eq "'")) ) {
                $raw = $raw.Substring(1, $len - 2)
            }

            return $raw.Trim()
        }
    }
    return $null
}

function Get-WindoBootstrapReleaseMetadata([string]$Text) {
    $releaseCommitRaw = Get-WindoBootstrapManifestValue -Text $Text -Key "releaseCommit"
    $releaseBranchRaw = Get-WindoBootstrapManifestValue -Text $Text -Key "releaseBranch"

    $normalizedCommit = if ($releaseCommitRaw -match '^[a-fA-F0-9]{40,64}$') { $releaseCommitRaw.ToLowerInvariant() } else { $null }
    $normalizedBranch = if ($releaseBranchRaw -match '^[A-Za-z0-9._-]{1,64}$') { $releaseBranchRaw } else { $null }

    return [pscustomobject]@{
        releaseCommit = $normalizedCommit
        releaseCommitRaw = $releaseCommitRaw
        releaseBranch = $normalizedBranch
        releaseBranchRaw = $releaseBranchRaw
    }
}

function Get-WindoBootstrapReleaseMetadataState {
    param(
        [string]$ReleaseRef,
        [string]$ReleaseCommit,
        [string]$ReleaseCommitRaw,
        [string]$ReleaseBranch
    )
    $resolvedCommit = $ReleaseRef.ToLowerInvariant()
    if ($resolvedCommit -match '^[a-fA-F0-9]{40}$') {
        if ($ReleaseCommit -notmatch '^[a-fA-F0-9]{40,64}$') {
            $raw = if ([string]::IsNullOrWhiteSpace($ReleaseCommitRaw)) { $null } else { $ReleaseCommitRaw }
            return [pscustomobject]@{ CompatibilityMode = $true; Detail = "manifest releaseCommit is missing or invalid (received '$raw') while release ref is commit $resolvedCommit." }
        }
        if ($ReleaseCommit -ine $resolvedCommit) {
            return [pscustomobject]@{ CompatibilityMode = $true; Detail = "manifest releaseCommit=$ReleaseCommit does not match resolved release commit=$resolvedCommit." }
        }
        return [pscustomobject]@{ CompatibilityMode = $false; Detail = $null }
    }

    $resolvedBranch = Get-WindoBootstrapReleaseBranch
    if ([string]::IsNullOrWhiteSpace($ReleaseBranch)) {
        return [pscustomobject]@{ CompatibilityMode = $true; Detail = "resolved release ref is branch '$resolvedBranch', but checksum manifest did not include releaseBranch metadata." }
    }
    if ($ReleaseBranch -ine $resolvedBranch) {
        return [pscustomobject]@{ CompatibilityMode = $true; Detail = "manifest releaseBranch=$ReleaseBranch does not match resolved branch=$resolvedBranch." }
    }

    return [pscustomobject]@{ CompatibilityMode = $true; Detail = "resolved release ref is branch '$resolvedBranch' (compatibility mode)." }
}

$script:_windo_bootstrap_retry_ms = @(350, 900, 2200)

$Temp = Join-Path $env:TEMP ("windo_install_" + [Guid]::NewGuid().ToString("n") + ".ps1")

function Write-WindoBootstrapBanner {
    Write-Host ""
    Write-Host "  __        _____ _   _ ____   ___" -ForegroundColor Cyan
    Write-Host "  \ \      / /_ _| \ | |  _ \ / _ \" -ForegroundColor Cyan
    Write-Host "   \ \ /\ / / | ||  \| | | | | | | |" -ForegroundColor Cyan
    Write-Host "    \ V  V /  | || |\  | |_| | |_| |" -ForegroundColor Cyan
    Write-Host "     \_/\_/  |___|_| \_|____/ \___/" -ForegroundColor Cyan
    Write-Host ""
    Write-Host ("  WINDO {0} {1} bootstrap" -f $script:WindoBootstrapExpectedVersion, (Get-WindoEditionLabel)) -ForegroundColor White
    Write-Host "  API-first verified download | UAC handoff | Windows integration plane" -ForegroundColor DarkGray
    Write-Host ""
}

function Write-WindoBootstrapStep {
    param(
        [Parameter(Mandatory)][string]$Status,
        [Parameter(Mandatory)][string]$Label,
        [string]$Detail = "",
        [ConsoleColor]$Color = [ConsoleColor]::Cyan
    )
    $mark = switch ($Status.ToLowerInvariant()) {
        "ok" { "[OK]" }
        "warn" { "[!!]" }
        "run" { "[..]" }
        default { "[**]" }
    }
    Write-Host ("  {0} {1}" -f $mark, $Label) -ForegroundColor $Color
    if (-not [string]::IsNullOrWhiteSpace($Detail)) {
        Write-Host ("       {0}" -f $Detail) -ForegroundColor DarkGray
    }
}

function Get-WindoBootstrapFileBlobSha1 {
    param([Parameter(Mandatory)][string]$Path)
    $raw = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path))
    $header = [System.Text.Encoding]::ASCII.GetBytes("blob $($raw.Length)`0")
    $blobBytes = New-Object byte[] ($header.Length + $raw.Length)
    [System.Buffer]::BlockCopy($header, 0, $blobBytes, 0, $header.Length)
    [System.Buffer]::BlockCopy($raw, 0, $blobBytes, $header.Length, $raw.Length)
    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    try {
        ($sha1.ComputeHash($blobBytes) | ForEach-Object { $_.ToString("X2") }) -join ""
    } finally {
        $sha1.Dispose()
    }
}

function Test-WindoBootstrapSpinnerEnabled {
    if (-not $script:WindoBootstrapSupportsBackgroundJobs) { return $false }
    if (ConvertFrom-WindoBootstrapBool -Name WINDO_NO_SPINNER) { return $false }
    if (ConvertFrom-WindoBootstrapBool -Name CI) { return $false }
    try {
        if ([Console]::IsOutputRedirected) { return $false }
    } catch {
        return $false
    }
    return $true
}

function Clear-WindoBootstrapSpinnerLine([int]$Width) {
    if (-not (Test-WindoBootstrapSpinnerEnabled)) { return }
    $w = [Math]::Max(20, [Math]::Min($Width, 120))
    [Console]::Write("`r$(' ' * $w)`r")
}

function Write-WindoBootstrapSpinnerLine([string]$Label, [int]$Frame) {
    if (-not (Test-WindoBootstrapSpinnerEnabled)) { return }
    $frames = @('|', '/', '-', '\')
    $c = $frames[$Frame % $frames.Length]
    [Console]::Write("`r${Label} ${c} ")
}

function Invoke-WindoBootstrapDownload {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$OutFile,
        [Parameter(Mandatory)][string]$Label
    )
    $baseLabel = "[windo] $Label"

    if (-not (Test-WindoBootstrapSpinnerEnabled)) {
        Write-Host $baseLabel -ForegroundColor DarkCyan
        Invoke-WindoBootstrapRestMethod -Uri $Uri -OutFile $OutFile
        return
    }

    $job = $null
    try {
        $job = Start-Job -ScriptBlock {
            param($u, $o)
            $ErrorActionPreference = "Stop"
            Invoke-WindoBootstrapRestMethod -Uri $u -OutFile $o
        } -ArgumentList $Uri, $OutFile
    } catch {
        $job = $null
    }

    if ($null -eq $job) {
        Write-Host $baseLabel -ForegroundColor DarkCyan
        Invoke-WindoBootstrapRestMethod -Uri $Uri -OutFile $OutFile
        return
    }

    $frame = 0
    while ((Get-Job -Id $job.Id -ErrorAction SilentlyContinue).State -eq "Running") {
        Write-WindoBootstrapSpinnerLine $baseLabel $frame
        $frame = ($frame + 1) % 4
        Start-Sleep -Milliseconds 100
    }

    Clear-WindoBootstrapSpinnerLine ($baseLabel.Length + 4)

    try {
        Receive-Job $job -ErrorAction Stop | Out-Null
    } catch {
        Remove-Job $job -Force -ErrorAction SilentlyContinue
        throw
    }
    Remove-Job $job -Force -ErrorAction SilentlyContinue
}

function Get-WindoBootstrapInstallerRawUrl {
    "https://raw.githubusercontent.com/l28bit/windo/$((Get-WindoBootstrapReleaseRef))/windo_install.ps1"
}

function Get-WindoBootstrapInstallerApiUrl {
    "https://api.github.com/repos/l28bit/windo/contents/windo_install.ps1?ref=$((Get-WindoBootstrapReleaseRef))"
}

function Save-WindoBootstrapPublishedInstaller {
    param([Parameter(Mandatory)][string]$OutFile)

    $apiUrl = Get-WindoBootstrapInstallerApiUrl
    $apiError = $null

    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            $api = Invoke-WindoBootstrapWebRequest -Uri $apiUrl -TimeoutSec 35 -UseBasicParsing
            $obj = $api.Content | ConvertFrom-Json -ErrorAction Stop
            if ($obj.content) {
                $bytes = [Convert]::FromBase64String(([string]$obj.content -replace '\s', ''))
                [IO.File]::WriteAllBytes($OutFile, $bytes)
                return [pscustomobject]@{
                    Source = "github-api"
                    Url = $apiUrl
                    Attempt = $attempt
                    BlobSha = if ($obj.sha) { [string]$obj.sha }
                }
            }
            throw "Installer API response did not contain content."
        } catch {
            $apiError = $_.Exception.Message
            if (-not (_windo_bootstrap_is_retryable_web_error $_) -or $attempt -ge 3) { break }
            Start-Sleep -Milliseconds $script:_windo_bootstrap_retry_ms[[Math]::Min($attempt - 1, 2)]
        }
    }

    $rawUrl = Get-WindoBootstrapInstallerRawUrl
    try {
        Invoke-WindoBootstrapDownload -Uri $rawUrl -OutFile $OutFile -Label "Downloading installer via raw fallback..."
        return [pscustomobject]@{ Source = "raw-fallback"; Url = $rawUrl; ApiError = $apiError; Attempt = 1; BlobSha = $null }
    } catch {
        throw "Published installer was not available. github-api: $apiError; raw: $($_.Exception.Message)"
    }
}

function Get-WindoBootstrapChecksumRawUrl {
    "https://raw.githubusercontent.com/l28bit/windo/$((Get-WindoBootstrapReleaseRef))/checksums/installer.sha256"
}

function Get-WindoBootstrapChecksumApiUrl {
    "https://api.github.com/repos/l28bit/windo/contents/checksums/installer.sha256?ref=$((Get-WindoBootstrapReleaseRef))"
}

function Get-WindoBootstrapNormalizedPublishedChecksum([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $candidates = [System.Collections.Generic.List[string]]::new()

    foreach ($line in ($Text -split "`r?`n")) {
        $trim = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trim) -or $trim.StartsWith("#")) { continue }

        if ($trim -match '^(?<key>[^=]+?)\s*=\s*(?<value>[A-Fa-f0-9]{64})$') {
            if ($matches.key -ieq "installerSha256") {
                return $matches.value.ToUpperInvariant()
            }
            continue
        }

        if ($trim -match '^[^=]+?=([A-Fa-f0-9]{64})$') {
            $null = $candidates.Add($matches[1].ToUpperInvariant())
            continue
        }
        if ($trim -match '^([A-Fa-f0-9]{64})\s*$') {
            $null = $candidates.Add($matches[1].ToUpperInvariant())
            continue
        }
        if ($trim -match '^([A-Fa-f0-9]{64})\s+\S+$') {
            $null = $candidates.Add($matches[1].ToUpperInvariant())
            continue
        }
        if ($trim -match '^\S+\s+([A-Fa-f0-9]{64})$') {
            $null = $candidates.Add($matches[1].ToUpperInvariant())
            continue
        }

        if ($trim -match '[A-Fa-f0-9]{64}') { return $null }
    }

    if ($candidates.Count -eq 1) { return $candidates[0] }
    return $null
}

function Get-WindoBootstrapParsedChecksumPayload([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $meta = Get-WindoBootstrapReleaseMetadata $Text
    return [pscustomobject]@{
        sha256 = Get-WindoBootstrapNormalizedPublishedChecksum $Text
        releaseCommit = $meta.releaseCommit
        releaseCommitRaw = $meta.releaseCommitRaw
        releaseBranch = $meta.releaseBranch
        releaseBranchRaw = $meta.releaseBranchRaw
    }
}

function Get-WindoBootstrapVersionedPublishedChecksum([string]$Version) {
    if ([string]::IsNullOrWhiteSpace($Version)) { return $null }
    $trimVersion = $Version.Trim()
    if (-not ($trimVersion -match '^\d+\.\d+\.\d+$')) { return $null }

    $rawUrl = "https://raw.githubusercontent.com/l28bit/windo/v$trimVersion/checksums/installer.sha256"
    $apiError = $null

    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            $resp = Invoke-WindoBootstrapWebRequest -Uri $rawUrl -TimeoutSec 25 -UseBasicParsing
            if ($null -ne $resp.Content) {
                return Get-WindoBootstrapNormalizedPublishedChecksum ([string]$resp.Content)
            }
            throw "Versioned checksum raw response was empty."
        } catch {
            $apiError = $_.Exception.Message
            if (-not (_windo_bootstrap_is_retryable_web_error $_) -or $attempt -ge 3) {
                return $null
            }
            Start-Sleep -Milliseconds $script:_windo_bootstrap_retry_ms[[Math]::Min($attempt - 1, 2)]
        }
    }

    if ($apiError) {
        Write-WindoBootstrapStep -Status warn -Label "Versioned checksum check failed" -Detail $apiError -Color Yellow
    }
    return $null
}

function Get-WindoBootstrapPublishedChecksum {
    $apiUrl = Get-WindoBootstrapChecksumApiUrl
    $releaseRef = Get-WindoBootstrapReleaseRef
    $releaseBranch = Get-WindoBootstrapReleaseBranch
    $requestedType = if ($env:WINDO_RELEASE_COMMIT -and [string]$env:WINDO_RELEASE_COMMIT -match '^[a-fA-F0-9]{40}$') { "commit" } else { "branch" }
    $requestedRef = if ($requestedType -eq "commit") { [string]$env:WINDO_RELEASE_COMMIT } else { $releaseBranch }
    $sourceReleaseBranch = if ($releaseRef -match '^[a-fA-F0-9]{40}$') { $releaseBranch } else { $releaseRef }
    $apiError = $null

    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            $api = Invoke-WindoBootstrapWebRequest -Uri $apiUrl -TimeoutSec 25 -UseBasicParsing
            $obj = $api.Content | ConvertFrom-Json -ErrorAction Stop
            if ($obj.content) {
                $contentText = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(([string]$obj.content -replace '\s', '')))
                $payload = Get-WindoBootstrapParsedChecksumPayload $contentText
                $sha = $payload.sha256
                $releaseCommit = $payload.releaseCommit
                $releaseBranch = $payload.releaseBranch
                $blobSha = if ($obj.sha) { [string]$obj.sha } else { $null }
                $metadataState = Get-WindoBootstrapReleaseMetadataState -ReleaseRef $releaseRef -ReleaseCommit $releaseCommit -ReleaseCommitRaw $payload.releaseCommitRaw -ReleaseBranch $payload.releaseBranch
                if ($sha) {
                    return [pscustomobject]@{
                        status = "available"
                        source = "github-api"
                        url = $apiUrl
                        sha256 = $sha
                        blobSha = $blobSha
                        requestedRef = $requestedRef
                        requestedType = $requestedType
                        releaseRef = $releaseRef
                        releaseBranch = $payload.releaseBranch
                        sourceReleaseRef = $releaseRef
                        sourceReleaseBranch = $sourceReleaseBranch
                        compatibilityMode = $metadataState.CompatibilityMode
                        compatibilityReason = $metadataState.Detail
                        releaseCommit = $payload.releaseCommit
                        releaseCommitRaw = $payload.releaseCommitRaw
                        releaseBranchRaw = $payload.releaseBranchRaw
                        error = $null
                    }
                }
                return [pscustomobject]@{
                    status = "invalid"
                    source = "github-api"
                    url = $apiUrl
                    sha256 = $null
                    blobSha = $blobSha
                    requestedRef = $requestedRef
                    requestedType = $requestedType
                    releaseRef = $releaseRef
                    releaseBranch = $payload.releaseBranch
                    sourceReleaseRef = $releaseRef
                    sourceReleaseBranch = $sourceReleaseBranch
                    compatibilityMode = $metadataState.CompatibilityMode
                    compatibilityReason = $metadataState.Detail
                    releaseCommit = $payload.releaseCommit
                    releaseCommitRaw = $payload.releaseCommitRaw
                    releaseBranchRaw = $payload.releaseBranchRaw
                    error = "published checksum payload was present but did not contain a valid SHA256"
                }
                throw "Published checksum payload was present but did not contain a valid SHA256."
            }
            throw "Published checksum API response was empty."
        } catch {
            if (-not (_windo_bootstrap_is_retryable_web_error $_) -or $attempt -ge 3) {
                $apiError = $_.Exception.Message
                break
            }
            Start-Sleep -Milliseconds $script:_windo_bootstrap_retry_ms[[Math]::Min($attempt - 1, 2)]
        }
    }

    $rawUrl = Get-WindoBootstrapChecksumRawUrl
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            $wr = Invoke-WindoBootstrapWebRequest -Uri $rawUrl -TimeoutSec 25 -UseBasicParsing
            if ($null -ne $wr.Content) {
                $payload = Get-WindoBootstrapParsedChecksumPayload ([string]$wr.Content)
                $sha = $payload.sha256
                $releaseCommit = $payload.releaseCommit
                $releaseBranch = $payload.releaseBranch
                $metadataState = Get-WindoBootstrapReleaseMetadataState -ReleaseRef $releaseRef -ReleaseCommit $releaseCommit -ReleaseCommitRaw $payload.releaseCommitRaw -ReleaseBranch $payload.releaseBranch
                if ($sha) {
                    return [pscustomobject]@{
                        status = "available"
                        source = "raw-fallback"
                        url = $rawUrl
                        sha256 = $sha
                        blobSha = $null
                        requestedRef = $requestedRef
                        requestedType = $requestedType
                        releaseRef = $releaseRef
                        releaseBranch = $payload.releaseBranch
                        sourceReleaseRef = $releaseRef
                        sourceReleaseBranch = $sourceReleaseBranch
                        compatibilityMode = $metadataState.CompatibilityMode
                        compatibilityReason = $metadataState.Detail
                        releaseCommit = $payload.releaseCommit
                        releaseCommitRaw = $payload.releaseCommitRaw
                        releaseBranchRaw = $payload.releaseBranchRaw
                        error = $null
                    }
                }
                return [pscustomobject]@{
                    status = "invalid"
                    source = "raw-fallback"
                    url = $rawUrl
                    sha256 = $null
                    blobSha = $null
                    requestedRef = $requestedRef
                    requestedType = $requestedType
                    releaseRef = $releaseRef
                    releaseBranch = $payload.releaseBranch
                    sourceReleaseRef = $releaseRef
                    sourceReleaseBranch = $sourceReleaseBranch
                    compatibilityMode = $metadataState.CompatibilityMode
                    compatibilityReason = if ($metadataState.Detail) { $metadataState.Detail } else { "published checksum payload did not include a valid SHA256." }
                    releaseCommit = $payload.releaseCommit
                    releaseCommitRaw = $payload.releaseCommitRaw
                    releaseBranchRaw = $payload.releaseBranchRaw
                    error = "Published checksum payload was present but did not contain a valid SHA256."
                }
            }
            throw "Published checksum raw response was empty."
        } catch {
            if (-not (_windo_bootstrap_is_retryable_web_error $_) -or $attempt -ge 3) { break }
            Start-Sleep -Milliseconds $script:_windo_bootstrap_retry_ms[[Math]::Min($attempt - 1, 2)]
        }
    }

    if ($apiError) {
        Write-WindoBootstrapStep -Status warn -Label "Checksum source check failed" -Detail $apiError -Color Yellow
    }
    return [pscustomobject]@{
        status = "unavailable"
        source = "none"
        url = $rawUrl
        sha256 = $null
        blobSha = $null
        requestedRef = $requestedRef
        requestedType = $requestedType
        releaseRef = $releaseRef
        releaseBranch = $releaseBranch
        sourceReleaseRef = $releaseRef
        sourceReleaseBranch = $sourceReleaseBranch
        compatibilityMode = $false
        compatibilityReason = $apiError
        releaseCommit = "unknown"
        releaseCommitRaw = "unknown"
        releaseBranchRaw = $sourceReleaseBranch
        error = $apiError
    }
}

function Start-WindoBootstrapInstaller {
    param(
        [Parameter(Mandatory)][string]$ScriptPath
    )

    $runnerExe = "powershell.exe"
    try {
        $pwshExe = Get-Command pwsh.exe -ErrorAction SilentlyContinue
        if ($pwshExe -and $pwshExe.Source) { $runnerExe = $pwshExe.Source }
    } catch {}

    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ScriptPath)
    $ciMode = ConvertFrom-WindoBootstrapBool -Name CI -Default $false
    $shouldElevate = [Environment]::UserInteractive -and -not $ciMode

    if ($shouldElevate) {
        Write-Host "[windo] Requesting elevation for installer..." -ForegroundColor Cyan
        try {
            $installerProcess = Start-WindoBootstrapProcess -FilePath $runnerExe -Verb RunAs -ArgumentList $argList -Wait -PassThru
            return [int]($installerProcess.ExitCode)
        } catch [System.ComponentModel.Win32Exception] {
            if ($_.Exception.NativeErrorCode -eq 1223) {
                Write-Host "[windo] Installer launch was blocked: UAC consent was denied." -ForegroundColor Yellow
                Write-Host "  Recovery one-liners:" -ForegroundColor Yellow
                Write-Host "    Start-Process pwsh.exe -Verb RunAs -ArgumentList '-NoProfile','-Command','windo install-latest'" -ForegroundColor DarkGray
                Write-Host "    Start-Process pwsh.exe -Verb RunAs -ArgumentList '-NoProfile','-Command','windo self-update'" -ForegroundColor DarkGray
                return 1223
            }
            throw
        }
    }

    Write-Host "[windo] Running installer without elevation (non-interactive/CI mode)." -ForegroundColor Cyan
    & $runnerExe @argList
    if ($LASTEXITCODE -is [int]) {
        return [int]$LASTEXITCODE
    }
    return 0
}

Write-WindoBootstrapBanner
try {
    $script:WindoBootstrapRuntime = Test-WindoBootstrapHostCompatibility
} catch {
    Write-Host "WINDO bootstrap cannot proceed in this environment." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Set-WindoBootstrapExitCode 1
    exit $global:WINDO_EXIT_CODE
}

if (Test-WindoBootstrapProcessElevated) {
    Write-Host ""
    Write-Host "WINDO bootstrap is disabled in elevated shells." -ForegroundColor Yellow
    Write-Host "  Open a normal (non-elevated) PowerShell window and run the bootstrap one-liner again." -ForegroundColor DarkGray
    Write-Host "  After a verified download, you will be asked to approve the installer handoff." -ForegroundColor DarkGray
    Write-Host ""
    Set-WindoBootstrapExitCode 1
    exit $global:WINDO_EXIT_CODE
}

 $bootstrapExitCode = 0
try {

    Write-WindoBootstrapStep -Status run -Label "Downloading installer" -Detail "GitHub API first, raw fallback"
        $downloadSource = Save-WindoBootstrapPublishedInstaller -OutFile $Temp
    Write-WindoBootstrapStep -Status ok -Label "Installer source" -Detail "$($downloadSource.Source): $($downloadSource.Url)" -Color Green
            $releaseBranch = Get-WindoBootstrapReleaseBranch

    if (!(Test-Path $Temp)) {
        throw "Installer download failed or was blocked. Confirm network access to GitHub endpoints, then re-run bootstrap."
    }

    if (-not (ConvertFrom-WindoBootstrapBool -Name WINDO_SKIP_INSTALLER_SHA256)) {
        Write-WindoBootstrapStep -Status run -Label "Verifying installer checksum" -Detail "published checksums/installer.sha256 (GitHub API, raw fallback)"
        $strictMode = ConvertFrom-WindoBootstrapBool -Name WINDO_STRICT_INSTALLER_VERIFICATION -Default $false
        $expected = Get-WindoBootstrapPublishedChecksum
        $releaseBranch = Get-WindoBootstrapReleaseBranch
        $releaseRef = Get-WindoBootstrapReleaseRef
        try {
            if ($null -eq $expected -or $expected.status -ne "available" -or -not $expected.sha256) {
                if ($strictMode) {
                    $detail = if ($null -ne $expected -and $expected.error) { $expected.error } else { "published checksum was unavailable" }
                    throw "Installer SHA256 cannot be validated against a verifiable published source in strict mode. Check network/API access and branch state, then re-run. Temporary override: WINDO_SKIP_INSTALLER_SHA256=1. $detail"
                }
                Write-WindoBootstrapStep -Status warn -Label "Checksum verification delayed" -Detail "Could not retrieve a parseable published checksum now; continuing in compatibility mode." -Color Yellow
            } else {
                $expectedSha = [string]$expected.sha256
$got = Get-WindoBootstrapFileHash -Path $Temp
                if ($got -cne $expectedSha) {
                    $blobSha = if ($downloadSource.BlobSha) { [string]$downloadSource.BlobSha } else { $null }
                    if (-not [string]::IsNullOrWhiteSpace($blobSha)) {
                        $gotBlob = Get-WindoBootstrapFileBlobSha1 -Path $Temp
                        if ($gotBlob -ieq $blobSha.ToUpperInvariant()) {
                            Write-WindoBootstrapStep -Status warn -Label "Checksum drift tolerated" -Detail "Installer blob SHA1 matches GitHub object $blobSha (continuing)." -Color Yellow
                            Write-WindoBootstrapStep -Status ok -Label "Checksum accepted" -Color Green
                            $expected = $null
                        }
                    }

                    if ($null -ne $expected) {
                        $installerText = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($Temp))
                        $version = if ($installerText -match '\$WindoVersion\s*=\s*"(?<v>\d+\.\d+\.\d+)"') { $matches.v } else { $null }
                        $snapshot = if ($version) { Get-WindoBootstrapVersionedPublishedChecksum -Version $version } else { $null }
                        if ($null -ne $snapshot -and $got -ieq $snapshot) {
                            Write-WindoBootstrapStep -Status warn -Label "Checksum drift tolerated" -Detail "SHA256 matches checksums/installer.sha256 snapshot for v$version on branch $releaseBranch. Continuing in compatibility mode." -Color Yellow
                            $expected = $null
                        } else {
                $releaseCommit = if ($null -ne $expected -and $expected.PSObject.Properties.Name -contains "releaseCommit") { [string]$expected.releaseCommit } else { $null }
                $releaseCommitRaw = if ($null -ne $expected -and $expected.PSObject.Properties.Name -contains "releaseCommitRaw") { [string]$expected.releaseCommitRaw } else { $null }
                $releaseBranch = if ($null -ne $expected -and $expected.PSObject.Properties.Name -contains "releaseBranch") { [string]$expected.releaseBranch } else { $null }
                $metadataState = Get-WindoBootstrapReleaseMetadataState -ReleaseRef $releaseRef -ReleaseCommit $releaseCommit -ReleaseCommitRaw $releaseCommitRaw -ReleaseBranch $releaseBranch
                if ($metadataState.CompatibilityMode) {
                    if ($strictMode) {
                        throw "Installer SHA256 does not match published checksum for ref $releaseRef. $($metadataState.Detail) Expected=$expectedSha Got=$got. Verify branch pins and manifest provenance before continuing."
                    }
                    Write-WindoBootstrapStep -Status warn -Label "Checksum drift tolerated" -Detail "$($metadataState.Detail) Continuing in compatibility mode." -Color Yellow
                    Write-WindoBootstrapStep -Status ok -Label "Checksum accepted" -Color Green
                    $expected = $null
                } elseif ($null -ne $expected) {
                    throw "Installer SHA256 does not match published checksum. Confirm manifest and release provenance before continuing. Temporary override: WINDO_SKIP_INSTALLER_SHA256=1 or WINDO_STRICT_INSTALLER_VERIFICATION=0. Expected=$expectedSha Got=$got"
                }
                        }
                    }
                }
            }
        } catch {
            if ($_.Exception.Message -match 'does not match') { throw }
        }
        Write-WindoBootstrapStep -Status ok -Label "Checksum accepted" -Color Green
    } else {
        Write-WindoBootstrapStep -Status warn -Label "Checksum verification skipped" -Detail "WINDO_SKIP_INSTALLER_SHA256 is set" -Color Yellow
    }

    $size = (Get-Item $Temp).Length
    if ($size -lt 5000) {
        throw "Installer file size is too small ($size bytes), likely truncated or tampered. Retry bootstrap from a trusted network path."
    }

    Write-WindoBootstrapStep -Status ok -Label "Installer ready" -Detail $Temp -Color Green
    $doLaunch = $false
    $bootstrapForceInstall = ConvertFrom-WindoBootstrapBool -Name WINDO_BOOTSTRAP_FORCE_INSTALL
    $bootstrapAutoLaunch = ConvertFrom-WindoBootstrapBool -Name WINDO_INSTALL_NONINTERACTIVE
    $ciAutoMode = ConvertFrom-WindoBootstrapBool -Name CI
    if ($bootstrapAutoLaunch -or $bootstrapForceInstall -or $ciAutoMode) {
        $doLaunch = $true
        Write-Host "[windo] Proceeding without prompt (CI or WINDO_BOOTSTRAP_FORCE_INSTALL or WINDO_INSTALL_NONINTERACTIVE)." -ForegroundColor DarkGray
    } elseif ([Environment]::UserInteractive) {
        $ans = Read-Host "Launch the installer now? (UAC may prompt for elevation.) [y/N]"
        if ($ans -eq 'y' -or $ans -eq 'Y' -or $ans -eq 'yes') { $doLaunch = $true }
    } else {
        Write-Host "[windo] Non-interactive shell: set WINDO_BOOTSTRAP_FORCE_INSTALL=1 or WINDO_INSTALL_NONINTERACTIVE=1 to launch after download, or run interactively." -ForegroundColor Yellow
        throw "Bootstrap: non-interactive without WINDO_BOOTSTRAP_FORCE_INSTALL or WINDO_INSTALL_NONINTERACTIVE"
    }

    if (-not $doLaunch) {
        Write-Host "[windo] Cancelled; removing temporary installer." -ForegroundColor DarkYellow
        Remove-Item -LiteralPath $Temp -Force -ErrorAction SilentlyContinue
        Set-WindoBootstrapExitCode 0
        exit $global:WINDO_EXIT_CODE
    }

    Write-WindoBootstrapStep -Status run -Label "Launching installer" -Detail "UAC may prompt for elevation"
    $installerExitCode = Start-WindoBootstrapInstaller -ScriptPath $Temp
    if ($installerExitCode -eq 1223) {
        Write-Host "[windo] Installer launch was declined. Bootstrap install was not applied." -ForegroundColor Yellow
        Write-Host "  Approve UAC for this command, or rerun this same bootstrap command from an elevated PowerShell session after verifying command trust." -ForegroundColor DarkGray
        Set-WindoBootstrapExitCode 2
    } elseif ($installerExitCode -ne 0) {
        Write-Host "[windo] Installer completed with exit code $installerExitCode. Check command output for details." -ForegroundColor Yellow
        Set-WindoBootstrapExitCode $installerExitCode
    }

}
catch {
    Write-Host ""
    Write-Host "WINDO bootstrap failed:" -ForegroundColor Red
    Write-Host $_
    Set-WindoBootstrapExitCode 1
}
finally {

    if (Test-Path -LiteralPath $Temp) {
        Remove-Item -LiteralPath $Temp -Force -ErrorAction SilentlyContinue
    }

    Write-Host ""
    Write-Host "Bootstrap finished." -ForegroundColor Green
}

exit $global:WINDO_EXIT_CODE
