#Requires -Version 7.5
# Manual CloudCompare updates: one folder per version under C:\Tools\CloudCompare plus a `current` junction.
# Design: docs\SETUP.md, "CloudCompare: manual update method".

Set-StrictMode -Version 3.0

function Install-CloudCompareVersion {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Version,
        [string]$Root = 'C:\Tools\CloudCompare'
    )
    $target = Join-Path $Root $Version
    if (Test-Path -LiteralPath $target) { throw "Version folder already exists: $target" }

    if (Test-Path -LiteralPath $Source -PathType Container) {
        New-Item -ItemType Directory -Force $target | Out-Null
        Copy-Item -Path (Join-Path $Source '*') -Destination $target -Recurse -ErrorAction Stop
        return $target
    }
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) { throw "Source not found: $Source" }

    $staging = Join-Path $Root "$Version.extracting"
    if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
    try {
        New-Item -ItemType Directory -Force $staging | Out-Null
        if ($Source -match '\.zip$') {
            Expand-Archive -LiteralPath $Source -DestinationPath $staging
        } else {
            $sevenZip = Get-Command 7z -ErrorAction SilentlyContinue
            if (-not $sevenZip) { throw '7z not found (scoop install 7zip)' }
            & $sevenZip.Source x "-o$staging" -y -- $Source | Out-Null
            if ($LASTEXITCODE) { throw "7z failed with exit code $LASTEXITCODE on $Source" }
        }
        $content = $staging
        $top = @(Get-ChildItem -LiteralPath $staging -Force)
        if ($top.Count -eq 1 -and $top[0].PSIsContainer) { $content = $top[0].FullName }
        if (-not (Test-Path -LiteralPath (Join-Path $content 'CloudCompare.exe'))) {
            throw "CloudCompare.exe not found in $Source"
        }
        Move-Item -LiteralPath $content -Destination $target
    } finally {
        if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
    }
    $target
}

function Set-CloudCompareCurrent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Version
    )
    $target = Join-Path $Root $Version
    if (-not (Test-Path -LiteralPath (Join-Path $target 'CloudCompare.exe'))) {
        throw "Version not found (no CloudCompare.exe): $target"
    }
    $current = Join-Path $Root 'current'
    $item = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
    if ($item) {
        if ($item.LinkType -ne 'Junction') { throw "$current exists and is not a junction; not touching it" }
        # Deletes the junction only, never the folder it points at.
        [IO.Directory]::Delete($current, $false)
    }
    New-Item -ItemType Junction -Path $current -Target $target | Out-Null
}

function Write-SmokeFixtures([string]$Dir) {
    # A 32 x 32 wavy grid (1,024 vertices), as an ASCII PLY mesh and an OBJ.
    $n = 32
    $verts = foreach ($j in 0..($n - 1)) {
        foreach ($i in 0..($n - 1)) {
            $z = 5 * [Math]::Sin($i / 4.0) * [Math]::Cos($j / 5.0)
            '{0} {1} {2:F4}' -f $i, $j, $z
        }
    }
    $faces = foreach ($j in 0..($n - 2)) {
        foreach ($i in 0..($n - 2)) {
            $a = $j * $n + $i; $b = $a + 1; $c = $a + $n; $d = $c + 1
            , @($a, $b, $d); , @($a, $d, $c)
        }
    }
    $ply = @('ply', 'format ascii 1.0', "element vertex $($n * $n)", 'property float x', 'property float y',
        'property float z', "element face $($faces.Count)", 'property list uchar int vertex_indices', 'end_header') +
    $verts + ($faces | ForEach-Object { "3 $($_ -join ' ')" })
    Set-Content -LiteralPath (Join-Path $Dir 'smoke.ply') $ply
    $obj = ($verts | ForEach-Object { "v $_" }) + ($faces | ForEach-Object { 'f ' + (($_ | ForEach-Object { $_ + 1 }) -join ' ') })
    Set-Content -LiteralPath (Join-Path $Dir 'smoke.obj') $obj
    Set-Content -LiteralPath (Join-Path $Dir 'shift.txt') @('1 0 0 0.8', '0 1 0 0.5', '0 0 1 0.3', '0 0 0 1')
}

function Invoke-CloudCompare([string]$Exe, [string[]]$CcArgs, [string]$WorkDir) {
    # Start-Process joins arguments with spaces and adds no quotes, so encode each one for the Windows command line.
    # A FILE name with a space must also carry its own quotes (see the space check below).
    $quoted = (@('-SILENT', '-AUTO_SAVE', 'OFF') + $CcArgs) |
        ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }
    $p = Start-Process -FilePath $Exe -ArgumentList $quoted `
        -WorkingDirectory $WorkDir -Wait -PassThru -WindowStyle Hidden
    $p.ExitCode
}

function Test-CloudCompareSmoke {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$Exe)
    $dir = Join-Path $env:TEMP "cc-smoke-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
    New-Item -ItemType Directory -Force $dir, "$dir\with space" | Out-Null
    Write-SmokeFixtures $dir

    $checks = [ordered]@{
        'open PLY as mesh, binary PLY save' = @{
            Args = @('-O', "$dir\smoke.ply", '-M_EXPORT_FMT', 'PLY', '-PLY_EXPORT_FMT', 'BINARY_LE', '-SAVE_MESHES', 'FILE', "$dir\ply_bin.ply")
            Out  = "$dir\ply_bin.ply"
        }
        'open OBJ as mesh'                  = @{
            Args = @('-O', "$dir\smoke.obj", '-M_EXPORT_FMT', 'PLY', '-PLY_EXPORT_FMT', 'BINARY_LE', '-SAVE_MESHES', 'FILE', "$dir\obj.ply")
            Out  = "$dir\obj.ply"
        }
        '-EXTRACT_VERTICES'                 = @{
            Args = @('-O', "$dir\smoke.ply", '-EXTRACT_VERTICES', '-C_EXPORT_FMT', 'BIN', '-SAVE_CLOUDS', 'FILE', "$dir\cloud_a.bin")
            Out  = "$dir\cloud_a.bin"
        }
        '-APPLY_TRANS'                      = @{
            Args = @('-O', "$dir\cloud_a.bin", '-APPLY_TRANS', "$dir\shift.txt", '-C_EXPORT_FMT', 'BIN', '-SAVE_CLOUDS', 'FILE', "$dir\cloud_b.bin")
            Out  = "$dir\cloud_b.bin"
        }
        'save to a path with a space'       = @{
            Args = @('-O', "$dir\smoke.ply", '-M_EXPORT_FMT', 'PLY', '-PLY_EXPORT_FMT', 'BINARY_LE', '-SAVE_MESHES', 'FILE', "`"$dir\with space\out mesh.ply`"")
            Out  = "$dir\with space\out mesh.ply"
        }
        'ICP on two .bin clouds'            = @{
            Args = @('-O', "$dir\cloud_b.bin", '-O', "$dir\cloud_a.bin", '-ICP', '-C_EXPORT_FMT', 'BIN', '-SAVE_CLOUDS', 'FILE', "$dir\icp_moved.bin $dir\icp_ref.bin")
            Out  = "$dir\icp_moved.bin"
        }
    }

    $ok = $true
    foreach ($name in $checks.Keys) {
        $c = $checks[$name]
        $code = Invoke-CloudCompare -Exe $Exe -CcArgs $c.Args -WorkDir $dir
        $pass = (Test-Path -LiteralPath $c.Out) -and (Get-Item -LiteralPath $c.Out).Length -gt 0
        $label = if ($pass) { 'PASS' } else { 'FAIL' }
        Write-Host ('{0} {1} (exit {2})' -f $label, $name, $code)
        if (-not $pass) { $ok = $false }
    }
    if ($ok) { Remove-Item -LiteralPath $dir -Recurse -Force } else { Write-Host "Smoke outputs kept in $dir" }
    $ok
}

function Update-CloudCompare {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Version,
        [string]$Root = 'C:\Tools\CloudCompare'
    )
    $path = Install-CloudCompareVersion -Source $Source -Version $Version -Root $Root
    if (-not (Test-CloudCompareSmoke -Exe (Join-Path $path 'CloudCompare.exe'))) {
        throw "CloudCompare $Version failed the smoke tests; current not changed. The new folder stays at $path for a look."
    }
    Set-CloudCompareCurrent -Root $Root -Version $Version
    Write-Host "current -> $path"
}

Export-ModuleMember -Function Install-CloudCompareVersion, Set-CloudCompareCurrent, Test-CloudCompareSmoke, Update-CloudCompare
