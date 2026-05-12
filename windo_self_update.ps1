$ErrorActionPreference = "Stop"

$RunnerPath = "C:\Users\<user>\.pwsh_secure\windo_runner.ps1"
$StampFile  = "C:\Users\<user>\.pwsh_secure\windo_self_update_last.txt"
$TaskName   = "WindoElevatedRunner"
$UserId     = "DOMAIN\User"

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
    param([Parameter(Mandatory=$true)][string]$TaskName, [Parameter(Mandatory=$true)][object]$Action)
    Set-ScheduledTask -TaskName $TaskName -Action $Action | Out-Null
}

function Register-WindoScheduledTask {
    param(
        [Parameter(Mandatory=$true)][string]$TaskName,
        [Parameter(Mandatory=$true)][object]$Action,
        [Parameter(Mandatory=$true)][object]$Principal,
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
    Import-Module ScheduledTasks -ErrorAction Stop
    Write-Trace "Imported ScheduledTasks"

    $PwshwCmd = Get-Command "pwshw.exe" -ErrorAction SilentlyContinue
    if ($PwshwCmd) {
        $Exe = $PwshwCmd.Source
        $Arg = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $RunnerPath + '"'
        Write-Trace ("Using pwshw.exe: " + $Exe)
    } else {
        $Exe = "powershell.exe"
        $Arg = '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $RunnerPath + '"'
        Write-Trace "Using powershell.exe hidden fallback"
    }

    $Action = New-WindoScheduledTaskAction -Execute $Exe -Argument $Arg

    try {
        Get-WindoScheduledTask -TaskName $TaskName | Out-Null
        Set-WindoScheduledTask -TaskName $TaskName -Action $Action
        Write-Trace ("Updated main task action -> " + $Exe + " " + $Arg)
    } catch {
        $Principal = New-WindoScheduledTaskPrincipal -UserId $UserId -LogonType Interactive
        $Settings  = New-WindoScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        Register-WindoScheduledTask -TaskName $TaskName -Action $Action -Principal $Principal -Settings $Settings
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
