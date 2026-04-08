# Mirrors windo_install.ps1 embedded _is_sha256_hex and _integrity_component_level (keep in sync when changing trust rules).
function Test-WindoSha256Hex {
    param([string]$s)
    if ($null -eq $s -or $s.Length -ne 64) { return $false }
    $s -match '^[0-9A-Fa-f]{64}$'
}

function Get-WindoIntegrityComponentLevel {
    param([string]$Actual, [string]$Expected)
    if ($Actual -eq "(missing)" -or $Actual -eq "(hash-error)") { return "UNKNOWN" }
    if ($Expected -match '^\(manifest' -or $Expected -eq "(unknown-key)") { return "UNKNOWN" }
    if ($Actual -eq $Expected) { return "OK" }
    if ((Test-WindoSha256Hex $Actual) -and (Test-WindoSha256Hex $Expected)) { return "TAMPERED" }
    return "DRIFT"
}
