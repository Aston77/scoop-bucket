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

function Assert-VdfNotRunning {
    $running = @(Get-Process -Name VDF.GUI, vdf-cli -ErrorAction SilentlyContinue)
    if ($running.Count -gt 0) {
        throw "VDF is running ($(($running.Name | Sort-Object -Unique) -join ', ')). Close it first."
    }
}

function Write-Utf8NoBom([string]$Path, [string]$Text) {
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}

function Copy-VerifiedFile([string]$Source, [string]$Destination) {
    Copy-Item -LiteralPath $Source -Destination $Destination
    $want = (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash
    $got = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash
    if ($want -ne $got) { throw "Hash mismatch after copying $Source to $Destination" }
}

$script:VdfBinSeed = 'avcodec-62.dll', 'avdevice-62.dll', 'avformat-62.dll', 'avutil-60.dll', 'avfilter-11.dll',
'swscale-9.dll', 'swresample-6.dll', 'ffmpeg.exe', 'ffprobe.exe', 'ffplay.exe'

function Initialize-VdfData {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$BackupDir,
        [Parameter(Mandatory)][string]$NewestDir,
        [Parameter(Mandatory)][string]$DataFolder,
        [Parameter(Mandatory)][string]$PersistDir
    )
    Assert-VdfNotRunning
    foreach ($target in $DataFolder, $PersistDir) {
        if ((Test-Path -LiteralPath $target) -and (Get-ChildItem -LiteralPath $target -Force | Select-Object -First 1)) {
            throw "Target folder is not empty: $target"
        }
    }

    $dataCopies = @(
        @("$BackupDir\ScannedFiles.db", 'ScannedFiles.db'),
        @("$BackupDir\ScannedFiles.fpheal1", 'ScannedFiles.fpheal1'),
        @("$BackupDir\UnionEmbeddings.db", 'UnionEmbeddings.db'),
        @("$NewestDir\DenseEmbeddings.db", 'DenseEmbeddings.db')
    )
    $persistCopies = @(Get-ChildItem -LiteralPath "$NewestDir\ai" -File | ForEach-Object { , @($_.FullName, "ai\$($_.Name)") })
    $persistCopies += @($script:VdfBinSeed | ForEach-Object { , @("$NewestDir\bin\$_", "bin\$_") })
    foreach ($c in $dataCopies + $persistCopies) {
        if (-not (Test-Path -LiteralPath $c[0] -PathType Leaf)) { throw "Source file missing: $($c[0])" }
    }

    if (-not $PSCmdlet.ShouldProcess("$DataFolder and $PersistDir", 'Seed VDF data and persist')) { return }

    New-Item -ItemType Directory -Force $DataFolder, "$PersistDir\ai", "$PersistDir\bin" | Out-Null
    foreach ($c in $dataCopies) { Copy-VerifiedFile $c[0] (Join-Path $DataFolder $c[1]) }
    foreach ($c in $persistCopies) { Copy-VerifiedFile $c[0] (Join-Path $PersistDir $c[1]) }

    $merged = Merge-VdfBlacklistedGroups -JsonA (Get-Content -LiteralPath "$BackupDir\BlacklistedGroups.json" -Raw) `
        -JsonB (Get-Content -LiteralPath "$NewestDir\BlacklistedGroups.json" -Raw)
    Write-Utf8NoBom (Join-Path $DataFolder 'BlacklistedGroups.json') $merged

    $settings = ConvertTo-VdfSettings -InputJson (Get-Content -LiteralPath "$NewestDir\Settings.json" -Raw) -DataFolder $DataFolder
    Write-Utf8NoBom (Join-Path $PersistDir 'Settings.json') $settings
}

function Get-VdfFileState([string]$Folder) {
    @(Get-ChildItem -LiteralPath $Folder -File | Sort-Object Name | ForEach-Object {
            [ordered]@{ name = $_.Name; size = $_.Length; lastWriteUtc = $_.LastWriteTimeUtc.ToString('o') }
        })
}

function Get-VdfSnapshotFolders([string]$SnapshotRoot) {
    @(Get-ChildItem -LiteralPath $SnapshotRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object Name -Match '^\d{8}-\d{6}$' | Sort-Object Name)
}

function Save-VdfSnapshot {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$DataFolder,
        [Parameter(Mandatory)][string]$SnapshotRoot,
        [ValidateRange(1, 100)][int]$Keep = 2
    )
    Assert-VdfNotRunning
    $state = @(Get-VdfFileState $DataFolder)
    $stateJson = ConvertTo-Json -InputObject $state -Depth 5 -Compress

    $newest = Get-VdfSnapshotFolders $SnapshotRoot | Select-Object -Last 1
    if ($newest -and (Test-Path -LiteralPath "$($newest.FullName)\manifest.json")) {
        $old = ConvertFrom-VdfJson (Get-Content -LiteralPath "$($newest.FullName)\manifest.json" -Raw)
        if ((ConvertTo-Json -InputObject @($old) -Depth 5 -Compress) -eq $stateJson) { return $null }
    }

    $time = Get-Date
    do {
        $name = $time.ToString('yyyyMMdd-HHmmss')
        $time = $time.AddSeconds(1)
    } while ((Test-Path -LiteralPath "$SnapshotRoot\$name") -or (Test-Path -LiteralPath "$SnapshotRoot\$name.partial"))
    $partial = Join-Path $SnapshotRoot "$name.partial"
    $final = Join-Path $SnapshotRoot $name

    try {
        New-Item -ItemType Directory -Force $partial | Out-Null
        foreach ($f in $state) {
            Copy-Item -LiteralPath (Join-Path $DataFolder $f.name) -Destination (Join-Path $partial $f.name) -ErrorAction Stop
        }
        Write-Utf8NoBom (Join-Path $partial 'manifest.json') $stateJson
        Rename-Item -LiteralPath $partial -NewName $name -ErrorAction Stop
    } catch {
        Remove-Item -LiteralPath $partial -Recurse -Force -ErrorAction SilentlyContinue
        throw
    }

    $all = @(Get-VdfSnapshotFolders $SnapshotRoot)
    if ($all.Count -gt $Keep) {
        $all | Select-Object -First ($all.Count - $Keep) | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force }
    }
    $final
}

function Invoke-Scoop([string[]]$ScoopArgs) {
    & scoop @ScoopArgs
    if ($LASTEXITCODE) { throw "scoop $($ScoopArgs -join ' ') failed with exit code $LASTEXITCODE" }
}

function Invoke-VdfRollback {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Version,
        [string]$DataFolder = 'C:\Tools\data\vdf',
        [string]$SnapshotRoot = 'C:\Tools\data\vdf-snapshots'
    )
    $snap = Save-VdfSnapshot -DataFolder $DataFolder -SnapshotRoot $SnapshotRoot
    if ($snap) { Write-Host "Snapshot: $snap" } else { Write-Host 'Snapshot: unchanged since the last one' }
    Invoke-Scoop -ScoopArgs @('reset', "vdf@$Version")
}

function Register-VdfSnapshotTask {
    [CmdletBinding()]
    param([string]$At = '04:30')
    $pwsh = (Get-Command pwsh -ErrorAction Stop).Source
    $script = Join-Path $PSScriptRoot 'vdf-nightly.ps1'
    $action = New-ScheduledTaskAction -Execute $pwsh -Argument "-NoProfile -NonInteractive -WindowStyle Hidden -File `"$script`""
    $trigger = New-ScheduledTaskTrigger -Daily -At $At
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopIfGoingOnBatteries -AllowStartIfOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 2)
    Register-ScheduledTask -TaskName 'VDF data snapshot' -Action $action -Trigger $trigger -Settings $settings `
        -Description 'Snapshot C:\Tools\data\vdf (skips while VDF runs or when unchanged), then the VDF post-update check.' -Force
}

Export-ModuleMember -Function ConvertTo-VdfSettings, Merge-VdfBlacklistedGroups, Initialize-VdfData,
Save-VdfSnapshot, Invoke-VdfRollback, Register-VdfSnapshotTask, Invoke-Scoop
