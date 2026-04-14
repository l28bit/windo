# Logic tests for shared snippets (no live WINDO profile). Run: ./tools/Test-WindoLogic.ps1
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root "src\windo\snippets\IntegrityLevels.ps1")
. (Join-Path $root "src\windo\snippets\StatsTimeFilter.ps1")
. (Join-Path $root "src\windo\snippets\WindoConfigEffective.ps1")

$failed = 0
function Assert-Equal($a, $b, $msg) {
    if ($a -ne $b) {
        Write-Host "FAIL: $msg  (expected '$b', got '$a')" -ForegroundColor Red
        $script:failed++
    }
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

$installerSource = Get-Content -Path (Join-Path $root "windo_install.ps1") -Raw
$runnerSource = Get-Content -Path (Join-Path $root "windo_runner.ps1") -Raw

Assert-Equal (($installerSource -match "function _windo_parse_timeout_override_ms") -eq $true) $true "installer parses timeout override"
Assert-Equal (($installerSource -match "PreserveEnvironment") -eq $true) $true "installer captures preserve-env payload"
Assert-Equal (($installerSource -match "TimeoutOverrideMs") -eq $true) $true "installer stores timeout override in request"
Assert-Equal (($installerSource -match "\('w', 'w,w', 'Alt\+w', 'Shift\+Enter', 'Alt\+Enter'\)") -eq $true) $true "installer removes legacy single-key and historical windo chords"
Assert-Equal ($installerSource.Contains("Set-PSReadLineKeyHandler -Chord 'w,w' -ScriptBlock `$windoPrefixOnly")) $false "installer no longer directly binds w,w in profile block"
Assert-Equal ($installerSource.Contains("Write-Host ""  Effective      : `$(if (`$policy.enabled) { if (`$effectiveChord) { `$effectiveChord } else { '(none)' } } else { '(disabled)' })"" -ForegroundColor DarkGray")) $true "installer profile block has balanced effective-chord status expression"
Assert-Equal ($installerSource.Contains('appliedChord = $null')) $true "installer keybinding policies expose appliedChord field"
Assert-Equal (($runnerSource -match "function Get-WindoRunnerTimeoutMs") -eq $true) $true "runner exposes timeout resolution helper"
Assert-Equal (($runnerSource -match "function _dpapi_unprotect") -eq $true) $true "runner provides dpapi unprotect helper"
Assert-Equal (($runnerSource -match "_windo_resolve_preserve_environment") -eq $true) $true "runner resolves protected preserve-environment payloads"
Assert-Equal (($runnerSource -match "PreserveEnvironment") -eq $true) $true "runner reads preserve-environment payload"
Assert-Equal (($runnerSource -match "_windo_get_member_value|_windo_unprotect_text") -eq $true) $true "runner includes preserve payload helpers"
Assert-Equal (($runnerSource -match "Invoke-WindoPreserveEnvironment") -eq $true) $true "runner applies preserved environment"
Assert-Equal (($runnerSource -match "Restore-WindoPreserveEnvironment") -eq $true) $true "runner restores preserved environment"

Assert-Equal ($installerSource.Contains("function _windo_modules_discover_rows") -eq $true) $true "installer defines module discovery helper"
Assert-Equal ($installerSource.Contains("WINDO optional modules loader") -eq $true) $true "installer profile includes optional modules loader stub"
Assert-Equal ($installerSource.Contains("enabledModules") -eq $true) $true "installer prefs include enabledModules for modules"
Assert-Equal ($installerSource.Contains("_windo_get_recipe_command_line") -eq $true) $true "installer defines recipe command resolver"
Assert-Equal ($installerSource.Contains("recipes run") -eq $true) $true "installer handles recipes run rewrite"
Assert-Equal ($installerSource.Contains("WINDO_LAST_REQUEST_ID") -eq $true) $true "installer sets WINDO_LAST_REQUEST_ID after elevation"
Assert-Equal ($installerSource.Contains("_windo_extras_index_url") -eq $true) $true "installer defines extras index URL helper"
Assert-Equal ($installerSource.Contains("extrasIndexUrl") -eq $true) $true "installer config json includes extrasIndexUrl"
Assert-Equal ($installerSource.Contains("WINDO_EXTRAS_INDEX_URL") -eq $true) $true "installer config lists WINDO_EXTRAS_INDEX_URL"
Assert-Equal ($installerSource.Contains("function _windo_keybinding_inspect_chord_for_doctor") -eq $true) $true "installer defines keybindings doctor inspector"
Assert-Equal ($installerSource.Contains("keybindings doctor") -eq $true) $true "installer handles keybindings doctor subcommand"
Assert-Equal ($installerSource.Contains("lastAudit") -eq $true) $true "installer session payload includes lastAudit"

$extrasIndex = Join-Path $root "extras\index.json"
if (Test-Path -LiteralPath $extrasIndex) {
    $idxRaw = Get-Content -LiteralPath $extrasIndex -Raw | ConvertFrom-Json
    Assert-Equal ($null -ne $idxRaw.schemaVersion) $true "extras index has schemaVersion"
    Assert-Equal ($idxRaw.items.Count -ge 1) $true "extras index has at least one item"
}

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
Assert-Equal ($jsonSchemaRaw.Contains("keybindings doctor") -eq $true) $true "json-schema documents keybindings doctor"
Assert-Equal ($jsonSchemaRaw.Contains('## `modules` payload') -eq $true) $true "json-schema documents modules payload"
Assert-Equal ($jsonSchemaRaw.Contains('## `recipes` payload') -eq $true) $true "json-schema documents recipes payload"
Assert-Equal ($jsonSchemaRaw.Contains('## `extras` payload') -eq $true) $true "json-schema documents extras payload"
Assert-Equal ($jsonSchemaRaw.Contains('## `dev` payload') -eq $true) $true "json-schema documents dev payload"
Assert-Equal ($jsonSchemaRaw.Contains('## `prompt` payload') -eq $true) $true "json-schema documents prompt payload"
Assert-Equal ($jsonSchemaRaw.Contains('## `help` payload') -eq $true) $true "json-schema documents help payload"
Assert-Equal ($jsonSchemaRaw.Contains('## `export` payload') -eq $true) $true "json-schema documents export payload"
Assert-Equal ($installerSource.Contains("auditIncludedInExcerpt") -eq $true) $true "installer export json includes auditIncludedInExcerpt"
Assert-Equal ($buildRaw.Contains("Sync-VersionSnapshot.ps1") -eq $true) $true "build.md documents Sync-VersionSnapshot.ps1"

if ($failed -gt 0) {
    Write-Host "Test-WindoLogic: $failed failure(s)." -ForegroundColor Red
    exit 1
}
Write-Host "Test-WindoLogic: OK." -ForegroundColor Cyan
