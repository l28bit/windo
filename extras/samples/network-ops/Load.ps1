<#
WINDO module: network-ops
Loads via Documents\windo\modules loader after the WINDO profile block.
Compatible with:
- module.json name/entry/requiresWindoVersion contract
- id-based enablement in windo_prefs.json
- dot-sourced execution semantics (non-fatal when a module fails)

Output contract:
- netops-rdp-vnc and netops-wsl use _emit_json with the WINDO envelope `rdp` or `wsl` when AsJson is present.
- netops-resolve, netops-subnet-scan, netops-arp-map, netops-netcat-send, and netops-netcat-recv
  emit native command objects and are not wrapped by the WINDO `command` envelope.

Commands are registered through wincmd when they are not already present.
#>

$WindoModuleId = 'network-ops'

if (-not (Get-Variable -Name __WindoNetOpsLoaded -Scope Global -ErrorAction SilentlyContinue)) {
    $global:__WindoNetOpsLoaded = $false
}
if ($global:__WindoNetOpsLoaded) { return }
$global:__WindoNetOpsLoaded = $true

if (-not (Get-Command -Name wincmd -ErrorAction SilentlyContinue)) {
    function global:wincmd {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)][string]$Name,
            [Parameter(Mandatory)][ScriptBlock]$ScriptBlock,
            [string]$Description = ""
        )
        if ($Name -notmatch '^[A-Za-z_][A-Za-z0-9_-]{0,50}$') {
            throw "wincmd: invalid command name '$Name'."
        }
        if (Get-Command -Name $Name -ErrorAction SilentlyContinue) {
            Write-Verbose ("wincmd skip " + $Name + ": command already exists.")
            return
        }
        Set-Item -Path ("Function:\global:" + $Name) -Value $ScriptBlock
        Write-Verbose ("wincmd registered " + $Name + ($(if ($Description) { " - " + $Description } else { "" } ))
    }
}

function _netops_is_admin {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [System.Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function _netops_emit_payload {
    param(
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory)]$Payload,
        [switch]$AsJson
    )
    if ($AsJson -and (Get-Command -Name _emit_json -ErrorAction SilentlyContinue)) {
        _emit_json $Command $Payload
        return $true
    }
    return $false
}

function _netops_uint_from_ip {
    param([Parameter(Mandatory)][string]$IpAddress)
    $bytes = [System.Net.IPAddress]::Parse($IpAddress).GetAddressBytes()
    [Array]::Reverse($bytes)
    return [BitConverter]::ToUInt32($bytes, 0)
}

function _netops_ip_from_uint {
    param([Parameter(Mandatory)][uint32]$Value)
    $bytes = [BitConverter]::GetBytes($Value)
    [Array]::Reverse($bytes)
    return ([System.Net.IPAddress]::new($bytes)).ToString()
}

function _netops_expand_subnet {
    param(
        [Parameter(Mandatory)][string]$Cidr,
        [Parameter(Mandatory)][int]$HostLimit
    )
    $trimmed = $Cidr.Trim()
    $parts = $trimmed -split '/'
    if ($parts.Count -ne 2) {
        throw "Invalid CIDR format. Use A.B.C.D/Prefix (for example 10.12.0.0/24)."
    }
    $network = $parts[0]
    $prefix = [int]$parts[1]
    if ($prefix -lt 8 -or $prefix -gt 30) {
        throw "Prefix $prefix is unsupported for interactive scans. Use /8../30."
    }
    $networkBytes = [System.Net.IPAddress]::Parse($network).GetAddressBytes()
    [Array]::Reverse($networkBytes)
    $networkInt = [BitConverter]::ToUInt32($networkBytes, 0)
    $hostBits = 32 - $prefix
    $hostCount = [int]([math]::Pow(2, $hostBits) - 2)
    if ($hostCount -gt $HostLimit) {
        throw "Subnet scan would produce $hostCount hosts which exceeds limit $HostLimit. Use a narrower prefix or increase hostLimit."
    }
    if ($hostCount -lt 1) {
        throw "Subnet prefix too narrow for host enumeration."
    }
    $start = $networkInt + 1
    $end = $networkInt + $hostCount
    $ips = [System.Collections.ArrayList]@()
    for ($i = $start; $i -le $end; $i++) {
        [void]$ips.Add((_netops_ip_from_uint $i))
    }
    return @($ips)
}

function _netops_scan_host {
    param(
        [Parameter(Mandatory)][string]$IpAddress,
        [int]$TimeoutSeconds = 1
    )
    try {
        $ok = Test-Connection -ComputerName $IpAddress -Count 1 -TimeoutSeconds $TimeoutSeconds -Quiet
        return [pscustomobject]@{
            IpAddress = $IpAddress
            Reachable = [bool]$ok
        }
    } catch {
        return [pscustomobject]@{
            IpAddress = $IpAddress
            Reachable = $false
        }
    }
}

function _netops_rdp_status {
    try {
        $reg = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -ErrorAction Stop
        $allowRdp = $reg.fDenyTSConnections -eq 0
    } catch {
        $allowRdp = $false
    }
    try {
        $service = Get-Service -Name TermService -ErrorAction Stop
        $svcState = $service.Status
        $svcStartup = $service.StartType
    } catch {
        $svcState = 'Unknown'
        $svcStartup = 'Unknown'
    }
    $fw = Get-NetFirewallRule -DisplayName 'Remote Desktop - User Mode (TCP-In)' -ErrorAction SilentlyContinue |
        Where-Object { $_.Enabled -eq 'True' }
    return [pscustomobject]@{
        Protocol = 'RDP'
        AllowRegistry = $allowRdp
        Service = $svcState
        ServiceStartup = $svcStartup
        FirewallEnabled = [bool]($fw.Count -gt 0)
    }
}

function _netops_vnc_status {
    $listening = @()
    try {
        $conns = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue
        foreach ($port in 5900, 5901) {
            if ($conns | Where-Object { $_.LocalPort -eq $port }) {
                $listening += $port
            }
        }
    } catch {
    }
    $vncFw = Get-NetFirewallRule -Name 'WINDO-VNC-*' -ErrorAction SilentlyContinue |
        Where-Object { $_.Enabled -eq 'True' }
    return [pscustomobject]@{
        Protocol = 'VNC'
        ListeningPorts = @($listening)
        FirewallEnabled = [bool]($vncFw.Count -gt 0)
    }
}

function _netops_wsl_distros {
    $raw = & wsl.exe -l -v 2>$null
    $list = [System.Collections.ArrayList]@()
    if ($null -eq $raw) { return @() }
    foreach ($line in @($raw)) {
        $trim = [string]$line.Trim()
        if ($trim -match '^(?:\*?\s+)?([^\s]+)\s+(\d+)\s+(\S+)$') {
            [void]$list.Add([pscustomobject]@{
                    IsDefault = $trim.StartsWith('*')
                    Name = $Matches[1]
                    Version = [int]$Matches[2]
                    State = $Matches[3]
                })
        }
    }
    return @($list)
}

function _netops_wsl_ip {
    param([Parameter(Mandatory)][string]$Distro)
    $ipLine = & wsl.exe -d $Distro -- ip -4 -o addr show eth0 2>$null
    if ($ipLine -match 'inet ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)') {
        return $Matches[1]
    }
    return $null
}

function _netops_parse_timeout_ms {
    param(
        [int]$TimeoutSeconds
    )
    if ($TimeoutSeconds -lt 1) { throw "timeoutSeconds must be at least 1." }
    if ($TimeoutSeconds -gt 900) { throw "timeoutSeconds must be <= 900." }
    return [Math]::Max(1, [int][Math]::Round($TimeoutSeconds * 1000))
}

function _netops_validate_port {
    param(
        [int]$Port,
        [string]$Label = 'port'
    )
    if ($Port -lt 1 -or $Port -gt 65535) {
        throw "${Label} must be in 1..65535."
    }
}

function _netops_validate_payload_limit {
    param([int]$Bytes, [string]$Label = 'payload')
    if ($Bytes -lt 1) { throw "${Label} bytes must be >= 1." }
    if ($Bytes -gt 65535) { throw "${Label} bytes must be <= 65535." }
}

function _netops_split_csv_items {
    param([string[]]$Values)
    $items = [System.Collections.ArrayList]@()
    foreach ($v in @($Values)) {
        if ($null -eq $v) { continue }
        $raw = [string]$v
        if ([string]::IsNullOrWhiteSpace($raw)) { continue }
        foreach ($piece in ($raw -split '[,;]')) {
            $trimmed = [string]$piece.Trim()
            if (-not [string]::IsNullOrWhiteSpace($trimmed)) {
                [void]$items.Add([string]$trimmed)
            }
        }
    }
    return @($items)
}

function _netops_netcat_load_allowlist {
    param(
        [string[]]$AllowHosts,
        [string]$AllowHostsFile
    )
    $entries = [System.Collections.ArrayList]@()
    if ($AllowHosts -and $AllowHosts.Count -gt 0) {
        foreach ($item in @(_netops_split_csv_items -Values $AllowHosts)) {
            [void]$entries.Add([string]$item)
        }
    }
    $envRaw = [string]$env:WINDO_NETOPS_NETCAT_ALLOWLIST
    if (-not [string]::IsNullOrWhiteSpace($envRaw)) {
        foreach ($item in @(_netops_split_csv_items -Values @($envRaw))) {
            [void]$entries.Add([string]$item)
        }
    }
    if ($AllowHostsFile) {
        if (-not (Test-Path -LiteralPath $AllowHostsFile)) {
            throw "AllowHostsFile not found: $AllowHostsFile"
        }
        try {
            $fileRaw = Get-Content -LiteralPath $AllowHostsFile -ErrorAction Stop -Raw
            if ([string]::IsNullOrWhiteSpace($fileRaw)) {
                throw "AllowHostsFile is empty."
            }
            $json = $fileRaw | ConvertFrom-Json -ErrorAction Stop
            if (($json -is [string]) -or -not ($json -is [System.Collections.IEnumerable])) {
                throw "AllowHostsFile must be a JSON array or comma-separated value list."
            }
            foreach ($item in @($json)) {
                [void]$entries.Add([string]$item.ToString())
            }
        } catch {
            throw "Invalid AllowHostsFile '$AllowHostsFile': $($_.Exception.Message)"
        }
    }
    return @($entries | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Sort-Object -Unique)
}

function _netops_netcat_addr_in_cidr {
    param(
        [Parameter(Mandatory)][string]$IpAddress,
        [Parameter(Mandatory)][string]$Cidr
    )
    if ($IpAddress -notmatch '^\d{1,3}(?:\.\d{1,3}){3}$') { return $false }
    if ($Cidr -notmatch '^\d{1,3}(?:\.\d{1,3}){3}/\d{1,2}$') { return $false }
    $parts = $Cidr.Split('/')
    $prefix = [int]$parts[1]
    if ($prefix -lt 0 -or $prefix -gt 32) { return $false }
    $network = $parts[0]
    $ipAddr = [System.Net.IPAddress]::Parse($IpAddress)
    $netAddr = [System.Net.IPAddress]::Parse($network)
    $ipBytes = $ipAddr.GetAddressBytes()
    $netBytes = $netAddr.GetAddressBytes()
    [Array]::Reverse($ipBytes)
    [Array]::Reverse($netBytes)
    $targetU32 = [BitConverter]::ToUInt32($ipBytes, 0)
    $baseU32 = [BitConverter]::ToUInt32($netBytes, 0)
    if ($prefix -eq 0) {
        $mask = [uint32]0
    } else {
        $mask = [uint32](([math]::Pow(2, $prefix) - 1) -shl (32 - $prefix))
    }
    return (($targetU32 -band $mask) -eq ($baseU32 -band $mask))
}

function _netops_netcat_validate_allow_target {
    param(
        [Parameter(Mandatory)][string]$Target,
        [string[]]$Allowlist,
        [bool]$AllowRemote
    )
    $targetTrim = [string]$Target.Trim()
    if (-not $targetTrim) {
        return [ordered]@{
            allowed = $false
            reason = "target is empty"
            matchedRule = $null
            addresses = @()
        }
    }
    if (_netops_is_loopback -Host $targetTrim) {
        return [ordered]@{
            allowed = $true
            reason = "loopback target"
            matchedRule = "loopback"
            addresses = @($targetTrim)
        }
    }
    if ($AllowRemote) {
        return [ordered]@{
            allowed = $true
            reason = "AllowRemote switch"
            matchedRule = "AllowRemote"
            addresses = @($targetTrim)
        }
    }
    if (-not $Allowlist -or $Allowlist.Count -eq 0) {
        return [ordered]@{
            allowed = $false
            reason = "No allowlist configured for remote targets."
            matchedRule = $null
            addresses = @()
        }
    }
    $targetLower = $targetTrim.ToLowerInvariant()
    $resolved = [System.Collections.ArrayList]@()
    $parsedIp = $null
    if ([System.Net.IPAddress]::TryParse($targetTrim, [ref]$parsedIp)) {
        [void]$resolved.Add($targetTrim)
    } else {
        try {
            foreach ($a in [System.Net.Dns]::GetHostAddresses($targetLower)) {
                if ($a.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) {
                    [void]$resolved.Add($a.ToString())
                }
            }
        } catch { }
    }
    $uniqueResolved = @($resolved | Where-Object { $_ } | Sort-Object -Unique)
    foreach ($entry in @($Allowlist)) {
        $rule = [string]$entry.Trim()
        if ([string]::IsNullOrWhiteSpace($rule)) { continue }
        $ruleLower = $rule.ToLowerInvariant()
        if ($ruleLower -eq '*') {
            return [ordered]@{
                allowed = $true
                reason = "Allowlist wildcard"
                matchedRule = $rule
                addresses = @($uniqueResolved)
            }
        }
        if ($ruleLower -eq $targetLower) {
            return [ordered]@{
                allowed = $true
                reason = "Allowlist host match"
                matchedRule = $rule
                addresses = @($uniqueResolved)
            }
        }
        if ($ruleLower -match '^\d{1,3}(?:\.\d{1,3}){3}$') {
            if (@($uniqueResolved) -contains $ruleLower) {
                return [ordered]@{
                    allowed = $true
                    reason = "Allowlist IP match"
                    matchedRule = $rule
                    addresses = @($uniqueResolved)
                }
            }
            continue
        }
        if ($ruleLower -match '^\d{1,3}(?:\.\d{1,3}){3}/\d{1,2}$') {
            foreach ($r in @($uniqueResolved)) {
                if (_netops_netcat_addr_in_cidr -IpAddress $r -Cidr $ruleLower) {
                    return [ordered]@{
                        allowed = $true
                        reason = "Allowlist CIDR match"
                        matchedRule = $rule
                        addresses = @($uniqueResolved)
                    }
                }
            }
            continue
        }
        if ($targetLower -like $ruleLower -or $ruleLower -like "*$targetLower*") {
            return [ordered]@{
                allowed = $true
                reason = "Allowlist wildcard hostname match"
                matchedRule = $rule
                addresses = @($uniqueResolved)
            }
        }
    }
    return [ordered]@{
        allowed = $false
        reason = "Target not on allowlist"
        matchedRule = $null
        addresses = @($uniqueResolved)
    }
}

function _netops_is_loopback {
    param([Parameter(Mandatory)][string]$HostName)
    $h = $HostName.Trim().ToLowerInvariant()
    if ($h -in @('localhost', '127.0.0.1', '::1')) { return $true }
    try {
        foreach ($a in ([System.Net.Dns]::GetHostAddresses($HostName))) {
            if ($a.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork -and $a.Equals([System.Net.IPAddress]::Loopback)) { return $true }
            if ($a.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetworkV6 -and $a.Equals([System.Net.IPAddress]::IPv6Loopback)) { return $true }
        }
    } catch {
    }
    return $false
}

function _netops_read_line_with_timeout_ms {
    param([int]$TimeoutMs)
    $reader = [System.IO.StreamReader]::new([System.Console]::OpenStandardInput())
    $task = $reader.ReadLineAsync()
    if ($task.Wait($TimeoutMs)) {
        return $task.Result
    }
    return $null
}

function _netops_preview_bytes {
    param(
        [Parameter(Mandatory)][byte[]]$Bytes,
        [int]$MaxChars = 240
    )
    if ($null -eq $Bytes -or $Bytes.Count -eq 0) { return "" }
    $text = [System.Text.Encoding]::UTF8.GetString($Bytes)
    if ($text.Length -gt $MaxChars) { return $text.Substring(0, $MaxChars) + "..." }
    return $text
}

function _netops_truncate_events([array]$Events,[int]$Max) {
    if ($Max -ge 1 -and $Events.Count -gt $Max) {
        return @($Events | Select-Object -Last $Max)
    }
    return @($Events)
}

$cmdNetcatSend = {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [string]$RemoteHost = '127.0.0.1',
        [int]$RemotePort = 9001,
        [ValidateSet('tcp', 'udp')]
        [string]$Protocol = 'tcp',
        [ValidateSet('check', 'apply')]
        [string]$Mode = 'apply',
        [string]$Message = 'windo-netcat-send',
        [string[]]$AllowHosts = @(),
        [string]$AllowHostsFile,
        [switch]$Interactive,
        [int]$TimeoutSeconds = 2,
        [int]$MaxPayloadBytes = 4096,
        [int]$MaxInteractiveLines = 32,
        [switch]$AsJson,
        [switch]$AllowRemote
    )

    $payload = $null
    try {
        $allowlist = _netops_netcat_load_allowlist -AllowHosts $AllowHosts -AllowHostsFile $AllowHostsFile
        $safety = _netops_netcat_validate_allow_target -Target $RemoteHost -Allowlist $allowlist -AllowRemote $AllowRemote
        _netops_validate_port -Port $RemotePort -Label 'remotePort'
        _netops_validate_payload_limit -Bytes $MaxPayloadBytes -Label 'maxPayloadBytes'
        $timeoutMs = _netops_parse_timeout_ms -TimeoutSeconds $TimeoutSeconds
        if (-not $safety.allowed -and $Mode -eq 'apply') {
            throw "Blocked by safety policy: $($safety.reason)."
        }
        if ($Mode -eq 'check') {
            $payload = [pscustomobject]@{
                command = 'netops-netcat-send'
                mode = 'check'
                protocol = $Protocol
                interactive = [bool]$Interactive
                remoteHost = $RemoteHost
                remotePort = $RemotePort
                timeoutSeconds = $TimeoutSeconds
                maxPayloadBytes = $MaxPayloadBytes
                maxInteractiveLines = $MaxInteractiveLines
                allowRemote = [bool]$AllowRemote
                allowlist = @($allowlist)
                allowlistMatched = $safety.matchedRule
                safety = @{
                    allowed = [bool]$safety.allowed
                    reason = [string]$safety.reason
                    resolvedAddresses = @($safety.addresses)
                }
                events = @()
                messages = 0
                bytes = 0
                timedOut = $false
                exitCode = 0
            }
            if ($AsJson) { $payload | ConvertTo-Json -Depth 12 } else { $payload }
            return
        }
        if (-not $PSCmdlet.ShouldProcess(("netcat send to {0}:{1}/{2}" -f $RemoteHost, $RemotePort, $Protocol))) {
            $payload = [pscustomobject]@{
                command = 'netops-netcat-send'
                mode = $Mode
                protocol = $Protocol
                interactive = [bool]$Interactive
                remoteHost = $RemoteHost
                remotePort = $RemotePort
                timeoutSeconds = $TimeoutSeconds
                maxPayloadBytes = $MaxPayloadBytes
                maxInteractiveLines = $MaxInteractiveLines
                allowRemote = [bool]$AllowRemote
                allowlist = @($allowlist)
                allowlistMatched = $safety.matchedRule
                safety = @{
                    allowed = [bool]$safety.allowed
                    reason = [string]$safety.reason
                    resolvedAddresses = @($safety.addresses)
                    confirmationSkipped = $true
                }
                events = @()
                messages = 0
                bytes = 0
                timedOut = $false
                exitCode = 3
            }
            if ($AsJson) { $payload | ConvertTo-Json -Depth 12 } else { $payload }
            return
        }

        $payloadBytesCap = $MaxPayloadBytes
        $payloadEvents = [System.Collections.ArrayList]@()
        $totalBytes = 0
        $lineCount = 0
        $timedOut = $false

        $startedAt = (Get-Date)

        function _netops_send_tcp_once {
            param([string]$Text, [System.Net.Sockets.TcpClient]$Client, [int]$MaxBytes)
            $lineBytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
            if ($lineBytes.Count -gt $MaxBytes) {
                throw "message exceeds maxPayloadBytes ($MaxBytes)."
            }
            $stream = $Client.GetStream()
            $stream.WriteTimeout = $timeoutMs
            $stream.Write($lineBytes, 0, $lineBytes.Count)
            [void]$stream.Flush()
            $lineCount++
            $totalBytes += $lineBytes.Count
            [void]$payloadEvents.Add([ordered]@{
                    sequence = $lineCount
                    bytes = $lineBytes.Count
                    text = $Text
                    preview = (_netops_preview_bytes -Bytes $lineBytes -MaxChars 160)
                })
        }

        function _netops_send_udp_once {
            param([string]$Text, [System.Net.Sockets.UdpClient]$Client, [string]$RemoteHost, [int]$Port, [int]$MaxBytes)
            $lineBytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
            if ($lineBytes.Count -gt $MaxBytes) {
                throw "message exceeds maxPayloadBytes ($MaxBytes)."
            }
            [void]$Client.Send($lineBytes, $lineBytes.Count, $RemoteHost, $Port)
            $lineCount++
            $totalBytes += $lineBytes.Count
            [void]$payloadEvents.Add([ordered]@{
                    sequence = $lineCount
                    bytes = $lineBytes.Count
                    text = $Text
                    preview = (_netops_preview_bytes -Bytes $lineBytes -MaxChars 160)
                    to = "$RemoteHost:$Port"
                })
        }

        if ($Protocol -eq 'tcp') {
            $client = New-Object System.Net.Sockets.TcpClient
            try {
                $connect = $client.ConnectAsync($RemoteHost, $RemotePort)
                if (-not $connect.Wait($timeoutMs)) {
                    throw "Connect timeout after $TimeoutSeconds second(s)."
                }
                $connect.Wait()
                $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                if ($Interactive) {
                    while ($lineCount -lt $MaxInteractiveLines -and $stopwatch.ElapsedMilliseconds -lt $timeoutMs) {
                        $leftMs = [Math]::Max(1, $timeoutMs - [int]$stopwatch.ElapsedMilliseconds)
                        $line = _netops_read_line_with_timeout_ms -TimeoutMs $leftMs
                        if ($null -eq $line) {
                            $timedOut = $true
                            break
                        }
                        _netops_send_tcp_once -Text ($line + "`n") -Client $client -MaxBytes $payloadBytesCap
                    }
                } else {
                    _netops_send_tcp_once -Text $Message -Client $client -MaxBytes $payloadBytesCap
                }
            } finally {
                $client.Close()
            }
        } else {
            $udp = New-Object System.Net.Sockets.UdpClient
            try {
                $udp.Client.SendTimeout = $timeoutMs
                if ($Interactive) {
                    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                    while ($lineCount -lt $MaxInteractiveLines -and $stopwatch.ElapsedMilliseconds -lt $timeoutMs) {
                        $leftMs = [Math]::Max(1, $timeoutMs - [int]$stopwatch.ElapsedMilliseconds)
                        $line = _netops_read_line_with_timeout_ms -TimeoutMs $leftMs
                        if ($null -eq $line) {
                            $timedOut = $true
                            break
                        }
                    _netops_send_udp_once -Text ($line + "`n") -Client $udp -RemoteHost $RemoteHost -Port $RemotePort -MaxBytes $payloadBytesCap
                    }
                } else {
                    _netops_send_udp_once -Text $Message -Client $udp -RemoteHost $RemoteHost -Port $RemotePort -MaxBytes $payloadBytesCap
                }
            } finally {
                $udp.Close()
            }
        }

        $completedAt = (Get-Date)
        $payload = [pscustomobject]@{
            command = 'netops-netcat-send'
            protocol = $Protocol
            mode = if ($Interactive) { 'interactive-apply' } else { 'one-shot-apply' }
            remoteHost = $RemoteHost
            remotePort = $RemotePort
            timeoutSeconds = $TimeoutSeconds
            maxPayloadBytes = $MaxPayloadBytes
            maxInteractiveLines = $MaxInteractiveLines
            allowRemote = [bool]$AllowRemote
            allowlist = @($allowlist)
            allowlistMatched = $safety.matchedRule
            safety = @{
                requestedMode = $Mode
                allowed = [bool]$safety.allowed
                reason = [string]$safety.reason
            }
            startedAt = $startedAt.ToString("o")
            completedAt = $completedAt.ToString("o")
            timedOut = $timedOut
            messages = $lineCount
            bytes = $totalBytes
            events = _netops_truncate_events -Events $payloadEvents -Max 128
            exitCode = if ($timedOut -and $lineCount -eq 0) { 1 } else { 0 }
        }
    } catch {
        $payload = [pscustomobject]@{
            command = 'netops-netcat-send'
            protocol = $Protocol
            mode = $Mode
            remoteHost = $RemoteHost
            remotePort = $RemotePort
            error = $_.Exception.Message
            startedAt = (Get-Date).ToString("o")
            timeoutSeconds = $TimeoutSeconds
            maxPayloadBytes = $MaxPayloadBytes
            maxInteractiveLines = $MaxInteractiveLines
            allowRemote = [bool]$AllowRemote
            allowlist = @($allowlist)
            safety = @{
                requestedMode = $Mode
                allowed = [bool]$safety.allowed
                reason = [string]$safety.reason
            }
            timedOut = $false
            messages = 0
            bytes = 0
            events = @()
            exitCode = 2
        }
    }
    if ($AsJson) { $payload | ConvertTo-Json -Depth 6 } else { $payload }
}

$cmdNetcatRecv = {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [string]$BindHost = '127.0.0.1',
        [int]$LocalPort = 9001,
        [ValidateSet('tcp', 'udp')]
        [string]$Protocol = 'tcp',
        [ValidateSet('check', 'apply')]
        [string]$Mode = 'apply',
        [switch]$Interactive,
        [int]$TimeoutSeconds = 2,
        [int]$MaxPayloadBytes = 4096,
        [int]$MaxMessages = 128,
        [switch]$AsJson,
        [switch]$AllowRemote,
        [string[]]$AllowHosts = @(),
        [string]$AllowHostsFile
    )

    try {
        $allowlist = _netops_netcat_load_allowlist -AllowHosts $AllowHosts -AllowHostsFile $AllowHostsFile
        $safety = _netops_netcat_validate_allow_target -Target $BindHost -Allowlist $allowlist -AllowRemote $AllowRemote
        _netops_validate_port -Port $LocalPort -Label 'localPort'
        _netops_validate_payload_limit -Bytes $MaxPayloadBytes -Label 'maxPayloadBytes'
        if ($MaxMessages -lt 1) { throw "maxMessages must be >= 1." }
        if (-not $safety.allowed -and $Mode -eq 'apply') {
            throw "Blocked by safety policy: $($safety.reason)."
        }
        if ($Mode -eq 'check') {
            $payload = [pscustomobject]@{
                command = 'netops-netcat-recv'
                mode = 'check'
                protocol = $Protocol
                bindHost = $BindHost
                localPort = $LocalPort
                timeoutSeconds = $TimeoutSeconds
                maxPayloadBytes = $MaxPayloadBytes
                maxMessages = $MaxMessages
                allowRemote = [bool]$AllowRemote
                allowlist = @($allowlist)
                allowlistMatched = $safety.matchedRule
                safety = @{
                    allowed = [bool]$safety.allowed
                    reason = [string]$safety.reason
                    resolvedAddresses = @($safety.addresses)
                }
                events = @()
                messages = 0
                bytes = 0
                timedOut = $false
                exitCode = 0
            }
            if ($AsJson) { $payload | ConvertTo-Json -Depth 12 } else { $payload }
            return
        }
        if (-not $PSCmdlet.ShouldProcess(("netcat receive on {0}:{1}/{2}" -f $BindHost, $LocalPort, $Protocol))) {
            $payload = [pscustomobject]@{
                command = 'netops-netcat-recv'
                protocol = $Protocol
                mode = $Mode
                bindHost = $BindHost
                localPort = $LocalPort
                timeoutSeconds = $TimeoutSeconds
                maxPayloadBytes = $MaxPayloadBytes
                maxMessages = $MaxMessages
                allowRemote = [bool]$AllowRemote
                allowlist = @($allowlist)
                allowlistMatched = $safety.matchedRule
                safety = @{
                    allowed = [bool]$safety.allowed
                    reason = [string]$safety.reason
                    resolvedAddresses = @($safety.addresses)
                    confirmationSkipped = $true
                }
                events = @()
                messages = 0
                bytes = 0
                timedOut = $false
                exitCode = 3
            }
            if ($AsJson) { $payload | ConvertTo-Json -Depth 12 } else { $payload }
            return
        }
        $timeoutMs = _netops_parse_timeout_ms -TimeoutSeconds $TimeoutSeconds
        $payloadEvents = [System.Collections.ArrayList]@()
        $timedOut = $false
        $messageCount = 0
        $totalBytes = 0
        $startedAt = (Get-Date)
        $buffer = New-Object byte[] ( [Math]::Min($MaxPayloadBytes, 65535) )

        if ($Protocol -eq 'tcp') {
            $ip = [System.Net.IPAddress]::Parse($BindHost)
            $listener = New-Object System.Net.Sockets.TcpListener($ip, $LocalPort)
            try {
                $listener.Start()
                $deadline = [System.Diagnostics.Stopwatch]::StartNew()
                $maxLoop = if ($Interactive) { [Math]::Max(1, $MaxMessages) } else { 1 }
                while ($messageCount -lt $maxLoop -and $deadline.ElapsedMilliseconds -lt $timeoutMs) {
                    $leftMs = [Math]::Max(1, $timeoutMs - [int]$deadline.ElapsedMilliseconds)
                    $acceptTask = $listener.AcceptTcpClientAsync()
                    if (-not $acceptTask.Wait($leftMs)) {
                        $timedOut = $true
                        break
                    }
                    $client = $acceptTask.GetAwaiter().GetResult()
                    try {
                        $stream = $client.GetStream()
                        $stream.ReadTimeout = $timeoutMs
                        $readTask = $stream.ReadAsync($buffer, 0, $buffer.Length)
                        if (-not $readTask.Wait($leftMs)) {
                            $timedOut = $true
                            break
                        }
                        $readCount = [int]$readTask.GetAwaiter().GetResult()
                        if ($readCount -le 0) { break }
                        $chunk = [byte[]]$buffer[0..($readCount - 1)]
                        $messageCount++
                        $totalBytes += $readCount
                        $src = $null
                        try {
                            $src = $client.Client.RemoteEndPoint.ToString()
                        } catch {
                        }
                        [void]$payloadEvents.Add([ordered]@{
                                sequence = $messageCount
                                bytes = $readCount
                                preview = (_netops_preview_bytes -Bytes $chunk -MaxChars 240)
                                source = $src
                                protocol = 'tcp'
                            })
                        if (-not $Interactive) { break }
                    } finally {
                        $client.Close()
                    }
                }
            } finally {
                $listener.Stop()
            }
        } else {
            $udp = New-Object System.Net.Sockets.UdpClient
            try {
                $bind = New-Object System.Net.IPEndPoint(([System.Net.IPAddress]::Parse($BindHost)), $LocalPort)
                $udp.Client.ReceiveTimeout = $timeoutMs
                $udp.ExclusiveAddressUse = $false
                $udp.Client.Bind($bind)
                $deadline = [System.Diagnostics.Stopwatch]::StartNew()
                $maxLoop = if ($Interactive) { [Math]::Max(1, $MaxMessages) } else { 1 }
                while ($messageCount -lt $maxLoop -and $deadline.ElapsedMilliseconds -lt $timeoutMs) {
                    $leftMs = [Math]::Max(1, $timeoutMs - [int]$deadline.ElapsedMilliseconds)
                    $recvTask = $udp.ReceiveAsync()
                    if (-not $recvTask.Wait($leftMs)) {
                        $timedOut = $true
                        break
                    }
                    $udpResult = $recvTask.GetAwaiter().GetResult()
                    if ($null -eq $udpResult) { break }
                    $messageCount++
                    $readCount = $udpResult.Buffer.Count
                    $chunk = [byte[]]$udpResult.Buffer
                    $totalBytes += $readCount
                    [void]$payloadEvents.Add([ordered]@{
                            sequence = $messageCount
                            bytes = $readCount
                            preview = (_netops_preview_bytes -Bytes $chunk -MaxChars 240)
                            source = $udpResult.RemoteEndPoint.ToString()
                            protocol = 'udp'
                        })
                    if (-not $Interactive -and $messageCount -gt 0) { break }
                }
            } finally {
                $udp.Close()
            }
        }

        $completedAt = (Get-Date)
        $payload = [pscustomobject]@{
            command = 'netops-netcat-recv'
            protocol = $Protocol
            mode = if ($Interactive) { 'interactive-apply' } else { 'one-shot-apply' }
            bindHost = $BindHost
            localPort = $LocalPort
            timeoutSeconds = $TimeoutSeconds
            maxPayloadBytes = $MaxPayloadBytes
            maxMessages = $MaxMessages
            allowRemote = [bool]$AllowRemote
            allowlist = @($allowlist)
            allowlistMatched = $safety.matchedRule
            safety = @{
                requestedMode = $Mode
                allowed = [bool]$safety.allowed
                reason = [string]$safety.reason
            }
            startedAt = $startedAt.ToString("o")
            completedAt = $completedAt.ToString("o")
            timedOut = $timedOut
            messages = $messageCount
            bytes = $totalBytes
            events = _netops_truncate_events -Events $payloadEvents -Max 128
            exitCode = if ($timedOut -and $messageCount -eq 0) { 1 } else { 0 }
        }
        if ($AsJson) { $payload | ConvertTo-Json -Depth 6 } else { $payload }
    } catch {
        $payload = [pscustomobject]@{
            command = 'netops-netcat-recv'
            protocol = $Protocol
            mode = $Mode
            bindHost = $BindHost
            localPort = $LocalPort
            timeoutSeconds = $TimeoutSeconds
            maxPayloadBytes = $MaxPayloadBytes
            maxMessages = $MaxMessages
            allowRemote = [bool]$AllowRemote
            allowlist = @($allowlist)
            safety = @{
                requestedMode = $Mode
                allowed = [bool]$safety.allowed
                reason = [string]$safety.reason
            }
            startedAt = (Get-Date).ToString("o")
            completedAt = (Get-Date).ToString("o")
            error = $_.Exception.Message
            timedOut = $false
            messages = 0
            bytes = 0
            events = @()
            exitCode = 2
        }
        if ($AsJson) { $payload | ConvertTo-Json -Depth 6 } else { $payload }
    }
}

$cmdResolve = {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Name
    )

    function _netops_resolve_reverse {
        param([Parameter(Mandatory)][string]$Address)
        $results = [System.Collections.ArrayList]@()
        try {
            $ptr = Resolve-DnsName -Name $Address -Type PTR -ErrorAction Stop |
                Where-Object { $_.NameHost -and $_.NameHost.Trim() } |
                Select-Object -ExpandProperty NameHost -Unique
            foreach ($name in @($ptr)) {
                [void]$results.Add([string]$name)
            }
            if ($results.Count -gt 0) { return @($results) }
        } catch {
            # fallback
        }
        try {
        $resolvedHost = [System.Net.Dns]::GetHostEntry($Address)
        if ($resolvedHost -and $resolvedHost.HostName) {
            [void]$results.Add([string]$resolvedHost.HostName)
            }
        } catch {
        }
        return @($results)
    }

    if (-not $Name -or $Name.Count -eq 0) {
        $Name = @($env:COMPUTERNAME, ([System.Net.Dns]::GetHostName()))
    }
    foreach ($target in $Name) {
        $trim = [string]$target.Trim()
        if ([string]::IsNullOrWhiteSpace($trim)) { continue }
        $rows = @()
        try {
            $rows = Resolve-DnsName -Name $trim -ErrorAction Stop | Where-Object { $_.Type -match 'A|AAAA' } | Select-Object -ExpandProperty IPAddress -Unique
        } catch {
            try {
                $rows = [System.Net.Dns]::GetHostAddresses($trim) | ForEach-Object { $_.ToString() } | Sort-Object -Unique
            } catch {
                Write-Warning ("netops-resolve: failed to resolve " + $trim + " (" + $_.Exception.Message + ")")
                continue
            }
        }
        foreach ($ip in @($rows)) {
            $rev = _netops_resolve_reverse -Address ([string]$ip)
            [pscustomobject]@{
                Host = $trim
                IpAddress = [string]$ip
                AddressFamily = if ($ip.Contains('.')) { 'IPv4' } else { 'IPv6' }
                ReverseDns = @($rev)
            }
        }
        if (-not $rows -or $rows.Count -eq 0) {
            $revOnly = @()
            $ipParsed = $null
            if ([System.Net.IPAddress]::TryParse($trim, [ref]$ipParsed)) {
                $revOnly = _netops_resolve_reverse -Address $trim
            }
            [pscustomobject]@{
                Host = $trim
                IpAddress = ''
                AddressFamily = ''
                ReverseDns = @($revOnly)
            }
        }
    }
}

$cmdSubnetScan = {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Cidr,
        [int]$TimeoutSeconds = 1,
        [int]$HostLimit = 120,
        [switch]$Force
    )
    if ($HostLimit -lt 1) {
        throw "hostLimit must be positive."
    }
    $effectiveHostLimit = if ($Force) { [Math]::Max($HostLimit, 32768) } else { $HostLimit }
    $ips = _netops_expand_subnet -Cidr $Cidr -HostLimit $effectiveHostLimit
    $results = [System.Collections.ArrayList]@()
    foreach ($ip in @($ips)) {
        [void]$results.Add(_netops_scan_host -IpAddress $ip -TimeoutSeconds $TimeoutSeconds)
    }
    return @($results)
}

$cmdArpMap = {
    [CmdletBinding()]
    param(
        [string]$InterfaceAlias,
        [switch]$IncludeStale
    )
    $neighbors = Get-NetNeighbor -AddressFamily IPv4 -ErrorAction SilentlyContinue
    if ($InterfaceAlias) {
        $neighbors = $neighbors | Where-Object { $_.InterfaceAlias -eq $InterfaceAlias }
    }
    if (-not $IncludeStale) {
        $neighbors = $neighbors | Where-Object {
            $_.State -notin @('Unreachable', 'Incomplete', 'Invalid')
        }
    }
    return $neighbors | Select-Object InterfaceAlias, IPAddress, LinkLayerAddress, State
}

$cmdRdpVnc = {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [ValidateSet('check', 'apply')]
        [string]$Mode = 'check',
        [ValidateSet('rdp', 'vnc', 'both')]
        [string]$Protocol = 'both',
        [switch]$Force,
        [ValidateSet('status', 'firewall')]
        [string]$Subcommand = 'status',
        [ValidateSet('status', 'enable', 'disable')]
        [string]$FirewallAction = 'status',
        [switch]$AsJson
    )

    function _netops_build_rdp_payload {
        param([Parameter(Mandatory)]$Rdp)
        return [ordered]@{
            subcommand = "status"
            scannedAt = (Get-Date -Format "o")
            service = [ordered]@{
                name = "TermService"
                status = [string]$Rdp.Service
                startup = [string]$Rdp.ServiceStartup
                exists = $Rdp.Service -ne 'Unknown'
            }
            config = [ordered]@{
                terminalServerFq = [bool]$Rdp.AllowRegistry
            }
            firewall = [ordered]@{
                count = if ([bool]$Rdp.FirewallEnabled) { 1 } else { 0 }
                rules = @(
                    [ordered]@{
                        name = "Remote Desktop - User Mode (TCP-In)"
                        enabled = [bool]$Rdp.FirewallEnabled
                    }
                )
            }
            exitCode = $(if ($Rdp.Service -eq 'Unknown') { 2 } else { 0 })
        }
    }

    if (-not _netops_is_admin) {
        if ($Mode -eq 'apply') {
            throw "apply mode requires an elevated shell."
        }
        Write-Warning "apply mode requested without admin; returning check mode only."
        $Mode = 'check'
    }

    $rdpEnabled = $Protocol -in @('rdp', 'both')
    $vncEnabled = $Protocol -in @('vnc', 'both')

    if ($Subcommand -eq 'firewall') {
        if (-not $rdpEnabled) {
            if ($AsJson) {
                if (_netops_emit_payload -Command "rdp" -Payload @{
                        subcommand = "firewall"
                        action = "status"
                        error = "rdp protocol required for firewall operations"
                        exitCode = 2
                    } -AsJson:$AsJson) { return }
            }
            Write-Host "[WINDO module $WindoModuleId] firewall inspection requires Protocol='rdp'." -ForegroundColor Yellow
            return
        }

        $rules = Get-NetFirewallRule -DisplayName 'Remote Desktop - User Mode (TCP-In)' -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -and ($_.DisplayName.Contains("Remote Desktop")) }
        $ruleRows = [System.Collections.ArrayList]@()
        $runCommands = [System.Collections.ArrayList]@()
        $updates = [System.Collections.ArrayList]@()

        foreach ($r in @($rules)) {
            [void]$ruleRows.Add([ordered]@{
                    name = [string]$r.Name
                    displayName = [string]$r.DisplayName
                    enabled = [bool]($r.Enabled -eq 'True')
                })
            if ($FirewallAction -in @('enable', 'disable')) {
                $commandText = "{0} -Name '{1}' -Confirm:`$false" -f $(if ($FirewallAction -eq 'disable') { 'Disable-NetFirewallRule' } else { 'Enable-NetFirewallRule' }), [string]$r.Name
                [void]$runCommands.Add($commandText)
                [void]$updates.Add([ordered]@{
                        name = [string]$r.Name
                        action = $FirewallAction
                        success = $true
                    })
            }
        }

        if ($FirewallAction -eq 'status') {
            $firewallPayload = [ordered]@{
                subcommand = "firewall"
                action = "status"
                requestedPorts = @()
                rules = @($ruleRows)
                scannedAt = (Get-Date -Format "o")
                exitCode = 0
            }
            if (_netops_emit_payload -Command "rdp" -Payload $firewallPayload -AsJson:$AsJson) { return }
            return $firewallPayload
        }

        $disablePayload = [ordered]@{
            subcommand = "firewall"
            action = [string]$FirewallAction
            requestedPorts = @()
            runCommand = @([string[]]$runCommands)
            command = @([string[]]$runCommands)
            "command-executed" = @([string[]]$runCommands)
            updates = @($updates)
            scannedAt = (Get-Date -Format "o")
            exitCode = $(if ($updates.Count -gt 0) { 0 } else { 2 })
        }
        if (_netops_emit_payload -Command "rdp" -Payload $disablePayload -AsJson:$AsJson) { return }
        return $disablePayload
    }

    if ($Mode -eq 'check') {
        if ($rdpEnabled) {
            $rdp = _netops_rdp_status
            if ($Subcommand -eq 'status' -and ($Protocol -eq 'rdp')) {
                $payload = _netops_build_rdp_payload -Rdp $rdp
                if (_netops_emit_payload -Command "rdp" -Payload $payload -AsJson:$AsJson) { return }
                return $payload
            }
            if ($Protocol -in @('rdp', 'both')) { $rdp }
        }
        if ($vncEnabled) { _netops_vnc_status }
        return
    }

    if (-not $Force -and -not $PSCmdlet.ShouldProcess("RDP/VNC control plane", "apply")) {
        return
    }

    if ($rdpEnabled) {
        Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Type DWord -Value 0 -Force | Out-Null
        Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name UserAuthentication -Type DWord -Value 1 -Force | Out-Null
        try { Enable-NetFirewallRule -DisplayName 'Remote Desktop - User Mode (TCP-In)' | Out-Null } catch {}
        try {
            Get-Service -Name TermService -ErrorAction Stop | Set-Service -StartupType Automatic
            if ((Get-Service -Name TermService).Status -ne 'Running') { Start-Service -Name TermService -ErrorAction SilentlyContinue }
        } catch {}
    }

    if ($vncEnabled) {
        foreach ($port in 5900, 5901) {
            $name = 'WINDO-VNC-' + $port
            if (-not (Get-NetFirewallRule -Name $name -ErrorAction SilentlyContinue)) {
                New-NetFirewallRule -Name $name -DisplayName ('WINDO VNC TCP ' + $port) -Direction Inbound -Protocol TCP -LocalPort $port -Action Allow -Profile Any | Out-Null
            } else {
                Enable-NetFirewallRule -Name $name | Out-Null
            }
        }
    }

    $rows = [System.Collections.ArrayList]@()
    if ($rdpEnabled) {
        $rdp = _netops_rdp_status
        if ($Protocol -eq 'rdp') {
            $payload = _netops_build_rdp_payload -Rdp $rdp
            if (_netops_emit_payload -Command "rdp" -Payload $payload -AsJson:$AsJson) { return }
            return $payload
        }
        [void]$rows.Add($rdp)
    }
    if ($vncEnabled) { [void]$rows.Add(_netops_vnc_status) }
    if ($rows.Count -gt 0) { return @($rows) }
}

$cmdWsl = {
    [CmdletBinding()]
    param(
        [ValidateSet('status', 'ip', 'check')]
        [string]$Mode = 'status',
        [string]$Distro,
        [ValidateSet('install', 'distro', 'import', 'export')]
        [string]$Check = 'install',
        [switch]$AsJson
    )
    $rawDistros = _netops_wsl_distros
    $defaultDistro = @($rawDistros | Where-Object { $_.IsDefault } | Select-Object -First 1)
    $distros = [ordered]@{
        distros = @($rawDistros)
        defaultName = if ($defaultDistro.Count -gt 0) { [string]$defaultDistro[0].Name } elseif ($rawDistros.Count -gt 0) { [string]$rawDistros[0].Name } else { $null }
        found = ($rawDistros.Count -gt 0)
    }
    $wslExe = Get-Command wsl.exe -ErrorAction SilentlyContinue
    $statusOutput = @()
    $statusExitCode = 0
    if ($Mode -in @('status', 'check')) {
        if ($wslExe) {
            try {
                $statusOutput = & wsl.exe --status 2>&1
                $statusExitCode = if ($LASTEXITCODE -ne $null) { [int]$LASTEXITCODE } else { 0 }
            } catch {
                $statusOutput = @()
                $statusExitCode = 1
            }
        } else {
            $statusExitCode = 1
        }
    }

    if ($Mode -eq 'check') {
        if ($Check -ne "install") {
            $payload = [ordered]@{
                command = "check $Check"
                error = "unsupported check target '$Check'"
                exitCode = 2
            }
            if (_netops_emit_payload -Command "wsl" -Payload $payload -AsJson:$AsJson) { return }
            return $payload
        }

        $notes = [System.Collections.ArrayList]@()
        if (-not $wslExe) {
            [void]$notes.Add("wsl.exe was not found in PATH.")
        } elseif ($statusExitCode -ne 0) {
            [void]$notes.Add("wsl --status returned $statusExitCode")
        } else {
            [void]$notes.Add("wsl command is executable")
        }
        $checkOk = if ($wslExe -and $statusExitCode -eq 0) { $true } else { $false }
        $payload = [ordered]@{
            command = 'check install'
            wslAvailable = [bool]$wslExe
            wslStatus = @($statusOutput)
            distros = @($distros.distros)
            default = $distros.defaultName
            notes = @($notes)
            exitCode = if ($checkOk) { 0 } else { 2 }
        }
        if (_netops_emit_payload -Command "wsl" -Payload $payload -AsJson:$AsJson) { return }
        return $payload
    }

    if ($Mode -eq 'status') {
        $rows = [System.Collections.ArrayList]@()
        foreach ($d in @($distros.distros)) {
            $ip = _netops_wsl_ip -Distro $d.Name
            [void]$rows.Add([pscustomobject]@{
                    Name = $d.Name
                    IsDefault = [bool]$d.IsDefault
                    State = $d.State
                    Version = $d.Version
                    Eth0Ip = $ip
                })
        }
        if ($AsJson) {
            $payload = [ordered]@{
                command = "status"
                wslAvailable = [bool]$wslExe
                wslStatus = @($statusOutput)
                wslExitCode = [int]$statusExitCode
                distros = @($distros.distros)
                default = $distros.defaultName
                exitCode = if ($wslExe -and $statusExitCode -eq 0) { 0 } else { 2 }
            }
            if (_netops_emit_payload -Command "wsl" -Payload $payload -AsJson:$AsJson) { return }
            return $payload
        }
        return @($rows)
    }

    if (-not $Distro) {
        if ($distros.found -eq $false) {
            throw "No WSL distro found. Run 'wsl --install' first."
        }
        $Distro = ($distros.distros | Where-Object { $_.IsDefault } | Select-Object -First 1).Name
        if (-not $Distro) { $Distro = $distros.distros[0].Name }
    }
    $ip = _netops_wsl_ip -Distro $Distro
    [pscustomobject]@{
        Distro = $Distro
        IpAddress = $ip
        ProbeCommand = "wsl -d $Distro -- ping -c 1 $(if ($ip) { $ip } else { 'localhost' })"
    }
}

wincmd -Name 'netops-resolve' -ScriptBlock $cmdResolve -Description "Resolve hostnames with built-in DNS fallback to System.Net.Dns."
wincmd -Name 'netops-subnet-scan' -ScriptBlock $cmdSubnetScan -Description "Scan a CIDR subnet using fast reachability checks."
wincmd -Name 'netops-arp-map' -ScriptBlock $cmdArpMap -Description "Render IPv4 ARP map from Get-NetNeighbor."
wincmd -Name 'netops-rdp-vnc' -ScriptBlock $cmdRdpVnc -Description "Check or apply RDP/VNC exposure controls."
wincmd -Name 'netops-wsl' -ScriptBlock $cmdWsl -Description "WSL integration status and eth0 endpoint lookup."
wincmd -Name 'netops-netcat-send' -ScriptBlock $cmdNetcatSend -Description "netcat-style safe send tool with TCP/UDP, timeout, one-shot/interactive, optional JSON."
wincmd -Name 'netops-netcat-recv' -ScriptBlock $cmdNetcatRecv -Description "netcat-style safe receive listener with TCP/UDP, timeout, one-shot/interactive, optional JSON."

Write-Host "[WINDO module $WindoModuleId] loaded (commands: netops-resolve, netops-subnet-scan, netops-arp-map, netops-rdp-vnc, netops-wsl)." -ForegroundColor DarkGray
