# Aligned with the embedded `windo` function in windo_install.ps1 (v3.0+).
# Copy into installer/profile code or dot-source during development; not loaded automatically.

function Build-WindoJsonEnvelope {
    param(
        [Parameter(Mandatory = $true)][string]$SchemaVersion,
        [Parameter(Mandatory = $true)][string]$WindoVersion,
        [Parameter(Mandatory = $true)][string]$CommandName,
        [Parameter(Mandatory = $true)]$Payload,
        [hashtable]$Meta = $null
    )
    $osDesc = ""
    try { $osDesc = [System.Environment]::OSVersion.VersionString } catch { $osDesc = "unknown" }
    $m = $Meta
    if (-not $m) {
        $m = @{
            psEdition = [string]$PSVersionTable.PSEdition
            psVersion = $PSVersionTable.PSVersion.ToString()
            osVersion = $osDesc
        }
    }
    [ordered]@{
        schemaVersion = $SchemaVersion
        windoVersion  = $WindoVersion
        command       = $CommandName
        generatedAt   = (Get-Date -Format "o")
        meta          = $m
        payload       = $Payload
    }
}
