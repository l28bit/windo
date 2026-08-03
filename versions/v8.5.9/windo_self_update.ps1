$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RunnerPath = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("__RUNNER_PATH_B64__"))
$StampFile  = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("__STAMP_FILE_B64__"))
$TaskName   = "__TASK_MAIN__"
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
    param(
        [switch]$StartWhenAvailable,
        [switch]$AllowStartIfOnBatteries,
        [switch]$DontStopIfGoingOnBatteries,
        [string]$MultipleInstances = "IgnoreNew"
    )
    New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances $MultipleInstances
}

function Test-WindoSelfUpdateTaskHealth {
    param(
        [Parameter(Mandatory=$true)]$Task,
        [Parameter(Mandatory=$true)][string]$ExpectedExecute,
        [Parameter(Mandatory=$true)][string]$ExpectedArgument,
        [Parameter(Mandatory=$true)][string]$ExpectedUserId
    )
    if ($null -eq $Task -or $null -eq $Task.Principal -or $null -eq $Task.Settings) { return $false }
    $actions = @($Task.Actions)
    if ($actions.Count -ne 1) { return $false }
    if ([string]$actions[0].Execute -ine $ExpectedExecute -or [string]$actions[0].Arguments -ine $ExpectedArgument) { return $false }
    if (
        [string]$Task.Principal.UserId -ine $ExpectedUserId -or
        [string]$Task.Principal.RunLevel -ne "Highest" -or
        [string]$Task.Principal.LogonType -ne "Interactive"
    ) { return $false }

    $settingsProperties = @($Task.Settings.PSObject.Properties.Name)
    $allowOnBatteries = if ($settingsProperties -contains "AllowStartIfOnBatteries") {
        [bool]$Task.Settings.AllowStartIfOnBatteries
    } elseif ($settingsProperties -contains "DisallowStartIfOnBatteries") {
        -not [bool]$Task.Settings.DisallowStartIfOnBatteries
    } else { $false }
    $dontStopOnBatteries = if ($settingsProperties -contains "DontStopIfGoingOnBatteries") {
        [bool]$Task.Settings.DontStopIfGoingOnBatteries
    } elseif ($settingsProperties -contains "StopIfGoingOnBatteries") {
        -not [bool]$Task.Settings.StopIfGoingOnBatteries
    } else { $false }
    return (
        [bool]$Task.Settings.StartWhenAvailable -and
        $allowOnBatteries -and
        $dontStopOnBatteries -and
        [string]$Task.Settings.MultipleInstances -eq "IgnoreNew"
    )
}

"SELF-UPDATE START" | Write-TextFileAtomic -Path $StampFile -Encoding (New-Object System.Text.UTF8Encoding($false))

try {
    try {
        Import-Module ScheduledTasks -ErrorAction Stop
        Write-Trace "Imported ScheduledTasks"
    } catch {
        Write-Trace "ScheduledTasks module unavailable; task maintenance is not possible in this context."
        Write-Trace "SELF-UPDATE END (FAILED)"
        exit 1
    }

    $PwshwCmd = Get-Command "pwshw.exe" -ErrorAction SilentlyContinue
    $quotedRunnerPath = [char]34 + ([System.IO.Path]::GetFullPath($RunnerPath)) + [char]34
    if ($PwshwCmd) {
        $Exe = $PwshwCmd.Source
        $Arg = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File $quotedRunnerPath"
        Write-Trace ("Using pwshw.exe: " + $Exe)
    } else {
        $Exe = "powershell.exe"
        $Arg = "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File $quotedRunnerPath"
        Write-Trace "Using powershell.exe hidden fallback"
    }

    $Action = New-WindoScheduledTaskAction -Execute $Exe -Argument $Arg

    try {
        Get-WindoScheduledTask -TaskName $TaskName | Out-Null
        Set-WindoScheduledTask -TaskName $TaskName -Action $Action | Out-Null
        $updated = Get-WindoScheduledTask -TaskName $TaskName
        if (-not (Test-WindoSelfUpdateTaskHealth -Task $updated -ExpectedExecute $Exe -ExpectedArgument $Arg -ExpectedUserId $UserId)) {
            Write-Trace ("VERIFY failed for " + $TaskName + " after update")
            Write-Trace ("EXPECTED: " + $Exe + " " + $Arg)
            throw "Updated task health verification failed; recreating the owned scoped task."
        }
        Write-Trace ("Updated main task action -> " + $Exe + " " + $Arg)
    } catch {
        $Principal = New-WindoScheduledTaskPrincipal -UserId $UserId -LogonType Interactive
        $Settings  = New-WindoScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        Register-WindoScheduledTask -TaskName $TaskName -Action $Action -Principal $Principal -Settings $Settings | Out-Null
        $updated = Get-WindoScheduledTask -TaskName $TaskName
        if (-not (Test-WindoSelfUpdateTaskHealth -Task $updated -ExpectedExecute $Exe -ExpectedArgument $Arg -ExpectedUserId $UserId)) {
            Write-Trace ("VERIFY failed for recreated " + $TaskName + " after registration")
            Write-Trace ("EXPECTED: " + $Exe + " " + $Arg)
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
