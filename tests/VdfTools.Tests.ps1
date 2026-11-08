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
