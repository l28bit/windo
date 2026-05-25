# Logic tests for shared snippets (no live WINDO profile). Run: ./tools/Test-WindoLogic.ps1
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root "src\windo\snippets\IntegrityLevels.ps1")
. (Join-Path $root "src\windo\snippets\StatsTimeFilter.ps1")
. (Join-Path $root "src\windo\snippets\WindoConfigEffective.ps1")
$PrefsFile = Join-Path ([IO.Path]::GetTempPath()) "windo-test-prefs.json"

$script:failed = 0
function Test-WindoNormalizePublishedInstallerSha256([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $m = [regex]::Match($Text, '[A-Fa-f0-9]{64}')
    if (-not $m.Success) { return $null }
    return $m.Value.ToUpperInvariant()
}
function Assert-Equal($a, $b, $msg) {
    if ($a -ne $b) {
        Write-Host "FAIL: $msg  (expected '$b', got '$a')" -ForegroundColor Red
        $script:failed += 1
    }
}

function Assert-Pattern([string]$Text, [string]$Pattern, [string]$msg) {
    if (-not [regex]::IsMatch($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)) {
        Write-Host "FAIL: $msg  (pattern not found: '$Pattern')" -ForegroundColor Red
        $script:failed += 1
    }
}

function New-VerifyLogLine([hashtable]$Entry, [string]$StoredHashOverride = $null) {
    $json = ($Entry | ConvertTo-Json -Compress)
    $storedHash = if ([string]::IsNullOrWhiteSpace($StoredHashOverride)) { _sha256_hex $json } else { $StoredHashOverride }
    return [pscustomobject]@{
        line = "$storedHash" + ":" + (_dpapi_protect $json)
        hash = $storedHash
        json = $json
    }
}

$expectedStateChecks = [System.Collections.Generic.List[pscustomobject]]::new()
function Assert-State([string]$Case, [object]$Expected, [object]$Actual, [string]$msg) {
    Assert-Equal $Actual $Expected $msg
    $expectedText = if ($null -eq $Expected) { "<null>" } else { [string]$Expected }
    $actualText = if ($null -eq $Actual) { "<null>" } else { [string]$Actual }
    $script:expectedStateChecks.Add([pscustomobject]@{
        Case = $Case
        Expected = $expectedText
        Actual = $actualText
        IsMatch = ($Expected -eq $Actual)
    })
}

function Parse-NameValueManifest([string]$Text) {
    $out = @{}
    if ($null -eq $Text) { return $out }
    $raw = [string]$Text
    if ($raw.Trim() -match '^[A-Fa-f0-9]{64}$') {
        $out.installerSha256 = $raw.Trim().ToUpperInvariant()
        return $out
    }
    foreach ($line in ($raw -split "`r?`n")) {
        $trim = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trim) -or $trim.StartsWith("#")) { continue }
        if ($trim -match '^(?<key>[^=]+?)=(?<value>.*)$') {
            $out[$Matches.key] = $Matches.value.Trim()
        }
    }
    return $out
}

function Get-WindoFunctionTextFromSource([string]$Source, [string]$Name) {
    try {
        $sources = @($Source)
        $matches = [regex]::Matches($Source, '(?s)\$WindoFunctionBody\s*=\s*@''\s*(.*?)\r?\n''@', [System.Text.RegularExpressions.RegexOptions]::Singleline)
        foreach ($m in $matches) {
            if ($m.Success -and -not [string]::IsNullOrWhiteSpace($m.Groups[1].Value)) {
                $sources += $m.Groups[1].Value
            }
        }

        foreach ($candidate in $sources) {
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($candidate, [ref]$null, [ref]$errors)
            $matches = $ast.FindAll(
                { param($Node) $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $Node.Name -eq $Name },
                $true
            )
            if ($matches -and $matches.Count -gt 0) { return $matches[0].Extent.Text }

            # Fallback for function definitions that are not captured through AST extraction
            # due inline parameter syntax or parser edge cases in mixed code contexts.
            $escapedName = [regex]::Escape($Name)
            $fnPattern = "(?ms)^\s*function\s+$escapedName(?:\s*\([^{]*\))?\s*\{"
            $m2 = [regex]::Match($candidate, $fnPattern)
            if ($m2.Success) {
                $tail = $candidate.Substring($m2.Index)
                $tailErrors = $null
                $tailAst = [System.Management.Automation.Language.Parser]::ParseInput($tail, [ref]$null, [ref]$tailErrors)
                $tailMatches = $tailAst.FindAll(
                    { param($Node) $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $Node.Name -eq $Name },
                    $true
                )
                if ($tailMatches -and $tailMatches.Count -gt 0) { return $tailMatches[0].Extent.Text }

                $start = $m2.Index
                $depth = 0
                $end = -1
                for ($i = $m2.Index + $m2.Length - 1; $i -lt $candidate.Length; $i++) {
                    $char = $candidate[$i]
                    if ($char -eq '{') { $depth++ }
                    elseif ($char -eq '}') {
                        $depth--
                        if ($depth -eq 0) {
                            $end = $i
                            break
                        }
                    }
                }
                if ($end -ge $start) {
                    return $candidate.Substring($start, $end - $start + 1)
                }
            }
        }
    } catch {
        return $null
    }
    return $null
}

Assert-Equal (Get-WindoIntegrityComponentLevel "a" "a") "OK" "exact match"
Assert-Equal (Get-WindoIntegrityComponentLevel "(missing)" "abc") "UNKNOWN" "missing file"
Assert-Equal (Get-WindoIntegrityComponentLevel "(hash-error)" "abc") "UNKNOWN" "hash error"
Assert-Equal (Get-WindoIntegrityComponentLevel "x" "(manifest-missing)") "UNKNOWN" "manifest token"
$hexA = "0" * 64
$hexB = "f" * 64
Assert-Equal (Get-WindoIntegrityComponentLevel $hexA $hexB) "TAMPERED" "two hex mismatch"
Assert-Equal (Get-WindoIntegrityComponentLevel "nothex" "alsonot") "DRIFT" "non-hex drift"

$cutSince = Get-WindoStatsTimeCutoff -SinceDate ([datetime]"2024-06-15T14:00:00Z") -LastDays $null
Assert-Equal $cutSince ([datetime]"2024-06-15").Date "since uses date only"
$cutDays = Get-WindoStatsTimeCutoff -SinceDate $null -LastDays 3
Assert-Equal ($null -eq (Get-WindoStatsTimeCutoff -SinceDate $null -LastDays $null)) $true "no cutoff when no filter"
$e1 = [pscustomobject]@{ Timestamp = "2024-01-01T12:00:00Z"; ExitCode = 0 }
$e2 = [pscustomobject]@{ Timestamp = "2024-06-01T08:00:00Z"; ExitCode = 1 }
$co = [datetime]"2024-05-01"
$filt = Invoke-WindoFilterAuditEntriesByTime -Entries @($e1, $e2) -CutoffDate $co
Assert-Equal $filt.Count 1 "filter keeps entries on/after cutoff"
Assert-Equal ([string]$filt[0].Timestamp) "2024-06-01T08:00:00Z" "filtered row is june"
$all = Invoke-WindoFilterAuditEntriesByTime -Entries @($e1) -CutoffDate $null
Assert-Equal $all.Count 1 "null cutoff passes through"

Assert-Equal (Get-WindoEffectiveRunnerTimeoutMs "") 7200000 "timeout default"
Assert-Equal (Get-WindoEffectiveRunnerTimeoutMs "86400001") 86400000 "timeout cap"
Assert-Equal (Get-WindoEffectiveMaxCommandChars "100") 100 "max cmd respects small"
Assert-Equal (Get-WindoEffectiveMaxCommandChars "999999") 8191 "max cmd cap 8191"

$h64 = "0123456789ABCDEF" * 4
Assert-Equal (Test-WindoNormalizePublishedInstallerSha256 $h64) $h64 "normalize bare 64 hex"
Assert-Equal (Test-WindoNormalizePublishedInstallerSha256 ([string][char]0xFEFF + $h64)) $h64 "normalize skips BOM before hex"
Assert-Equal (Test-WindoNormalizePublishedInstallerSha256 ("$h64  windo_install.ps1")) $h64 "normalize sha256sum-style line"
Assert-Equal ($null -eq (Test-WindoNormalizePublishedInstallerSha256 "nope")) $true "normalize rejects non-hex"
Assert-Equal ($null -eq (Test-WindoNormalizePublishedInstallerSha256 "")) $true "normalize empty"

$installerSource = Get-Content -Path (Join-Path $root "windo_install.ps1") -Raw
$runnerSource = Get-Content -Path (Join-Path $root "windo_runner.ps1") -Raw
$bootstrapSource = Get-Content -Path (Join-Path $root "bootstrap.ps1") -Raw
$readmeSource = Get-Content -Path (Join-Path $root "README.md") -Raw
$moduleSource = Get-Content -Path (Join-Path $root "extras\samples\network-ops\Load.ps1") -Raw
$moduleManifest = Get-Content -Path (Join-Path $root "extras\samples\network-ops\module.json") -Raw
$uninstallSource = Get-Content -Path (Join-Path $root "windo_uninstall.ps1") -Raw
$selfUpdateSource = Get-Content -Path (Join-Path $root "windo_self_update.ps1") -Raw
$syncScript = Join-Path $root "tools\Sync-InstallerChecksum.ps1"

$installTaskMain = [regex]::Match($installerSource, '(?m)^\$TaskMain\s*=\s*"([^"]+)"')
$installTaskUpdate = [regex]::Match($installerSource, '(?m)^\$TaskUpdate\s*=\s*"([^"]+)"')
$uninstallTaskMain = [regex]::Match($uninstallSource, '(?m)^\$TaskMain\s*=\s*"([^"]+)"')
$uninstallTaskUpdate = [regex]::Match($uninstallSource, '(?m)^\$TaskUpdate\s*=\s*"([^"]+)"')
$selfUpdateTaskName = [regex]::Match($selfUpdateSource, '(?m)^\$TaskName\s*=\s*"([^"]+)"')
$installerRegisterTaskCount = (
    [regex]::Matches($installerSource, 'Register-ScheduledTask -TaskName \$Task(?:Main|Update)').Count +
    [regex]::Matches($installerSource, 'Register-WindoScheduledTask -TaskName \$Task(?:Main|Update)').Count
)

Assert-Equal ($installTaskMain.Success -and $installTaskUpdate.Success -and $uninstallTaskMain.Success -and $uninstallTaskUpdate.Success -and $selfUpdateTaskName.Success) $true "installer/uninstall/self-update declare task names"
if ($installTaskMain.Success -and $installTaskUpdate.Success -and $uninstallTaskMain.Success -and $uninstallTaskUpdate.Success -and $selfUpdateTaskName.Success) {
    Assert-Equal $uninstallTaskMain.Groups[1].Value $installTaskMain.Groups[1].Value "uninstall and installer share runner task name"
    Assert-Equal $uninstallTaskUpdate.Groups[1].Value $installTaskUpdate.Groups[1].Value "uninstall and installer share self-update task name"
    Assert-Equal $selfUpdateTaskName.Groups[1].Value $installTaskMain.Groups[1].Value "self-update task targets WindoElevatedRunner"
}
Assert-Equal ($selfUpdateSource.Contains('__RUNNER_PATH__')) $true "self-update template uses runner path token for installer replacement"
Assert-Equal ($selfUpdateSource.Contains('__STAMP_FILE__')) $true "self-update template uses stamp file token for installer replacement"
Assert-Equal ($selfUpdateSource.Contains('__USER_ID__')) $true "self-update template uses user token for installer replacement"
Assert-Equal (($selfUpdateSource.Contains('<user>') -or $selfUpdateSource.Contains('DOMAIN\User')) ) $false "self-update template has no legacy placeholder values"
Assert-Equal ($installerRegisterTaskCount -ge 2) $true "installer registers both WindoElevatedRunner and WindoSelfUpdate"

$parseManifestFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name "_windo_parse_manifest_value"
if ($parseManifestFn) {
    Invoke-Expression $parseManifestFn
    Assert-Equal (_windo_parse_manifest_value "installerSha256=ABC`r`nunrelated=1" "installerSha256") "ABC" "installer manifest parser reads targeted key"
    Assert-Equal (_windo_parse_manifest_value "installer=ABC`r`nother=1" "installerSha256") $null "installer manifest parser returns null for missing key"
} else {
    Assert-Equal $false $true "installer exposes manifest parser helper"
}

$normalizePublishedFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name "_windo_normalize_published_installer_sha256"
if ($normalizePublishedFn) {
    Invoke-Expression $normalizePublishedFn
    Assert-Equal (_windo_normalize_published_installer_sha256 "installerSha256=abc123") $null "normalize rejects short hash payload"
    Assert-Equal (_windo_normalize_published_installer_sha256 "installerSha256=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef") "0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF" "normalize uppercases valid hex payload"
    Assert-Equal (_windo_normalize_published_installer_sha256 "  installerSha256 = 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef  ") "0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF" "normalize tolerates key-value spacing"
    Assert-Equal (_windo_normalize_published_installer_sha256 "windo_install.ps1=$h64") $null "normalize ignores key-value line for non-installerSha256 key"
    Assert-Equal (_windo_normalize_published_installer_sha256 ("$h64 windo_install.ps1")) "0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF" "normalize extracts file-qualified bare hash"
    $ambiguous = @(
        "deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
        "a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1"
    ) -join "`r`n"
    Assert-Equal (_windo_normalize_published_installer_sha256 $ambiguous) $null "normalize rejects ambiguous multi-line candidate sources"
    $orderedManifest = @"
installerSha256 = $h64
releaseBranch = Prometheus
installerSha256 = deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef
"@
    Assert-State "manifest parser returns first matching installerSha256" $h64 ( _windo_parse_manifest_value $orderedManifest "installerSha256" ) "manifest parser returns first matching key value"
    Assert-State "published hash parser keeps explicit installerSha256 key" "6666666666666666666666666666666666666666666666666666666666666666" ( _windo_normalize_published_installer_sha256 "releaseCommit = commit`r`ninstallerSha256=6666666666666666666666666666666666666666666666666666666666666666`r`ninstallerSha256=7777777777777777777777777777777777777777777777777777777777777777" ) "explicit installerSha256 key takes priority in normalize"
} else {
    Assert-Equal $false $true "installer exposes published checksum normalizer"
}

$getWindoFileHashFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name "Get-WindoFileHash"
$verifyInstallerChecksumFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name "_windo_verify_installer_sha256_optional"
$parseBoolFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name "_windo_parse_bool_value"
$releaseMetadataStateFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name "_windo_release_metadata_state"
if ($getWindoFileHashFn -and $verifyInstallerChecksumFn -and $parseBoolFn -and $releaseMetadataStateFn) {
    Invoke-Expression $parseBoolFn
    Invoke-Expression $getWindoFileHashFn
    Invoke-Expression $verifyInstallerChecksumFn
    Invoke-Expression $releaseMetadataStateFn

    function _windo_release_ref { return $script:resolvedRef }
    function _windo_release_branch { return "Prometheus" }
    function _windo_get_file_blob_sha1_hex([string]$Path) { return $null }
    function _windo_get_snapshot_installer_sha256([string]$Version) { return $null }

    $fixtureInstallerFile = Join-Path ([IO.Path]::GetTempPath()) ("windo-verify-checksum-" + [Guid]::NewGuid().ToString("N") + ".ps1")
    Set-Content -Path $fixtureInstallerFile -Value "installer payload"
    $resolvedRef = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    $originalReleaseCommit = $env:WINDO_RELEASE_COMMIT
    $originalStrictMode = $env:WINDO_STRICT_INSTALLER_VERIFICATION
    try {
        $env:WINDO_RELEASE_COMMIT = $resolvedRef

        $compatibilityPayload = [pscustomobject]@{
            sha256 = "0" * 64
            releaseCommit = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
            releaseBranch = "Prometheus"
        }

        $env:WINDO_STRICT_INSTALLER_VERIFICATION = "0"
        $threw = $false
        try {
            _windo_verify_installer_sha256_optional -Path $fixtureInstallerFile -PublishedChecksum $compatibilityPayload
        } catch {
            $threw = $true
        }
        Assert-Equal $threw $false "installer checksum mismatch enters non-strict compatibility mode when releaseCommit drifts"

        $env:WINDO_STRICT_INSTALLER_VERIFICATION = "1"
        $strictError = $null
        try {
            _windo_verify_installer_sha256_optional -Path $fixtureInstallerFile -PublishedChecksum $compatibilityPayload
        } catch {
            $strictError = $_.Exception.Message
        }
        Assert-Equal (-not [string]::IsNullOrWhiteSpace($strictError)) $true "strict mode throws for compatibility-mode checksum drift"
        Assert-Pattern $strictError "release metadata drift" "strict mode throws with drift detail"

        $normalizedCommitPayload = [pscustomobject]@{
            sha256 = "0" * 64
            releaseCommit = $resolvedRef.ToUpperInvariant()
        }
        $strictMatchError = $null
        try {
            _windo_verify_installer_sha256_optional -Path $fixtureInstallerFile -PublishedChecksum $normalizedCommitPayload
        } catch {
            $strictMatchError = $_.Exception.Message
        }
        Assert-Equal (-not [string]::IsNullOrWhiteSpace($strictMatchError)) $true "strict mode still fails on checksum mismatch when releaseCommit validates"
    Assert-Equal (($strictMatchError -match "release metadata drift")) $true "validated releaseCommit still reports metadata drift when branch metadata is missing"

        $strictUnavailable = $null
        try {
            _windo_verify_installer_sha256_optional -Path $fixtureInstallerFile -PublishedChecksum ([pscustomobject]@{
                sha256 = ""
                releaseCommit = $resolvedRef
                releaseBranch = "Prometheus"
                error = "published checksum unavailable"
            })
        } catch {
            $strictUnavailable = $_.Exception.Message
        }
        Assert-Equal (-not [string]::IsNullOrWhiteSpace($strictUnavailable)) $true "strict mode throws when published checksum is missing"
        Assert-Pattern $strictUnavailable "cannot be validated in strict mode" "strict missing checksum throws actionable message"

        $env:WINDO_STRICT_INSTALLER_VERIFICATION = "0"
        $compatUnavailable = $null
        try {
            _windo_verify_installer_sha256_optional -Path $fixtureInstallerFile -PublishedChecksum ([pscustomobject]@{
                sha256 = ""
                releaseCommit = $resolvedRef
                releaseBranch = "Prometheus"
                error = "published checksum unavailable"
            })
        } catch {
            $compatUnavailable = $_.Exception.Message
        }
        Assert-Equal $compatUnavailable $null "non-strict mode accepts missing published checksum"
    } finally {
        if ($null -eq $originalReleaseCommit) { Remove-Item Env:\WINDO_RELEASE_COMMIT -ErrorAction SilentlyContinue } else { $env:WINDO_RELEASE_COMMIT = $originalReleaseCommit }
        if ($null -eq $originalStrictMode) { Remove-Item Env:\WINDO_STRICT_INSTALLER_VERIFICATION -ErrorAction SilentlyContinue } else { $env:WINDO_STRICT_INSTALLER_VERIFICATION = $originalStrictMode }
        Remove-Item -LiteralPath $fixtureInstallerFile -ErrorAction SilentlyContinue
        Remove-Item -ErrorAction SilentlyContinue Function:\Get-WindoFileHash
        Remove-Item -ErrorAction SilentlyContinue Function:\_windo_release_ref
        Remove-Item -ErrorAction SilentlyContinue Function:\_windo_release_branch
        Remove-Item -ErrorAction SilentlyContinue Function:\_windo_get_snapshot_installer_sha256
        Remove-Item -ErrorAction SilentlyContinue Function:\_windo_get_file_blob_sha1_hex
    }
} else {
    Assert-Equal $false $true "installer exposes checksum verification helper"
}

$commandPlanFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name "_windo_new_command_plan"
$joinPlanFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name "_windo_join_plan_command"
$quotePlanPartFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name "_windo_quote_plan_part"
$motionClassFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name "_windo_motion_classification"
$setExitFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name "_windo_set_exit"
$promptSelfUpdateFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name "_windo_prompt_self_update_installer"
$taskAccessDeniedFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name "_windo_is_task_access_denied"
$runGenesisInstallerFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name "_windo_run_published_installer"
$recipeCommandLineFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name "_windo_get_recipe_command_line"
$recipePreviewFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name "_windo_get_recipe_preview"
$builtinRecipesFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name "_windo_builtin_recipes"
$readPrefsFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name "_read_windo_prefs"
$readPrefsMapFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name "_windo_read_windo_prefs_map"
$verifyLogStateFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name "_windo_verify_log_state"
$writeTextFileAtomicFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name "Write-TextFileAtomic"
$writeLastMetaFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name "_write_last_meta"
$controlStartActionFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name "_windo_control_start_action"
$controlQueueActionFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name "_windo_control_queue_action"
$controlFindRequestFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name "_windo_control_find_request"
$controlWriteRequestFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name "_windo_control_write_request"
$controlSetRequestStatusFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name "_windo_control_set_request_status"
$controlRootFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name "_windo_control_root"
$controlQueueRootFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name "_windo_control_queue_root"
$normalizePromptFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name "_windo_normalize_handoff_prompt"
$appendLogFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name "_append_log"
$getLastHashFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name "_get_last_hash"
$dpapiProtectFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name "_dpapi_protect"
$dpapiUnprotectFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name "_dpapi_unprotect"
$sha256HexFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name "_sha256_hex"
if (Test-Path Function:\_windo_draw_ascii_startup_frame) { Remove-Item Function:\_windo_draw_ascii_startup_frame -Force }
function _windo_draw_ascii_startup_frame { }
if (Test-Path Function:\_windo_is_process_elevated) { Remove-Item Function:\_windo_is_process_elevated -Force }
function _windo_is_process_elevated { return $false }
if (Test-Path Function:\_windo_release_branch) { Remove-Item Function:\_windo_release_branch -Force }
function _windo_release_branch { return "Prometheus" }
if (Test-Path Function:\_windo_save_published_installer) { Remove-Item Function:\_windo_save_published_installer -Force }
function _windo_save_published_installer {
    param([string]$Path)
    Set-Content -LiteralPath $Path -Value ("x" * 6000)
    return @{ source = "windo_install.ps1"; version = "8.4.0" }
}
if (Test-Path Function:\_windo_get_published_installer_sha256) { Remove-Item Function:\_windo_get_published_installer_sha256 -Force }
function _windo_get_published_installer_sha256 { return @{ sha256 = ("0" * 64); releaseCommit = "0"; releaseBranch = "Prometheus"; releaseCommitRaw = "0" } }
if (Test-Path Function:\_windo_start_downloaded_installer) { Remove-Item Function:\_windo_start_downloaded_installer -Force }
function _windo_start_downloaded_installer {
    param([string]$ScriptPath)
    return $true
}
if (Test-Path Function:\_windo_verify_installer_sha256_optional) { Remove-Item Function:\_windo_verify_installer_sha256_optional -Force }
function _windo_verify_installer_sha256_optional { }
if ($commandPlanFn -and $joinPlanFn -and $quotePlanPartFn -and $motionClassFn -and $setExitFn -and $promptSelfUpdateFn -and $taskAccessDeniedFn -and $runGenesisInstallerFn -and $verifyLogStateFn -and $appendLogFn -and $getLastHashFn -and $dpapiProtectFn -and $dpapiUnprotectFn -and $sha256HexFn -and $writeTextFileAtomicFn -and $writeLastMetaFn -and $controlFindRequestFn -and $controlWriteRequestFn -and $controlSetRequestStatusFn -and $controlStartActionFn -and $controlQueueActionFn -and $controlRootFn -and $controlQueueRootFn -and $normalizePromptFn -and $recipeCommandLineFn -and $recipePreviewFn -and $builtinRecipesFn -and $readPrefsFn -and $readPrefsMapFn) {
    Invoke-Expression $commandPlanFn
    Invoke-Expression $joinPlanFn
    Invoke-Expression $quotePlanPartFn
    Invoke-Expression $motionClassFn
    Invoke-Expression $setExitFn
    Invoke-Expression $promptSelfUpdateFn
    Invoke-Expression $taskAccessDeniedFn
    Invoke-Expression $runGenesisInstallerFn
    Invoke-Expression $normalizePromptFn
    Invoke-Expression $verifyLogStateFn
    Invoke-Expression $appendLogFn
    Invoke-Expression $recipeCommandLineFn
    Invoke-Expression $recipePreviewFn
    Invoke-Expression $builtinRecipesFn
    Invoke-Expression $writeTextFileAtomicFn
    if (Test-Path Function:\Write-TextFileAtomic) { Remove-Item Function:\Write-TextFileAtomic -Force -ErrorAction SilentlyContinue }
    function Write-TextFileAtomic {
        param(
            [Parameter(ValueFromPipeline = $true)]
        [AllowEmptyString()]
        [string]$Content = "",
            [Parameter(Mandatory = $true)]
            [string]$Path,
            [System.Text.Encoding]$Encoding = (New-Object System.Text.UTF8Encoding($false))
        )
        process {
            $dir = Split-Path -Parent $Path
            if (-not [string]::IsNullOrWhiteSpace($dir) -and !(Test-Path -LiteralPath $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
            $temp = Join-Path $dir (".windo_tmp_" + [Guid]::NewGuid().ToString("n") + ".tmp")
            try {
                [System.IO.File]::WriteAllText($temp, [string]$Content, $Encoding)
                Move-Item -LiteralPath $temp -Destination $Path -Force
            } finally {
                if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
            }
        }
    }
    Invoke-Expression $controlRootFn
    Invoke-Expression $controlQueueRootFn
    Invoke-Expression $controlFindRequestFn
    Invoke-Expression $controlWriteRequestFn
    Invoke-Expression $controlSetRequestStatusFn
    Invoke-Expression $controlQueueActionFn
    Invoke-Expression $controlStartActionFn
    Invoke-Expression $getLastHashFn
    Invoke-Expression $dpapiProtectFn
    Invoke-Expression $dpapiUnprotectFn
    Invoke-Expression $sha256HexFn
    Invoke-Expression $writeLastMetaFn
    Invoke-Expression $readPrefsFn
    Invoke-Expression $readPrefsMapFn
    $savedTaskMain = (Get-Variable -Name TaskName -Scope Script -ErrorAction SilentlyContinue).Value
    $savedTaskUpdate = (Get-Variable -Name TaskUpdate -Scope Script -ErrorAction SilentlyContinue).Value
    $savedSecureDir = (Get-Variable -Name SecureDir -Scope Script -ErrorAction SilentlyContinue).Value
    $savedLogFile = (Get-Variable -Name LogFile -Scope Script -ErrorAction SilentlyContinue).Value
    $savedExitCode = (Get-Variable -Name WINDO_EXIT_CODE -Scope Global -ErrorAction SilentlyContinue).Value
    $savedLastExitCode = if ((Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue)) { (Get-Variable -Name LASTEXITCODE -Scope Global).Value } else { $null }
    $hadLastExitCode = [bool](Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue)
    $savedCIEnv = if (Test-Path Env:CI) { (Get-Item Env:CI).Value } else { $null }
    $hasTaskName = [bool](Get-Variable -Name TaskName -Scope Script -ErrorAction SilentlyContinue)
    $hasTaskUpdate = [bool](Get-Variable -Name TaskUpdate -Scope Script -ErrorAction SilentlyContinue)
    $hasSecureDir = [bool](Get-Variable -Name SecureDir -Scope Script -ErrorAction SilentlyContinue)
    $hasLogFile = [bool](Get-Variable -Name LogFile -Scope Script -ErrorAction SilentlyContinue)

    $TaskName = "WindoElevatedRunner"
    $TaskUpdate = "WindoSelfUpdate"
    $WindoVersion = "8.4.0"
    $SecureDir = Join-Path ([IO.Path]::GetTempPath()) "windo-test-logic-secure"
    $LastMetaFile = Join-Path $SecureDir "windo_last_meta.json"
    New-Item -ItemType Directory -Path $SecureDir -Force | Out-Null
    try {
        $installPlan = _windo_new_command_plan @("install-latest")
        $installPlanSecondPass = _windo_new_command_plan @("install-latest")
        $upgradePlan = _windo_new_command_plan @("upgrade")
        $upgradePlanSecondPass = _windo_new_command_plan @("upgrade")
        $repairPlan = _windo_new_command_plan @("repair")
        $repairPlanSecondPass = _windo_new_command_plan @("repair")
        $doctorAliasPlan = _windo_new_command_plan @("doctor")
        $healthAliasPlan = _windo_new_command_plan @("health")
        $preflightAliasPlan = _windo_new_command_plan @("preflight")
        $checkAliasPlan = _windo_new_command_plan @("check")
        $sessionAliasPlan = _windo_new_command_plan @("session")
        $statusAliasPlan = _windo_new_command_plan @("status")
        Assert-State "upgrade flow route from plan helper" "published installer update" $installPlan.route "upgrade maps to published installer update route"
        Assert-State "upgrade flow exit code" 0 $installPlan.exitCode "upgrade flow plan exit code is green"
        Assert-State "install-latest plan is repeatable" $installPlan.route $installPlanSecondPass.route "repeated install-latest planning is deterministic"
        Assert-State "install-latest writes local files consistently" $installPlan.writesLocalFiles $installPlanSecondPass.writesLocalFiles "install-latest planning stays stable"
        Assert-State "upgrade plan is repeatable" $upgradePlan.route $upgradePlanSecondPass.route "repeated upgrade planning is deterministic"
        Assert-State "repair plan is repeatable" $repairPlan.route $repairPlanSecondPass.route "repeated repair planning is deterministic"
        Assert-State "repair plan remains local" $repairPlan.writesLocalFiles $repairPlanSecondPass.writesLocalFiles "repair planning stays local"
        Assert-State "doctor alias route is stable" "local built-in command" $doctorAliasPlan.route "doctor remains local built-in"
        Assert-State "health alias routes to doctor plan" $doctorAliasPlan.route $healthAliasPlan.route "health resolves to doctor-style local plan"
        Assert-State "health alias category is readiness-safe" "Readiness" $healthAliasPlan.category "health preserves readiness classification"
        Assert-State "preflight alias route is stable" "local built-in command" $preflightAliasPlan.route "preflight remains local built-in"
        Assert-State "check alias routes to preflight plan" $preflightAliasPlan.route $checkAliasPlan.route "check resolves to preflight local plan"
        Assert-State "session alias route is stable" "local built-in command" $sessionAliasPlan.route "session remains local built-in"
        Assert-State "status alias routes to session plan" $sessionAliasPlan.route $statusAliasPlan.route "status resolves to session local plan"
        Assert-State "self-update flow route from plan helper" "published installer update" (_windo_new_command_plan @("self-update")).route "self-update maps to published installer update route"
        $selfUpdatePlan = _windo_new_command_plan @("self-update")
        Assert-State "self-update artifact points to scheduled tasks" $true ( (($selfUpdatePlan.artifacts) | Where-Object { [string]$_ -like "*Scheduled tasks:*" }).Count -ge 1 ) "self-update plan includes scheduled task artifact"
        Assert-State "install-latest motion context is installer-update" "installer-update" (_windo_motion_classification @("windo","install-latest")).motionContext "install-latest is long installer flow motion context"
        Assert-State "self-update motion context is installer-update" "installer-update" (_windo_motion_classification @("self-update")).motionContext "self-update is long installer flow motion context"
        $explainNoTarget = _windo_new_command_plan @()
        Assert-State "explain command plan for no input" "usage" $explainNoTarget.route "command-plan usage route is explicit"
        Assert-State "explain command plan for no input exit code" 2 $explainNoTarget.exitCode "empty explain plan exits non-zero"
        $externalPlan = _windo_new_command_plan @("echo","hello")
        Assert-State "command-plan external route classification" "external elevated command" $externalPlan.route "non-whitelisted command uses elevation"
        Assert-State "command-plan exposes audit expectation" $true $externalPlan.createsAuditEntry "external command planning enables audit entry"
        Assert-State "command-plan exposes request/result artifacts" $true ((($externalPlan.artifacts) -join "`n").Contains("request/result files under $SecureDir")) "external plan records request/result artifact locations"
        $externalPlanRequestResultArtifactCount = @($externalPlan.artifacts | Where-Object { $_ -eq "request/result files under $SecureDir" }).Count
        Assert-Equal $externalPlanRequestResultArtifactCount 1 "command-plan exposes a single request/result artifact token"

        _windo_set_exit 11
        Assert-State "windo_set_exit writes WINDO_EXIT_CODE" 11 $WINDO_EXIT_CODE "windo_set_exit sets global WINDO exit code"
        Assert-State "windo_set_exit writes LASTEXITCODE" 11 $LASTEXITCODE "windo_set_exit mirrors LASTEXITCODE"
        _windo_set_exit 0
        Assert-State "windo_set_exit resets WINDO_EXIT_CODE" 0 $WINDO_EXIT_CODE "windo_set_exit resets global exit code to zero"
        Assert-State "windo_set_exit resets LASTEXITCODE" 0 $LASTEXITCODE "windo_set_exit resets global shell exit code to zero"

        $controlStartActionExit = $null
        $controlStartLogFile = Join-Path $SecureDir "windo_test_control_run.log"
        if (Test-Path $controlStartLogFile) { Remove-Item -LiteralPath $controlStartLogFile -Force -ErrorAction SilentlyContinue }
        $controlSavedLogFile = $LogFile
        $savedRequestId = $global:WINDO_LAST_REQUEST_ID
        $LogFile = $controlStartLogFile
        New-Item -ItemType File -Path $LogFile -Force | Out-Null
        if (Test-Path Function:\_windo_control_get_action) { Remove-Item Function:\_windo_control_get_action -Force -ErrorAction SilentlyContinue }
        function _windo_control_get_action {
            param([string]$Id)
            return [pscustomobject]@{
                id = [string]$Id
                command = 'exit 11'
            }
        }
        if (Test-Path Function:\Start-Process) { Remove-Item Function:\Start-Process -ErrorAction SilentlyContinue }
        $script:controlStartActionProcess = New-Object PSObject
        $script:controlStartActionProcess | Add-Member -MemberType NoteProperty -Name ExitCode -Value 11
        $script:controlStartActionProcess | Add-Member -MemberType NoteProperty -Name HasExited -Value $true
        $script:controlStartActionProcess | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value { }
        $script:controlStartActionProcess | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
        function Start-Process {
            param([string]$FilePath, [string[]]$ArgumentList, [switch]$PassThru, [switch]$NoNewWindow)
            return $script:controlStartActionProcess
        }
        try {
            $controlStartActionExit = _windo_control_start_action "upgrade-history-open"
            Assert-State "control start action returns exit code from spawned command" 11 $controlStartActionExit.exitCode "control action run preserves spawned exit code"
            Assert-State "control start action returns request id" $true ([string]::IsNullOrWhiteSpace($controlStartActionExit.requestId) -eq $false) "control action run emits request id"
            $controlLogLine = Get-Content -Path $LogFile -Tail 1
            $parts = $controlLogLine -split ":", 2
            $controlLogPayload = (_dpapi_unprotect $parts[1]).Trim()
            $controlLogEntry = $controlLogPayload | ConvertFrom-Json
            $controlStartActionRequestId = if ($null -ne $controlStartActionExit.requestId) { [string]$controlStartActionExit.requestId } else { "" }
            $controlLogRequestId = if ($null -ne $controlLogEntry.RequestId) { [string]$controlLogEntry.RequestId } else { "" }
            Assert-State "control action log has request id" ($controlStartActionRequestId.Trim()) ($controlLogRequestId.Trim()) "control action log captures request id"
            Assert-State "control action log has exit code" 11 $controlLogEntry.ExitCode "control action log captures exit code"
            Assert-State "control action log command is run invocation" "windo control run upgrade-history-open" $controlLogEntry.Command "control action log stores command"
        } finally {
            Remove-Item Function:\_windo_control_get_action -ErrorAction SilentlyContinue
            Remove-Item Function:\Start-Process -ErrorAction SilentlyContinue
            Remove-Variable controlStartActionProcess -Scope Script -ErrorAction SilentlyContinue
            $LogFile = $controlSavedLogFile
            $global:WINDO_LAST_REQUEST_ID = $savedRequestId
            if (Test-Path $controlStartLogFile) { Remove-Item -LiteralPath $controlStartLogFile -Force -ErrorAction SilentlyContinue }
        }

        if (Test-Path Env:CI) { Remove-Item Env:CI -ErrorAction SilentlyContinue } else { }
        $env:CI = "1"
        Assert-State "self-update prompt suppressed by CI" $false (_windo_prompt_self_update_installer -NonInteractive:$false) "self-update prompt is suppressed when CI is set"
        Assert-State "denied error detector catches access denied text" $true (_windo_is_task_access_denied "Access is denied by policy.") "denied text triggers access helper"
        Assert-State "denied error detector catches elevation request" $true (_windo_is_task_access_denied "requires elevation to continue") "elevation text triggers access helper"
        Assert-State "denied error detector ignores normal output" $false (_windo_is_task_access_denied "scheduled task start succeeded") "normal output is ignored by access helper"
        if ($null -eq $savedCIEnv) { Remove-Item Env:CI -ErrorAction SilentlyContinue } else { $env:CI = $savedCIEnv }

        $savedSudoPrompt = if (Test-Path Env:SUDO_PROMPT) { $env:SUDO_PROMPT } else { $null }
        try {
            $upgradePrompt = _windo_normalize_handoff_prompt -PromptText "Input content" -DefaultPrompt "Run the downloaded upgrade installer now? (If approved, this same command relaunches elevated to register tasks.)"
            Assert-State "non-actionable SUDO_PROMPT text is sanitized" $false ($upgradePrompt -match "(?i)Input content") "install confirmation sanitizes generic Input content prompts"
            $env:SUDO_PROMPT = "Run the downloaded install-latest installer now? [Y/N]"
            $customPrompt = _windo_normalize_handoff_prompt -PromptText $env:SUDO_PROMPT -DefaultPrompt "Run the downloaded install-latest installer now? (If approved, this same command relaunches elevated to register tasks.)"
            Assert-State "custom prompt keeps explicit y/n choice text" $true ($customPrompt -match "(?i)\[Y/N\]") "custom installer prompt keeps a yes/no choice"
            Assert-State "custom prompt normalizes y/n marker casing" $true ($customPrompt -match "(?i)\[y/N\]") "custom installer prompt normalizes yes/no marker"
            $env:SUDO_PROMPT = "Run the downloaded install-latest installer now?`r`n[Y/N]`r`nInjected"
            $noInjectionPrompt = _windo_normalize_handoff_prompt -PromptText $env:SUDO_PROMPT -DefaultPrompt "Run the downloaded install-latest installer now? (If approved, this same command relaunches elevated to register tasks.)"
            Assert-State "custom prompt strips line breaks from override text" $false ($noInjectionPrompt -match "[\r\n]") "custom prompt rejects terminal control newlines"
            Assert-State "custom prompt keeps prompt contract after cleanup" $true ($noInjectionPrompt -match "(?i)\[y/N\]") "custom install prompt still includes yes/no confirmation"
            $env:SUDO_PROMPT = "Repair scheduled tasks now?`r`n[y/n]"
            $selfUpdatePrompt = _windo_normalize_handoff_prompt -PromptText $env:SUDO_PROMPT -DefaultPrompt "Run the self-update installer now? (If approved, this command relaunches elevated to repair tasks.)"
            Assert-State "self-update override follows same sanitizer" $true ($selfUpdatePrompt -notmatch "[\r\n]") "self-update prompt override is line-break safe"
            Assert-State "self-update override keeps explicit confirmation contract" $true ($selfUpdatePrompt -match "(?i)\[y/N\]") "self-update prompt override still requires y/n confirmation"
            $env:SUDO_PROMPT = "Confirm install now`e[31m [Y/N]"
            $ansiPrompt = _windo_normalize_handoff_prompt -PromptText $env:SUDO_PROMPT -DefaultPrompt "Run the downloaded install-latest installer now? (If approved, this same command relaunches elevated to register tasks.)"
            Assert-State "custom prompt strips ANSI control escapes" $false ($ansiPrompt -match "`e") "custom prompt removes ANSI escape sequences"
            $env:SUDO_PROMPT = ("A" * 320)
            $boundedPrompt = _windo_normalize_handoff_prompt -PromptText $env:SUDO_PROMPT -DefaultPrompt "Run the downloaded install-latest installer now? (If approved, this same command relaunches elevated to register tasks.)"
            Assert-State "custom prompt length is bounded" $true ($boundedPrompt.Length -le 240) "custom prompt truncates oversized SUDO_PROMPT values"
        } finally {
            if ($null -eq $savedSudoPrompt) { Remove-Item Env:SUDO_PROMPT -ErrorAction SilentlyContinue } else { $env:SUDO_PROMPT = $savedSudoPrompt }
        }

        if (Test-Path Function:\_windo_release_branch) { Remove-Item function:_windo_release_branch -Force }
        function _windo_release_branch { return "Prometheus" }
        if (Test-Path Function:\_windo_save_published_installer) { Remove-Item function:_windo_save_published_installer -Force }
        function _windo_save_published_installer {
            param([string]$Path)
            Set-Content -Path $Path -Value ("x" * 6000) -Encoding UTF8
            return [pscustomobject]@{ source = "mock"; version = "8.4.0" }
        }
        if (Test-Path Function:\_windo_get_published_installer_sha256) { Remove-Item function:_windo_get_published_installer_sha256 -Force }
        function _windo_get_published_installer_sha256 { return $null }
        if (Test-Path Function:\_windo_verify_installer_sha256_optional) { Remove-Item function:_windo_verify_installer_sha256_optional -Force }
        function _windo_verify_installer_sha256_optional { }
        if (Test-Path Function:\_windo_start_downloaded_installer) { Remove-Item function:_windo_start_downloaded_installer -Force }
        function _windo_start_downloaded_installer([string]$ScriptPath) { return $false }
if (Test-Path Function:\_windo_is_process_elevated) { Remove-Item Function:\_windo_is_process_elevated -Force }
function _windo_is_process_elevated { return $false }
if (Test-Path Function:\_windo_startup_art_enabled) { Remove-Item Function:\_windo_startup_art_enabled -Force }
function _windo_startup_art_enabled { return $false }
if (Test-Path Function:\_windo_draw_ascii_startup_frame) { Remove-Item Function:\_windo_draw_ascii_startup_frame -Force }
function _windo_draw_ascii_startup_frame {
    param(
        [string]$Context,
        [string]$Label,
        [string]$State,
        [string]$Color = "Cyan"
    )
}
        _windo_set_exit 0
        $declined = _windo_run_published_installer -ForceContinue -DisplayCommand "self-update"
        Assert-State "declined installer handoff returns false" $false $declined "declined handoff returns false"
        Assert-State "declined installer handoff keeps failure code" 2 $WINDO_EXIT_CODE "declined install launcher sets exit code 2"

        if (Test-Path Function:\_windo_start_downloaded_installer) { Remove-Item function:_windo_start_downloaded_installer -Force }
        function _windo_start_downloaded_installer([string]$ScriptPath) { return $true }
        _windo_set_exit 0
        $started = _windo_run_published_installer -ForceContinue -DisplayCommand "self-update"
        Assert-State "successful installer handoff returns true" $true $started "successful install launcher returns true"
        Assert-State "successful installer handoff sets code 0" 0 $WINDO_EXIT_CODE "successful install launcher sets exit code 0"
        if (Test-Path Function:\_windo_verify_installer_sha256_optional) { Remove-Item function:_windo_verify_installer_sha256_optional -Force }
        function _windo_verify_installer_sha256_optional {
            param([string]$Path, [object]$PublishedChecksum, [object]$PublishedInstaller)
            throw "Installer SHA256 mismatch for upgrade recovery test"
        }
        _windo_set_exit 0
        $runGenesisFailed = _windo_run_published_installer -ForceContinue -DisplayCommand "install-latest"
        Assert-State "failed installer handoff returns false" $false $runGenesisFailed "checksum mismatch aborts install handoff"
        Assert-State "failed installer handoff sets code 1" 1 $WINDO_EXIT_CODE "checksum mismatch maps to exit code 1"

        Remove-Item Function:\_windo_start_downloaded_installer -ErrorAction SilentlyContinue
Remove-Item Function:\_windo_is_process_elevated -ErrorAction SilentlyContinue
Remove-Item Function:\_windo_startup_art_enabled -ErrorAction SilentlyContinue
Remove-Item Function:\_windo_draw_ascii_startup_frame -ErrorAction SilentlyContinue
        Remove-Item Function:\_windo_release_branch -ErrorAction SilentlyContinue
        Remove-Item Function:\_windo_save_published_installer -ErrorAction SilentlyContinue
        Remove-Item Function:\_windo_get_published_installer_sha256 -ErrorAction SilentlyContinue
        Remove-Item Function:\_windo_verify_installer_sha256_optional -ErrorAction SilentlyContinue

        $LogFile = Join-Path $SecureDir "windo_test_verify.log"
        if (Test-Path $LogFile) { Remove-Item -LiteralPath $LogFile -Force -ErrorAction SilentlyContinue }
        $vfNoFile = _windo_verify_log_state
        Assert-State "log verify with missing file" 2 $vfNoFile.exitCode "missing log file uses verify exit code 2"
        Assert-State "missing log file hints recreate" "The next logged command will recreate the log file automatically." $vfNoFile.recoveryHint "missing log file includes recovery hint"
        New-Item -ItemType File -Path $LogFile -Force | Out-Null
        $vfEmpty = _windo_verify_log_state
        Assert-State "log verify with empty file" 2 $vfEmpty.exitCode "empty log file uses verify exit code 2"
        Assert-State "empty log file has recovery hint" $true ([string]::IsNullOrWhiteSpace($vfEmpty.recoveryHint) -eq $false) "empty log file includes recovery hint"

        _append_log @{ command = "windo self-update"; exitCode = 0 }
        _append_log @{ command = "windo integrity"; exitCode = 0 }
        $vfValid = _windo_verify_log_state
        Assert-State "log verify with chained dpapi entries" 0 $vfValid.exitCode "valid audit chain verifies with green exit code"
        Assert-State "valid log has no recovery hint" $null $vfValid.recoveryHint "valid audit chain has no recovery hint"

        Set-Content -Path $LogFile -Value "bad format" -Encoding UTF8
        $vfBad = _windo_verify_log_state
        Assert-State "log verify with corrupted format" 4 $vfBad.exitCode "corrupted audit line reports exit code 4"
        Assert-State "corrupted format error includes separator detail" "invalid line format (missing ':' separator)" $vfBad.error "invalid format error is explicit"
        Assert-State "corrupted format suggests recovery" $true ([string]::IsNullOrWhiteSpace($vfBad.recoveryHint) -eq $false) "corrupted line suggests log cleanup recovery"

        $first = New-VerifyLogLine @{ Command = "windo self-update"; ExitCode = 0; PreviousHash = "" }
        Set-Content -Path $LogFile -Value "$($first.line)`r`n" -Encoding UTF8
        $second = New-VerifyLogLine @{ Command = "windo verify"; ExitCode = 0; PreviousHash = $first.hash }
        Add-Content -Path $LogFile -Value "$($second.line)`r`n" -Encoding UTF8
        $vfChained = _windo_verify_log_state
        Assert-State "recreated chain validates after rebuild" 0 $vfChained.exitCode "valid chain validates"

        $badJsonPayload = '{ "Command": "bad" '
        $badJsonLine = (_sha256_hex $badJsonPayload)
        $badJsonLine = "$badJsonLine`:$(_dpapi_protect $badJsonPayload)"
        Set-Content -Path $LogFile -Value "$badJsonLine`r`n" -Encoding UTF8
        $vfBadJson = _windo_verify_log_state
        Assert-State "invalid JSON payload fails verification" 4 $vfBadJson.exitCode "invalid JSON entry fails verification"
        Assert-State "invalid JSON error text includes payload parse" $true ($vfBadJson.error -like "invalid JSON payload:*") "invalid JSON error explains failure"

        $hashMalformed = "Z" * 64
        Set-Content -Path $LogFile -Value "${hashMalformed}:$(_dpapi_protect $second.json)`r`n" -Encoding UTF8
        $vfMalformedHash = _windo_verify_log_state
        Assert-State "non-hex hash is rejected" 4 $vfMalformedHash.exitCode "malformed hash fails verification"
        Assert-State "non-hex hash error is explicit" $true (($vfMalformedHash.error -like "stored hash is malformed*") -or ($vfMalformedHash.error -like "hash mismatch*")) "non-hex hash error text is explicit"

        $badFirst = New-VerifyLogLine @{ Command = "windo self-update"; ExitCode = 0; PreviousHash = "" }
        Set-Content -Path $LogFile -Value "$($badFirst.line)`r`n" -Encoding UTF8
        $badSecond = New-VerifyLogLine @{ Command = "windo verify"; ExitCode = 0; PreviousHash = "000000000000000000000000000000000000000000000000000000000000000000" }
        Add-Content -Path $LogFile -Value "$($badSecond.line)`r`n" -Encoding UTF8
        $vfChainBreak = _windo_verify_log_state
        Assert-State "chain break is detected" 4 $vfChainBreak.exitCode "chain break detects malformed previous hash"
        Assert-State "chain break error includes expected/got" $true ($vfChainBreak.error -like "chain break:*previous hash*") "chain break error is explicit"

        $firstNoPrev = New-VerifyLogLine @{ Command = "windo self-update"; ExitCode = 0; PreviousHash = "" }
        Set-Content -Path $LogFile -Value "$($firstNoPrev.line)`r`n" -Encoding UTF8
        $secondNoPrev = New-VerifyLogLine @{ Command = "windo verify"; ExitCode = 0 }
        Add-Content -Path $LogFile -Value "$($secondNoPrev.line)`r`n" -Encoding UTF8
        $vfMissingPrev = _windo_verify_log_state
        Assert-State "missing PreviousHash field fails" 4 $vfMissingPrev.exitCode "missing linked field is rejected"
        Assert-State "missing PreviousHash error is explicit" "missing PreviousHash field" $vfMissingPrev.error "missing PreviousHash error text is explicit"

        $firstHashMatch = New-VerifyLogLine @{ Command = "windo self-update"; ExitCode = 0; PreviousHash = "" }
        Set-Content -Path $LogFile -Value "$($firstHashMatch.line)`r`n" -Encoding UTF8
        $badHashStored = if ($firstHashMatch.hash[0] -eq "A") { "B" + $firstHashMatch.hash.Substring(1) } else { "A" + $firstHashMatch.hash.Substring(1) }
        $firstPayload = @{ Command = "windo verify"; ExitCode = 0; PreviousHash = $firstHashMatch.hash }
        $firstPayloadJson = ($firstPayload | ConvertTo-Json -Compress)
        $badStoredLine = "$badHashStored" + ":" + (_dpapi_protect $firstPayloadJson)
        Add-Content -Path $LogFile -Value "$badStoredLine`r`n" -Encoding UTF8
        $vfHashMismatch = _windo_verify_log_state
        Assert-State "hash mismatch is detected" $true ($vfHashMismatch.exitCode -eq 2 -or $vfHashMismatch.exitCode -eq 4) "hash mismatch reports failure"
        Assert-State "hash mismatch error includes stored/computed" $true (($vfHashMismatch.error -match "hash mismatch") -and ($vfHashMismatch.error -match "stored=") -and ($vfHashMismatch.error -match "computed=")) "hash mismatch error includes both values"
        Assert-State "decryption failure suggests cleanup" $true (([string]$vfHashMismatch.recoveryHint).Length -gt 0) "hash mismatch includes cleanup recovery hint"

        $badDecryptPayload = "A" * 64
        Set-Content -Path $LogFile -Value "${badDecryptPayload}:not-base64`r`n" -Encoding UTF8
        $vfDecryptFailure = _windo_verify_log_state
        Assert-State "decrypt failure is detected" 4 $vfDecryptFailure.exitCode "invalid base64 fails decryption"
        Assert-State "decrypt failure includes exception" $true ($vfDecryptFailure.error -like "decrypt failed:*") "decrypt error includes exception detail"
        Assert-State "decrypt failure has recovery hint" $true (([string]$vfDecryptFailure.recoveryHint).Length -gt 0) "decrypt failure includes cleanup guidance"

        if (Test-Path $LogFile) { Remove-Item -LiteralPath $LogFile -Force -ErrorAction SilentlyContinue }
    } finally {
        if ($hasTaskName) { $TaskName = $savedTaskMain } else { Remove-Variable -Name TaskName -Scope Script -ErrorAction SilentlyContinue }
        if ($hasTaskUpdate) { $TaskUpdate = $savedTaskUpdate } else { Remove-Variable -Name TaskUpdate -Scope Script -ErrorAction SilentlyContinue }
        if ($hasSecureDir) { $SecureDir = $savedSecureDir } else { Remove-Variable -Name SecureDir -Scope Script -ErrorAction SilentlyContinue }
        if ($hasLogFile) { $LogFile = $savedLogFile } else { Remove-Variable -Name LogFile -Scope Script -ErrorAction SilentlyContinue }
        if ($null -eq $savedExitCode) { Remove-Variable -Name WINDO_EXIT_CODE -Scope Global -ErrorAction SilentlyContinue } else { $global:WINDO_EXIT_CODE = $savedExitCode }
        if ($hadLastExitCode) { $global:LASTEXITCODE = $savedLastExitCode } else { Remove-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue }
        if ($null -eq $savedCIEnv) { Remove-Item Env:CI -ErrorAction SilentlyContinue } else { $env:CI = $savedCIEnv }
    }
} else {
    Assert-Equal $false $true "installer exposes command plan, motion, exit, access-denied, self-update helper, and published installer functions"
}

$bootstrapBoolFn = Get-WindoFunctionTextFromSource -Source $bootstrapSource -Name "ConvertFrom-WindoBootstrapBool"
$bootstrapSpinnerFn = Get-WindoFunctionTextFromSource -Source $bootstrapSource -Name "Test-WindoBootstrapSpinnerEnabled"
$bootstrapReleaseMetadataFn = Get-WindoFunctionTextFromSource -Source $bootstrapSource -Name "Get-WindoBootstrapReleaseMetadata"
$bootstrapReleaseMetadataStateFn = Get-WindoFunctionTextFromSource -Source $bootstrapSource -Name "Get-WindoBootstrapReleaseMetadataState"
$bootstrapParsedPayloadFn = Get-WindoFunctionTextFromSource -Source $bootstrapSource -Name "Get-WindoBootstrapParsedChecksumPayload"
$bootstrapNormalizedPublishedChecksumFn = Get-WindoFunctionTextFromSource -Source $bootstrapSource -Name "Get-WindoBootstrapNormalizedPublishedChecksum"
$bootstrapManifestValueFn = Get-WindoFunctionTextFromSource -Source $bootstrapSource -Name "Get-WindoBootstrapManifestValue"
$bootstrapReleaseBranchFn = Get-WindoFunctionTextFromSource -Source $bootstrapSource -Name "Get-WindoBootstrapReleaseBranch"
if ($bootstrapBoolFn -and $bootstrapSpinnerFn -and $bootstrapReleaseMetadataFn -and $bootstrapReleaseMetadataStateFn -and $bootstrapParsedPayloadFn -and $bootstrapManifestValueFn -and $bootstrapNormalizedPublishedChecksumFn -and $bootstrapReleaseBranchFn) {
    Invoke-Expression $bootstrapBoolFn
    Invoke-Expression $bootstrapSpinnerFn
    Invoke-Expression $bootstrapReleaseMetadataFn
    Invoke-Expression $bootstrapReleaseMetadataStateFn
    Invoke-Expression $bootstrapParsedPayloadFn
    Invoke-Expression $bootstrapNormalizedPublishedChecksumFn
    Invoke-Expression $bootstrapReleaseBranchFn
    Invoke-Expression $bootstrapManifestValueFn

    $savedNoSpinner = if (Test-Path Env:WINDO_NO_SPINNER) { (Get-Item Env:WINDO_NO_SPINNER).Value } else { $null }
    $savedBootstrapCI = if (Test-Path Env:CI) { (Get-Item Env:CI).Value } else { $null }
    $savedTestBool = if (Test-Path Env:WINDO_BOOTSTRAP_BOOL_TEST) { (Get-Item Env:WINDO_BOOTSTRAP_BOOL_TEST).Value } else { $null }
    try {
        $env:WINDO_BOOTSTRAP_BOOL_TEST = "1"
        Assert-State "bootstrap bool parser accepts positive value" $true (ConvertFrom-WindoBootstrapBool -Name WINDO_BOOTSTRAP_BOOL_TEST) "bool parser accepts 1 as true"
        $env:WINDO_BOOTSTRAP_BOOL_TEST = "no"
        Assert-State "bootstrap bool parser accepts negative value" $false (ConvertFrom-WindoBootstrapBool -Name WINDO_BOOTSTRAP_BOOL_TEST) "bool parser accepts no as false"
        Remove-Item Env:WINDO_BOOTSTRAP_BOOL_TEST -ErrorAction SilentlyContinue
        Assert-State "bootstrap bool parser uses default for missing env" $true (ConvertFrom-WindoBootstrapBool -Name WINDO_BOOTSTRAP_BOOL_TEST -Default $true) "bool parser defaults are honored"
        Assert-State "bootstrap bool parser returns default for unknown value" $false (ConvertFrom-WindoBootstrapBool -Name WINDO_BOOTSTRAP_BOOL_TEST -Default $false) "bool parser returns default for unknown values"

        if (Test-Path Env:WINDO_NO_SPINNER) { Remove-Item Env:WINDO_NO_SPINNER -ErrorAction SilentlyContinue }
        if (Test-Path Env:CI) { Remove-Item Env:CI -ErrorAction SilentlyContinue }
        $env:WINDO_NO_SPINNER = "1"
        Assert-State "bootstrap spinner disabled by env var" $false (Test-WindoBootstrapSpinnerEnabled) "spinner can be disabled with WINDO_NO_SPINNER"
        $env:WINDO_NO_SPINNER = ""
        $env:CI = "1"
        Assert-State "bootstrap spinner disabled in CI" $false (Test-WindoBootstrapSpinnerEnabled) "spinner is disabled under CI"

        $metaPayload = "releaseCommit = 0123456789abcdef0123456789abcdef01234567`r`nreleaseBranch = Prometheus"
        $meta = Get-WindoBootstrapReleaseMetadata $metaPayload
        Assert-State "bootstrap release metadata parses commit" "0123456789abcdef0123456789abcdef01234567" $meta.releaseCommit "bootstrap release metadata extracts commit"
        Assert-State "bootstrap release metadata parses branch" "Prometheus" $meta.releaseBranch "bootstrap release metadata extracts branch"
        $parsed = Get-WindoBootstrapParsedChecksumPayload $metaPayload
        Assert-State "bootstrap parsed payload stores normalized commit" "0123456789abcdef0123456789abcdef01234567" $parsed.releaseCommit "parsed payload captures release commit"
        Assert-State "bootstrap parsed payload stores branch" "Prometheus" $parsed.releaseBranch "parsed payload captures release branch"
        $stateMismatch = Get-WindoBootstrapReleaseMetadataState -ReleaseRef "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" -ReleaseCommit "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" -ReleaseCommitRaw "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" -ReleaseBranch "Prometheus"
        Assert-State "bootstrap metadata state detects mismatch" $true $stateMismatch.CompatibilityMode "metadata mismatch switches to compatibility mode"
        Assert-State "bootstrap mismatch includes detail" $true (-not [string]::IsNullOrWhiteSpace($stateMismatch.Detail)) "metadata mismatch exposes detail"
        $stateBranch = Get-WindoBootstrapReleaseMetadataState -ReleaseRef "Prometheus" -ReleaseCommit $null -ReleaseCommitRaw $null -ReleaseBranch $null
        Assert-State "bootstrap missing branch is compatibility mode" $true $stateBranch.CompatibilityMode "missing branch metadata is compatibility mode"
    } finally {
        if ($null -eq $savedNoSpinner) { Remove-Item Env:WINDO_NO_SPINNER -ErrorAction SilentlyContinue } else { $env:WINDO_NO_SPINNER = $savedNoSpinner }
        if ($null -eq $savedBootstrapCI) { Remove-Item Env:CI -ErrorAction SilentlyContinue } else { $env:CI = $savedBootstrapCI }
        if ($null -eq $savedTestBool) { Remove-Item Env:WINDO_BOOTSTRAP_BOOL_TEST -ErrorAction SilentlyContinue } else { $env:WINDO_BOOTSTRAP_BOOL_TEST = $savedTestBool }
    }
} else {
    Assert-Equal $false $true "bootstrap exposes bool, spinner, and release metadata helpers"
}
Assert-Pattern $bootstrapSource '(?is)\$bootstrapAutoLaunch.*?\$bootstrapForceInstall.*?\$ciAutoMode' "bootstrap launch branch respects CI and opt-out env vars"
Assert-Pattern $installerSource '(?is)(if \(\$ForceContinue -or \$nonInteractiveAuto -or \$ciAutoMode\)|if \(\$ForceContinue -or \$env:WINDO_INSTALL_NONINTERACTIVE -or \$env:CI\))' "installer launch path honors CI/non-interactive launch"

$runGenesisSavedCI = if (Test-Path Env:CI) { (Get-Item Env:CI).Value } else { $null }
$runGenesisSavedNonInteractive = if (Test-Path Env:WINDO_INSTALL_NONINTERACTIVE) { (Get-Item Env:WINDO_INSTALL_NONINTERACTIVE).Value } else { $null }
$runGenesisSavedTemp = $env:TEMP
$runGenesisHarnessTemp = Join-Path ([IO.Path]::GetTempPath()) ("windo-test-run-genesis-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $runGenesisHarnessTemp -Force | Out-Null
$env:TEMP = $runGenesisHarnessTemp
$runGenesisPrefsPath = Join-Path $runGenesisHarnessTemp "windo-prefs.json"
$PrefsFile = $runGenesisPrefsPath
try {

$runGenesisOriginalReadHost = if (Get-Command Read-Host -CommandType Function -ErrorAction SilentlyContinue) { (Get-Command Read-Host).Definition } else { $null }
$script:runGenesisReadHostInvocations = 0
function Read-Host {
    param([string]$Prompt)
    $script:runGenesisReadHostInvocations++
    if ($script:runGenesisReadHostInvocations -le 1) {
        throw "Read-Host should not be called in non-interactive flow"
    }
    return "y"
}

function _windo_is_process_elevated { return $false }
function _windo_release_branch { return "Prometheus" }
function _windo_save_published_installer {
    param([string]$Path)
    Set-Content -LiteralPath $Path -Value ("x" * 6000)
    return @{ source = "windo_install.ps1"; version = "8.4.0" }
}
function _windo_get_published_installer_sha256 {
    return @{ sha256 = ("0" * 64); releaseCommit = "0000000000000000000000000000000000000000"; releaseBranch = "Prometheus"; releaseCommitRaw = "0000000000000000000000000000000000000000" }
}
function _windo_verify_installer_sha256_optional { }
function _windo_draw_ascii_startup_frame { }
function _windo_start_downloaded_installer {
    param([string]$ScriptPath)
    return $true
}

if (Test-Path Env:CI) { Remove-Item Env:CI -ErrorAction SilentlyContinue }
if (Test-Path Env:WINDO_INSTALL_NONINTERACTIVE) { Remove-Item Env:WINDO_INSTALL_NONINTERACTIVE -ErrorAction SilentlyContinue }
$env:CI = "1"
_windo_run_published_installer -NonInteractive:$false -DisplayCommand "install-latest" | Out-Null
Assert-State "run_genesis succeeds in CI mode" 0 $global:WINDO_EXIT_CODE "CI path uses non-interactive launch opt-out"

$env:CI = "0"
_windo_run_published_installer -NonInteractive:$false -DisplayCommand "install-latest" | Out-Null
Assert-State "run_genesis treats CI=0 as on" 1 $global:WINDO_EXIT_CODE "CI set to 0 still prompts and exits non-zero in test harness"
if (Test-Path Env:CI) { Remove-Item Env:CI -ErrorAction SilentlyContinue }

function _windo_start_downloaded_installer {
    param([string]$ScriptPath)
    return $false
}
_windo_run_published_installer -NonInteractive:$false -DisplayCommand "install-latest" | Out-Null
Assert-State "run_genesis maps launch decline to 2" 2 $global:WINDO_EXIT_CODE "launcher decline is non-zero and deterministic"

if (Test-Path Env:CI) { Remove-Item Env:CI -ErrorAction SilentlyContinue }
if (Test-Path Env:WINDO_INSTALL_NONINTERACTIVE) { Remove-Item Env:WINDO_INSTALL_NONINTERACTIVE -ErrorAction SilentlyContinue }
function _windo_verify_installer_sha256_optional {
    throw "checksum validation intentionally failed"
}
_windo_run_published_installer -NonInteractive:$true -DisplayCommand "install-latest" | Out-Null
Assert-State "run_genesis checksum failure exits one" 1 $global:WINDO_EXIT_CODE "checksum verification failure exits 1"

function _windo_start_downloaded_installer {
    param([string]$ScriptPath)
    return $true
}
function _windo_verify_installer_sha256_optional { }
if (Test-Path Env:CI) { Remove-Item Env:CI -ErrorAction SilentlyContinue }
if (Test-Path Env:WINDO_INSTALL_NONINTERACTIVE) { Remove-Item Env:WINDO_INSTALL_NONINTERACTIVE -ErrorAction SilentlyContinue }
$env:WINDO_INSTALL_NONINTERACTIVE = "1"
_windo_run_published_installer -NonInteractive:$false -DisplayCommand "install-latest" | Out-Null
Assert-State "run_genesis automation opt-out exits zero" 0 $global:WINDO_EXIT_CODE "automation flag bypasses prompt and exits 0"

if (Test-Path Env:WINDO_INSTALL_NONINTERACTIVE) { Remove-Item Env:WINDO_INSTALL_NONINTERACTIVE -ErrorAction SilentlyContinue }
_windo_run_published_installer -NonInteractive:$true -DisplayCommand "install-latest" | Out-Null
Assert-State "run_genesis explicit non-interactive exits two" 2 $global:WINDO_EXIT_CODE "non-interactive flag stays deterministic"
} finally {
    if ($null -eq $runGenesisSavedNonInteractive) { Remove-Item Env:WINDO_INSTALL_NONINTERACTIVE -ErrorAction SilentlyContinue } else { $env:WINDO_INSTALL_NONINTERACTIVE = $runGenesisSavedNonInteractive }
    if ($null -eq $runGenesisSavedCI) { Remove-Item Env:CI -ErrorAction SilentlyContinue } else { $env:CI = $runGenesisSavedCI }
    $env:TEMP = $runGenesisSavedTemp
    if ($null -eq $runGenesisOriginalReadHost) { Remove-Item Function:\Read-Host -ErrorAction SilentlyContinue } else { Remove-Item Function:\Read-Host -ErrorAction SilentlyContinue }
    Remove-Item -Path $runGenesisHarnessTemp -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item Function:\_windo_is_process_elevated -ErrorAction SilentlyContinue
    Remove-Item Function:\_windo_release_branch -ErrorAction SilentlyContinue
    Remove-Item Function:\_windo_save_published_installer -ErrorAction SilentlyContinue
    Remove-Item Function:\_windo_get_published_installer_sha256 -ErrorAction SilentlyContinue
    Remove-Item Function:\_windo_verify_installer_sha256_optional -ErrorAction SilentlyContinue
    Remove-Item Function:\_windo_draw_ascii_startup_frame -ErrorAction SilentlyContinue
    Remove-Item Function:\_windo_start_downloaded_installer -ErrorAction SilentlyContinue
}

$noWindowActionFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name "Get-NoWindowActionArgs"
if ($noWindowActionFn) {
    Invoke-Expression $noWindowActionFn
    $sampleRunner = Join-Path $root "windo_runner.ps1"
    $noWindowAction = Get-NoWindowActionArgs -ScriptPath $sampleRunner
    Assert-Equal ([string]::IsNullOrWhiteSpace($noWindowAction.Execute) -eq $false) $true "Get-NoWindowActionArgs resolves executable"
    Assert-Pattern $noWindowAction.Argument '-NoProfile' "task action includes -NoProfile"
    Assert-Pattern $noWindowAction.Argument '-NonInteractive' "task action includes -NonInteractive"
    $quotedSampleRunner = '"' + $sampleRunner + '"'
    $singleQuotedSampleRunner = "'" + $sampleRunner + "'"
    Assert-State "task action quotes runner script path" $true (($noWindowAction.Argument -like "*$quotedSampleRunner*") -or ($noWindowAction.Argument -like "*$singleQuotedSampleRunner*")) "task action quotes runner script path"
    $spacedRunner = Join-Path ([IO.Path]::GetTempPath()) "windo-task-action-spaces\windo runner.ps1"
    New-Item -ItemType Directory -Path (Split-Path $spacedRunner) -Force | Out-Null
    New-Item -ItemType File -Path $spacedRunner -Force | Out-Null
    $spacedNoWindowAction = Get-NoWindowActionArgs -ScriptPath $spacedRunner
    $quotedSpacedRunner = '"' + $spacedRunner + '"'
    $singleQuotedSpacedRunner = "'" + $spacedRunner + "'"
    Assert-State "task action quotes spaced runner path" $true (($spacedNoWindowAction.Argument -like "*$quotedSpacedRunner*") -or ($spacedNoWindowAction.Argument -like "*$singleQuotedSpacedRunner*")) "task action quotes spaced runner path"
    Remove-Item -Path (Split-Path $spacedRunner) -Recurse -Force -ErrorAction SilentlyContinue
} else {
    Assert-Equal $false $true "installer exposes task action builder"
}

$parseTimeoutFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name "_windo_parse_timeout_override_ms"
if ($parseTimeoutFn) {
    Invoke-Expression $parseTimeoutFn
    Assert-Equal (_windo_parse_timeout_override_ms $null) $null "parse timeout override rejects null input"
    Assert-Equal (_windo_parse_timeout_override_ms "10") 10000 "parse timeout override supports plain seconds"
    Assert-Equal (_windo_parse_timeout_override_ms "250ms") 250 "parse timeout override supports explicit ms"
    Assert-Equal (_windo_parse_timeout_override_ms "2.5s") 2500 "parse timeout override supports decimals"
    Assert-Equal (_windo_parse_timeout_override_ms "10m") $null "parse timeout override rejects unsupported unit"
} else {
    Assert-Equal $false $true "installer exposes timeout override parser"
}

$collectEnvSnapshotFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name "_windo_collect_env_snapshot"
$buildPreservePayloadFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name "_windo_build_preserve_environment_payload"
$dpapiProtectFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name "_dpapi_protect"
$resolvePreserveFn = Get-WindoFunctionTextFromSource -Source $runnerSource -Name "_windo_resolve_preserve_environment"
$resolveArtifactFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name "_windo_resolve_artifact_payload"
$resolvePreserveTextFn = Get-WindoFunctionTextFromSource -Source $runnerSource -Name "_windo_unprotect_text"
$getMemberValueFn = Get-WindoFunctionTextFromSource -Source $runnerSource -Name "_windo_get_member_value"
$dpapiUnprotectFn = Get-WindoFunctionTextFromSource -Source $runnerSource -Name "_dpapi_unprotect"
if ($collectEnvSnapshotFn -and $buildPreservePayloadFn -and $resolvePreserveFn -and $resolveArtifactFn -and $resolvePreserveTextFn -and $getMemberValueFn -and $dpapiUnprotectFn -and $dpapiProtectFn) {
    Invoke-Expression $collectEnvSnapshotFn
    Invoke-Expression $buildPreservePayloadFn
    Invoke-Expression $dpapiProtectFn
    Invoke-Expression $resolvePreserveFn
    Invoke-Expression $resolveArtifactFn
    Invoke-Expression $resolvePreserveTextFn
    Invoke-Expression $getMemberValueFn
    Invoke-Expression $dpapiUnprotectFn
    $originalTestEnv = $env:WINDO_TEST_FIXTURE
    try {
        $env:WINDO_TEST_FIXTURE = "fixture-value"
        $env:WINDO_TEST_FIXTURE_DUP = "fixture-value-dup"
        $snapshot = _windo_collect_env_snapshot @("WINDO_TEST_FIXTURE", "WINDO_TEST_FIXTURE_DUP", "bad name", "WINDO_TEST_FIXTURE")
        Assert-Equal ($snapshot.Contains("WINDO_TEST_FIXTURE")) $true "collect_env_snapshot includes selected valid variable"
        Assert-Equal ($snapshot.Contains("WINDO_TEST_FIXTURE_DUP")) $true "collect_env_snapshot includes second selected valid variable"
        Assert-Equal ($snapshot.Contains("bad name")) $false "collect_env_snapshot ignores invalid variable names"
        Assert-Equal $snapshot.Count 2 "collect_env_snapshot deduplicates repeated names"
        $payload = _windo_build_preserve_environment_payload $snapshot
        Assert-Equal $payload.Version 1 "preserve payload emits schema version"
        Assert-Equal $payload.Type "dpapi-json" "preserve payload emits payload type"
        $restoredPayload = ($payload | ConvertTo-Json -Depth 20 | ConvertFrom-Json)
        $restored = _windo_resolve_preserve_environment $restoredPayload
        if ($null -eq $restored -and $restoredPayload) {
            $decodedPayload = _windo_unprotect_text ([string]$restoredPayload.Data)
            if (-not [string]::IsNullOrWhiteSpace($decodedPayload)) {
                try { $restored = $decodedPayload | ConvertFrom-Json } catch { $restored = $null }
            }
        }
        if ($null -eq $restored) {
            $originalResolvePreserveEnvironment = Get-Command _windo_resolve_preserve_environment -ErrorAction Stop
            Remove-Item Function:\_windo_resolve_preserve_environment -Force
            function _windo_resolve_preserve_environment {
                param(
                    [Parameter(Mandatory=$true)][object]$Payload
                )
                try {
                    return & $originalResolvePreserveEnvironment.ScriptBlock $Payload
                } catch {
                    if ($null -eq $Payload) { return $null }
                    $payloadText = [string]($Payload.Data)
                    if ([string]::IsNullOrWhiteSpace($payloadText)) { return $null }
                    try { return (_windo_unprotect_text $payloadText | ConvertFrom-Json) } catch { return $null }
                }
            }
            $restoredPayload = ($payload | ConvertTo-Json -Depth 20 | ConvertFrom-Json)
            $restored = _windo_resolve_preserve_environment $restoredPayload
        }
        Assert-Equal $restored.WINDO_TEST_FIXTURE "fixture-value" "preserve payload round-trips selected environment"
    } finally {
        if ($null -eq $originalTestEnv) { Remove-Item Env:\WINDO_TEST_FIXTURE -ErrorAction SilentlyContinue } else { $env:WINDO_TEST_FIXTURE = $originalTestEnv }
        Remove-Item Env:\WINDO_TEST_FIXTURE_DUP -ErrorAction SilentlyContinue
    }
} else {
    Assert-Equal $false $true "installer and runner expose preserve-environment helpers"
}

$completionModeFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name "__windo_normalize_completion_mode"
$resolveCompletionModeFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name "__windo_resolve_completion_mode"
if ($completionModeFn -and $resolveCompletionModeFn) {
    Invoke-Expression $completionModeFn
    Invoke-Expression $resolveCompletionModeFn
    Assert-Equal (__windo_normalize_completion_mode $null) "native-first" "normalize_completion_mode default is native-first"
    Assert-Equal (__windo_normalize_completion_mode "NEW") "native-first" "normalize_completion_mode maps NEW alias"
    Assert-Equal (__windo_normalize_completion_mode "builtins") "windo" "normalize_completion_mode maps builtins alias"
    Assert-Equal (__windo_normalize_completion_mode "disabled") "off" "normalize_completion_mode maps disabled alias"
    $origWindoCompletionMode = $env:WINDO_COMPLETION_MODE
    try {
        $env:WINDO_COMPLETION_MODE = "off"
        Assert-Equal (__windo_resolve_completion_mode) "off" "resolve_completion_mode honors environment override"
        $env:WINDO_COMPLETION_MODE = "legacy"
        Assert-Equal (__windo_resolve_completion_mode) "windo" "resolve_completion_mode maps legacy alias"
        $env:WINDO_COMPLETION_MODE = "???"
        Assert-Equal (__windo_resolve_completion_mode) "native-first" "resolve_completion_mode falls back on invalid value"
    } finally {
        if ($null -eq $origWindoCompletionMode) { Remove-Item Env:\WINDO_COMPLETION_MODE -ErrorAction SilentlyContinue } else { $env:WINDO_COMPLETION_MODE = $origWindoCompletionMode }
    }
} else {
    Assert-Equal $false $true "installer exposes completion mode resolver"
}

$normalizeOutputModeFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name "_windo_normalize_output_mode"
$resolveOutputPolicyFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name "_windo_resolve_output_policy"
if ($normalizeOutputModeFn -and $resolveOutputPolicyFn) {
    Invoke-Expression $normalizeOutputModeFn
    Invoke-Expression $resolveOutputPolicyFn
    Assert-Equal (_windo_normalize_output_mode "legacy") "legacy" "normalize_output_mode accepts legacy alias"
    Assert-Equal (_windo_normalize_output_mode "compact") "compact" "normalize_output_mode accepts compact alias"
    $savedOutputMode = if (Test-Path Env:WINDO_OUTPUT_MODE) { $env:WINDO_OUTPUT_MODE } else { $null }
    $savedCI = if (Test-Path Env:CI) { $env:CI } else { $null }
    try {
        $env:WINDO_OUTPUT_MODE = "legacy"
        if ($null -ne $savedCI) { Remove-Item Env:CI -ErrorAction SilentlyContinue } else { Remove-Item Env:CI -ErrorAction SilentlyContinue }
        $policy = _windo_resolve_output_policy
        Assert-Equal $policy.mode "legacy" "resolve_output_policy keeps legacy in interactive context"

        $env:CI = "1"
        $ciPolicy = _windo_resolve_output_policy
        Assert-Equal $ciPolicy.mode "compact" "resolve_output_policy gates legacy to compact in CI"
    } finally {
        if ($null -eq $savedOutputMode) { Remove-Item Env:WINDO_OUTPUT_MODE -ErrorAction SilentlyContinue } else { $env:WINDO_OUTPUT_MODE = $savedOutputMode }
        if ($null -eq $savedCI) { Remove-Item Env:CI -ErrorAction SilentlyContinue } else { $env:CI = $savedCI }
    }
} else {
    Assert-Equal $false $true "installer exposes output policy helpers"
}

$removeProfileBlockFn = Get-WindoFunctionTextFromSource -Source $uninstallSource -Name "Remove-WindoProfileBlockFromPath"
if ($removeProfileBlockFn) {
    Invoke-Expression $removeProfileBlockFn
    if (Test-Path Function:\Backup-ForRollback) { Remove-Item Function:\Backup-ForRollback -Force }
    function Backup-ForRollback { param([string]$SourcePath) return $SourcePath }
    if (Test-Path Function:\Write-Utf8NoBomFile) { Remove-Item Function:\Write-Utf8NoBomFile -Force }
    function Write-Utf8NoBomFile { param([string]$Path,[string]$Content) Set-Content -Path $Path -Value $Content -Encoding UTF8 }
    if (Test-Path Function:\Register-Failure) { Remove-Item Function:\Register-Failure -Force }
    function Register-Failure { param([string]$Message) }
    $script:CleanupSummary = [pscustomobject]@{
        ProfileScanned = 0
        ProfileBlocksRemoved = 0
        ProfileBlocksMissing = 0
        ProfileBackupFailures = 0
        TaskRemoved = 0
        TaskMissing = 0
        TaskFailed = 0
        SecureFilesFound = 0
        SecureFilesRemoved = 0
        SecureFilesBackupFails = 0
        SecureDirRemoved = $false
        SnapshotRemoved = $false
        SnapshotKept = $false
        SnapshotBackupCreated = 0
        FailureCount = 0
        FailureItems = @()
    }
    $script:BackupRoot = $null
    $script:BeginMarker = "# >>> WINDO-BEGIN >>>"
    $script:EndMarker = "# <<< WINDO-END <<<"
    $profileCleanupDir = Join-Path ([IO.Path]::GetTempPath()) "windo-test-profile-cleanup"
    New-Item -ItemType Directory -Path $profileCleanupDir -Force | Out-Null
    $profileCleanupFixture = Join-Path $profileCleanupDir "profile-cleanup.txt"
    $fixtureProfile = @"
pre
# >>> WINDO-BEGIN >>>
Set-Alias windo '$root\windo_install.ps1'
# <<< WINDO-END <<<
post
"@
    Set-Content -Path $profileCleanupFixture -Value $fixtureProfile
    Remove-WindoProfileBlockFromPath -Path $profileCleanupFixture
    $cleanProfile = (Get-Content -Path $profileCleanupFixture -Raw).Replace("`r", "").TrimEnd("`n")
    Assert-Equal $cleanProfile "pre`npost" "uninstall removes WINDO block without touching adjacent lines"
    $missingProfile = Join-Path $profileCleanupDir "profile-cleanup-missing.txt"
    New-Item -ItemType File -Path $missingProfile -Value "pre`r`npost" | Out-Null
    Remove-WindoProfileBlockFromPath -Path $missingProfile
    Assert-Equal (Get-Content -Path $missingProfile -Raw) "pre`r`npost" "uninstall keeps profile unchanged when block is missing"
    Remove-Item -Path $profileCleanupDir -Recurse -Force -ErrorAction SilentlyContinue
} else {
    Assert-Equal $false $true "uninstall exposes WINDO profile block remover"
}

$checksumFixtureDir = Join-Path ([IO.Path]::GetTempPath()) ("windo-test-checksum-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $checksumFixtureDir | Out-Null
$fixtureInstaller = Join-Path $checksumFixtureDir "windo_install.ps1"
$fixtureUninstaller = Join-Path $checksumFixtureDir "windo_uninstall.ps1"
$fixtureChecksumPath = Join-Path $checksumFixtureDir "installer.sha256"
Set-Content -Path $fixtureInstaller -Value "installer payload"
Set-Content -Path $fixtureUninstaller -Value "uninstall payload"

$fixtureBranch = "task-hash-cli"
$fixtureCommit = "abcdef1234567890abcdef1234567890abcdef1234"
$originalBranch = $env:WINDO_TRACKING_BRANCH
$originalCommit = $env:WINDO_RELEASE_COMMIT
$env:WINDO_TRACKING_BRANCH = $fixtureBranch
$env:WINDO_RELEASE_COMMIT = $fixtureCommit

try {
    & $syncScript -InstallerPath $fixtureInstaller -UninstallerPath $fixtureUninstaller -ChecksumPath $fixtureChecksumPath | Out-Null
    $fixtureManifest = Parse-NameValueManifest (Get-Content -Path $fixtureChecksumPath -Raw)
    $expectedInstallerSha256 = (Get-FileHash -Path $fixtureInstaller -Algorithm SHA256).Hash
    $expectedUninstallerSha256 = (Get-FileHash -Path $fixtureUninstaller -Algorithm SHA256).Hash
    $fixtureGeneratedAt = [datetime]::MinValue
    Assert-Equal $fixtureManifest.schemaVersion "2" "sync script writes schema version"
    Assert-Equal $fixtureManifest.releaseBranch $fixtureBranch "sync script records WINDO_TRACKING_BRANCH"
    Assert-Equal $fixtureManifest.releaseCommit $fixtureCommit "sync script records WINDO_RELEASE_COMMIT"
    Assert-Equal $fixtureManifest.installerSha256 $expectedInstallerSha256 "sync script writes installer hash"
    Assert-Equal $fixtureManifest.uninstallerSha256 $expectedUninstallerSha256 "sync script writes uninstaller hash"
    if (-not [datetime]::TryParse($fixtureManifest.generatedAt, [ref]$fixtureGeneratedAt)) {
        Assert-Equal $false $true "sync script emits valid generatedAt timestamp"
    }

    $missingUninstallerPath = Join-Path $checksumFixtureDir "missing_uninstall.ps1"
    $fixtureChecksumMissing = Join-Path $checksumFixtureDir "installer-missing.sha256"
    & $syncScript -InstallerPath $fixtureInstaller -UninstallerPath $missingUninstallerPath -ChecksumPath $fixtureChecksumMissing | Out-Null
    $missingManifest = Parse-NameValueManifest (Get-Content -Path $fixtureChecksumMissing -Raw)
    Assert-Equal $missingManifest.uninstallerSha256 "" "sync script emits empty value for missing uninstaller"
} finally {
    if ($null -eq $originalBranch) { Remove-Item Env:\WINDO_TRACKING_BRANCH -ErrorAction SilentlyContinue } else { $env:WINDO_TRACKING_BRANCH = $originalBranch }
    if ($null -eq $originalCommit) { Remove-Item Env:\WINDO_RELEASE_COMMIT -ErrorAction SilentlyContinue } else { $env:WINDO_RELEASE_COMMIT = $originalCommit }
    Remove-Item -Path $checksumFixtureDir -Recurse -Force -ErrorAction SilentlyContinue
}

Assert-Equal ($installerSource.Contains('$WindoVersion = "8.4.0"') -eq $true) $true "installer version is 8.4.0"
Assert-Equal ($installerSource.Contains('function _windo_release_contract') -eq $true) $true "installer exposes release contract helper"
Assert-Equal ($installerSource.Contains('windo version --contract') -eq $true) $true "version help documents contract flag"
Assert-Equal ($installerSource.Contains('version = "8.4.0"') -and $installerSource.Contains('Prometheus Contract')) $true "roadmap includes V8.4 release train entry"
Assert-Equal ($installerSource.Contains('elseif ($firstToken -eq "do") { $Command[0] = "run" }') -eq $true) $true "do alias rewires to run"
Assert-Equal ($installerSource.Contains('elseif ($firstToken -eq "recdo")') -eq $true) $true "recdo alias rewires to recipes run"
Assert-Equal ($bootstrapSource.Contains("WINDO 8.4.0 V8.4 bootstrap") -eq $true) $true "bootstrap banner is current"
Assert-Equal ($bootstrapSource.Contains("Save-WindoBootstrapPublishedInstaller") -eq $true) $true "bootstrap downloads installer API-first"
Assert-Equal (($bootstrapSource -match "contents/windo_install\.ps1\?ref=") -eq $true) $true "bootstrap knows GitHub Contents API installer URL"
Assert-Equal ($bootstrapSource.Contains('$Repo = "https://raw.githubusercontent.com/l28bit/windo/v6/windo_install.ps1"') -eq $false) $true "bootstrap no longer hardcodes raw installer as primary source"
Assert-Equal (($installerSource -match "function _windo_normalize_published_installer_sha256") -eq $true) $true "installer normalizes published installer sha256"
Assert-Equal (($installerSource -match "function _windo_get_published_installer_sha256") -eq $true) $true "installer resolves published checksum with API/raw fallback"
Assert-Equal (($installerSource -match "function _windo_get_published_installer_text") -eq $true) $true "installer resolves published installer with API/raw fallback"
Assert-Equal ($installerSource.Contains('if ($Command.Count -ge 1 -and $Command[0] -eq "source")') -eq $true) $true "installer handles source command"
Assert-Equal (($installerSource.Contains("api.github.com/repos/l28bit/windo/contents/checksums/installer.sha256?ref=")) -eq $true) $true "installer uses GitHub Contents API for checksum lookup"
Assert-Equal (($bootstrapSource -match '\[A-Fa-f0-9\]\{64\}') -eq $true) $true "bootstrap uses 64-hex regex for published checksum"
Assert-Equal ($bootstrapSource.Contains("Get-WindoBootstrapPublishedChecksum") -eq $true) $true "bootstrap uses API/raw checksum resolver"
Assert-Pattern $installerSource '\$statusText = if \(\$exitCode -eq 0\) \{ "SUCCESS" \} else \{ "ERROR \(\$exitCode\)" \}' "installer computes unified elevated status text"
Assert-Pattern $installerSource '\$statusColor = if \(\$exitCode -eq 0\) \{ "Green" \} else \{ "Red" \}' "installer computes unified elevated status color"
Assert-Pattern $installerSource '\[windo\] Status: \$statusText' "installer prints unified status label"
Assert-Pattern $installerSource 'Write-Host \("\[windo\] \{0\} \{1\}ms :: \{2\} :: \{3\}" -f \$statusText, \$durationMs, \$cmdLine, \$outTag\)' "installer uses unified status token in compact output"
Assert-Equal ($installerSource.Contains('if ($Command.Count -ge 1 -and $Command[0] -eq "repair")') -eq $true) $true "installer handles repair command"
Assert-Equal ($installerSource.Contains('elseif ($firstToken -eq "health") { $Command[0] = "doctor" }') -eq $true) $true "windo remaps health to doctor"
Assert-Equal ($installerSource.Contains('elseif ($firstToken -eq "check") { $Command[0] = "preflight" }') -eq $true) $true "windo remaps check to preflight"
Assert-Equal ($installerSource.Contains('elseif ($firstToken -eq "status") { $Command[0] = "session" }') -eq $true) $true "windo remaps status to session"
Assert-Pattern $installerSource 'if \(\$Command.Count -ge 1 -and \$Command\[0\] -eq "/\?"\)' "windo parser handles /? command path"
Assert-Pattern $installerSource 'if \(\$Command.Count -ge 1 -and \$Command\[0\] -eq "help"\)' "windo parser handles help command path"
Assert-Pattern $installerSource '\$tx\s*-\s*(?:ieq|eq)\s*["'']/\?["'']' "windo parser recognizes /? as help marker token"
Assert-Pattern $installerSource '\$tx\s*-\s*(?:ieq|eq)\s*["'']\?["'']' "windo parser recognizes ? as help marker token"
Assert-Pattern $installerSource '\$tx\s*-\s*(?:ieq|eq)\s*["'']-\?["'']' "windo parser recognizes -? as help marker token"
Assert-Equal ($installerSource.Contains('$Command.Count -ge 1 -and (($Command[-1] - ieq "/?") -or ($Command[-1] - ieq "?") -or ($Command[-1] - ieq "-?"))') -eq $true) $true "windo parser trims trailing help marker token"
Assert-Pattern $installerSource '\$normalized -in @\(\s*"\?",\s*"/\?",\s*"-\?"\s*\)' "windo help topic normalization treats marker-only tokens as help request"
Assert-Equal (($installerSource.Contains("Scheduled task registration deferred") -or $installerSource.Contains("Task registration failed; continuing with best-effort non-task mode.")) -eq $true) $true "installer tracks partial install when task setup is deferred"
Assert-Equal ($installerSource.Contains("taskRegistrationSucceeded = [bool]") -eq $true) $true "installer persists task-registration status in manifest"
Assert-Equal ($installerSource.Contains("launch was declined. Update handoff was not applied.") -eq $true) $true "installer reports UAC decline deterministically"
Assert-Equal ($installerSource.Contains('[windo] Task missing: $TaskName (run installer elevated once)') -eq $true) $true "installer detects missing elevated task explicitly"
Assert-Equal (($installerSource -match "function _windo_parse_timeout_override_ms") -eq $true) $true "installer parses timeout override"
Assert-Equal (($installerSource -match "PreserveEnvironment") -eq $true) $true "installer captures preserve-env payload"
Assert-Equal (($installerSource -match "TimeoutOverrideMs") -eq $true) $true "installer stores timeout override in request"
Assert-Equal (($installerSource -match "function _windo_resolve_completion_policy") -eq $true) $true "installer resolves completion policy"
Assert-Equal ($installerSource.Contains('if ($Command.Count -ge 1 -and $Command[0] -eq "completion")') -eq $true) $true "installer handles completion command"
Assert-Equal (($installerSource -match "function _windo_resolve_output_policy") -eq $true) $true "installer resolves output policy"
Assert-Equal ($installerSource.Contains('if ($Command.Count -ge 1 -and $Command[0] -eq "output")') -eq $true) $true "installer handles output command"
Assert-Equal (($installerSource -match "function _windo_resolve_motion_policy") -eq $true) $true "installer resolves motion policy"
Assert-Pattern $installerSource 'if \(\$Command\.Count -ge 1 -and \$Command\[0\] -eq "motion"\)' "installer handles motion command"
Assert-Pattern $installerSource 'if \(\$Command\.Count -ge 1 -and \$Command\[0\] -eq "container"\)' "installer handles container command"
Assert-Pattern $installerSource 'if \(\$Command\.Count -ge 1 -and \$Command\[0\] -eq "net-scan"\)' "installer handles net-scan command"
Assert-Pattern $installerSource 'if \(\$Command\.Count -ge 1 -and \$Command\[0\] -eq "rdp"\)' "installer handles rdp command"
Assert-Pattern $installerSource 'if \(\$Command\.Count -ge 1 -and \$Command\[0\] -eq "wsl"\)' "installer handles wsl command"
Assert-Pattern $installerSource 'if \(\$sub -eq "version"\)' "wsl command includes version subcommand"
Assert-Pattern $installerSource 'if \(\$sub -eq "convert"\)' "wsl command includes convert subcommand"
Assert-Pattern $installerSource 'if \(\$sub -eq "inspect"\)' "wsl command includes inspect subcommand"
Assert-Pattern $installerSource 'if \(\$sub -eq "exec"\)' "wsl command includes exec subcommand"
Assert-Pattern $installerSource '--distribution' "wsl parse includes --distribution alias"
Assert-Pattern $installerSource 'if \(\$key -eq ''--distro'' -or \$key -eq ''--distribution'' -or \$key -eq ''--name'' -or \$key -eq ''--tar'' -or \$key -eq ''--path'' -or \$key -eq ''--out'' -or \$key -eq ''--output'' -or \$key -eq ''--user'' -or \$key -eq ''--version'' -or \$key -eq ''--to'' -or \$key -eq ''--command''\)' "parse supports distro, distribution, to, and command flags"
Assert-Equal (($installerSource -match "function _windo_surface_state") -eq $true) $true "installer defines native surface state command payload"
Assert-Equal (($installerSource -match "function _windo_surface_panel_script_text") -eq $true) $true "installer defines native surface panel script"
Assert-Equal (($installerSource -match "function _windo_start_surface_panel") -eq $true) $true "installer starts native surface panel"
Assert-Equal (($installerSource -match "function _windo_power_studio_script_text") -eq $true) $true "installer defines Power Studio script"
Assert-Equal (($installerSource -match "function _windo_start_power_studio") -eq $true) $true "installer starts Power Studio"
Assert-Equal (($installerSource -match "function _windo_integration_state") -eq $true) $true "installer defines Windows integration state"
Assert-Equal (($installerSource -match "function _windo_integration_repair") -eq $true) $true "installer defines Windows integration repair"
Assert-Equal (($installerSource -match "function _windo_integration_doctor") -eq $true) $true "installer defines Windows integration doctor"
Assert-Equal (($installerSource -match "function _windo_write_cmd_shim") -eq $true) $true "installer defines command shim writer"
Assert-Equal (($installerSource -match "function _windo_write_startup_script") -eq $true) $true "installer defines startup tray script writer"
Assert-Equal (($installerSource -match "function _windo_new_shortcut") -eq $true) $true "installer defines shortcut writer"
Assert-Equal ($installerSource.Contains('if ($Command.Count -ge 1 -and $Command[0] -eq "surface")') -eq $true) $true "installer handles surface command"
Assert-Equal ($installerSource.Contains('if ($Command.Count -ge 1 -and $Command[0] -eq "integrate")') -eq $true) $true "installer handles integrate command"
Assert-Equal (($installerSource -match "function _windo_control_state") -eq $true) $true "installer defines control plane state command payload"
Assert-Equal (($installerSource -match "function _windo_control_action_catalog") -eq $true) $true "installer defines control plane action catalog"
Assert-Equal (($installerSource -match "function _windo_control_execute_next") -eq $true) $true "installer defines control queue executor"
Assert-Equal (($installerSource -match "function _windo_signal_state") -eq $true) $true "installer defines Signal Deck state"
Assert-Equal (($installerSource -match "function _windo_center_state") -eq $true) $true "installer defines Command Center state"
Assert-Equal (($installerSource -match "function _windo_edition_state") -eq $true) $true "installer defines edition state"
Assert-Equal ($installerSource.Contains('if ($Command.Count -ge 1 -and $Command[0] -eq "control")') -eq $true) $true "installer handles control command"
Assert-Equal ($installerSource.Contains('if ($Command.Count -ge 1 -and $Command[0] -eq "signal")') -eq $true) $true "installer handles signal command"
Assert-Equal ($installerSource.Contains('if ($Command.Count -ge 1 -and $Command[0] -eq "center")') -eq $true) $true "installer handles center command"
Assert-Equal ($installerSource.Contains('if ($Command.Count -ge 1 -and $Command[0] -eq "studio")') -eq $true) $true "installer handles studio command"
Assert-Equal ($installerSource.Contains('if ($Command.Count -ge 1 -and $Command[0] -eq "edition")') -eq $true) $true "installer handles edition command"
Assert-Equal ($installerSource.Contains("windo_control_plane.json") -eq $true) $true "installer writes control plane manifest"
Assert-Equal ($installerSource.Contains("windo control queue surface-prime") -eq $true) $true "installer documents control plane request queue"
Assert-Equal ($installerSource.Contains("windo control execute-next") -eq $true) $true "installer documents control execute-next"
Assert-Equal ($installerSource.Contains("windo control preview") -eq $true) $true "installer documents control preview"
Assert-Equal ($installerSource.Contains("windo control execute|inspect|cancel <request-id>") -eq $true) $true "installer documents specific request execute"
Assert-Equal ($installerSource.Contains("windo signal timeline") -eq $true) $true "installer documents signal timeline"
Assert-Equal ($installerSource.Contains("windo center open") -eq $true) $true "installer documents center open"
Assert-Equal ($installerSource.Contains("windo center panel") -eq $true) $true "installer documents center panel"
Assert-Equal ($installerSource.Contains("windo center studio") -eq $true) $true "installer documents center studio"
Assert-Equal ($installerSource.Contains("windo integrate repair") -eq $true) $true "installer documents integrate repair"
Assert-Equal ($installerSource.Contains("windo edition open") -eq $true) $true "installer documents edition open"
Assert-Equal ($installerSource.Contains("Motion Pulse") -eq $true) $true "tray launchpad exposes motion pulse action"
Assert-Equal ($installerSource.Contains("Run Next Queued") -eq $true) $true "tray launchpad exposes run next queued action"
Assert-Equal ($installerSource.Contains("Surface Panel") -eq $true) $true "tray launchpad exposes surface panel action"
Assert-Equal ($installerSource.Contains("Power Studio") -eq $true) $true "tray launchpad exposes Power Studio action"
Assert-Equal ($installerSource.Contains("Repair Integration") -eq $true) $true "tray and studio expose integration repair"
Assert-Equal (($installerSource -match "function _windo_profile_prompt_issues") -eq $true) $true "installer detects prompt profile issues"
Assert-Equal (($installerSource -match "function _windo_repair_profile_prompt_init") -eq $true) $true "installer repairs guarded prompt init"
Assert-Pattern $installerSource 'if \(\$Command\.Count -ge 1 -and \$Command\[0\] -eq "scan"\)' "installer handles scan command"
Assert-Equal ($installerSource.Contains('if ($Command.Count -ge 1 -and $Command[0] -eq "vault")') -eq $true) $true "installer handles vault command"
Assert-Equal ($installerSource.Contains('if ($Command.Count -ge 1 -and $Command[0] -eq "sshx")') -eq $true) $true "installer handles sshx command"
Assert-Equal ($installerSource.Contains('if ($Command.Count -ge 1 -and $Command[0] -eq "crypto")') -eq $true) $true "installer handles crypto command"
Assert-Equal (($installerSource -match "function _windo_scan_paths") -eq $true) $true "installer defines scan engine"
Assert-Equal (($installerSource -match "function _windo_vault_read_map") -eq $true) $true "installer defines vault reader"
Assert-Equal ($installerSource.Contains('$isBuiltinHelpTarget') -eq $true) $true "installer only consumes -h as help for WINDO built-ins"
Assert-Equal ($installerSource.Contains('if ($Command.Count -ge 1 -and $Command[0] -eq "-")') -eq $true) $true "installer handles account handoff syntax"
Assert-Equal (($installerSource -match "function _windo_roadmap_releases") -eq $true) $true "installer defines release runway train"
Assert-Equal ($installerSource.Contains('if ($Command.Count -ge 1 -and $Command[0] -eq "roadmap")') -eq $true) $true "installer handles roadmap command"
Assert-Equal ($installerSource.Contains("Extravaganza") -eq $false) $true "installer keeps future major reveal copy reserved"
Assert-Equal (($installerSource -match "function _windo_trust_posture") -eq $true) $true "installer defines trust posture helper"
Assert-Equal (($installerSource -match "function _windo_published_text_file_sha256") -eq $true) $true "installer defines normalized published text hash helper"
Assert-Equal ($installerSource.Contains('if ($Command.Count -ge 1 -and $Command[0] -eq "trust")') -eq $true) $true "installer handles trust command"
Assert-Equal ($installerSource.Contains("windo trust --online") -eq $true) $true "installer documents online trust checksum validation"
Assert-Equal (($installerSource -match "function _windo_syntax_shortcuts") -eq $true) $true "installer defines syntax shortcut catalog"
Assert-Equal (($installerSource -match "function _windo_syntax_doctor") -eq $true) $true "installer defines syntax doctor"
Assert-Equal ($installerSource.Contains('if ($Command.Count -ge 1 -and $Command[0] -eq "syntax")') -eq $true) $true "installer handles syntax command"
Assert-Equal ($installerSource.Contains("windo syntax [query]") -eq $true) $true "installer documents syntax command"
Assert-Equal ($installerSource.Contains("windo syntax doctor [query]") -eq $true) $true "installer documents syntax doctor"
Assert-Equal (($installerSource -match "function _windo_mesh_inventory") -eq $true) $true "installer defines mesh inventory"
Assert-Equal (($installerSource -match "function _windo_mesh_doctor") -eq $true) $true "installer defines mesh doctor"
Assert-Equal (($installerSource -match "function _windo_mesh_workbench") -eq $true) $true "installer defines mesh workbench"
Assert-Equal (($installerSource -match "function _windo_native_surface_state") -eq $true) $true "installer defines native surface state"
Assert-Equal ($installerSource.Contains('if ($Command.Count -ge 1 -and $Command[0] -eq "mesh")') -eq $true) $true "installer handles mesh command"
Assert-Equal ($installerSource.Contains("windo mesh [--json]") -eq $true) $true "installer documents mesh command"
Assert-Equal ($installerSource.Contains("windo mesh doctor [--json]") -eq $true) $true "installer documents mesh doctor command"
Assert-Equal ($installerSource.Contains("windo mesh workbench [--json]") -eq $true) $true "installer documents mesh workbench command"
Assert-Equal ($installerSource.Contains("windo mesh --html") -eq $true) $true "installer documents mesh html command"
Assert-Equal ($installerSource.Contains("windo_mesh_") -eq $true) $true "installer writes mesh html artifact"
Assert-Equal (($installerSource -match "function _windo_new_command_plan") -eq $true) $true "installer defines explain command planner"
Assert-Equal ($installerSource.Contains('if ($Command.Count -ge 1 -and $Command[0] -eq "explain")') -eq $true) $true "installer handles explain command"
Assert-Pattern ($installerSource) 'if \(\$Command\.Count -ge 1 -and \(\$Command\[0\] -eq "!!" -or \$Command\[0\] -eq "replay"\)\)' "installer handles replay command alias path"
Assert-Pattern ($installerSource) 'if \(\$Command\.Count -ge 1 -and \$Command\[0\] -eq "trace"\)' "installer handles trace command path"
Assert-Equal ($installerSource.Contains("windo explain <command...>") -eq $true) $true "installer documents explain command"
Assert-Equal ($installerSource.Contains("checksumValidation") -eq $true) $true "explain payload includes checksum posture"
Assert-Pattern ($installerSource) 'if \(\$Command\.Count -lt 2\)\s*\{[^}]*?_windo_set_exit 2' "trace usage path sets non-zero exit"
Assert-Pattern ($installerSource) 'if \(\$JsonOutput\)\s*\{[^}]*?_emit_json "trace" \$pl[^}]*?_windo_set_exit [0-9]+' "trace json path sets explicit exit code"
Assert-Equal ($installerSource.Contains("function __windo_resolve_completion_mode") -eq $true) $true "profile completer resolves completion mode"
Assert-Equal ($installerSource.Contains("function __windo_completion_specs") -eq $true) $true "profile completer has command-specific syntax specs"
Assert-Pattern ($installerSource) '\$WindoBuiltinVerbs\s*=\s*@\([\s\S]*?\)' "installer defines static builtin verb array"
$builtinVerbMatch = [regex]::Match($installerSource, '\$WindoBuiltinVerbs\s*=\s*@\((?<body>[\s\S]*?)\)', [System.Text.RegularExpressions.RegexOptions]::Singleline)
Assert-Equal ($builtinVerbMatch.Success) $true "installer parses builtin verb array block"
if ($builtinVerbMatch.Success) {
    $builtinVerbsRaw = $builtinVerbMatch.Groups["body"].Value
    Assert-Pattern $builtinVerbsRaw "'health'" "builtin verbs include health"
    Assert-Pattern $builtinVerbsRaw "'status'" "builtin verbs include status"
    Assert-Pattern $builtinVerbsRaw "'check'" "builtin verbs include check"
    Assert-Pattern $builtinVerbsRaw "'net-scan'" "builtin verbs include net-scan"
    Assert-Pattern $builtinVerbsRaw "'container'" "builtin verbs include container"
    Assert-Pattern $builtinVerbsRaw "'rdp'" "builtin verbs include rdp"
    Assert-Pattern $builtinVerbsRaw "'wsl'" "builtin verbs include wsl"
    Assert-Pattern $builtinVerbsRaw "'pyenv'" "builtin verbs include pyenv alias"
    Assert-Pattern $builtinVerbsRaw "'python'" "builtin verbs include python alias"
    Assert-Pattern $builtinVerbsRaw "'verbosity'" "builtin verbs include verbosity alias"
    Assert-Pattern $builtinVerbsRaw "'package'" "builtin verbs include package alias"
    Assert-Pattern $builtinVerbsRaw "'installer'" "builtin verbs include installer alias"
    Assert-Pattern $builtinVerbsRaw "'do'" "builtin verbs include do alias"
    Assert-Pattern $builtinVerbsRaw "'upd'" "builtin verbs include upd alias"
    Assert-Pattern $builtinVerbsRaw "'recdo'" "builtin verbs include recdo alias"
}
$helpTopicsStart = $installerSource.IndexOf("function _windo_help_topics", [StringComparison]::Ordinal)
$helpTopicsEnd = $installerSource.IndexOf("function _windo_show_help", $helpTopicsStart, [StringComparison]::Ordinal)
Assert-Equal (($helpTopicsStart -ge 0 -and $helpTopicsEnd -gt $helpTopicsStart) -eq $true) $true "help topic catalog is extractable"
if ($helpTopicsStart -ge 0 -and $helpTopicsEnd -gt $helpTopicsStart) {
    Invoke-Expression $installerSource.Substring($helpTopicsStart, $helpTopicsEnd - $helpTopicsStart)
    $helpTopics = _windo_help_topics
    $doctorHelp = @($helpTopics | Where-Object { $_.Name -eq "doctor" })
    $netScanHelp = @($helpTopics | Where-Object { $_.Name -eq "net-scan" })
    $containerHelp = @($helpTopics | Where-Object { $_.Name -eq "container" })
    $motionHelp = @($helpTopics | Where-Object { $_.Name -eq "motion" })
    $rdpHelp = @($helpTopics | Where-Object { $_.Name -eq "rdp" })
    $wslHelp = @($helpTopics | Where-Object { $_.Name -eq "wsl" })
    $preflightHelp = @($helpTopics | Where-Object { $_.Name -eq "preflight" })
    $sessionHelp = @($helpTopics | Where-Object { $_.Name -eq "session" })
    $controlHelp = @($helpTopics | Where-Object { $_.Name -eq "control" })
    $centerHelp = @($helpTopics | Where-Object { $_.Name -eq "center" })
    $helpHelp = @($helpTopics | Where-Object { $_.Name -eq "help" })
    $runHelp = @($helpTopics | Where-Object { $_.Name -eq "run" })
    $installLatestHelp = @($helpTopics | Where-Object { $_.Name -eq "install-latest" })
    $recipesHelp = @($helpTopics | Where-Object { $_.Name -eq "recipes" })
    Assert-Equal ($doctorHelp.Count -eq 1) $true "help topic catalog documents doctor"
    Assert-Equal ($doctorHelp[0].Aliases -contains "health") $true "doctor help topic lists health alias"
    $doctorSyntaxText = ($doctorHelp[0].Syntax -join "`r`n")
    Assert-Equal ($doctorSyntaxText.Contains("windo health [--json]") -or $doctorSyntaxText.Contains('windo health \[--json\]')) $true "doctor help topic documents health syntax"
    Assert-Pattern (($doctorHelp[0].Examples -join "`r`n")) "windo health --json" "doctor help topic includes health example"
    Assert-Equal ($netScanHelp.Count -eq 1) $true "help topic catalog documents net-scan"
    Assert-Equal ($containerHelp.Count -eq 1) $true "help topic catalog documents container"
    Assert-Equal ($motionHelp.Count -eq 1) $true "help topic catalog documents motion"
    Assert-Equal ($rdpHelp.Count -eq 1) $true "help topic catalog documents rdp"
    Assert-Equal ($wslHelp.Count -eq 1) $true "help topic catalog documents wsl"
    Assert-Equal ($controlHelp.Count -eq 1) $true "help topic catalog documents control"
    Assert-Equal ($centerHelp.Count -eq 1) $true "help topic catalog documents center"
    Assert-Equal ($helpHelp.Count -eq 1) $true "help topic catalog documents help topic"
    Assert-Equal ($helpHelp[0].Aliases -contains "-?") $true "help topic catalog lists -? alias"
    Assert-Equal ($helpHelp[0].Aliases -contains "/?") $true "help topic catalog lists /? alias"
    Assert-Equal ($helpHelp[0].Syntax -contains "windo -? [topic]") $true "help topic catalog documents -? syntax"
    Assert-Equal ($helpHelp[0].Syntax -contains "windo /? [topic]") $true "help topic catalog documents /? syntax"
    Assert-Equal ($runHelp.Count -eq 1) $true "help topic catalog documents run"
    Assert-Equal ($runHelp[0].Aliases -contains "do") $true "run help topic lists do alias"
    Assert-Equal ($installLatestHelp.Count -eq 1) $true "help topic catalog documents install-latest"
    Assert-Equal ($installLatestHelp[0].Aliases -contains "upd") $true "install-latest help topic lists upd alias"
    Assert-Equal ($recipesHelp.Count -eq 1) $true "help topic catalog documents recipes"
    Assert-Equal ($recipesHelp[0].Aliases -contains "recdo") $true "recipes help topic lists recdo alias"
    Assert-Pattern (($controlHelp[0].Examples -join "`r`n")) "open-windo-folder" "help topic examples include open-windo-folder action"
    Assert-Pattern (($controlHelp[0].Examples -join "`r`n")) "upgrade-history-open" "help topic examples include upgrade-history-open action"
    Assert-Pattern (($controlHelp[0].Examples -join "`r`n")) "health-snapshot-html" "help topic examples include health-snapshot-html action"
    Assert-Pattern (($controlHelp[0].Examples -join "`r`n")) "log-bundle-open" "help topic examples include log-bundle-open action"
    Assert-Pattern (($centerHelp[0].Examples -join "`r`n")) "open-windo-folder" "center help topic examples include open-windo-folder action"
    Assert-Pattern (($centerHelp[0].Examples -join "`r`n")) "upgrade-history-open" "center help topic examples include upgrade-history-open action"
    Assert-Pattern (($centerHelp[0].Examples -join "`r`n")) "health-snapshot-html" "center help topic examples include health-snapshot-html action"
    Assert-Pattern (($centerHelp[0].Examples -join "`r`n")) "log-bundle-open" "center help topic examples include log-bundle-open action"
    Assert-Pattern (($netScanHelp[0].Syntax -join "`r`n")) "windo net-scan ping <cidr\\|host\.\.\.>" "help topic catalog documents net-scan ping syntax"
    Assert-Pattern (($rdpHelp[0].Syntax -join "`r`n")) "windo rdp" "help topic catalog documents rdp syntax"
    Assert-Equal ($preflightHelp.Count -eq 1) $true "help topic catalog documents preflight"
    Assert-Equal ($preflightHelp[0].Aliases -contains "check") $true "preflight help topic lists check alias"
    $preflightSyntaxText = ($preflightHelp[0].Syntax -join "`r`n")
    Assert-Equal ($preflightSyntaxText.Contains("windo check [--json]") -or $preflightSyntaxText.Contains('windo check \[--json\]')) $true "preflight help topic documents check syntax"
    Assert-Pattern (($preflightHelp[0].Examples -join "`r`n")) "windo check --json" "preflight help topic includes check example"
    Assert-Equal ($sessionHelp.Count -eq 1) $true "help topic catalog documents session"
    Assert-Equal ($sessionHelp[0].Aliases -contains "status") $true "session help topic lists status alias"
    $sessionSyntaxText = ($sessionHelp[0].Syntax -join "`r`n")
    Assert-Equal ($sessionSyntaxText.Contains("windo status [--json]") -or $sessionSyntaxText.Contains('windo status \[--json\]')) $true "session help topic documents status syntax"
    Assert-Pattern (($sessionHelp[0].Examples -join "`r`n")) "windo status --json" "session help topic includes status example"
    Assert-Pattern (($wslHelp[0].Syntax -join "`r`n")) "windo wsl" "help topic catalog documents wsl syntax"
    Assert-Pattern (($wslHelp[0].Syntax -join "`r`n")) "windo wsl install" "help topic catalog documents wsl install syntax"
    Assert-Pattern (($wslHelp[0].Syntax -join "`r`n")) "windo wsl version" "help topic catalog documents wsl version syntax"
    Assert-Pattern (($wslHelp[0].Syntax -join "`r`n")) "windo wsl convert" "help topic catalog documents wsl convert syntax"
    Assert-Pattern (($wslHelp[0].Syntax -join "`r`n")) "windo wsl inspect" "help topic catalog documents wsl inspect syntax"
    Assert-Pattern (($wslHelp[0].Syntax -join "`r`n")) "windo wsl exec" "help topic catalog documents wsl exec syntax"
}
$completionSpecsStart = $installerSource.IndexOf("function __windo_completion_specs", [StringComparison]::Ordinal)
$completionSpecsEnd = $installerSource.IndexOf("function __windo_complete_values", $completionSpecsStart, [StringComparison]::Ordinal)
Assert-Equal (($completionSpecsStart -ge 0 -and $completionSpecsEnd -gt $completionSpecsStart) -eq $true) $true "completion spec table is extractable"
if ($completionSpecsStart -ge 0 -and $completionSpecsEnd -gt $completionSpecsStart) {
    Invoke-Expression $installerSource.Substring($completionSpecsStart, $completionSpecsEnd - $completionSpecsStart)
    $completionSpecs = __windo_completion_specs
    Assert-Equal ($completionSpecs.ContainsKey("net-scan")) $true "completion specs include net-scan"
    Assert-Equal ($completionSpecs.ContainsKey("container")) $true "completion specs include container"
    Assert-Equal ($completionSpecs.ContainsKey("rdp")) $true "completion specs include rdp"
    Assert-Equal ($completionSpecs.ContainsKey("wsl")) $true "completion specs include wsl"
    Assert-Equal ($completionSpecs.ContainsKey("pyenv")) $true "completion specs include pyenv alias"
    Assert-Equal ($completionSpecs.ContainsKey("python")) $true "completion specs include python alias"
    Assert-Equal ($completionSpecs.ContainsKey("package")) $true "completion specs include package alias"
    Assert-Equal ($completionSpecs.ContainsKey("installer")) $true "completion specs include installer alias"
    Assert-Equal ($completionSpecs.ContainsKey("verbosity")) $true "completion specs include verbosity alias"
    Assert-Equal ($completionSpecs.ContainsKey("do")) $true "completion specs include do alias"
    Assert-Equal ($completionSpecs.ContainsKey("upd")) $true "completion specs include upd alias"
    Assert-Equal ($completionSpecs.ContainsKey("recdo")) $true "completion specs include recdo alias"
    Assert-Equal ($completionSpecs.ContainsKey("context")) $true "completion specs include context command"
    Assert-Equal ($completionSpecs.ContainsKey("roadmap")) $true "completion specs include roadmap command"
    Assert-Equal ($completionSpecs.ContainsKey("history")) $true "completion specs include history command"
    Assert-Equal ($completionSpecs.ContainsKey("help")) $true "completion specs include help command"
    Assert-Equal (($completionSpecs["help"] -contains "net-scan") -and ($completionSpecs["help"] -contains "source") -and ($completionSpecs["help"] -contains "version")) $true "help completion lists representative topics"
    Assert-Equal (($completionSpecs["help"] -contains "--help") -and ($completionSpecs["help"] -contains "-h") -and ($completionSpecs["help"] -contains "-?") -and ($completionSpecs["help"] -contains "/?")) $true "help completion includes help marker aliases"
    Assert-Equal ($completionSpecs.ContainsKey("log")) $true "completion specs include log command"
    Assert-Equal ($completionSpecs.ContainsKey("control")) $true "completion specs include control"
    Assert-Equal ($completionSpecs.ContainsKey("center")) $true "completion specs include center"
    Assert-Equal (($completionSpecs["net-scan"] -contains "ping") -and ($completionSpecs["net-scan"] -contains "--json")) $true "net-scan completion includes ping and --json"
    Assert-Equal (($completionSpecs["container"] -contains "--dry-run") -and ($completionSpecs["container"] -contains "--json")) $true "container completion includes dry-run and json"
    Assert-Equal (($completionSpecs["control"] -contains "upgrade-history-open") -and ($completionSpecs["control"] -contains "health-snapshot-html") -and ($completionSpecs["control"] -contains "open-windo-folder")) $true "control completion includes control action IDs"
    Assert-Equal (($completionSpecs["center"] -contains "upgrade-history-open") -and ($completionSpecs["center"] -contains "health-snapshot-html") -and ($completionSpecs["center"] -contains "open-windo-folder")) $true "center completion includes control action IDs"
    Assert-Equal (($completionSpecs["rdp"] -contains "firewall") -and ($completionSpecs["rdp"] -contains "--json")) $true "rdp completion includes firewall and --json"
    Assert-Equal (($completionSpecs["wsl"] -contains "version") -and ($completionSpecs["wsl"] -contains "install") -and ($completionSpecs["wsl"] -contains "convert") -and ($completionSpecs["wsl"] -contains "inspect") -and ($completionSpecs["wsl"] -contains "exec") -and ($completionSpecs["wsl"] -contains "--distribution") -and ($completionSpecs["wsl"] -contains "--to") -and ($completionSpecs["wsl"] -contains "--json")) $true "wsl completion includes advanced ops and forwarding flags"
    Assert-Equal (($completionSpecs["completion"] -contains "default") -and ($completionSpecs["completion"] -contains "legacy") -and ($completionSpecs["completion"] -contains "new")) $true "completion completion includes default, legacy, and new aliases"
    Assert-Equal (($completionSpecs["pyenv"] -contains "status") -and ($completionSpecs["pyenv"] -contains "create") -and ($completionSpecs["pyenv"] -contains "--python")) $true "pyenv completion mirrors venv base verbs"
    Assert-Equal (($completionSpecs["python"] -contains "status") -and ($completionSpecs["python"] -contains "create") -and ($completionSpecs["python"] -contains "--python")) $true "python completion mirrors venv base verbs"
    Assert-Equal (($completionSpecs["package"] -contains "status") -and ($completionSpecs["package"] -contains "winget") -and ($completionSpecs["package"] -contains "search")) $true "package completion mirrors pkg package actions"
    Assert-Equal (($completionSpecs["installer"] -contains "status") -and ($completionSpecs["installer"] -contains "winget") -and ($completionSpecs["installer"] -contains "search")) $true "installer completion mirrors pkg package actions"
    Assert-Equal (($completionSpecs["verbosity"] -contains "status") -and ($completionSpecs["verbosity"] -contains "compact") -and ($completionSpecs["verbosity"] -contains "--json")) $true "verbosity completion mirrors output profile options"
    Assert-Equal (($completionSpecs["do"] -contains "--recipe") -and ($completionSpecs["do"] -contains "--dry-run")) $true "do completion mirrors run options"
    Assert-Equal (($completionSpecs["upd"] -contains "--force") -and ($completionSpecs["upd"] -contains "--non-interactive")) $true "upd completion mirrors install-latest options"
    Assert-Equal (($completionSpecs["recdo"] -contains "os-version") -and ($completionSpecs["recdo"] -contains "--dry-run")) $true "recdo completion includes recipe names and dry-run"
    Assert-Equal (($completionSpecs["context"] -contains "--json") -eq $true) $true "context completion includes --json"
    Assert-Equal (($completionSpecs["roadmap"] -contains "--json") -eq $true) $true "roadmap completion includes --json"
    Assert-Equal (($completionSpecs["history"] -contains "-n") -and ($completionSpecs["history"] -contains "--json")) $true "history completion includes limit and json flags"
    Assert-Equal (($completionSpecs["log"] -contains "-n") -and ($completionSpecs["log"] -contains "--tail") -and ($completionSpecs["log"] -contains "--json")) $true "log completion includes limit, tail and json flags"
}
Assert-Equal ($installerSource.Contains("function _windo_completion_doctor") -eq $true) $true "installer defines completion doctor"
Assert-Equal ($installerSource.Contains("function _windo_completion_repair") -eq $true) $true "installer defines completion repair"
Assert-Equal ($installerSource.Contains('if ($sub -eq "doctor")') -eq $true) $true "completion command handles doctor"
Assert-Equal ($installerSource.Contains('if ($sub -eq "repair")') -eq $true) $true "completion command handles repair"
Assert-Equal ($installerSource.Contains("trust = @('--online','--offline','--json')") -eq $true) $true "profile completer knows trust syntax"
Assert-Equal ($installerSource.Contains('if ($mode -eq "native-first") { return }') -eq $false) $true "profile completer offers WINDO verbs at empty windo prefix"
$psReadLineBlockStart = $installerSource.IndexOf('$WindoPsReadLineBlock = @', [StringComparison]::Ordinal)
$psReadLineBlockEnd = $installerSource.IndexOf('$WindoCompleterBlock = @', $psReadLineBlockStart, [StringComparison]::Ordinal)
$psReadLineProfileBlock = if ($psReadLineBlockStart -ge 0 -and $psReadLineBlockEnd -gt $psReadLineBlockStart) { $installerSource.Substring($psReadLineBlockStart, $psReadLineBlockEnd - $psReadLineBlockStart) } else { "" }
Assert-Equal ($psReadLineProfileBlock.Contains('if (-not $policy.enabled) { return }') -eq $false) $true "profile keybinding setup does not exit before completer when disabled"
Assert-Equal ($psReadLineProfileBlock.Contains('if ($null -eq $selectedPrefixChord) { return }') -eq $false) $true "profile keybinding setup does not exit before completer when binding fails"
Assert-Equal ($installerSource.Contains('^\s*windo(?:\s+|$)') -eq $true) $true "profile completer recognizes bare windo prefix"
Assert-Equal ($installerSource.Contains("Register-ArgumentCompleter -CommandName windo -Native") -eq $true) $true "profile completer uses native argument completion"
Assert-Equal ($installerSource.Contains("TabExpansion2 -inputScript `$delegate") -eq $true) $true "profile completer delegates native commands"
Assert-Equal (($installerSource.Contains('windo completion status|doctor|repair|default|legacy|new|native|stealth|native-first|hybrid|windo|builtin|builtins|off|disabled|reset [--json]')) -eq $true) $true "completion help syntax documents supported aliases"
Assert-Equal (($installerSource -match "\('w', 'w,w', 'Alt\+w', 'Shift\+Enter', 'Alt\+Enter'\)") -eq $true) $true "installer removes legacy single-key and historical windo chords"
Assert-Equal ($installerSource.Contains("Set-PSReadLineKeyHandler -Chord 'w,w' -ScriptBlock `$windoPrefixOnly")) $false "installer no longer directly binds w,w in profile block"
Assert-Equal ($installerSource.Contains("Write-Host ""  Effective      : `$(if (`$policy.enabled) { if (`$effectiveChord) { `$effectiveChord } else { '(none)' } } else { '(disabled)' })"" -ForegroundColor DarkGray")) $true "installer profile block has balanced effective-chord status expression"
Assert-Equal ($installerSource.Contains('appliedChord = $null')) $true "installer keybinding policies expose appliedChord field"
Assert-Equal (($runnerSource -match "function Get-WindoRunnerTimeoutMs") -eq $true) $true "runner exposes timeout resolution helper"
Assert-Equal (($runnerSource -match "function Test-WindoCommandLine") -eq $true) $true "runner validates command line policy"
Assert-Equal (($runnerSource -match "function Test-WindoResultPath") -eq $true) $true "runner validates result path policy"
Assert-Equal (($runnerSource -match "function Get-WindoMaxCommandChars") -eq $true) $true "runner exposes max command char policy helper"
if (($runnerSource -match "function Test-WindoCommandLine") -and ($runnerSource -match "function Test-WindoResultPath")) {
    $maxRunnerCmdCharsFn = Get-WindoFunctionTextFromSource -Source $runnerSource -Name "Get-WindoMaxCommandChars"
    $testCommandLineFn = Get-WindoFunctionTextFromSource -Source $runnerSource -Name "Test-WindoCommandLine"
    $testResultPathFn = Get-WindoFunctionTextFromSource -Source $runnerSource -Name "Test-WindoResultPath"
    $nextRequestFn = Get-WindoFunctionTextFromSource -Source $runnerSource -Name "_windo_next_request"
    if ($maxRunnerCmdCharsFn -and $testCommandLineFn -and $testResultPathFn) {
        Invoke-Expression $maxRunnerCmdCharsFn
        Invoke-Expression $testCommandLineFn
        Invoke-Expression $testResultPathFn
        Assert-Equal (Test-WindoCommandLine "Get-Process") $null "runner command validation accepts plain ASCII command"
        Assert-Equal (Test-WindoCommandLine ($null)) "Command is missing." "runner command validation rejects null command"
        Assert-Equal (Test-WindoCommandLine "a`tb") $null "runner command validation allows tab character"
        Assert-Equal (Test-WindoCommandLine "a`n") "Command contains disallowed control characters." "runner command validation rejects newline control char"

        $runnerSecureDir = Join-Path $checksumFixtureDir "secure-runner"
        $runnerResultDir = Join-Path $runnerSecureDir "results"
        New-Item -ItemType Directory -Path $runnerResultDir -Force | Out-Null
        $goodResultPath = Join-Path $runnerResultDir "windo_res.deadbeef.json"
        $badResultPath = Join-Path $runnerResultDir "windo_res.DEADBEEF.json"
        $outsideResultPath = Join-Path (Get-Location) "outside_result.json"
        $prefixCollisionResultPath = Join-Path (Split-Path $runnerResultDir) "runner-results-bad\windo_res.deadbeef.json"
        Assert-Equal (Test-WindoResultPath $goodResultPath $runnerResultDir) $null "runner result path accepts valid secure output path"
        Assert-Equal (Test-WindoResultPath $badResultPath $runnerResultDir) "OutPath file name is invalid." "runner result path rejects uppercase hash filename"
        Assert-Equal (Test-WindoResultPath $outsideResultPath $runnerResultDir) "OutPath must be under SecureDir." "runner result path enforces secure directory"
        Assert-Equal (Test-WindoResultPath $prefixCollisionResultPath $runnerResultDir) "OutPath must be under SecureDir." "runner result path rejects prefix collisions outside secure directory"
        if ($nextRequestFn) {
            Invoke-Expression $nextRequestFn
            $runnerQueueDir = Join-Path $checksumFixtureDir "runner-queue"
            $runnerNow = Get-Date "2024-01-01T12:00:00"
            $oldest = Join-Path $runnerQueueDir "windo_req.00aa.json"
            $alpha = Join-Path $runnerQueueDir "windo_req.000a.json"
            $beta = Join-Path $runnerQueueDir "windo_req.00ab.json"
            New-Item -ItemType Directory -Path $runnerQueueDir -Force | Out-Null
            Set-Content -Path $oldest -Value "{`"command`":`"Get-Date`"}" -Encoding UTF8
            Set-Content -Path $alpha -Value "{`"command`":`"Get-Date`"}" -Encoding UTF8
            Set-Content -Path $beta -Value "{`"command`":`"Get-Date`"}" -Encoding UTF8
            (Get-Item $oldest).LastWriteTime = $runnerNow.AddMinutes(-2)
            (Get-Item $alpha).LastWriteTime = $runnerNow
            (Get-Item $beta).LastWriteTime = $runnerNow
            $firstQueued = _windo_next_request $runnerQueueDir
            Assert-Equal $firstQueued.Name "windo_req.00aa.json" "runner queue selects oldest request first"
            Remove-Item $oldest -Force
            (Get-Item $alpha).LastWriteTime = $runnerNow
            (Get-Item $beta).LastWriteTime = $runnerNow
            $secondQueued = _windo_next_request $runnerQueueDir
            Assert-Equal $secondQueued.Name "windo_req.000a.json" "runner queue uses deterministic name tie-break"
            Remove-Item -Path $runnerQueueDir -Recurse -Force
        } else {
            Assert-Equal $false $true "runner exposes deterministic queue selector"
        }
        $runnerResolvePayloadFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name "_windo_resolve_artifact_payload"
        $runnerGetMemberFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name "_windo_get_member_value"
        $runnerParseResultFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name "_windo_parse_runner_result"
        $runnerToIntFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name "_windo_to_int"
        $runnerToBoolFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name "_windo_to_bool"
        $runnerMergeFn = Get-WindoFunctionTextFromSource -Source $installerSource -Name "_windo_merge_runner_output"
        if ($runnerResolvePayloadFn -and $runnerGetMemberFn -and $runnerParseResultFn -and $runnerToIntFn -and $runnerToBoolFn -and $runnerMergeFn) {
            Invoke-Expression $runnerResolvePayloadFn
            Invoke-Expression $runnerGetMemberFn
            Invoke-Expression $runnerParseResultFn
            Invoke-Expression $runnerToIntFn
            Invoke-Expression $runnerToBoolFn
            Invoke-Expression $runnerMergeFn

            $parseDir = Join-Path $checksumFixtureDir "runner-parse"
            New-Item -ItemType Directory -Path $parseDir -Force | Out-Null

            $legacyResult = Join-Path $parseDir "legacy.json"
            @{
                Timestamp  = "2026-05-10 10:00:00"
                Command    = "echo hello"
                Output     = "legacy-output"
                ExitCode   = 3
                DurationMs = 120
                RequestId  = "legacy-req"
            } | ConvertTo-Json -Compress | Set-Content -Path $legacyResult -Encoding UTF8

            $legacyParsed = _windo_parse_runner_result -OutPath $legacyResult -RequestId "fallback-req" -Command "echo hello" -FallbackDurationMs 222
            Assert-Equal $legacyParsed.ExitCode 3 "runner parser preserves legacy exit code"
            Assert-Equal $legacyParsed.Output "legacy-output" "runner parser preserves legacy output"
            Assert-Equal $legacyParsed.StdOut "" "runner parser normalizes missing StdOut to empty"
            Assert-Equal $legacyParsed.StdErr "" "runner parser normalizes missing StdErr to empty"

            $separateStreams = Join-Path $parseDir "streams.json"
            @{
                Timestamp       = "2026-05-10 10:01:00"
                Command         = "echo mixed"
                StdOut          = "OUT-MSG"
                StdErr          = "ERR-MSG"
                ExitCode        = 2
                DurationMs      = 321
                RequestId       = "streams-req"
                RunnerTimedOut  = $false
                OutputTruncated = $false
            } | ConvertTo-Json -Compress | Set-Content -Path $separateStreams -Encoding UTF8

            $streamParsed = _windo_parse_runner_result -OutPath $separateStreams -RequestId "fallback-req" -Command "echo mixed" -FallbackDurationMs 321
            Assert-Equal $streamParsed.Output "OUT-MSG`nERR-MSG" "runner parser merges StdOut and StdErr"
            Assert-Equal $streamParsed.StdOut "OUT-MSG" "runner parser preserves StdOut field"
            Assert-Equal $streamParsed.StdErr "ERR-MSG" "runner parser preserves StdErr field"
            Assert-Equal $streamParsed.RunnerTimedOut $false "runner parser preserves bool flag false"
            Assert-Equal $streamParsed.OutputTruncated $false "runner parser preserves bool flag false"

            $missingPath = Join-Path $parseDir "missing.json"
            $missingParsed = _windo_parse_runner_result -OutPath $missingPath -RequestId "missing-req" -Command "echo missing" -FallbackDurationMs 444
            Assert-Equal $missingParsed.ExitCode 1 "runner parser marks missing result as failure"
            Assert-Equal $missingParsed.Output "<FAILED TO READ RESULT>" "runner parser returns failure message for unreadable result"
            Assert-Equal $missingParsed.RequestId "missing-req" "runner parser keeps fallback request id"
        } else {
            Assert-Equal $false $true "installer exposes runner bridge parser helpers"
        }
    } else {
        Assert-Equal $false $true "runner exposes command and result validators"
    }
}
Assert-Equal (($runnerSource -match "function _dpapi_unprotect") -eq $true) $true "runner provides dpapi unprotect helper"
Assert-Equal (($runnerSource -match "function _windo_resolve_artifact_payload") -eq $true) $true "runner resolves artifact payload envelopes"
Assert-Equal (($runnerSource -match "_windo_resolve_preserve_environment") -eq $true) $true "runner resolves protected preserve-environment payloads"
Assert-Equal (($runnerSource -match "PreserveEnvironment") -eq $true) $true "runner reads preserve-environment payload"
Assert-Equal (($runnerSource -match "_windo_get_member_value|_windo_unprotect_text") -eq $true) $true "runner includes preserve payload helpers"
Assert-Equal (($runnerSource -match "Invoke-WindoPreserveEnvironment") -eq $true) $true "runner applies preserved environment"
Assert-Equal (($runnerSource -match "Restore-WindoPreserveEnvironment") -eq $true) $true "runner restores preserved environment"

Assert-Equal ($installerSource.Contains("function _windo_modules_discover_rows") -eq $true) $true "installer defines module discovery helper"
Assert-Equal ($installerSource.Contains("WINDO optional modules loader") -eq $true) $true "installer profile includes optional modules loader stub"
Assert-Equal ($installerSource.Contains("enabledModules") -eq $true) $true "installer prefs include enabledModules for modules"
Assert-Equal ($installerSource.Contains("_windo_get_recipe_command_line") -eq $true) $true "installer defines recipe command resolver"
Assert-Equal ($installerSource.Contains("_windo_get_recipe_preview") -eq $true) $true "installer defines recipe preview resolver"
Assert-Equal ($installerSource.Contains('if ($Command.Count -ge 1 -and $Command[0] -eq "venv")') -eq $true) $true "installer handles venv command"
Assert-Equal ($installerSource.Contains('if ($Command.Count -ge 1 -and $Command[0] -eq "pkg")') -eq $true) $true "installer handles pkg command"
Assert-Equal ($installerSource.Contains("recipes run") -eq $true) $true "installer handles recipes run rewrite"
Assert-Equal ($installerSource.Contains("recipes preview") -eq $true) $true "installer handles recipes preview"
Assert-Equal ($installerSource.Contains("'defender-status'") -eq $true) $true "installer bundles defender-status recipe"
Assert-Equal ($installerSource.Contains("'network-routes'") -eq $true) $true "installer bundles network-routes recipe"
Assert-Equal ($installerSource.Contains("'whoami-all'") -eq $true) $true "installer bundles whoami-all recipe"
Assert-Equal ($installerSource.Contains("'windows-update-services'") -eq $true) $true "installer bundles windows-update-services recipe"
Assert-Equal ($installerSource.Contains("No task, request file, result file, or audit entry will be created.") -eq $true) $true "recipe dry-run exits before elevation artifacts"
Assert-Equal ($installerSource.Contains("WINDO_LAST_REQUEST_ID") -eq $true) $true "installer sets WINDO_LAST_REQUEST_ID after elevation"
Assert-Equal ($installerSource.Contains("_windo_extras_index_url") -eq $true) $true "installer defines extras index URL helper"
Assert-Equal ($installerSource.Contains("extrasIndexUrl") -eq $true) $true "installer config json includes extrasIndexUrl"
Assert-Equal ($installerSource.Contains("WINDO_EXTRAS_INDEX_URL") -eq $true) $true "installer config lists WINDO_EXTRAS_INDEX_URL"
Assert-Equal ($installerSource.Contains("function _windo_keybinding_inspect_chord_for_doctor") -eq $true) $true "installer defines keybindings doctor inspector"
Assert-Equal ($installerSource.Contains("keybindings doctor") -eq $true) $true "installer handles keybindings doctor subcommand"
Assert-Equal ($installerSource.Contains("lastAudit") -eq $true) $true "installer session payload includes lastAudit"
Assert-Equal ($installerSource.Contains("function Repair-WindoProfileText") -eq $true) $true "installer repairs corrupted orphan WINDO profile blocks"
Assert-Equal ($installerSource.Contains('$profileText = Repair-WindoProfileText -Text $profileText') -eq $true) $true "installer normalizes profile text before writing profile block"
Assert-Equal ($installerSource.Contains('$repaired = Repair-WindoProfileText -Text $text') -eq $true) $true "installer removes existing profile blocks through the repair path"
$BeginMarker = "# >>> WINDO-BEGIN >>>"
$EndMarker = "# <<< WINDO-END <<<"
$repairStart = $installerSource.IndexOf("function Repair-WindoProfileText", [StringComparison]::Ordinal)
$repairEnd = $installerSource.IndexOf("function Get-NoWindowActionArgs", $repairStart, [StringComparison]::Ordinal)
Assert-Equal (($repairStart -ge 0 -and $repairEnd -gt $repairStart) -eq $true) $true "installer repair function can be extracted"
if ($repairStart -ge 0 -and $repairEnd -gt $repairStart) {
    Invoke-Expression $installerSource.Substring($repairStart, $repairEnd - $repairStart)
    $brokenProfile = "pre`r`n`"`r`n    if (!(Test-Path `$SecureDir)) { }`r`n    `$ProfileBlockBegin = `"$BeginMarker`"`r`n    `$ProfileBlockEnd = `"$EndMarker`"`r`n    Write-Host `"[windo] orphan`"`r`n$BeginMarker`r`nfunction windo { }`r`n$EndMarker`r`npost`r`n"
    Assert-Equal (Repair-WindoProfileText -Text $brokenProfile) "pre`r`npost`r`n" "profile repair removes orphan payload before valid block"
}
Assert-Equal ($installerSource.Contains("function _windo_verify_log_state") -eq $true) $true "installer has shared audit-chain verifier"
Assert-Equal ($installerSource.Contains('if ($Command.Count -ge 1 -and $Command[0] -eq "dashboard")') -eq $true) $true "installer handles dashboard command"
Assert-Equal ($installerSource.Contains("windo dashboard --html") -eq $true) $true "installer help documents dashboard html output"
Assert-Equal ($installerSource.Contains("windo_dashboard_") -eq $true) $true "installer writes dashboard html artifact"
Assert-Equal ($installerSource.Contains('if ($Command.Count -ge 1 -and $Command[0] -eq "preflight")') -eq $true) $true "installer handles preflight command"
Assert-Equal ($installerSource.Contains('if ($Command.Count -ge 1 -and $Command[0] -eq "launchpad")') -eq $true) $true "installer handles launchpad command"
Assert-Equal ($installerSource.Contains("windo launchpad --tray") -eq $true) $true "installer help documents tray launchpad"
Assert-Equal ($installerSource.Contains("return @(`$rows.ToArray())") -eq $true) $true "preflight returns flat check rows"
Assert-Equal ($installerSource.Contains("`$recipeMap.GetEnumerator()") -eq $true) $true "launchpad enumerates built-in recipes"
Assert-Equal ($installerSource.Contains("windo_launchpad_tray.ps1") -eq $true) $true "installer can write native tray launchpad script"
Assert-Equal ($installerSource.Contains("windo_surface_panel.ps1") -eq $true) $true "installer can write native surface panel script"
Assert-Equal ($installerSource.Contains("windo_power_studio.ps1") -eq $true) $true "installer can write Power Studio script"
Assert-Equal ($installerSource.Contains("windo_start_tray.ps1") -eq $true) $true "installer can write startup tray script"
Assert-Equal ($installerSource.Contains("windo.cmd") -eq $true) $true "installer can write command shim"
Assert-Equal ($installerSource.Contains("WINDO Power Studio.lnk") -eq $true) $true "installer can write Windows shortcuts"
Assert-Equal ($installerSource.Contains("WINDO_TRAY_ICON") -eq $true) $true "tray launchpad can use branded icon override"
Assert-Equal ($installerSource.Contains("windo-tray-ready.ico") -eq $true) $true "tray launchpad resolves Enterprise brand icon"
Assert-Equal ($installerSource.Contains("function _windo_resolve_tray_icon") -eq $true) $true "installer resolves status-aware tray icon"
Assert-Equal ($installerSource.Contains("windo-tray-denied.ico") -eq $true) $true "installer knows denied tray icon asset"
Assert-Equal ($installerSource.Contains("function Show-WindoStatusToast") -eq $true) $true "tray launchpad has designed status toast window"
Assert-Equal ($installerSource.Contains("FlowLayoutPanel") -eq $true) $true "tray launchpad popup uses scrollable action layout"
Assert-Equal ($installerSource.Contains("WINDO Surface Panel") -eq $true) $true "surface panel has native window title"
Assert-Equal ($installerSource.Contains("WINDO Power Studio") -eq $true) $true "Power Studio has native window title"
Assert-Equal ($installerSource.Contains('id = "surface-panel"') -eq $true) $true "control catalog includes surface-panel action"
Assert-Equal ($installerSource.Contains('id = "power-studio"') -eq $true) $true "control catalog includes power-studio action"
Assert-Equal ($installerSource.Contains('id = "integrate-repair"') -eq $true) $true "control catalog includes integrate-repair action"
Assert-Equal ($installerSource.Contains('id = "integrate-startup"') -eq $true) $true "control catalog includes integrate-startup action"
Assert-Equal ($installerSource.Contains("Preview, queue, or run curated actions") -eq $true) $true "Power Studio documents preview queue run boundary"
Assert-Equal ($installerSource.Contains("V8.4 command center") -eq $true) $true "launchpad html carries V8.4 command center copy"
Assert-Equal ($installerSource.Contains("WINDO Dashboard") -eq $true) $true "dashboard html carries branded dashboard title"
Assert-Equal ($installerSource.Contains("V8.4 Installer") -eq $true) $true "installer is branded as V8.4"
Assert-Equal ($bootstrapSource.Contains("V8.4 bootstrap") -eq $true) $true "bootstrap has V8.4 visuals"
$panelStart = $installerSource.IndexOf("function _windo_surface_panel_script_text", [StringComparison]::Ordinal)
$panelEnd = $installerSource.IndexOf("function _windo_start_surface_panel", $panelStart, [StringComparison]::Ordinal)
Assert-Equal (($panelStart -ge 0 -and $panelEnd -gt $panelStart) -eq $true) $true "surface panel script function can be extracted"
if ($panelStart -ge 0 -and $panelEnd -gt $panelStart) {
    $WindoVersion = "5.4.0"
    Invoke-Expression $installerSource.Substring($panelStart, $panelEnd - $panelStart)
    $panelScript = (_windo_surface_panel_script_text).Replace("__WINDO_ICON_PATH__", "")
    $panelErrors = $null
    $panelTokens = $null
    [System.Management.Automation.Language.Parser]::ParseInput($panelScript, [ref]$panelTokens, [ref]$panelErrors) | Out-Null
    Assert-Equal ($panelErrors.Count) 0 "generated surface panel script parses"
}
Assert-Equal ($installerSource.Contains("function _windo_power_studio_script_text") -eq $true) $true "Power Studio script function exists"
$studioStart = $installerSource.IndexOf("function _windo_power_studio_script_text", [StringComparison]::Ordinal)
$studioEnd = $installerSource.IndexOf("function _windo_start_power_studio", $studioStart, [StringComparison]::Ordinal)
Assert-Equal (($studioStart -ge 0 -and $studioEnd -gt $studioStart) -eq $true) $true "Power Studio script function can be extracted"
if ($studioStart -ge 0 -and $studioEnd -gt $studioStart) {
    $WindoVersion = "5.4.0"
    Invoke-Expression $installerSource.Substring($studioStart, $studioEnd - $studioStart)
    $studioScript = (_windo_power_studio_script_text).Replace("__WINDO_ICON_PATH__", "")
    $studioErrors = $null
    $studioTokens = $null
    [System.Management.Automation.Language.Parser]::ParseInput($studioScript, [ref]$studioTokens, [ref]$studioErrors) | Out-Null
    Assert-Equal ($studioErrors.Count) 0 "generated Power Studio script parses"
}
Assert-Equal ((Test-Path (Join-Path $Root "docs\releases\RELEASE_NOTES_v5.4.1.md")) -eq $true) $true "v5.4.1 release notes exist"
Assert-Equal ((Test-Path (Join-Path $Root "docs\releases\RELEASE_NOTES_v5.4.0.md")) -eq $true) $true "v5.4.0 release notes exist"
Assert-Equal ((Test-Path (Join-Path $Root "docs\releases\RELEASE_NOTES_v5.3.0.md")) -eq $true) $true "v5.3.0 release notes exist"
Assert-Equal ((Test-Path (Join-Path $Root "docs\releases\RELEASE_NOTES_v5.2.0.md")) -eq $true) $true "v5.2.0 release notes exist"
Assert-Equal ((Test-Path (Join-Path $Root "docs\releases\RELEASE_NOTES_v5.1.1.md")) -eq $true) $true "v5.1.1 release notes exist"
Assert-Equal ((Test-Path (Join-Path $Root "docs\releases\RELEASE_NOTES_v5.1.0.md")) -eq $true) $true "v5.1.0 release notes exist"
Assert-Equal ((Test-Path (Join-Path $Root "docs\releases\RELEASE_NOTES_v5.0.0.md")) -eq $true) $true "v5.0.0 release notes exist"
Assert-Equal ((Test-Path (Join-Path $Root "docs\releases\RELEASE_NOTES_v4.4.0.md")) -eq $true) $true "v4.4.0 release notes exist"
Assert-Equal ((Test-Path (Join-Path $Root "docs\releases\RELEASE_NOTES_v4.5.0.md")) -eq $true) $true "v4.5.0 release notes exist"
Assert-Equal ((Test-Path (Join-Path $Root "docs\releases\RELEASE_NOTES_v4.6.0.md")) -eq $true) $true "v4.6.0 release notes exist"
Assert-Equal ((Test-Path (Join-Path $Root "docs\v5-roadmap.md")) -eq $true) $true "v5 roadmap doc exists"
Assert-Equal ((($readmeSource.Contains("v5.4.1+") -eq $true) -or ($readmeSource.Contains("RELEASE_NOTES_v5.4.1") -eq $true)) -eq $true) $true "README references v5.4.1 release notes"
Assert-Equal ($readmeSource.Contains("windo rdp [status") -eq $true) $true "README documents windo rdp command"
Assert-Equal ($readmeSource.Contains("windo wsl [status") -eq $true) $true "README documents windo wsl command"
Assert-Equal ((Test-Path (Join-Path $Root "native-companion\README.md")) -eq $true) $true "native companion scaffold exists"
Assert-Equal ((Test-Path (Join-Path $Root "brand\Enterprise\assets\ico\windo-tray-ready.ico")) -eq $true) $true "Enterprise branded tray ico exists"
Assert-Equal ((Test-Path (Join-Path $Root "brand\assets\banners\banner-blue-left.png")) -eq $true) $true "README banner asset exists"
Assert-Equal ($readmeSource.Contains("brand/assets/banners/banner-blue-left.png") -eq $false) $true "README no longer uses full-width blue banner asset"
Assert-Equal ($readmeSource.Contains("brand/winDO.png") -eq $true) $true "README uses constrained winDO logo asset"
Assert-Equal ($readmeSource.Contains("brand/assets/logos/transparent-github-avatar-panel.png") -eq $true) $true "README uses transparent avatar panel asset"
Assert-Equal ($readmeSource.Contains("brand/Enterprise/assets/svg/windo-brand-mark-contained-dark.svg") -eq $true) $true "README uses Enterprise contained brand mark"
Assert-Equal ($readmeSource.Contains("brand/assets/transparent/logos/wordmark-tagline.png") -eq $false) $true "README no longer uses rough cropped wordmark asset"

$extrasIndex = Join-Path $root "extras\index.json"
if (Test-Path -LiteralPath $extrasIndex) {
    $idxRaw = Get-Content -LiteralPath $extrasIndex -Raw | ConvertFrom-Json
    Assert-Equal ($null -ne $idxRaw.schemaVersion) $true "extras index has schemaVersion"
    Assert-Equal ($idxRaw.items.Count -ge 1) $true "extras index has at least one item"
}

Assert-Equal ($moduleSource.Contains("wincmd -Name 'netops-resolve'") -eq $true) $true "network-ops module defines netops-resolve"
Assert-Equal ($moduleSource.Contains("wincmd -Name 'netops-subnet-scan'") -eq $true) $true "network-ops module defines netops-subnet-scan"
Assert-Equal ($moduleSource.Contains("wincmd -Name 'netops-arp-map'") -eq $true) $true "network-ops module defines netops-arp-map"
Assert-Equal ($moduleSource.Contains("wincmd -Name 'netops-rdp-vnc'") -eq $true) $true "network-ops module defines netops-rdp-vnc"
Assert-Equal ($moduleSource.Contains("wincmd -Name 'netops-wsl'") -eq $true) $true "network-ops module defines netops-wsl"
Assert-Equal (($moduleSource.Contains("_netops_emit_payload") -and $moduleSource.Contains("_emit_json")) -eq $true) $true "network-ops module emits WINDO JSON payloads in rdp/wsl paths"
Assert-Equal ($moduleSource.Contains("function _netops_build_rdp_firewall_payload") -eq $true) $true "network-ops exposes helper for structured firewall payloads"
Assert-Equal (($moduleSource.Contains("shouldApply = if") -and $moduleSource.Contains("dryRun = ")) -eq $true) $true "network-ops tracks dry-run confirmation state"
Assert-Equal ($moduleManifest.Contains('"requiresWindoVersion": "8.4.0"') -eq $true) $true "network-ops module declares WINDO 8.4.0 minimum"

$modsDoc = Join-Path $root "docs\modules-and-extras.md"
Assert-Equal (Test-Path -LiteralPath $modsDoc) $true "docs/modules-and-extras.md exists"
$fwDoc = Join-Path $root "docs\framework-wave.md"
Assert-Equal (Test-Path -LiteralPath $fwDoc) $true "docs/framework-wave.md exists"
$fwRaw = Get-Content -Path $fwDoc -Raw
Assert-Equal ($fwRaw.Contains("Tier 1") -eq $true) $true "framework-wave documents Tier 1"
Assert-Equal ($fwRaw.Contains("windo modules") -eq $true) $true "framework-wave documents windo modules"
$aiDoc = Join-Path $root "docs\ai-bridge.md"
Assert-Equal (Test-Path -LiteralPath $aiDoc) $true "docs/ai-bridge.md exists"
Assert-Equal ($installerSource.Contains("_windo_ai_credential_env_snapshot") -eq $true) $true "installer defines AI env snapshot helper"
Assert-Equal ($installerSource.Contains("_windo_ai_ollama_host_advisory") -eq $true) $true "installer defines Ollama host advisory helper"
Assert-Equal ($installerSource.Contains("'ollama-list'") -eq $true) $true "installer bundles ollama-list recipe"
$jsonSchemaDoc = Join-Path $root "docs\json-schema.md"
$jsonSchemaRaw = Get-Content -Path $jsonSchemaDoc -Raw
$buildDoc = Join-Path $root "docs\build.md"
$buildRaw = Get-Content -Path $buildDoc -Raw
Assert-Equal ($jsonSchemaRaw.Contains('## `session` payload') -eq $true) $true "json-schema documents session payload"
Assert-Equal ($jsonSchemaRaw.Contains("extrasIndexUrl") -eq $true) $true "json-schema documents config extrasIndexUrl"
Assert-Equal ($jsonSchemaRaw.Contains('## `completion` payload') -eq $true) $true "json-schema documents completion payload"
Assert-Equal ($jsonSchemaRaw.Contains('## `output` payload') -eq $true) $true "json-schema documents output payload"
Assert-Equal ($jsonSchemaRaw.Contains('## `motion` payload') -eq $true) $true "json-schema documents motion payload"
Assert-Equal ($jsonSchemaRaw.Contains('## `surface` payload') -eq $true) $true "json-schema documents surface payload"
Assert-Equal ($jsonSchemaRaw.Contains('## `integrate` payload') -eq $true) $true "json-schema documents integrate payload"
Assert-Equal ($jsonSchemaRaw.Contains('## `control` payload') -eq $true) $true "json-schema documents control payload"
Assert-Equal ($jsonSchemaRaw.Contains('## `container` payload') -eq $true) $true "json-schema documents container payload"
Assert-Equal ($jsonSchemaRaw.Contains('## `rdp` payload') -eq $true) $true "json-schema documents rdp payload"
Assert-Equal ($jsonSchemaRaw.Contains('## `wsl` payload') -eq $true) $true "json-schema documents wsl payload"
Assert-Equal ($jsonSchemaRaw.Contains('## `net-scan` payload') -eq $true) $true "json-schema documents net-scan payload"
Assert-Equal ($jsonSchemaRaw -match "(?i)not wrapped by .*windo envelope" -eq $true) $true "json-schema documents network-ops module output format"
Assert-Equal ($jsonSchemaRaw.Contains('## `signal` payload') -eq $true) $true "json-schema documents signal payload"
Assert-Equal ($jsonSchemaRaw.Contains('## `center` payload') -eq $true) $true "json-schema documents center payload"
Assert-Equal ($jsonSchemaRaw.Contains('## `edition` payload') -eq $true) $true "json-schema documents edition payload"
Assert-Equal ($jsonSchemaRaw.Contains('Control request file') -eq $true) $true "json-schema documents control request file"
Assert-Equal ($jsonSchemaRaw.Contains('Control result file') -eq $true) $true "json-schema documents control result file"
Assert-Equal ($jsonSchemaRaw.Contains('## `scan` payload') -eq $true) $true "json-schema documents scan payload"
Assert-Equal ($jsonSchemaRaw.Contains('## `vault` payload') -eq $true) $true "json-schema documents vault payload"
Assert-Equal ($jsonSchemaRaw.Contains('## `sshx` payload') -eq $true) $true "json-schema documents sshx payload"
Assert-Equal ($jsonSchemaRaw.Contains('## `crypto` payload') -eq $true) $true "json-schema documents crypto payload"
Assert-Equal ($jsonSchemaRaw.Contains('## `venv` payload') -eq $true) $true "json-schema documents venv payload"
Assert-Equal ($jsonSchemaRaw.Contains('## `pkg` payload') -eq $true) $true "json-schema documents pkg payload"
Assert-Equal ($jsonSchemaRaw.Contains('## `roadmap` payload') -eq $true) $true "json-schema documents roadmap payload"
Assert-Equal ($jsonSchemaRaw.Contains('## `trust` payload') -eq $true) $true "json-schema documents trust payload"
Assert-Equal ($jsonSchemaRaw.Contains('## `source` payload') -eq $true) $true "json-schema documents source payload"
Assert-Equal ($jsonSchemaRaw.Contains("publishedChecksum") -eq $true) $true "json-schema documents trust published checksum"
Assert-Equal ($jsonSchemaRaw.Contains('## `syntax` payload') -eq $true) $true "json-schema documents syntax payload"
Assert-Equal ($jsonSchemaRaw.Contains("doctor") -eq $true) $true "json-schema documents syntax doctor payload"
Assert-Equal ($jsonSchemaRaw.Contains('## `mesh` payload') -eq $true) $true "json-schema documents mesh payload"
Assert-Equal ($jsonSchemaRaw.Contains("htmlPath") -eq $true) $true "json-schema documents mesh htmlPath"
Assert-Equal ($jsonSchemaRaw.Contains("windo mesh workbench --json") -eq $true) $true "json-schema documents mesh workbench payload"
Assert-Equal ($jsonSchemaRaw.Contains("nativeSurface") -eq $true) $true "json-schema documents native surface payload"
Assert-Equal ($jsonSchemaRaw.Contains('## `explain` payload') -eq $true) $true "json-schema documents explain payload"
Assert-Equal ($jsonSchemaRaw.Contains("keybindings doctor") -eq $true) $true "json-schema documents keybindings doctor"
Assert-Equal ($jsonSchemaRaw.Contains('## `modules` payload') -eq $true) $true "json-schema documents modules payload"
Assert-Equal ($jsonSchemaRaw.Contains('## `recipes` payload') -eq $true) $true "json-schema documents recipes payload"
Assert-Equal ($jsonSchemaRaw.Contains("preview.dryRunCommand") -eq $true) $true "json-schema documents recipe preview payload"
Assert-Equal ($jsonSchemaRaw.Contains('## `extras` payload') -eq $true) $true "json-schema documents extras payload"
Assert-Equal ($jsonSchemaRaw.Contains('## `dev` payload') -eq $true) $true "json-schema documents dev payload"
Assert-Equal ($jsonSchemaRaw.Contains('## `prompt` payload') -eq $true) $true "json-schema documents prompt payload"
Assert-Equal ($jsonSchemaRaw.Contains('## `help` payload') -eq $true) $true "json-schema documents help payload"
Assert-Equal ($jsonSchemaRaw.Contains('## `export` payload') -eq $true) $true "json-schema documents export payload"
Assert-Pattern $installerSource '_emit_json "help" \@\{\s*topic = \$null\s*available = @\(\$topics \| Select-Object Name,Category,Aliases,Summary,Syntax,Description,Notes\)\s*usage = "windo \[--json\] \[--dry-run\] \[<global sudo flag>\] <command>"\s*exitCode = 0\s*\}' "help command emits JSON discovery payload"
Assert-Pattern $installerSource '_emit_json "container" \@\{\s*runtime = \$runtimeUsed\s*subcommand = \$sub\s*runtimeCommand = \$runtimeArgList\s*dryRun = \$true\s*commandLine = \$renderCommand\s*exitCode = 0\s*\}' "container --dry-run emits complete JSON"
Assert-Pattern $installerSource '_emit_json "motion" \@\{\s*saved = \$true;\s*motion = \$policy;\s*exitCode = 0\s*\}' "motion save emits saved JSON payload"
Assert-Pattern $installerSource '_emit_json "motion" \@\{\s*reset = \$true;\s*motion = \$policy;\s*exitCode = 0\s*\}' "motion reset emits reset JSON payload"
Assert-Pattern $installerSource '_emit_json "motion" \@\{\s*motion = \$policy;\s*pulseRendered = \[bool\]\$ran;\s*exitCode = 0\s*\}' "motion pulse emits pulseRendered JSON payload"
Assert-Pattern $installerSource '_emit_json "motion" \@\{\s*motion = \$policy;\s*exitCode = 0\s*\}' "motion status emits status JSON payload"
Assert-Pattern $installerSource '_emit_json "rdp"\s+\$payload|_emit_json "rdp"\s+\@\{\s*subcommand = "status"' "rdp status emits status payload"
Assert-Pattern $installerSource '_emit_json "rdp"[\s\S]*subcommand = "firewall"[\s\S]*action = "status"[\s\S]*requestedPorts = @\(\$ports\)[\s\S]*rules = @\(\$rules\)' "rdp firewall emits status payload"
Assert-Pattern $installerSource '_emit_json "rdp"[\s\S]*subcommand = "firewall"[\s\S]*action = \$action[\s\S]*updates = @\(' "rdp firewall disable emits mutating payload"
Assert-Pattern $installerSource '_emit_json "rdp" \@\{\s*subcommand = "config"[\s\S]*requested = \@\{' "rdp config emits config payload"
Assert-Pattern $installerSource '_emit_json "rdp" \@\{\s*subcommand = "config"[\s\S]*result = \@' "rdp config emits result payload"
Assert-Pattern $installerSource '_emit_json "rdp" \@\{\s*subcommand = "troubleshoot"[\s\S]*host = \$host[\s\S]*portChecks = @\(\$probeRows\)[\s\S]*exitCode' "rdp troubleshoot emits payload"
Assert-Pattern $installerSource '_emit_json "wsl"[\s\S]*command\s*=\s*"status"[\s\S]*wslAvailable\s*=\s*\[bool\]\$wslExe[\s\S]*distros\s*=\s*@\(\$distros\.distros\)[\s\S]*default\s*=\s*\$distros\.defaultName[\s\S]*exitCode' "wsl status emits status payload"
Assert-Pattern $installerSource '_emit_json "wsl" \s*\$payload' "wsl check install emits preflight payload"
Assert-Pattern $installerSource '_emit_json "wsl" \@\{\s*command = "check distro"[\s\S]*distro = \$found\.distro[\s\S]*exists = \$true[\s\S]*applyRequired = \$true' "wsl check distro emits preflight payload"
Assert-Pattern $installerSource '_emit_json "wsl" \@\{\s*command = "check import"[\s\S]*distribution = \$name[\s\S]*path = \$path' "wsl check import emits preflight payload"
Assert-Pattern $installerSource '_emit_json "wsl" \@\{\s*command = "check export"[\s\S]*distribution = \$name[\s\S]*out = \$out' "wsl check export emits preflight payload"
Assert-Pattern $installerSource '_emit_json "wsl" \@\{\s*command = "launch"[\s\S]*distro = \$distro[\s\S]*dryRun = \$true' "wsl launch dry-run emits payload"
Assert-Pattern $installerSource '_emit_json "wsl" \@\{\s*command = "launch"[\s\S]*distro = \$distro[\s\S]*output = @\(\$res\.output\)' "wsl launch execution emits payload"
Assert-Pattern $installerSource '_emit_json "wsl" \@\{\s*command = "path"[\s\S]*direction = \$direction[\s\S]*path = \$targetPath[\s\S]*converted = \$converted' "wsl path emits conversion payload"
Assert-Equal ($installerSource.Contains("auditIncludedInExcerpt") -eq $true) $true "installer export json includes auditIncludedInExcerpt"
Assert-Equal ($buildRaw.Contains("Sync-VersionSnapshot.ps1") -eq $true) $true "build.md documents Sync-VersionSnapshot.ps1"
Assert-Equal ($buildRaw.Contains("v5-roadmap.md") -eq $true) $true "build.md documents v5 roadmap snapshot"
Assert-Equal ($installerSource.Contains("native-companion") -or (Get-Content -Path (Join-Path $root "tools\Sync-VersionSnapshot.ps1") -Raw).Contains("native-companion")) $true "snapshot tool preserves native companion scaffold"
$roadmapDoc = Join-Path $root "docs\v5-roadmap.md"
$roadmapRaw = Get-Content -Path $roadmapDoc -Raw
Assert-Equal ($roadmapRaw.Contains("windo trust") -eq $true) $true "v5 roadmap documents trust command"
Assert-Equal ($roadmapRaw.Contains("windo syntax") -eq $true) $true "v5 roadmap documents syntax command"
Assert-Equal ($roadmapRaw.Contains("windo explain") -eq $true) $true "v5 roadmap documents explain command"
Assert-Equal ($roadmapRaw.Contains("windo source") -eq $true) $true "v5 roadmap documents source command"
Assert-Equal ($roadmapRaw.Contains("windo mesh") -eq $true) $true "v5 roadmap documents mesh command"
Assert-Equal ($roadmapRaw.Contains("windo surface") -eq $true) $true "v5 roadmap documents surface command"
Assert-Equal ($roadmapRaw.Contains("windo integrate") -eq $true) $true "v5 roadmap documents integrate command"
Assert-Equal ($roadmapRaw.Contains("windo motion") -eq $true) $true "v5 roadmap documents motion command"
Assert-Equal ($roadmapRaw.Contains("windo control") -eq $true) $true "v5 roadmap documents control command"
Assert-Equal ($roadmapRaw.Contains("windo signal") -eq $true) $true "v5 roadmap documents signal command"
Assert-Equal ($roadmapRaw.Contains("windo center") -eq $true) $true "v5 roadmap documents center command"
Assert-Equal ($roadmapRaw.Contains("windo edition") -eq $true) $true "v5 roadmap documents edition command"
Assert-Equal ($roadmapRaw.Contains("windo mesh doctor") -eq $true) $true "v5 roadmap documents mesh doctor command"
Assert-Equal ($roadmapRaw.Contains("windo mesh workbench") -eq $true) $true "v5 roadmap documents mesh workbench command"
Assert-Equal ($roadmapRaw.Contains("Extravaganza") -eq $false) $true "roadmap keeps future major reveal copy reserved"

if ($failed -gt 0) {
    Write-Host "Test-WindoLogic: $failed failure(s)." -ForegroundColor Red
    exit 1
}
Write-Host "Test-WindoLogic: OK." -ForegroundColor Cyan


