<#
.SYNOPSIS
    Starts the Oracle E-Business Suite 12.2 application tier on a Windows node in
    the DR region. Invoked by an OCI Full Stack Disaster Recovery user-defined step
    via the Oracle Cloud Agent Run Command plugin, or manually per RB-01 / RB-02.

.DESCRIPTION
    Order of operations is load-bearing:
      1. Verify storage is mounted (fs1, fs2 AND fs_ne)
      2. Verify database reachability and role
      3. Run cmclean.sql with all managers down  (My Oracle Support Doc ID 134007.1)
      4. Start web / forms services
      5. Start Concurrent Managers last

    In -DrillMode, five isolation controls are enforced BEFORE anything starts.
    If any cannot be verified the script aborts. A drill that transmits a real
    payment file or emails real suppliers is worse than no drill at all.

.PARAMETER Node
    ALL, WEB, CM, or BI. Determines which service groups start.

.PARAMETER RunCmClean
    Execute cmclean.sql before starting Concurrent Managers. Required after any
    role transition. See RB-02 §5.

.PARAMETER DrillMode
    Enforce drill isolation (RB-04 §2) and refuse to start without it.

.EXAMPLE
    .\Start-EBSAppTier.ps1 -Node ALL -RunCmClean
    .\Start-EBSAppTier.ps1 -Node ALL -RunCmClean -DrillMode
#>
[CmdletBinding()]
param(
    [ValidateSet('ALL','WEB','CM','BI')][string]$Node = 'ALL',
    [switch]$RunCmClean,
    [switch]$DrillMode,
    [string]$EbsEnvScript = $env:EBS_ENV_SCRIPT,
    [string]$ContextFile  = $env:CONTEXT_FILE
)

$ErrorActionPreference = 'Stop'
function Info  ($m) { Write-Host "[INFO ] $m" }
function Warn  ($m) { Write-Host "[WARN ] $m" -ForegroundColor Yellow }
function Fail  ($m) { Write-Host "[FAIL ] $m" -ForegroundColor Red; exit 3 }

Info "Start-EBSAppTier  node=$Node  drill=$($DrillMode.IsPresent)  $(Get-Date -Format o)"

# --- 1. Storage preflight ---------------------------------------------------
# EBS 12.2 keeps a run edition, a patch edition, and a non-editioned filesystem.
# A node missing fs2 will start, but the next adop cycle fails and you have no
# patching capability in DR. Fail here rather than discovering it weeks later.
Info 'Verifying EBS filesystems are mounted'
foreach ($fsVar in @('EBS_FS1','EBS_FS2','EBS_FS_NE')) {
    $path = [Environment]::GetEnvironmentVariable($fsVar, 'Machine')
    if (-not $path)            { Fail "$fsVar is not set. Storage attach step did not complete." }
    if (-not (Test-Path $path)) { Fail "$fsVar path not present: $path. Volume group activation likely incomplete." }
    Info "  ok $fsVar -> $path"
}

# --- 2. Drill isolation (enforced before ANY service starts) ----------------
if ($DrillMode) {
    Info 'DRILL MODE — enforcing isolation controls (RB-04 §2)'
    $isolation = @{}

    # (a) Workflow Mailer must be unable to send — otherwise it mails real customers.
    #     Oracle's documented tool for a copied instance is $FND_TOP/sql/wfmlpcln.sql, which
    #     resets the notification mailer configuration and nulls the outbound SMTP server
    #     name (Oracle Workflow Administrator's Guide 12.2, "Cloning"). A snapshot standby
    #     drill IS a copied instance that is discarded on convert-back, so this is the
    #     right tool. Direct updates to the mailer parameter tables are undocumented and
    #     deliberately not used here.
    $isolation['WorkflowMailer'] = {
        $fndTop = $env:FND_TOP
        if (-not $fndTop) { return $false }
        $wfmlpcln = Join-Path $fndTop 'sql\wfmlpcln.sql'
        if (-not (Test-Path $wfmlpcln)) { return $false }
        & sqlplus -s "$env:APPS_CONN" "@$wfmlpcln"
        return $LASTEXITCODE -eq 0
    }

    # (b) Outbound integration endpoints redirected to sinks.
    $isolation['OutboundEndpoints'] = {
        if (-not $env:DR_DRILL_SINK_HOST) { return $false }
        return (Test-NetConnection -ComputerName $env:DR_DRILL_SINK_HOST -Port 443 -InformationLevel Quiet)
    }

    # (c) Printers redirected to a null queue.
    $isolation['Printers'] = {
        return [bool](Get-Printer -Name 'DR_DRILL_NULL' -ErrorAction SilentlyContinue)
    }

    # (d) Site-level banner makes it unmistakable to any user who logs in.
    $isolation['Banner'] = {
        & sqlplus -s "$env:APPS_CONN" @"
BEGIN fnd_profile.save('SITE_NAME','DR DRILL - NOT PRODUCTION','SITE'); COMMIT; END;
/
exit
"@
        return $LASTEXITCODE -eq 0
    }

    # (e) Drill LB must NOT be registered in OCI Traffic Management.
    $isolation['NotInTrafficMgmt'] = {
        return ($env:DR_DRILL_LB_REGISTERED -ne 'true')
    }

    $failed = @()
    foreach ($k in $isolation.Keys) {
        try   { if (& $isolation[$k]) { Info "  ok isolation: $k" } else { $failed += $k } }
        catch { $failed += $k }
    }
    if ($failed.Count -gt 0) {
        Fail ("ABORTING DRILL. Could not verify isolation: {0}. " -f ($failed -join ', ') +
              'Starting EBS now risks real outbound traffic to customers, suppliers or banks.')
    }
    Info 'All five isolation controls verified.'
}

# --- 3. Database reachability and role --------------------------------------
Info 'Checking database role'
$role = (& sqlplus -s "$env:APPS_CONN" @"
SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT database_role || ':' || open_mode FROM v`$database;
exit
"@) -join '' -replace '\s',''
Info "  database reports: $role"
if ($role -notmatch 'PRIMARY|SNAPSHOTSTANDBY') {
    Fail "Database is '$role'. The EBS application tier requires PRIMARY (failover) or SNAPSHOT STANDBY (drill). Do not start EBS against a physical standby."
}

# --- 4. cmclean -------------------------------------------------------------
# Stale FND_CONCURRENT_QUEUES / ICM rows from the old region prevent managers
# from starting, and the failure mode is confusing. Always run after a role change.
if ($RunCmClean) {
    Info 'Running cmclean.sql (all managers must be down)'
    $cmclean = Join-Path $PSScriptRoot '..\ebs\cmclean.sql'
    if (-not (Test-Path $cmclean)) {
        Fail "cmclean.sql not found at $cmclean. Obtain the current version from My Oracle Support Doc ID 134007.1 and place it there — it is not redistributable and is deliberately not vendored in this repository."
    }
    & sqlplus -s "$env:APPS_CONN" "@$cmclean"
    if ($LASTEXITCODE -ne 0) { Fail 'cmclean.sql failed. Do not start Concurrent Managers.' }
    Info '  cmclean complete'
}

# --- 5. Start services ------------------------------------------------------
function Start-Group ($label, $script) {
    Info "Starting $label"
    & cmd.exe /c "$EbsEnvScript && $script"
    if ($LASTEXITCODE -ne 0) { Fail "$label failed to start (exit $LASTEXITCODE)" }
    Info "  $label started"
}

switch ($Node) {
    'WEB' { Start-Group 'web/forms tier' 'adstrtal.cmd -nopromptmsg' }
    'BI'  { Start-Group 'BI/visualization tier' 'start_bi_services.cmd' }
    'CM'  { Start-Group 'concurrent managers' 'adcmctl.cmd start' }
    'ALL' {
        Start-Group 'web/forms tier' 'adstrtal.cmd -nopromptmsg'
        Info 'Verifying web tier responds before starting Concurrent Managers'
        $probe = "http://$env:COMPUTERNAME`:$env:EBS_HTTP_PORT/OA_HTML/AppsLocalLogin.jsp"
        $ok = $false
        foreach ($i in 1..30) {
            try { if ((Invoke-WebRequest -Uri $probe -UseBasicParsing -TimeoutSec 10).StatusCode -eq 200) { $ok = $true; break } } catch {}
            Start-Sleep -Seconds 10
        }
        if (-not $ok) { Fail "Web tier did not respond at $probe after 5 minutes. Not starting Concurrent Managers." }
        Info '  web tier healthy'
        Start-Group 'concurrent managers' 'adcmctl.cmd start'
    }
}

# --- 6. Post-start verification --------------------------------------------
Info 'Verifying FND_NODES matches the running hostname'
$nodes = (& sqlplus -s "$env:APPS_CONN" @"
SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT COUNT(*) FROM fnd_nodes WHERE UPPER(node_name) = UPPER('$env:COMPUTERNAME');
exit
"@) -join '' -replace '\s',''
if ($nodes -eq '0') {
    Warn "FND_NODES has no entry for $env:COMPUTERNAME."
    Warn 'The identical-hostname design (docs/01-architecture.md §5.1) has drifted.'
    Warn 'You are now on the AutoConfig branch — see RB-02 §7b. Expect +3-5 hours.'
} else {
    Info "  ok FND_NODES entry present for $env:COMPUTERNAME"
}

Info "Start-EBSAppTier complete  $(Get-Date -Format o)"
exit 0
