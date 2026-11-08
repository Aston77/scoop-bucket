#Requires -Version 7.5
<#
.SYNOPSIS
    Install a CloudCompare build downloaded from cloudcompare.org, smoke-test it, and point
    C:\Tools\CloudCompare\current at it only if every check passes.
.EXAMPLE
    Update-CloudCompare.ps1 $HOME\Downloads\CloudCompare_v2.14.beta_bin_x64.7z
    Update-CloudCompare.ps1 .\cc.7z -Version v2.14.beta4
.NOTES
    The version defaults to the newest pre-release tag of CloudCompare/CloudCompare on GitHub.
    Roll back with: Import-Module CloudCompareTools.psm1; Set-CloudCompareCurrent -Root C:\Tools\CloudCompare -Version <old>
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)][string]$Archive,
    [string]$Version
)
Import-Module "$PSScriptRoot\CloudCompareTools.psm1" -Force
if (-not $Version) {
    $Version = gh release list -R CloudCompare/CloudCompare --json tagName,isPrerelease --limit 20 `
        --jq '[.[] | select(.isPrerelease)][0].tagName'
    if (-not $Version) { throw 'Could not read the latest pre-release tag; pass -Version.' }
    Write-Host "Version (latest GitHub pre-release tag): $Version"
}
Update-CloudCompare -Source $Archive -Version $Version -Root 'C:\Tools\CloudCompare'
