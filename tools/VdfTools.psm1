#Requires -Version 7.5
# Helpers for the VDF install: settings, data seeding, snapshots, guards. Design: docs\SETUP.md.

Set-StrictMode -Version 3.0

function ConvertFrom-VdfJson([string]$Json) {
    # DateKind String keeps date-like text exactly as written.
    $Json | ConvertFrom-Json -AsHashtable -DateKind String
}

function ConvertTo-VdfSettings {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$InputJson,
        [Parameter(Mandatory)][string]$DataFolder
    )
    $s = ConvertFrom-VdfJson $InputJson

    $s['FilePathContainsTexts'] = @('*.gif', '*.mp4', '*.mov')
    $s['FilterByFilePathContains'] = $true

    $quarantine = 'D:\Media\quarantine'
    $blacklists = @($s['Blacklists'] | Where-Object { $_ })
    if (-not ($blacklists | Where-Object { $_ -ieq $quarantine })) { $blacklists += $quarantine }
    $s['Blacklists'] = $blacklists

    $s['CustomDatabaseFolder'] = $DataFolder
    $s['HddMaxDegreeOfParallelism'] = 1
    $s['Includes'] = @('D:\Media\archive')
    $s['FilterByFileSize'] = $true
    $s['MaximumFileSize'] = 50
    $s['MinimumFileSize'] = 0
    $s['IncludeImages'] = $true

    $s | ConvertTo-Json -Depth 20 -Compress
}

function Merge-VdfBlacklistedGroups {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$JsonA,
        [Parameter(Mandatory)][string]$JsonB
    )
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $groups = [System.Collections.Generic.List[object]]::new()
    foreach ($json in $JsonA, $JsonB) {
        foreach ($g in (ConvertFrom-VdfJson $json)['groups']) {
            $key = (@($g) | Sort-Object { $_.ToLowerInvariant() } | ForEach-Object { $_.ToLowerInvariant() }) -join '|'
            if ($seen.Add($key)) { $groups.Add(@($g)) }
        }
    }
    [ordered]@{ version = 1; groups = $groups.ToArray() } | ConvertTo-Json -Depth 20 -Compress
}

Export-ModuleMember -Function ConvertTo-VdfSettings, Merge-VdfBlacklistedGroups
