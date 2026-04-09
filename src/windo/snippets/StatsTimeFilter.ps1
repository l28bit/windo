# Mirrors windo_install.ps1 _windo_filter_entries_by_time / stats cutoff rules (test + maintainer reference).
function Get-WindoStatsTimeCutoff {
    param(
        [Nullable[datetime]]$SinceDate,
        [Nullable[int]]$LastDays
    )
    if ($null -ne $SinceDate) {
        return $SinceDate.Date
    }
    if ($null -ne $LastDays -and [int]$LastDays -gt 0) {
        return (Get-Date).Date.AddDays(-[int]$LastDays)
    }
    return $null
}

function Invoke-WindoFilterAuditEntriesByTime {
    param(
        $Entries,
        [Nullable[datetime]]$CutoffDate
    )
    if ($null -eq $CutoffDate) { return @($Entries) }
    $out = [System.Collections.ArrayList]@()
    foreach ($e in $Entries) {
        try {
            $ts = [DateTime]::Parse([string]$e.Timestamp, [System.Globalization.CultureInfo]::InvariantCulture)
            if ($ts -ge $CutoffDate) { [void]$out.Add($e) }
        } catch { }
    }
    return @($out)
}
