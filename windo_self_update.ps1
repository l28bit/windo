$ErrorActionPreference = "Stop"

$RunnerPath = "__RUNNER_PATH__"
$StampFile  = "__STAMP_FILE__"
$TaskName   = "WindoElevatedRunner"
$UserId     = "__USER_ID__"

function Write-TextFileAtomic {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter()][System.Text.Encoding]$Encoding = (New-Object System.Text.UTF8Encoding($false))
    )
    $dir = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($dir) -and !(Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $tmp = Join-Path $dir (".windo_tmp_" + [Guid]::NewGuid().ToString("n") + ".tmp")
    try {
        [System.IO.File]::WriteAllText($tmp, $Content, $Encoding)
        Move-Item -LiteralPath $tmp -Destination $Path -Force
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
}

function Write-Trace {
    param([string]$Message)
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $Message" | Add-Content -Path $StampFile -Encoding UTF8
}

function Get-WindoScheduledTask {
    param([Parameter(Mandatory=$true)][string]$TaskName)
    Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
}

function Set-WindoScheduledTask {
    param([Parameter(Mandatory=$true)][string]$TaskName, [Parameter(Mandatory=$true)]$Action)
    Set-ScheduledTask -TaskName $TaskName -Action $Action | Out-Null
}

function Register-WindoScheduledTask {
    param(
        [Parameter(Mandatory=$true)][string]$TaskName,
        [Parameter(Mandatory=$true)]$Action,
        [Parameter(Mandatory=$true)]$Principal,
        [Parameter(Mandatory=$true)]$Settings
    )
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Principal $Principal -Settings $Settings -Force | Out-Null
}

function New-WindoScheduledTaskAction {
    param([Parameter(Mandatory=$true)][string]$Execute, [Parameter(Mandatory=$true)][string]$Argument)
    New-ScheduledTaskAction -Execute $Execute -Argument $Argument
}

function New-WindoScheduledTaskPrincipal {
    param([Parameter(Mandatory=$true)][string]$UserId, [Parameter(Mandatory=$true)][string]$LogonType)
    New-ScheduledTaskPrincipal -UserId $UserId -LogonType $LogonType -RunLevel Highest
}

function New-WindoScheduledTaskSettingsSet {
    param([switch]$StartWhenAvailable, [switch]$AllowStartIfOnBatteries, [switch]$DontStopIfGoingOnBatteries)
    New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
}

"SELF-UPDATE START" | Write-TextFileAtomic -Path $StampFile -Encoding (New-Object System.Text.UTF8Encoding($false))

try {
    try {
        Import-Module ScheduledTasks -ErrorAction Stop
        Write-Trace "Imported ScheduledTasks"
    } catch {
        Write-Trace "ScheduledTasks module unavailable; task maintenance is not possible in this context."
        Write-Trace "SELF-UPDATE END (SKIPPED)"
        exit 0
    }

    $PwshwCmd = Get-Command "pwshw.exe" -ErrorAction SilentlyContinue
    $escapedRunnerPath = $RunnerPath.Replace("'", "''")
    if ($PwshwCmd) {
        $Exe = $PwshwCmd.Source
        $Arg = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File '$escapedRunnerPath'"
        Write-Trace ("Using pwshw.exe: " + $Exe)
    } else {
        $Exe = "powershell.exe"
        $Arg = "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File '$escapedRunnerPath'"
        Write-Trace "Using powershell.exe hidden fallback"
    }

    $Action = New-WindoScheduledTaskAction -Execute $Exe -Argument $Arg

    try {
        Get-WindoScheduledTask -TaskName $TaskName | Out-Null
        Set-WindoScheduledTask -TaskName $TaskName -Action $Action | Out-Null
        $updated = Get-WindoScheduledTask -TaskName $TaskName -ErrorAction Stop
        $updatedAction = @($updated.Actions | Select-Object -First 1)
        if (
            $null -eq $updatedAction -or
            $updatedAction.Count -eq 0 -or
            ([string]$updatedAction[0].Execute -ine $Exe) -or
            ([string]$updatedAction[0].Arguments -ine $Arg) -or
            ($null -eq $updated.Principal) -or
            ([string]$updated.Principal.UserId -ine $UserId) -or
            ([string]$updated.Principal.RunLevel -ne "Highest") -or
            ($null -eq $updated.Settings) -or
            (-not $updated.Settings.StartWhenAvailable) -or
            (-not $updated.Settings.AllowStartIfOnBatteries) -or
            (-not $updated.Settings.DontStopIfGoingOnBatteries)
        ) {
            Write-Trace ("VERIFY failed for " + $TaskName + " after update")
            Write-Trace ("EXPECTED: " + $Exe + " " + $Arg)
            if ($null -ne $updatedAction -and $updatedAction.Count -gt 0) {
                Write-Trace ("ACTUAL: " + [string]$updatedAction[0].Execute + " " + [string]$updatedAction[0].Arguments)
            }
            exit 1
        }
        Write-Trace ("Updated main task action -> " + $Exe + " " + $Arg)
    } catch {
        $Principal = New-WindoScheduledTaskPrincipal -UserId $UserId -LogonType Interactive
        $Settings  = New-WindoScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        Register-WindoScheduledTask -TaskName $TaskName -Action $Action -Principal $Principal -Settings $Settings | Out-Null
        $updated = Get-WindoScheduledTask -TaskName $TaskName -ErrorAction Stop
        $updatedAction = @($updated.Actions | Select-Object -First 1)
        if (
            $null -eq $updated -or
            $null -eq $updatedAction -or
            $updatedAction.Count -eq 0 -or
            ([string]$updatedAction[0].Execute -ine $Exe) -or
            ([string]$updatedAction[0].Arguments -ine $Arg) -or
            $null -eq $updated.Principal -or
            ([string]$updated.Principal.UserId -ine $UserId) -or
            ([string]$updated.Principal.RunLevel -ne "Highest") -or
            ($null -eq $updated.Settings) -or
            (-not $updated.Settings.StartWhenAvailable) -or
            (-not $updated.Settings.AllowStartIfOnBatteries) -or
            (-not $updated.Settings.DontStopIfGoingOnBatteries)
        ) {
            Write-Trace ("VERIFY failed for recreated " + $TaskName + " after registration")
            Write-Trace ("EXPECTED: " + $Exe + " " + $Arg)
            if ($null -ne $updatedAction -and $updatedAction.Count -gt 0) {
                Write-Trace ("ACTUAL: " + [string]$updatedAction[0].Execute + " " + [string]$updatedAction[0].Arguments)
            }
            exit 1
        }
        Write-Trace ("Recreated main task -> " + $Exe + " " + $Arg)
    }

    Write-Trace "SELF-UPDATE END"
    exit 0
}
catch {
    Write-Trace ("FATAL: " + $_.Exception.Message)
    try { Write-Trace ("TYPE: " + $_.Exception.GetType().FullName) } catch {}
    exit 1
}
