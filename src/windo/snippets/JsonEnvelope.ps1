# Aligned with the embedded `windo` function in windo_install.ps1 (v2.6+).
# Copy into installer/profile code or dot-source during development; not loaded automatically.

function Build-WindoJsonEnvelope {
    param(
        [Parameter(Mandatory = $true)][string]$SchemaVersion,
        [Parameter(Mandatory = $true)][string]$WindoVersion,
        [Parameter(Mandatory = $true)][string]$CommandName,
        [Parameter(Mandatory = $true)]$Payload
    )
    [ordered]@{
        schemaVersion = $SchemaVersion
        windoVersion  = $WindoVersion
        command       = $CommandName
        generatedAt   = (Get-Date -Format "o")
        payload       = $Payload
    }
}
