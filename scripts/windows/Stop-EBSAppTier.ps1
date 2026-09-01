<#
.SYNOPSIS
    Gracefully quiesces the Oracle E-Business Suite 12.2 application tier on a
    Windows node. Invoked by an OCI Full Stack Disaster Recovery user-defined step
    via the Oracle Cloud Agent Run Command plugin, or manually per RB-01 §3.

.DESCRIPTION
    Shutdown order is the reverse of startup and matters just as much:
      1. Drain the node from the OCI Flexible Load Balancer (if -Drain)
      2. Stop Concurrent Managers FIRST and wait for running requests to finish
      3. Stop Workflow Mailer
      4. Stop web / forms services

    Stopping the web tier before the Concurrent Managers strands running requests
    and produces exactly the stale FND_CONCURRENT_QUEUES rows that force a
    cmclean.sql on the far side.

.PARAMETER GraceSeconds
    How long to wait for in-flight concurrent requests before escalating.
    Default 300. Set to 0 for an emergency stop (accepts stranded requests).
#>
[CmdletBinding()]
param(
    [ValidateSet('ALL','WEB','CM','BI')][string]$Node = 'ALL',
    [switch]$Drain,
    [int]$GraceSeconds = 300,
    [string]$EbsEnvScript = $env:EBS_ENV_SCRIPT
)

$ErrorActionPreference = 'Stop'
function Info ($m) { Write-Host "[INFO ] $m" }
function Warn ($m) { Write-Host "[WARN ] $m" -ForegroundColor Yellow }

Info "Stop-EBSAppTier  node=$Node  grace=${GraceSeconds}s  $(Get-Date -Format o)"

# --- 1. Drain from the load balancer ---------------------------------------
if ($Drain -and $env:DR_LB_OCID -and $env:DR_LB_BACKENDSET) {
    Info 'Draining node from OCI Flexible Load Balancer'
    & oci lb backend update --load-balancer-id $env:DR_LB_OCID `
        --backend-set-name $env:DR_LB_BACKENDSET `
        --backend-name "$($env:COMPUTERNAME):$($env:EBS_HTTP_PORT)" `
        --drain true --offline false --backup false --weight 1 --force
    Start-Sleep -Seconds 30   # allow in-flight HTTP sessions to complete
}

# --- 2. Capture in-flight concurrent requests (feeds the WRT reconciliation) -
Info 'Capturing in-flight concurrent request list for WRT reconciliation'
$evidence = Join-Path $PSScriptRoot '..\..\evidence'
if (-not (Test-Path $evidence)) { New-Item -ItemType Directory -Path $evidence | Out-Null }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
& sqlplus -s "$env:APPS_CONN" @"
SET PAGESIZE 0 FEEDBACK OFF LINESIZE 300
SPOOL $evidence\inflight-requests-$stamp.txt
SELECT request_id || '|' || phase_code || '|' || status_code || '|' || user_concurrent_program_name
  FROM fnd_conc_req_summary_v WHERE phase_code IN ('R','P');
SPOOL OFF
exit
"@
Info "  captured -> inflight-requests-$stamp.txt"

# --- 3. Stop Concurrent Managers FIRST --------------------------------------
if ($Node -in @('ALL','CM')) {
    Info 'Stopping Concurrent Managers'
    & cmd.exe /c "$EbsEnvScript && adcmctl.cmd stop"

    if ($GraceSeconds -gt 0) {
        Info "Waiting up to ${GraceSeconds}s for in-flight requests to complete"
        $deadline = (Get-Date).AddSeconds($GraceSeconds)
        while ((Get-Date) -lt $deadline) {
            $running = (& sqlplus -s "$env:APPS_CONN" @"
SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT COUNT(*) FROM fnd_concurrent_requests WHERE phase_code = 'R';
exit
"@) -join '' -replace '\s',''
            if ($running -eq '0') { Info '  all requests drained'; break }
            Info "  $running request(s) still running..."
            Start-Sleep -Seconds 15
        }
        if ((Get-Date) -ge $deadline) {
            Warn 'Grace period expired with requests still running.'
            Warn 'These will need reconciliation on the far side - see RB-02 §6.'
        }
    }
}

# --- 4. Workflow Mailer -----------------------------------------------------
if ($Node -in @('ALL','CM')) {
    Info 'Stopping Workflow Mailer'
    try { & cmd.exe /c "$EbsEnvScript && adworkflowmailer.cmd stop" } catch { Warn 'Workflow Mailer stop reported an error - continuing' }
}

# --- 5. Web / forms ---------------------------------------------------------
if ($Node -in @('ALL','WEB')) {
    Info 'Stopping web/forms tier'
    & cmd.exe /c "$EbsEnvScript && adstpall.cmd -nopromptmsg"
}

if ($Node -in @('ALL','BI')) {
    Info 'Stopping BI/visualization tier'
    try { & cmd.exe /c "$EbsEnvScript && stop_bi_services.cmd" } catch { Warn 'BI stop reported an error - continuing' }
}

Info "Stop-EBSAppTier complete  $(Get-Date -Format o)"
exit 0
