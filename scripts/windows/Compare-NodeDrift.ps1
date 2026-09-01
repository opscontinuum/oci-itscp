<#
.SYNOPSIS
    Audits local configuration drift on a Windows EBS node in the places that
    NO replicated volume carries. Part of RB-03 §4 (failback drift
    reconciliation) and docs/04-monitoring.md §5 (weekly drift report).

.DESCRIPTION
    Volume Group Replication carries the disks. It does not carry what is only
    true of the running OS: scheduled task definitions, local certificates,
    installed hotfixes, service start modes, ODBC DSNs, machine environment
    variables, the hosts file, Oracle Cloud Agent and JRE versions, and the
    contents of local scratch paths. Those are exactly what changes under
    incident pressure in the DR region and is then lost at failback.

    Two modes:
      Capture  - write a JSON manifest of this node's state (run on BOTH nodes
                 of a pair: the Ashburn node and its identically-named Phoenix
                 twin, or the same node before and after a DR period).
      Compare  - diff two manifests and write a Markdown drift report.

    READ-ONLY. It never changes the node. Remediation goes through the image
    or through code, not by hand (RB-03 §4 rule).

.PARAMETER Mode
    Capture or Compare.

.PARAMETER Out
    Capture: manifest path (.json). Compare: report path (.md).

.PARAMETER Baseline
    Compare: the manifest to treat as the reference (normally the Phoenix
    node's manifest after the DR period, because that is what production
    became).

.PARAMETER Candidate
    Compare: the manifest to check against the baseline (normally the rebuilt
    Ashburn node).

.PARAMETER ScratchPaths
    Capture: local paths outside replicated volumes to inventory. Default
    C:\temp and the scheduled-task and cert stores are always included.

.EXAMPLE
    # On WIN-EBSCM01 in Phoenix, and again on WIN-EBSCM01 in Ashburn:
    .\Compare-NodeDrift.ps1 -Mode Capture -Out C:\drift\WIN-EBSCM01-phx.json
    .\Compare-NodeDrift.ps1 -Mode Capture -Out C:\drift\WIN-EBSCM01-iad.json
    # Anywhere:
    .\Compare-NodeDrift.ps1 -Mode Compare -Baseline C:\drift\WIN-EBSCM01-phx.json `
        -Candidate C:\drift\WIN-EBSCM01-iad.json -Out evidence\drift-WIN-EBSCM01.md

.NOTES
    Exit codes: 0 = no drift, 1 = drift found (report written), 3 = usage/error.
    Compatible with Windows PowerShell 5.1 (the version on Windows Server) and
    PowerShell 7. Cmdlets that are Windows-only degrade to "unavailable" so the
    manifest is still produced.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Capture','Compare')][string]$Mode,
    [Parameter(Mandatory)][string]$Out,
    [string]$Baseline,
    [string]$Candidate,
    [string[]]$ScratchPaths = @('C:\temp', 'C:\Windows\Temp\ebs', 'C:\Oracle\scripts')
)

$ErrorActionPreference = 'Stop'
function Info ($m) { Write-Host "[INFO ] $m" }
function Warn ($m) { Write-Host "[WARN ] $m" -ForegroundColor Yellow }
function Fail ($m) { Write-Host "[FAIL ] $m" -ForegroundColor Red; exit 3 }

# Run a probe; on any failure record the reason instead of aborting the capture.
function Try-Probe ([string]$Name, [scriptblock]$Body) {
    try { return (& $Body) }
    catch { Warn "$Name unavailable: $($_.Exception.Message)"; return @{ '_unavailable' = $_.Exception.Message } }
}

# Normalise any object list into a sorted hashtable keyed by $KeyProp, values = selected props.
function To-Map ($items, [string]$KeyProp, [string[]]$Props) {
    $m = [ordered]@{}
    foreach ($i in ($items | Sort-Object $KeyProp)) {
        $k = [string]$i.$KeyProp
        if (-not $k) { continue }
        $v = [ordered]@{}
        foreach ($p in $Props) { $v[$p] = [string]$i.$p }
        $m[$k] = $v
    }
    return $m
}

function File-Hash ([string]$Path) {
    if (Test-Path $Path) { return (Get-FileHash -Path $Path -Algorithm SHA256).Hash } else { return 'ABSENT' }
}

# ---------------------------------------------------------------------------
# CAPTURE
# ---------------------------------------------------------------------------
function Invoke-Capture {
    Info "Capture on $env:COMPUTERNAME  $(Get-Date -Format o)"
    $m = [ordered]@{
        _meta = [ordered]@{
            hostname   = $env:COMPUTERNAME
            capturedAt = (Get-Date).ToUniversalTime().ToString('o')
            os         = Try-Probe 'OS' { (Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, BuildNumber, LastBootUpTime) }
            tool       = 'Compare-NodeDrift.ps1'
        }
    }

    Info 'Scheduled tasks (definitions and actions, not last-run times)'
    $m.scheduledTasks = Try-Probe 'ScheduledTasks' {
        $tasks = Get-ScheduledTask | Where-Object { $_.TaskPath -notlike '\Microsoft\*' }
        $r = [ordered]@{}
        foreach ($t in ($tasks | Sort-Object TaskPath, TaskName)) {
            $r["$($t.TaskPath)$($t.TaskName)"] = [ordered]@{
                state    = [string]$t.State
                user     = [string]$t.Principal.UserId
                actions  = (($t.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) -join ' ; ')
                triggers = (($t.Triggers | ForEach-Object { $_.CimClass.CimClassName + ':' + $_.StartBoundary }) -join ' ; ')
            }
        }
        $r
    }

    Info 'Local certificates (LocalMachine\My and \Root thumbprints)'
    $m.certificates = Try-Probe 'Certificates' {
        $r = [ordered]@{}
        foreach ($store in 'My','Root','CA') {
            foreach ($c in (Get-ChildItem "Cert:\LocalMachine\$store" | Sort-Object Thumbprint)) {
                $r["$store\$($c.Thumbprint)"] = [ordered]@{ subject = $c.Subject; notAfter = $c.NotAfter.ToString('o') }
            }
        }
        $r
    }

    Info 'Installed hotfixes'
    $m.hotfixes = Try-Probe 'HotFix' { (Get-HotFix | Sort-Object HotFixID | ForEach-Object { $_.HotFixID }) }

    Info 'Services (start mode) -- non-Microsoft plus Oracle, WebLogic, EBS'
    $m.services = Try-Probe 'Services' {
        $svcs = Get-CimInstance Win32_Service | Where-Object { $_.PathName -notlike '*\Windows\*' -or $_.Name -like '*Oracle*' }
        To-Map $svcs 'Name' @('StartMode','StartName','PathName')
    }

    Info 'Machine environment variables'
    $m.environment = Try-Probe 'Environment' {
        $r = [ordered]@{}
        $e = [Environment]::GetEnvironmentVariables('Machine')
        foreach ($k in ($e.Keys | Sort-Object)) { $r[$k] = [string]$e[$k] }
        $r
    }

    Info 'ODBC DSNs and drivers'
    $m.odbc = Try-Probe 'ODBC' {
        [ordered]@{
            dsns    = (To-Map (Get-OdbcDsn -ErrorAction Stop) 'Name' @('DriverName','Platform','DsnType'))
            drivers = ((Get-OdbcDriver | Sort-Object Name | ForEach-Object { "$($_.Name)|$($_.Platform)" }))
        }
    }

    Info 'Versions: Oracle Cloud Agent, JRE, Forms client, MKS Toolkit'
    $m.versions = Try-Probe 'Versions' {
        $apps = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                                 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -match 'Oracle Cloud Agent|Java|JRE|JDK|Forms|MKS|Cygwin|WebLogic|Oracle' }
        To-Map $apps 'DisplayName' @('DisplayVersion','InstallDate')
    }

    Info 'Hosts file and TNS admin hashes'
    $tns = if ($env:TNS_ADMIN) { Join-Path $env:TNS_ADMIN 'tnsnames.ora' } else { 'ABSENT' }
    $m.fileHashes = [ordered]@{
        hosts        = File-Hash "$env:SystemRoot\System32\drivers\etc\hosts"
        tnsnames     = if ($tns -ne 'ABSENT') { File-Hash $tns } else { 'TNS_ADMIN unset' }
        sqlnet       = if ($tns -ne 'ABSENT') { File-Hash (Join-Path $env:TNS_ADMIN 'sqlnet.ora') } else { 'TNS_ADMIN unset' }
    }

    Info 'Local users and group membership'
    $m.localAccounts = Try-Probe 'LocalAccounts' {
        [ordered]@{
            users  = (Get-LocalUser | Sort-Object Name | ForEach-Object { "$($_.Name)|enabled=$($_.Enabled)" })
            admins = (Get-LocalGroupMember -Group 'Administrators' | Sort-Object Name | ForEach-Object { $_.Name })
        }
    }

    Info "Scratch paths outside replicated volumes: $($ScratchPaths -join ', ')"
    $m.scratch = [ordered]@{}
    foreach ($p in $ScratchPaths) {
        if (Test-Path $p) {
            $files = Get-ChildItem -Path $p -Recurse -File -ErrorAction SilentlyContinue | Sort-Object FullName
            $m.scratch[$p] = [ordered]@{ count = $files.Count; files = ($files | ForEach-Object { "$($_.FullName)|$($_.Length)|$($_.LastWriteTimeUtc.ToString('o'))" }) }
        } else { $m.scratch[$p] = 'ABSENT' }
    }

    Info 'Windows Firewall rules (enabled, non-default)'
    $m.firewall = Try-Probe 'Firewall' {
        $rules = Get-NetFirewallRule -Enabled True | Where-Object { $_.Group -eq '' -or $_.Group -eq $null }
        To-Map $rules 'Name' @('DisplayName','Direction','Action','Profile')
    }

    $dir = Split-Path -Parent $Out
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    $m | ConvertTo-Json -Depth 8 | Set-Content -Path $Out -Encoding UTF8
    Info "Manifest written: $Out"
    exit 0
}

# ---------------------------------------------------------------------------
# COMPARE
# ---------------------------------------------------------------------------
function Flatten ($obj, [string]$prefix, [hashtable]$acc) {
    # Flatten nested PSCustomObject/array into "path" -> string leaf pairs.
    if ($null -eq $obj) { $acc[$prefix] = ''; return }
    if ($obj -is [string] -or $obj -is [ValueType]) { $acc[$prefix] = [string]$obj; return }
    if ($obj -is [System.Collections.IEnumerable] -and -not ($obj -is [System.Management.Automation.PSCustomObject])) {
        $i = 0; foreach ($e in $obj) { Flatten $e "$prefix[$i]" $acc; $i++ }
        if ($i -eq 0) { $acc[$prefix] = '(empty)' }
        return
    }
    foreach ($p in $obj.PSObject.Properties) { Flatten $p.Value "$prefix/$($p.Name)" $acc }
}

function Invoke-Compare {
    if (-not $Baseline -or -not $Candidate) { Fail 'Compare requires -Baseline and -Candidate manifests.' }
    if (-not (Test-Path $Baseline))  { Fail "Baseline not found: $Baseline" }
    if (-not (Test-Path $Candidate)) { Fail "Candidate not found: $Candidate" }

    $b = Get-Content $Baseline  -Raw | ConvertFrom-Json
    $c = Get-Content $Candidate -Raw | ConvertFrom-Json
    Info "Comparing candidate $($c._meta.hostname) ($($c._meta.capturedAt)) against baseline $($b._meta.hostname) ($($b._meta.capturedAt))"

    $fb = @{}; $fc = @{}
    Flatten $b '' $fb; Flatten $c '' $fc
    # Metadata and scratch timestamps legitimately differ; keep scratch file names, drop their mtimes.
    $ignore = '^/_meta/'
    $norm = { param($k, $v) if ($k -like '/scratch/*') { ($v -split '\|')[0] } else { $v } }

    $findings = New-Object System.Collections.Generic.List[object]
    $keys = ($fb.Keys + $fc.Keys | Sort-Object -Unique) | Where-Object { $_ -notmatch $ignore }
    foreach ($k in $keys) {
        $inB = $fb.ContainsKey($k); $inC = $fc.ContainsKey($k)
        $vb = if ($inB) { & $norm $k $fb[$k] } else { $null }
        $vc = if ($inC) { & $norm $k $fc[$k] } else { $null }
        if ($inB -and -not $inC)      { $findings.Add([pscustomobject]@{ Area = ($k -split '/')[1]; Item = $k; Baseline = $vb; Candidate = '(missing)'; Kind = 'MISSING ON CANDIDATE' }) }
        elseif ($inC -and -not $inB)  { $findings.Add([pscustomobject]@{ Area = ($k -split '/')[1]; Item = $k; Baseline = '(missing)'; Candidate = $vc; Kind = 'EXTRA ON CANDIDATE' }) }
        elseif ($vb -ne $vc)          { $findings.Add([pscustomobject]@{ Area = ($k -split '/')[1]; Item = $k; Baseline = $vb; Candidate = $vc; Kind = 'DIFFERENT' }) }
    }

    $severity = @{
        scheduledTasks = 'HIGH'; certificates = 'HIGH'; services = 'HIGH'; environment = 'HIGH'; fileHashes = 'HIGH';
        odbc = 'MEDIUM'; versions = 'MEDIUM'; localAccounts = 'MEDIUM'; firewall = 'MEDIUM'; hotfixes = 'MEDIUM'; scratch = 'LOW'
    }

    $dir = Split-Path -Parent $Out
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# In-guest drift report — $($c._meta.hostname)")
    $lines.Add('')
    $lines.Add("Baseline: ``$Baseline`` ($($b._meta.hostname), $($b._meta.capturedAt))  ")
    $lines.Add("Candidate: ``$Candidate`` ($($c._meta.hostname), $($c._meta.capturedAt))  ")
    $lines.Add("Generated $((Get-Date).ToUniversalTime().ToString('o')) by ``Compare-NodeDrift.ps1`` (RB-03 §4, docs/04 §5).")
    $lines.Add('')
    if ($findings.Count -eq 0) {
        $lines.Add('**No in-guest drift detected** across scheduled tasks, certificates, hotfixes, services, environment, ODBC, versions, file hashes, local accounts, firewall rules and scratch paths.')
    } else {
        $lines.Add("**$($findings.Count) finding(s).** Nothing goes back to Ashburn that was not re-applied through Terraform or captured in an image (RB-03 §4). Each row needs an owner.")
        $lines.Add('')
        $lines.Add('| # | Severity | Area | Item | Baseline | Candidate | Kind | Owner | Due |')
        $lines.Add('|---|---|---|---|---|---|---|---|---|')
        $i = 0
        foreach ($f in ($findings | Sort-Object { $severity[$_.Area] }, Area, Item)) {
            $i++
            $sev = if ($severity.ContainsKey($f.Area)) { $severity[$f.Area] } else { 'LOW' }
            $esc = { param($s) ([string]$s) -replace '\|', '\|' }
            $lines.Add("| $i | $sev | $($f.Area) | ``$(& $esc $f.Item)`` | $(& $esc $f.Baseline) | $(& $esc $f.Candidate) | $($f.Kind) | | |")
        }
    }
    $lines | Set-Content -Path $Out -Encoding UTF8
    Info "Report written: $Out ($($findings.Count) finding(s))"
    if ($findings.Count -gt 0) { exit 1 } else { exit 0 }
}

switch ($Mode) {
    'Capture' { Invoke-Capture }
    'Compare' { Invoke-Compare }
}
