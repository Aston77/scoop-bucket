#Requires -Version 7.5
# One-time seeding of C:\Tools\data\vdf and the Scoop persist folder from the old Downloads copies.
# Copies only: the Downloads folders are never written. See docs\SETUP.md, "VDF: which data carries forward".
[CmdletBinding(SupportsShouldProcess)]
param()

Import-Module "$PSScriptRoot\VdfTools.psm1" -Force
Initialize-VdfData -BackupDir 'C:\Users\User\Downloads\GUI-win-x64_Backup' `
    -NewestDir 'C:\Users\User\Downloads\GUI-win-x64' `
    -DataFolder 'C:\Tools\data\vdf' `
    -PersistDir 'C:\Tools\scoop\persist\vdf' `
    -WhatIf:$WhatIfPreference
