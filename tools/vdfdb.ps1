#Requires -Version 7.5
# vdf-cli with the data folder always passed: vdfdb db export -o out.json
# Without --db, vdf-cli silently starts an empty database in the app folder.
Import-Module "$PSScriptRoot\VdfTools.psm1" -Force
if (-not (Test-VdfDataFolder -DataFolder 'C:\Tools\data\vdf')) { exit 1 }
& vdf-cli @(Get-VdfCliArgs -UserArgs $args)
exit $LASTEXITCODE
