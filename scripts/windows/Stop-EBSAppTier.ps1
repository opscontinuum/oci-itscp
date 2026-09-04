#ps1
<#
.SYNOPSIS
    Gracefully quiesces the Oracle E-Business Suite 12.2 application tier on a
    Windows node. Invoked by an OCI Full Stack Disaster Recovery user-defined step
    via the Oracle Cloud Agent Run Command plugin, or manually per RB-01 §3.

.DESCRIPTION
    Shutdown order is the reverse of startup and matters just as much:
      1. Drain the node from THIS region's OCI Flexible Load Balancer (if -Drain)
      2. Stop Concurrent Managers FIRST and wait for running requests to finish
         (the Workflow notification mailer is a service component managed by the
         concurrent-manager tier, so it stops with adcmctl.cmd stop)
      3. Stop web / forms services

    Environment: EBS_LB_OCID / EBS_LB_BACKENDSET name the load balancer this node is
    behind (the region-local one); EBS_NODE_IP is the backend's IP address, because
    the OCI CLI identifies a backend as <ip>:<port>. APPS_PWD supplies the APPS
    password for adcmctl.cmd non-interactively (from OCI Vault via the step
    environment). EBS_BI_STOP_CMD is the site-specific BI tier stop command.

    Stopping the web tier before the Concurrent Managers strands running requests.
    Stale FND_CONCURRENT_QUEUES / ICM rows on the far side are the usual result
    (engineering judgment; see the cmclean applicability note in scripts/ebs/README.md).

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
if ($Drain -and $env:EBS_LB_OCID -and $env:EBS_LB_BACKENDSET -and $env:EBS_NODE_IP) {
    Info 'Draining node from the region-local OCI Flexible Load Balancer'
    & oci lb backend update --load-balancer-id $env:EBS_LB_OCID `
        --backend-set-name $env:EBS_LB_BACKENDSET `
        --backend-name "$($env:EBS_NODE_IP):$($env:EBS_HTTP_PORT)" `
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
    & cmd.exe /c "$EbsEnvScript && adcmctl.cmd stop apps/$env:APPS_PWD"

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

# --- 5. Web / forms ---------------------------------------------------------
if ($Node -in @('ALL','WEB')) {
    Info 'Stopping web/forms tier'
    & cmd.exe /c "$EbsEnvScript && adstpall.cmd -nopromptmsg"
}

if ($Node -in @('ALL','BI')) {
    Info 'Stopping BI/visualization tier'
    if ($env:EBS_BI_STOP_CMD) { try { & cmd.exe /c "$EbsEnvScript && $env:EBS_BI_STOP_CMD" } catch { Warn 'BI stop reported an error - continuing' } }
    else { Warn 'EBS_BI_STOP_CMD not set; BI tier stop is site-specific and was skipped' }
}

Info "Stop-EBSAppTier complete  $(Get-Date -Format o)"
exit 0
