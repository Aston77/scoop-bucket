BeforeDiscovery {
    $script:IsPs7 = $PSVersionTable.PSVersion.Major -ge 7
}

BeforeAll {
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        Import-Module "$PSScriptRoot\..\tools\CloudCompareTools.psm1" -Force
    }
    function New-FakeBuild([string]$Dir, [string]$Marker) {
        New-Item -ItemType Directory "$Dir\plugins" -Force | Out-Null
        Set-Content "$Dir\CloudCompare.exe" $Marker
        Set-Content "$Dir\plugins\QCORE_IO_PLUGIN.dll" 'plugin'
        $Dir
    }
}

Describe 'Install-CloudCompareVersion' -Skip:(-not $IsPs7) {
    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid())
        $src = New-FakeBuild (Join-Path $TestDrive "src-$([guid]::NewGuid())") 'build A'
    }

    It 'copies a folder build into Root\Version and returns that path' {
        $path = Install-CloudCompareVersion -Source $src -Version 'v2.14.beta-2026-09-26' -Root $root
        $path | Should -Be (Join-Path $root 'v2.14.beta-2026-09-26')
        Get-Content "$path\CloudCompare.exe" | Should -Be 'build A'
        "$path\plugins\QCORE_IO_PLUGIN.dll" | Should -Exist
    }

    It 'throws when the version folder already exists' {
        Install-CloudCompareVersion -Source $src -Version 'v1' -Root $root | Out-Null
        { Install-CloudCompareVersion -Source $src -Version 'v1' -Root $root } | Should -Throw '*exists*'
    }

    It 'extracts a zip whose files sit in one top folder' {
        $zipSrc = Join-Path $TestDrive "zip-$([guid]::NewGuid())"
        New-FakeBuild "$zipSrc\CloudCompare_v2.14.beta3_bin_x64" 'build Z' | Out-Null
        $zip = "$zipSrc.zip"
        Compress-Archive -Path "$zipSrc\*" -DestinationPath $zip
        $path = Install-CloudCompareVersion -Source $zip -Version 'v2.14.beta3' -Root $root
        Get-Content "$path\CloudCompare.exe" | Should -Be 'build Z'
    }
}

Describe 'Set-CloudCompareCurrent' -Skip:(-not $IsPs7) {
    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid())
        New-FakeBuild "$root\v1" 'one' | Out-Null
        New-FakeBuild "$root\v2" 'two' | Out-Null
    }

    It 'points the current junction at the version folder' {
        Set-CloudCompareCurrent -Root $root -Version 'v1'
        $item = Get-Item "$root\current"
        $item.LinkType | Should -Be 'Junction'
        $item.Target | Should -Be "$root\v1"
    }

    It 're-points an existing junction and keeps both version folders' {
        Set-CloudCompareCurrent -Root $root -Version 'v1'
        Set-CloudCompareCurrent -Root $root -Version 'v2'
        (Get-Item "$root\current").Target | Should -Be "$root\v2"
        Get-Content "$root\v1\CloudCompare.exe" | Should -Be 'one'
        Get-Content "$root\current\CloudCompare.exe" | Should -Be 'two'
    }

    It 'refuses a missing version' {
        { Set-CloudCompareCurrent -Root $root -Version 'v9' } | Should -Throw '*not found*'
    }
}

Describe 'Update-CloudCompare' -Skip:(-not $IsPs7) {
    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid())
        New-FakeBuild "$root\v1" 'one' | Out-Null
        Set-CloudCompareCurrent -Root $root -Version 'v1'
        $src = New-FakeBuild (Join-Path $TestDrive "src-$([guid]::NewGuid())") 'two'
    }

    It 'leaves current unchanged when the smoke test fails' {
        Mock Test-CloudCompareSmoke -ModuleName CloudCompareTools { $false }
        { Update-CloudCompare -Source $src -Version 'v2' -Root $root } | Should -Throw '*smoke*'
        (Get-Item "$root\current").Target | Should -Be "$root\v1"
    }

    It 'flips current when the smoke test passes' {
        Mock Test-CloudCompareSmoke -ModuleName CloudCompareTools { $true }
        Update-CloudCompare -Source $src -Version 'v2' -Root $root
        (Get-Item "$root\current").Target | Should -Be "$root\v2"
        Should -Invoke Test-CloudCompareSmoke -ModuleName CloudCompareTools -Times 1 -ParameterFilter {
            $Exe -eq "$root\v2\CloudCompare.exe"
        }
    }
}
