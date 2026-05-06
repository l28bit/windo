# Logic tests for shared snippets (no live WINDO profile). Run: ./tools/Test-WindoLogic.ps1
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root "src\windo\snippets\IntegrityLevels.ps1")
. (Join-Path $root "src\windo\snippets\StatsTimeFilter.ps1")
. (Join-Path $root "src\windo\snippets\WindoConfigEffective.ps1")

$failed = 0
function Test-WindoNormalizePublishedInstallerSha256([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $m = [regex]::Match($Text, '[A-Fa-f0-9]{64}')
    if (-not $m.Success) { return $null }
    return $m.Value.ToUpperInvariant()
}
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

Assert-Equal ($installerSource.Contains('$WindoVersion = "5.3.0"') -eq $true) $true "installer version is 5.3.0"
Assert-Equal ($bootstrapSource.Contains("WINDO 5.3.0 Limited Edition bootstrap") -eq $true) $true "bootstrap banner is current"
Assert-Equal ($bootstrapSource.Contains("Save-WindoBootstrapPublishedInstaller") -eq $true) $true "bootstrap downloads installer API-first"
Assert-Equal ($bootstrapSource.Contains("contents/windo_install.ps1?ref=Exodus") -eq $true) $true "bootstrap knows GitHub Contents API installer URL"
Assert-Equal ($bootstrapSource.Contains('$Repo = "https://raw.githubusercontent.com/l28bit/windo/Exodus/windo_install.ps1"') -eq $false) $true "bootstrap no longer hardcodes raw installer as primary source"
Assert-Equal (($installerSource -match "function _windo_normalize_published_installer_sha256") -eq $true) $true "installer normalizes published installer sha256"
Assert-Equal (($installerSource -match "function _windo_get_published_installer_sha256") -eq $true) $true "installer resolves published checksum with API/raw fallback"
Assert-Equal (($installerSource -match "function _windo_get_published_installer_text") -eq $true) $true "installer resolves published installer with API/raw fallback"
Assert-Equal ($installerSource.Contains('if ($Command.Count -ge 1 -and $Command[0] -eq "source")') -eq $true) $true "installer handles source command"
Assert-Equal ($installerSource.Contains("api.github.com/repos/l28bit/windo/contents/checksums/installer.sha256?ref=Exodus") -eq $true) $true "installer uses GitHub Contents API for checksum lookup"
Assert-Equal (($bootstrapSource -match '\[A-Fa-f0-9\]\{64\}') -eq $true) $true "bootstrap uses 64-hex regex for published checksum"
Assert-Equal ($bootstrapSource.Contains("Get-WindoBootstrapPublishedChecksum") -eq $true) $true "bootstrap uses API/raw checksum resolver"
Assert-Equal ($installerSource.Contains('if ($Command.Count -ge 1 -and $Command[0] -eq "repair")') -eq $true) $true "installer handles repair command"
Assert-Equal (($installerSource -match "function _windo_parse_timeout_override_ms") -eq $true) $true "installer parses timeout override"
Assert-Equal (($installerSource -match "PreserveEnvironment") -eq $true) $true "installer captures preserve-env payload"
Assert-Equal (($installerSource -match "TimeoutOverrideMs") -eq $true) $true "installer stores timeout override in request"
Assert-Equal (($installerSource -match "function _windo_resolve_completion_policy") -eq $true) $true "installer resolves completion policy"
Assert-Equal ($installerSource.Contains('if ($Command.Count -ge 1 -and $Command[0] -eq "completion")') -eq $true) $true "installer handles completion command"
Assert-Equal (($installerSource -match "function _windo_resolve_output_policy") -eq $true) $true "installer resolves output policy"
Assert-Equal ($installerSource.Contains('if ($Command.Count -ge 1 -and $Command[0] -eq "output")') -eq $true) $true "installer handles output command"
Assert-Equal (($installerSource -match "function _windo_resolve_motion_policy") -eq $true) $true "installer resolves motion policy"
Assert-Equal ($installerSource.Contains('if ($Command.Count -ge 1 -and $Command[0] -eq "motion")') -eq $true) $true "installer handles motion command"
Assert-Equal (($installerSource -match "function _windo_surface_state") -eq $true) $true "installer defines native surface state command payload"
Assert-Equal (($installerSource -match "function _windo_surface_panel_script_text") -eq $true) $true "installer defines native surface panel script"
Assert-Equal (($installerSource -match "function _windo_start_surface_panel") -eq $true) $true "installer starts native surface panel"
Assert-Equal (($installerSource -match "function _windo_power_studio_script_text") -eq $true) $true "installer defines Power Studio script"
Assert-Equal (($installerSource -match "function _windo_start_power_studio") -eq $true) $true "installer starts Power Studio"
Assert-Equal ($installerSource.Contains('if ($Command.Count -ge 1 -and $Command[0] -eq "surface")') -eq $true) $true "installer handles surface command"
Assert-Equal (($installerSource -match "function _windo_control_state") -eq $true) $true "installer defines control plane state command payload"
Assert-Equal (($installerSource -match "function _windo_control_action_catalog") -eq $true) $true "installer defines control plane action catalog"
Assert-Equal (($installerSource -match "function _windo_control_execute_next") -eq $true) $true "installer defines control queue executor"
Assert-Equal (($installerSource -match "function _windo_signal_state") -eq $true) $true "installer defines Signal Deck state"
Assert-Equal (($installerSource -match "function _windo_center_state") -eq $true) $true "installer defines Command Center state"
Assert-Equal (($installerSource -match "function _windo_edition_state") -eq $true) $true "installer defines Limited Edition state"
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
Assert-Equal ($installerSource.Contains("windo edition open") -eq $true) $true "installer documents edition open"
Assert-Equal ($installerSource.Contains("Motion Pulse") -eq $true) $true "tray launchpad exposes motion pulse action"
Assert-Equal ($installerSource.Contains("Run Next Queued") -eq $true) $true "tray launchpad exposes run next queued action"
Assert-Equal ($installerSource.Contains("Surface Panel") -eq $true) $true "tray launchpad exposes surface panel action"
Assert-Equal ($installerSource.Contains("Power Studio") -eq $true) $true "tray launchpad exposes Power Studio action"
Assert-Equal (($installerSource -match "function _windo_profile_prompt_issues") -eq $true) $true "installer detects prompt profile issues"
Assert-Equal (($installerSource -match "function _windo_repair_profile_prompt_init") -eq $true) $true "installer repairs guarded prompt init"
Assert-Equal ($installerSource.Contains('if ($Command.Count -ge 1 -and $Command[0] -eq "scan")') -eq $true) $true "installer handles scan command"
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
Assert-Equal ($installerSource.Contains("windo explain <command...>") -eq $true) $true "installer documents explain command"
Assert-Equal ($installerSource.Contains("checksumValidation") -eq $true) $true "explain payload includes checksum posture"
Assert-Equal ($installerSource.Contains("function __windo_resolve_completion_mode") -eq $true) $true "profile completer resolves completion mode"
Assert-Equal ($installerSource.Contains("function __windo_completion_specs") -eq $true) $true "profile completer has command-specific syntax specs"
Assert-Equal ($installerSource.Contains("trust = @('--online','--offline','--json')") -eq $true) $true "profile completer knows trust syntax"
Assert-Equal ($installerSource.Contains('if ($mode -eq "native-first") { return }') -eq $false) $true "profile completer offers WINDO verbs at empty windo prefix"
Assert-Equal ($installerSource.Contains('^\s*windo(?:\s+|$)') -eq $true) $true "profile completer recognizes bare windo prefix"
Assert-Equal ($installerSource.Contains("Register-ArgumentCompleter -CommandName windo -Native") -eq $true) $true "profile completer uses native argument completion"
Assert-Equal ($installerSource.Contains("TabExpansion2 -inputScript `$delegate") -eq $true) $true "profile completer delegates native commands"
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
Assert-Equal ($installerSource.Contains("Preview, queue, or run curated actions") -eq $true) $true "Power Studio documents preview queue run boundary"
Assert-Equal ($installerSource.Contains("Exodus Limited Edition command center") -eq $true) $true "launchpad html carries limited edition copy"
Assert-Equal ($installerSource.Contains("WINDO Dashboard") -eq $true) $true "dashboard html carries branded dashboard title"
Assert-Equal ($installerSource.Contains("Limited Edition Installer") -eq $true) $true "installer is branded as limited edition"
Assert-Equal ($bootstrapSource.Contains("Limited Edition bootstrap") -eq $true) $true "bootstrap has limited edition visuals"
$panelStart = $installerSource.IndexOf("function _windo_surface_panel_script_text", [StringComparison]::Ordinal)
$panelEnd = $installerSource.IndexOf("function _windo_start_surface_panel", $panelStart, [StringComparison]::Ordinal)
Assert-Equal (($panelStart -ge 0 -and $panelEnd -gt $panelStart) -eq $true) $true "surface panel script function can be extracted"
if ($panelStart -ge 0 -and $panelEnd -gt $panelStart) {
    $WindoVersion = "5.3.0"
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
    $WindoVersion = "5.3.0"
    Invoke-Expression $installerSource.Substring($studioStart, $studioEnd - $studioStart)
    $studioScript = (_windo_power_studio_script_text).Replace("__WINDO_ICON_PATH__", "")
    $studioErrors = $null
    $studioTokens = $null
    [System.Management.Automation.Language.Parser]::ParseInput($studioScript, [ref]$studioTokens, [ref]$studioErrors) | Out-Null
    Assert-Equal ($studioErrors.Count) 0 "generated Power Studio script parses"
}
Assert-Equal ((Test-Path (Join-Path $Root "docs\releases\RELEASE_NOTES_v5.3.0.md")) -eq $true) $true "v5.3.0 release notes exist"
Assert-Equal ((Test-Path (Join-Path $Root "docs\releases\RELEASE_NOTES_v5.2.0.md")) -eq $true) $true "v5.2.0 release notes exist"
Assert-Equal ((Test-Path (Join-Path $Root "docs\releases\RELEASE_NOTES_v5.1.1.md")) -eq $true) $true "v5.1.1 release notes exist"
Assert-Equal ((Test-Path (Join-Path $Root "docs\releases\RELEASE_NOTES_v5.1.0.md")) -eq $true) $true "v5.1.0 release notes exist"
Assert-Equal ((Test-Path (Join-Path $Root "docs\releases\RELEASE_NOTES_v5.0.0.md")) -eq $true) $true "v5.0.0 release notes exist"
Assert-Equal ((Test-Path (Join-Path $Root "docs\releases\RELEASE_NOTES_v4.4.0.md")) -eq $true) $true "v4.4.0 release notes exist"
Assert-Equal ((Test-Path (Join-Path $Root "docs\releases\RELEASE_NOTES_v4.5.0.md")) -eq $true) $true "v4.5.0 release notes exist"
Assert-Equal ((Test-Path (Join-Path $Root "docs\releases\RELEASE_NOTES_v4.6.0.md")) -eq $true) $true "v4.6.0 release notes exist"
Assert-Equal ((Test-Path (Join-Path $Root "docs\v5-roadmap.md")) -eq $true) $true "v5 roadmap doc exists"
Assert-Equal ($readmeSource.Contains("RELEASE_NOTES_v5.3.0.md") -eq $true) $true "README links v5.3.0 release notes"
Assert-Equal ((Test-Path (Join-Path $Root "native-companion\README.md")) -eq $true) $true "native companion scaffold exists"
Assert-Equal ((Test-Path (Join-Path $Root "brand\Enterprise\assets\ico\windo-tray-ready.ico")) -eq $true) $true "Enterprise branded tray ico exists"
Assert-Equal ((Test-Path (Join-Path $Root "brand\assets\banners\banner-blue-left.png")) -eq $true) $true "README banner asset exists"
Assert-Equal ($readmeSource.Contains("brand/assets/banners/banner-blue-left.png") -eq $true) $true "README uses blue banner asset"
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
Assert-Equal ($jsonSchemaRaw.Contains('## `control` payload') -eq $true) $true "json-schema documents control payload"
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
