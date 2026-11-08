#Requires -Version 7.5
# Run by the "VDF data snapshot" scheduled task. Snapshots the VDF data folder; a refusal (VDF running) is
# logged, not fatal.
Import-Module "$PSScriptRoot\VdfTools.psm1" -Force
$root = 'C:\Tools\data\vdf-snapshots'
New-Item -ItemType Directory -Force $root | Out-Null
$log = Join-Path $root 'snapshot.log'
$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
try {
    $snap = Save-VdfSnapshot -DataFolder 'C:\Tools\data\vdf' -SnapshotRoot $root
    $msg = if ($snap) { "snapshot $snap" } else { 'unchanged, skipped' }
    Add-Content -LiteralPath $log "$stamp $msg"
} catch {
    Add-Content -LiteralPath $log "$stamp FAILED: $($_.Exception.Message)"
}
# After any update (UniGetUI included): data-folder guard and pinned AI model check, logged to checks.log.
if (Test-Path -LiteralPath 'C:\Tools\scoop\apps\vdf\current\manifest.json') {
    Invoke-VdfPostUpdateCheck | Out-Null
}
