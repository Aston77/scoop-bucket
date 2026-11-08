BeforeDiscovery {
    $script:IsPs7 = $PSVersionTable.PSVersion.Major -ge 7
    $script:NewestDir = 'C:\Users\User\Downloads\GUI-win-x64'
    $script:BackupDir = 'C:\Users\User\Downloads\GUI-win-x64_Backup'
    $script:HasRealFiles = (Test-Path "$NewestDir\Settings.json") -and (Test-Path "$BackupDir\BlacklistedGroups.json")
}

BeforeAll {
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        Import-Module "$PSScriptRoot\..\tools\VdfTools.psm1" -Force
    }
    $NewestDir = 'C:\Users\User\Downloads\GUI-win-x64'
    $BackupDir = 'C:\Users\User\Downloads\GUI-win-x64_Backup'
}

Describe 'ConvertTo-VdfSettings' -Skip:(-not $IsPs7) {
    Context 'real Settings.json' -Skip:(-not $HasRealFiles) {
        BeforeAll {
            $inputJson = Get-Content "$NewestDir\Settings.json" -Raw
            $in = $inputJson | ConvertFrom-Json -AsHashtable
            $out = ConvertTo-VdfSettings -InputJson $inputJson -DataFolder 'C:\Tools\data\vdf' | ConvertFrom-Json -AsHashtable
        }
        It 'fixes the path filter to *.gif, *.mp4, *.mov' {
            $out.FilePathContainsTexts | Should -Be @('*.gif', '*.mp4', '*.mov')
            $out.FilterByFilePathContains | Should -BeTrue
        }
        It 'blacklists quarantine exactly once' {
            @($out.Blacklists | Where-Object { $_ -eq 'D:\Media\quarantine' }).Count | Should -Be 1
        }
        It 'sets the data folder, HDD parallelism and scope' {
            $out.CustomDatabaseFolder | Should -Be 'C:\Tools\data\vdf'
            $out.HddMaxDegreeOfParallelism | Should -Be 1
            $out.Includes | Should -Be @('D:\Media\archive')
        }
        It 'sets the phase 1 size filter and keeps images on' {
            $out.FilterByFileSize | Should -BeTrue
            $out.MaximumFileSize | Should -Be 50
            $out.MinimumFileSize | Should -Be 0
            $out.IncludeImages | Should -BeTrue
        }
        It 'leaves AI and tombstone settings unchanged' {
            foreach ($k in 'UseAiMatching', 'EnableAiPartialDetection', 'EnablePartialClipDetection', 'RememberDeletedContent') {
                $out[$k] | Should -Be $in[$k] -Because $k
                $out[$k] | Should -BeTrue -Because $k
            }
        }
        It 'keeps the key count' {
            $out.Count | Should -Be $in.Count
        }
        It 'round-trips nested CustomCommands' {
            ($out.CustomCommands | ConvertTo-Json -Compress) | Should -Be ($in.CustomCommands | ConvertTo-Json -Compress)
        }
    }

    It 'does not add quarantine twice when the input already has it' {
        $json = '{"Blacklists":["D:\\Media\\quarantine"],"Includes":[],"FilePathContainsTexts":[]}'
        $out = ConvertTo-VdfSettings -InputJson $json -DataFolder 'C:\Tools\data\vdf' | ConvertFrom-Json -AsHashtable
        @($out.Blacklists | Where-Object { $_ -eq 'D:\Media\quarantine' }).Count | Should -Be 1
    }
}

Describe 'Merge-VdfBlacklistedGroups' -Skip:(-not $IsPs7) {
    It 'unions groups, matching path sets case-insensitively in any order' {
        $a = '{"version":1,"groups":[["C:\\a\\1.mp4","C:\\a\\2.mp4"],["C:\\b\\1.mp4","C:\\b\\2.mp4"]]}'
        $b = '{"version":1,"groups":[["c:\\A\\2.MP4","C:\\a\\1.mp4"],["C:\\c\\1.mp4","C:\\c\\2.mp4"]]}'
        $out = Merge-VdfBlacklistedGroups -JsonA $a -JsonB $b | ConvertFrom-Json -AsHashtable
        $out.version | Should -Be 1
        $out.groups.Count | Should -Be 3
    }

    It 'keeps at least as many groups as the larger real file' -Skip:(-not $HasRealFiles) {
        $a = Get-Content "$BackupDir\BlacklistedGroups.json" -Raw
        $b = Get-Content "$NewestDir\BlacklistedGroups.json" -Raw
        $countA = ($a | ConvertFrom-Json -AsHashtable).groups.Count
        $countB = ($b | ConvertFrom-Json -AsHashtable).groups.Count
        $out = Merge-VdfBlacklistedGroups -JsonA $a -JsonB $b | ConvertFrom-Json -AsHashtable
        $out.groups.Count | Should -BeGreaterOrEqual ([Math]::Max($countA, $countB))
    }
}

Describe 'Initialize-VdfData' -Skip:(-not $IsPs7) {
    BeforeAll {
        $binWanted = 'avcodec-62.dll', 'avdevice-62.dll', 'avformat-62.dll', 'avutil-60.dll', 'avfilter-11.dll',
        'swscale-9.dll', 'swresample-6.dll', 'ffmpeg.exe', 'ffprobe.exe', 'ffplay.exe'

        function New-FakeSources([string]$Root) {
            $backup = New-Item -ItemType Directory "$Root\backup" -Force
            $newest = New-Item -ItemType Directory "$Root\newest" -Force
            foreach ($n in 'ScannedFiles.db', 'ScannedFiles.fpheal1', 'UnionEmbeddings.db', 'DenseEmbeddings.db') {
                Set-Content "$backup\$n" "backup $n" -NoNewline
                Set-Content "$newest\$n" "newest $n" -NoNewline
            }
            Set-Content "$backup\BlacklistedGroups.json" '{"version":1,"groups":[["C:/a/1.mp4","C:/a/2.mp4"]]}' -NoNewline
            Set-Content "$newest\BlacklistedGroups.json" '{"version":1,"groups":[["C:/b/1.mp4","C:/b/2.mp4"]]}' -NoNewline
            Set-Content "$newest\Settings.json" '{"Blacklists":[],"Includes":[],"FilePathContainsTexts":[],"CustomDatabaseFolder":""}' -NoNewline
            New-Item -ItemType Directory "$newest\ai", "$newest\bin" -Force | Out-Null
            Set-Content "$newest\ai\dinov2-small-int8.onnx" 'model' -NoNewline
            Set-Content "$newest\ai\runtime.version" '1.23.2' -NoNewline
            foreach ($n in $binWanted + 'avcodec-63.dll', 'avutil-61.dll') { Set-Content "$newest\bin\$n" "bin $n" -NoNewline }
            @{ Backup = $backup.FullName; Newest = $newest.FullName }
        }

        function Get-TreeState([string]$Dir) {
            Get-ChildItem $Dir -Recurse -File | Sort-Object FullName | ForEach-Object {
                '{0}|{1}|{2}' -f $_.FullName, $_.LastWriteTimeUtc.Ticks, (Get-FileHash $_.FullName).Hash
            }
        }
    }

    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid())
        $src = New-FakeSources $root
        $params = @{
            BackupDir  = $src.Backup
            NewestDir  = $src.Newest
            DataFolder = "$root\data\vdf"
            PersistDir = "$root\persist\vdf"
        }
        Mock Get-Process -ModuleName VdfTools { }
    }

    It 'copies every file to the right place with equal hashes' {
        Initialize-VdfData @params
        $pairs = @(
            @("$($src.Backup)\ScannedFiles.db", "$($params.DataFolder)\ScannedFiles.db"),
            @("$($src.Backup)\ScannedFiles.fpheal1", "$($params.DataFolder)\ScannedFiles.fpheal1"),
            @("$($src.Backup)\UnionEmbeddings.db", "$($params.DataFolder)\UnionEmbeddings.db"),
            @("$($src.Newest)\DenseEmbeddings.db", "$($params.DataFolder)\DenseEmbeddings.db"),
            @("$($src.Newest)\ai\dinov2-small-int8.onnx", "$($params.PersistDir)\ai\dinov2-small-int8.onnx"),
            @("$($src.Newest)\ai\runtime.version", "$($params.PersistDir)\ai\runtime.version")
        )
        foreach ($p in $pairs) {
            (Get-FileHash $p[1]).Hash | Should -Be (Get-FileHash $p[0]).Hash -Because $p[1]
        }
        $groups = (Get-Content "$($params.DataFolder)\BlacklistedGroups.json" -Raw | ConvertFrom-Json -AsHashtable).groups
        $groups.Count | Should -Be 2
        $settings = Get-Content "$($params.PersistDir)\Settings.json" -Raw | ConvertFrom-Json -AsHashtable
        $settings.CustomDatabaseFolder | Should -Be $params.DataFolder
    }

    It 'writes Settings.json as UTF-8 without BOM' {
        Initialize-VdfData @params
        $bytes = [IO.File]::ReadAllBytes("$($params.PersistDir)\Settings.json")
        $bytes[0] | Should -Be ([byte][char]'{')
    }

    It 'copies only the FFmpeg 8.x set into bin' {
        Initialize-VdfData @params
        $names = (Get-ChildItem "$($params.PersistDir)\bin").Name | Sort-Object
        $names | Should -Be ($binWanted | Sort-Object)
        foreach ($n in $binWanted) {
            (Get-FileHash "$($params.PersistDir)\bin\$n").Hash | Should -Be (Get-FileHash "$($src.Newest)\bin\$n").Hash
        }
    }

    It 'throws on a non-empty target and leaves it unchanged' {
        New-Item -ItemType Directory $params.DataFolder -Force | Out-Null
        Set-Content "$($params.DataFolder)\keep.txt" 'mine'
        $before = Get-TreeState (Split-Path $params.DataFolder)
        { Initialize-VdfData @params } | Should -Throw '*not empty*'
        Get-TreeState (Split-Path $params.DataFolder) | Should -Be $before
        Test-Path $params.PersistDir | Should -BeFalse
    }

    It 'throws on a non-empty persist folder' {
        New-Item -ItemType Directory $params.PersistDir -Force | Out-Null
        Set-Content "$($params.PersistDir)\Settings.json" '{}'
        { Initialize-VdfData @params } | Should -Throw '*not empty*'
        Test-Path $params.DataFolder | Should -BeFalse
    }

    It 'throws while VDF is running and creates nothing' {
        Mock Get-Process -ModuleName VdfTools { [pscustomobject]@{ Name = 'VDF.GUI' } }
        { Initialize-VdfData @params } | Should -Throw '*running*'
        Test-Path $params.DataFolder | Should -BeFalse
        Test-Path $params.PersistDir | Should -BeFalse
    }

    It 'leaves source timestamps and hashes unchanged' {
        $before = Get-TreeState $root
        Initialize-VdfData @params
        $after = Get-TreeState $root | Where-Object { $_ -like "$($src.Backup)*" -or $_ -like "$($src.Newest)*" }
        $after | Should -Be $before
    }

    It 'creates nothing with -WhatIf' {
        Initialize-VdfData @params -WhatIf
        Test-Path $params.DataFolder | Should -BeFalse
        Test-Path $params.PersistDir | Should -BeFalse
    }

    It 'takes no D: path (Review Focus 1)' {
        $params.Values | Where-Object { $_ -match '^D:' } | Should -BeNullOrEmpty
        Initialize-VdfData @params
        Should -Invoke Get-Process -ModuleName VdfTools -Times 1
    }
}

Describe 'Save-VdfSnapshot' -Skip:(-not $IsPs7) {
    BeforeAll {
        function Get-Hashes([string]$Dir) {
            Get-ChildItem $Dir -File | Where-Object Name -ne 'manifest.json' | Sort-Object Name |
                ForEach-Object { '{0}|{1}' -f $_.Name, (Get-FileHash $_.FullName).Hash }
        }
        function Get-Snapshots([string]$Root) {
            @(Get-ChildItem $Root -Directory -ErrorAction SilentlyContinue | Sort-Object Name)
        }
    }

    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid())
        $data = New-Item -ItemType Directory "$root\data" -Force
        $snaps = "$root\snapshots"
        Set-Content "$data\ScannedFiles.db" 'db v1'
        Set-Content "$data\UnionEmbeddings.db" 'union'
        Set-Content "$data\BlacklistedGroups.json" '{}'
        Mock Get-Process -ModuleName VdfTools { }
    }

    It 'creates a snapshot with an identical file set and hashes' {
        $path = Save-VdfSnapshot -DataFolder $data -SnapshotRoot $snaps
        $path | Should -Exist
        Split-Path $path -Leaf | Should -Match '^\d{8}-\d{6}$'
        Get-Hashes $path | Should -Be (Get-Hashes $data)
        "$path\manifest.json" | Should -Exist
    }

    It 'returns $null and copies nothing when nothing changed' {
        Save-VdfSnapshot -DataFolder $data -SnapshotRoot $snaps | Out-Null
        Save-VdfSnapshot -DataFolder $data -SnapshotRoot $snaps | Should -BeNullOrEmpty
        (Get-Snapshots $snaps).Count | Should -Be 1
    }

    It 'makes a new snapshot after a change and keeps exactly 2' {
        Save-VdfSnapshot -DataFolder $data -SnapshotRoot $snaps | Out-Null
        Set-Content "$data\ScannedFiles.db" 'db v2'
        Save-VdfSnapshot -DataFolder $data -SnapshotRoot $snaps | Should -Not -BeNullOrEmpty
        Set-Content "$data\ScannedFiles.db" 'db v3 longer'
        $last = Save-VdfSnapshot -DataFolder $data -SnapshotRoot $snaps
        $all = Get-Snapshots $snaps
        $all.Count | Should -Be 2
        $all[-1].FullName | Should -Be $last
        Get-Content "$last\ScannedFiles.db" | Should -Be 'db v3 longer'
    }

    It 'refuses while VDF is running and creates nothing (Review Focus 4)' {
        Mock Get-Process -ModuleName VdfTools { [pscustomobject]@{ Name = 'VDF.GUI' } }
        { Save-VdfSnapshot -DataFolder $data -SnapshotRoot $snaps } | Should -Throw '*running*'
        Test-Path $snaps | Should -BeFalse
    }

    It 'removes the partial folder, keeps older snapshots and throws when a copy fails (Review Focus 5)' {
        $first = Save-VdfSnapshot -DataFolder $data -SnapshotRoot $snaps
        Set-Content "$data\ScannedFiles.db" 'db v2'
        $global:VdfCopyCount = 0
        Mock Copy-Item -ModuleName VdfTools {
            $global:VdfCopyCount++
            if ($global:VdfCopyCount -gt 1) { throw 'There is not enough space on the disk.' }
            Microsoft.PowerShell.Management\Copy-Item @PesterBoundParameters
        }
        { Save-VdfSnapshot -DataFolder $data -SnapshotRoot $snaps } | Should -Throw '*not enough space*'
        $all = Get-Snapshots $snaps
        $all.Count | Should -Be 1
        $all[0].FullName | Should -Be $first
        Get-Hashes $first | Should -Not -BeNullOrEmpty
        @(Get-ChildItem $snaps -Filter '*.partial').Count | Should -Be 0
    }
}

Describe 'Invoke-VdfRollback' -Skip:(-not $IsPs7) {
    It 'never resets when the snapshot throws' {
        Mock Save-VdfSnapshot -ModuleName VdfTools { throw 'VDF is running' }
        Mock Invoke-Scoop -ModuleName VdfTools { }
        { Invoke-VdfRollback -Version '4.1.20261009.1645' } | Should -Throw '*running*'
        Should -Invoke Invoke-Scoop -ModuleName VdfTools -Times 0
    }

    It 'snapshots, then resets to the named version' {
        Mock Save-VdfSnapshot -ModuleName VdfTools { 'C:\snap' }
        Mock Invoke-Scoop -ModuleName VdfTools { }
        Invoke-VdfRollback -Version '4.1.20261009.1645'
        Should -Invoke Save-VdfSnapshot -ModuleName VdfTools -Times 1
        Should -Invoke Invoke-Scoop -ModuleName VdfTools -Times 1 -ParameterFilter {
            ($ScoopArgs -join ' ') -eq 'reset vdf@4.1.20261009.1645'
        }
    }
}

Describe 'Register-VdfSnapshotTask' -Skip:(-not $IsPs7) {
    It 'registers a daily per-user task named VDF data snapshot running the nightly script' {
        Mock Register-ScheduledTask -ModuleName VdfTools { }
        Register-VdfSnapshotTask -At '04:30'
        Should -Invoke Register-ScheduledTask -ModuleName VdfTools -Times 1 -ParameterFilter {
            $TaskName -eq 'VDF data snapshot' -and $Action.Arguments -like '*vdf-nightly.ps1*' -and
            ([datetime]$Trigger.StartBoundary).ToString('HH:mm') -eq '04:30'
        }
    }
}
