# Portable Tools (Scoop bucket, VDF data, CloudCompare) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move VDF, LosslessCut and CloudCompare out of Downloads into updateable installs. VDF data lives in
one place, survives updates, and can roll back.

**Architecture:**
- A public Scoop bucket repo `Aston77/scoop-bucket`, cloned to `C:\Tools\scoop-bucket`, holds:
  - the `vdf` manifest (GUI + CLI in one app);
  - a PowerShell module `tools\VdfTools.psm1` (settings transform, data seeding, snapshots, guards);
  - `tools\CloudCompareTools.psm1` (manual-update helper);
  - Pester 5 tests.
- Scoop lives in `C:\Tools\scoop` and UniGetUI drives updates. VDF data sits outside Scoop in `C:\Tools\data\vdf`.

**Tech Stack:** PowerShell 7.6, Pester 5, Scoop, GitHub Actions (ScoopInstaller/BucketTemplate Excavator), `gh`, git.

**Spec:** `C:\Tools\SETUP.md` (approved 2026-11-07). Read it in full first. The facts and reasons behind every
value here are there.

## Global Constraints

- **Downloads is read-only.** Never modify, move or delete anything in `C:\Users\User\Downloads\GUI-win-x64`,
  `GUI-win-x64_Backup`, `GUI-win-x64 - Copy`, `LosslessCut-win-x64` or `CloudCompare_v2.14.beta_bin_x64`
  until Task 11, which needs the owner's explicit go-ahead.
- **Paths:**
  - Scoop root `C:\Tools\scoop`
  - VDF data `C:\Tools\data\vdf`
  - snapshots `C:\Tools\data\vdf-snapshots\<yyyyMMdd-HHmmss>\`, keep 2
  - VDF persist `C:\Tools\scoop\persist\vdf\{Settings.json, ai\, bin\}`
- **Never run `vdf-cli db clean`.** Cleanup is done only through the GUI (the spec explains why).
- **The CLI always gets `--db C:\Tools\data\vdf`.** Without it, VDF starts an empty database in the app folder.
- **VDF must not be running** during install, update, snapshot, rollback or seeding. Check with
  `Get-Process VDF.GUI,vdf-cli`.
- **UniGetUI Scoop cleanup options stay off:** `EnableScoopCleanupApps`, `EnableScoopCleanup`.
- **No admin.** Everything is per-user. System Python is absent; use `uv` if Python is ever needed.
- **context-mode plugin limits:** Read files over 16 KB with offset/limit. Keep shell output under ~4 KB.
- **Commits** in `C:\Tools\scoop-bucket` and `C:\Scans` end with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never save or close Fusion documents (unrelated,
  but a standing rule).

## Review Focus

1. **D: asleep or unplugged** during a snapshot, the seeding or a check. Expected: nothing touches D:, nothing is
   deleted, and checks that need D: say so. (Task 3: the seeding test runs with no D: paths. Task 5:
   `Save-VdfSnapshot` reads C: only.)
2. **VDF started with the data folder missing.** Expected: a loud failure, never a silent empty database.
   (Task 6: `Test-VdfDataFolder` test with the folder renamed away. Task 7: the guard is part of the launch check.)
3. **The daily asset is replaced between the check and the install,** so the hash mismatches. Expected: the
   install aborts before the old version is uninstalled, and `current` still points at the old version.
   (Task 4 verification step.)
4. **An update, snapshot or rollback while VDF is running.** Expected: refused, with no partial changes.
   (Task 5: `Save-VdfSnapshot` refuse test. Task 7: `scoop update vdf` with the GUI open.)
5. **C: runs out of space mid-snapshot.** Expected: the partial snapshot folder is removed, older snapshots are
   untouched, and the command exits non-zero. (Task 5: a test with a copy that throws partway.)

---

## File Structure (repo `C:\Tools\scoop-bucket`)

| Path | Responsibility |
|---|---|
| `bucket\vdf.json` | Scoop manifest: VDF daily build, GUI + CLI zips, persist, checkver/autoupdate |
| `tools\VdfTools.psm1` | All VDF helper functions (signatures below) |
| `tools\vdfdb.ps1` | CLI wrapper: runs `vdf-cli` with the user's args plus `--db C:\Tools\data\vdf` |
| `tools\Initialize-VdfData.ps1` | One-time seeding from Downloads (calls the module) |
| `tools\CloudCompareTools.psm1` | `Install-CloudCompareVersion`, `Test-CloudCompareSmoke` |
| `tools\Update-CloudCompare.ps1` | Owner-facing wrapper: `Update-CloudCompare.ps1 <archive>` |
| `tests\VdfTools.Tests.ps1`, `tests\CloudCompareTools.Tests.ps1` | Pester 5 tests |
| `docs\SETUP.md`, `docs\plans\2026-11-07-portable-tools.md` | Copies of the spec and this plan |

---

### Task 1: Bootstrap: Pester 5, Scoop, bucket repo

**Files:** Create the repo `Aston77/scoop-bucket` (public, from template `ScoopInstaller/BucketTemplate`);
`docs\SETUP.md`, `docs\plans\…` (copies).

- [ ] **Step 1:** `Install-Module Pester -MinimumVersion 5.6 -Scope CurrentUser -Force -SkipPublisherCheck`.
  Verify that `(Get-Module -ListAvailable Pester | Sort Version -desc)[0].Version` is ≥ 5.6.
- [ ] **Step 2:** Set user env `SCOOP=C:\Tools\scoop`, then install Scoop per-user with the official installer
  (`irm get.scoop.sh | iex` in a pwsh where `$env:SCOOP` is set). Verify that `scoop --version` prints a version
  and that `C:\Tools\scoop\apps\scoop\current` exists. `scoop install git` only if Scoop asks for it (git 2.56 is
  already on PATH).
- [ ] **Step 3:** `gh repo create Aston77/scoop-bucket --public --template ScoopInstaller/BucketTemplate --clone`
  run from `C:\Tools` (clones to `C:\Tools\scoop-bucket`). Verify that the repo exists and Actions are enabled:
  `gh api repos/Aston77/scoop-bucket/actions/permissions --jq .enabled` → `true`.
- [ ] **Step 4:** Edit README (bucket name, one-line purpose, `scoop bucket add aston77 https://github.com/Aston77/scoop-bucket`).
  Copy `C:\Tools\SETUP.md` and this plan into `docs\`. Run the template tests: `.\bin\test.ps1` → all pass.
- [ ] **Step 5:** Commit "Bucket from template; spec and plan" and push.

### Task 2: Settings transform and blacklist merge (pure functions)

**Files:** Create `tools\VdfTools.psm1`, `tests\VdfTools.Tests.ps1`.

**Interfaces (Produces):**
- `ConvertTo-VdfSettings -InputJson <string> -DataFolder <string> -> [string]` (JSON text). All other keys are
  kept unchanged.
- `Merge-VdfBlacklistedGroups -JsonA <string> -JsonB <string> -> [string]`. Format
  `{"version":1,"groups":[[path,...],...]}`. Output is the union of groups; a group counts as a duplicate when
  its path set matches case-insensitively, order ignored.

- [ ] **Step 1: Write failing tests.** Fixture: the real `C:\Users\User\Downloads\GUI-win-x64\Settings.json`
  (read-only) and small inline JSON.
  - `ConvertTo-VdfSettings` output parsed:
    - `FilePathContainsTexts` equals `@('*.gif','*.mp4','*.mov')`
    - `FilterByFilePathContains` is `$true`
    - `Blacklists` contains `D:\Media\quarantine` exactly once (also when the input already has it)
    - `CustomDatabaseFolder` is `C:\Tools\data\vdf`
    - `HddMaxDegreeOfParallelism` is `1`
    - `Includes` equals `@('D:\Media\archive')`
    - `FilterByFileSize` is `$true`, `MaximumFileSize` is `50`, `MinimumFileSize` is `0`
    - `IncludeImages` is `$true`
    - `UseAiMatching`, `EnableAiPartialDetection` and `EnablePartialClipDetection` are unchanged (`$true`)
    - `RememberDeletedContent` is unchanged (`$true`)
    - the key count equals the input's key count
    - nested `CustomCommands` round-trips
  - `Merge-VdfBlacklistedGroups`:
    - A has 2 groups and B has 2, one of them shared with its paths in a different order and case → 3 groups,
      `version` 1
    - on the real Backup and newest files, the result count ≥ max(countA, countB)
- [ ] **Step 2:** `Invoke-Pester tests\VdfTools.Tests.ps1` → FAIL (functions not defined).
- [ ] **Step 3: Implement both functions.** Use `ConvertFrom-Json -AsHashtable` and
  `ConvertTo-Json -Depth 20 -Compress`, written as UTF-8 without BOM by the caller.
- [ ] **Step 4:** Run the tests → PASS.
- [ ] **Step 5:** Commit "VdfTools: settings transform and blacklist merge".

### Task 3: One-time data seeding

**Files:** Modify `tools\VdfTools.psm1`; create `tools\Initialize-VdfData.ps1`; test in `tests\VdfTools.Tests.ps1`.

**Interfaces:**
- Consumes `ConvertTo-VdfSettings` and `Merge-VdfBlacklistedGroups`.
- Produces `Initialize-VdfData -BackupDir <string> -NewestDir <string> -DataFolder <string> -PersistDir <string> [-WhatIf]`.
  It copies:
  - **to DataFolder:** from BackupDir `ScannedFiles.db`, `ScannedFiles.fpheal1`, `UnionEmbeddings.db`; from
    NewestDir `DenseEmbeddings.db`; the merged `BlacklistedGroups.json`.
  - **to PersistDir:** `Settings.json` (transformed from NewestDir); `ai\` (all files from NewestDir\ai);
    `bin\` only `avcodec-62.dll`, `avdevice-62.dll`, `avformat-62.dll`, `avutil-60.dll`, `avfilter-11.dll`,
    `swscale-9.dll`, `swresample-6.dll`, `ffmpeg.exe`, `ffprobe.exe`, `ffplay.exe` from NewestDir\bin.
  - It throws if DataFolder or PersistDir is non-empty, or if VDF is running. It verifies each copy by SHA256
    against its source, and never writes to the source folders.

- [ ] **Step 1: Write failing tests** with fake source trees in `$TestDrive`:
  - all listed files land in the right places, hashes equal;
  - `bin` contains exactly those 10 files (fake `avcodec-63.dll`, `avutil-61.dll` are present in the source and
    absent in the target);
  - a non-empty target throws and leaves the target unchanged;
  - source file timestamps and hashes are unchanged afterwards;
  - no path under `D:\` is touched (Review Focus 1: the function takes no D: input; assert that the parameters
    used contain no `D:`).
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement. `Initialize-VdfData.ps1` calls it with:
  - BackupDir `C:\Users\User\Downloads\GUI-win-x64_Backup`
  - NewestDir `C:\Users\User\Downloads\GUI-win-x64`
  - DataFolder `C:\Tools\data\vdf`
  - PersistDir `C:\Tools\scoop\persist\vdf`
- [ ] **Step 4:** Run tests → PASS.
- [ ] **Step 5:** Run `Initialize-VdfData.ps1` for real.
  - Verify that `C:\Tools\data\vdf\ScannedFiles.db` is 2,672,018,461 bytes, `UnionEmbeddings.db` is
    915,272,114, and `DenseEmbeddings.db` is 57,431,246.
  - Verify that `C:\Tools\scoop\persist\vdf\Settings.json` parses with `CustomDatabaseFolder` = `C:\Tools\data\vdf`.
- [ ] **Step 6:** Commit "VdfTools: seed data and persist from Downloads (copies only)".

### Task 4: `vdf` manifest

**Files:** Create `bucket\vdf.json`.

**Values:**
- `url`: `https://github.com/0x90d/videoduplicatefinder/releases/download/4.1.x/GUI-win-x64.zip` and
  `…/4.1.x/CLI-win-x64.zip`, with a hash array.
- `persist`: `["Settings.json","ai","bin"]`.
- `pre_install`: throw "Seed persist first (Initialize-VdfData.ps1)" if `$persist_dir\Settings.json` is not a
  file. This prevents Scoop creating a directory named `Settings.json`.
- `shortcuts`: `[["VDF.GUI.exe","Video Duplicate Finder"]]`.
- `bin`: `vdf-cli.exe`.
- **Version:** time-sortable, from the `GUI-win-x64.zip` asset `updated_at` in
  `https://api.github.com/repos/0x90d/videoduplicatefinder/releases/tags/4.1.x`, e.g. `4.1.20261009.1645`.
- **Autoupdate hash:** from the asset `digest` (Scoop's GitHub digest lookup).
- **Commit:** record the commit named in the release body (`Last build based on <sha>`) in `description` or
  `notes`. It is needed by `Test-VdfAiModel` (Task 6).

- [ ] **Step 1:** Write the manifest. Run `.\bin\checkver.ps1 vdf` → it prints the current version. Then run
  `.\bin\checkver.ps1 vdf -u` → the manifest is updated with the hashes, unchanged if already current.
- [ ] **Step 2:** `.\bin\test.ps1` → PASS. `.\bin\checkhashes.ps1 vdf` → hashes match.
- [ ] **Step 3:** Commit and push. Run the Excavator workflow (`gh workflow run excavator.yml`) → it completes
  green, with no change or a version-bump commit.
- [ ] **Step 4 (Review Focus 3):** In a scratch copy of the manifest, change one hash, then
  `scoop install <scratch manifest path>` into a scratch `SCOOP` root (`$env:SCOOP` set to a temp folder for
  that shell). Verify that the install aborts with a hash error and leaves no `current`. This also documents that
  a failed update keeps the old version (Scoop checks the hash before uninstalling).

### Task 5: Snapshots and rollback

**Files:** Modify `tools\VdfTools.psm1` and `tests\VdfTools.Tests.ps1`.

**Interfaces (Produces):**
- `Save-VdfSnapshot -DataFolder <string> -SnapshotRoot <string> [-Keep 2] -> [string]` (the snapshot path, or
  `$null` when skipped as unchanged).
  - Throws if VDF is running.
  - Writes to `<root>\<yyyyMMdd-HHmmss>.partial\` and renames when complete.
  - On any error it removes the `.partial` folder and rethrows.
  - "Unchanged" means the file names, sizes and LastWriteTimeUtc equal those recorded in the newest snapshot's
    `manifest.json`.
  - After success, deletes snapshots beyond Keep, oldest first.
- `Invoke-VdfRollback -Version <string>`: calls `Save-VdfSnapshot`, then `scoop reset vdf@<Version>`. If the
  snapshot throws, it does not reset.
- `Register-VdfSnapshotTask -At '04:30'`: a per-user scheduled task named `VDF data snapshot` that runs
  `Save-VdfSnapshot` daily. The task skips while VDF runs (the function throws; the task logs it).

- [ ] **Step 1: Write failing tests** in `$TestDrive`:
  - the first call creates a snapshot with an identical file set and hashes;
  - a second call with no change returns `$null`;
  - after touching a file, a third call creates a new one and leaves exactly 2;
  - a mocked `Get-Process` returning `VDF.GUI` throws and creates nothing (Review Focus 4);
  - a mocked copy that throws after the first file leaves no `.partial` folder, keeps the older snapshots, and the
    function throws (Review Focus 5);
  - `Invoke-VdfRollback` with a throwing `Save-VdfSnapshot` never calls `scoop` (mock `scoop`).
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement. Copy with `Copy-Item` per file. `manifest.json` lists `{name,size,lastWriteUtc}`.
- [ ] **Step 4:** Run → PASS.
- [ ] **Step 5:** `Register-VdfSnapshotTask`. Verify with `Get-ScheduledTask 'VDF data snapshot'` → Ready.
- [ ] **Step 6:** Commit "VdfTools: snapshots, rollback, nightly task".

### Task 6: Guards, AI model check, CLI wrapper

**Files:** Modify `tools\VdfTools.psm1` and `tests\VdfTools.Tests.ps1`; create `tools\vdfdb.ps1`.

**Interfaces (Produces):**
- `Test-VdfDataFolder -DataFolder <string> -> [bool]`: true only if the folder exists and contains a non-empty
  `ScannedFiles.db`. It writes a clear error otherwise.
- `Test-VdfAiModel -AiFolder <string> -Commit <string> [-Fix]`:
  - reads `ModelSha256` from `https://raw.githubusercontent.com/0x90d/videoduplicatefinder/<Commit>/VDF.Core/AI/AiComponents.cs`;
  - compares it with the SHA256 of `dinov2-small-int8.onnx`;
  - on mismatch, writes a warning and, with `-Fix`, deletes the model file;
  - returns `$true` when they match.
  - Known value at commit 4ab0e82: `3afdc8bc63b50558d6e5770f5b799bb82455c2311183a2de43803f343a29d917`.
- `tools\vdfdb.ps1`: runs `vdf-cli @args --db C:\Tools\data\vdf` (the option goes last, after the user's
  subcommand). It refuses if `Test-VdfDataFolder` fails.
- `Invoke-VdfPostUpdateCheck`:
  - reads the commit recorded in `C:\Tools\scoop\apps\vdf\current\manifest.json` (Task 4);
  - runs `Test-VdfDataFolder` and `Test-VdfAiModel -Fix`;
  - writes one result line to `C:\Tools\data\vdf-snapshots\checks.log`.
  The nightly task from Task 5 runs it after `Save-VdfSnapshot`, so after any update (UniGetUI included) a
  pinned-model change is fixed by the next morning. The owner can also run it by hand right after an update.

- [ ] **Step 1: Write failing tests:**
  - a missing folder → `$false`;
  - an empty `ScannedFiles.db` → `$false`;
  - a renamed-away folder → `$false` with the error text naming the path (Review Focus 2);
  - `Test-VdfAiModel` with mocked web content and a fake model file: a matching hash → `$true`; a mismatch with
    `-Fix` → the file is deleted and the result is `$false`;
  - `vdfdb.ps1` builds the argument list `db export -o x.json --db C:\Tools\data\vdf` (test the arg builder
    function `Get-VdfCliArgs -UserArgs <string[]> -> [string[]]`).
  - `Invoke-VdfPostUpdateCheck` with a fake `manifest.json` naming commit `abc1234`: it calls `Test-VdfAiModel`
    with `-Commit abc1234 -Fix`, and appends one line to `checks.log`.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement. Add `C:\Tools\scoop-bucket\tools` to the user PATH.
- [ ] **Step 4:** Run → PASS. Run `Test-VdfAiModel -AiFolder C:\Tools\scoop\persist\vdf\ai -Commit 4ab0e82` →
  `$true`.
- [ ] **Step 5:** Commit "VdfTools: data-folder guard, AI model check, vdfdb wrapper".

### Task 7: Install VDF and verify the cut-over

**Files:** none new. Record the results in `docs\SETUP.md` under a new "Install log" heading.

- [ ] **Step 1:** `scoop bucket add aston77 https://github.com/Aston77/scoop-bucket`, then `scoop install aston77/vdf`.
  Verify:
  - `C:\Tools\scoop\apps\vdf\current\VDF.GUI.exe` and `vdf-cli.exe` exist;
  - `Settings.json`, `ai` and `bin` in `current` are links to persist (`(Get-Item …).LinkType` is `HardLink` or
    `Junction`).
- [ ] **Step 2:** `Test-VdfDataFolder C:\Tools\data\vdf` → `$true`. Then `vdfdb db export -o $env:TEMP\vdf-check.json`
  → stderr says `Database loaded: 985,293 entries`. Delete the export.
- [ ] **Step 3 (owner):** The owner starts the GUI from the Start menu shortcut and closes it after it loads.
  Verify from `current\log.txt`:
  - the database path is `C:\Tools\data\vdf`;
  - 985,293 entries were imported;
  - the native FFmpeg binding loaded;
  - no AI download was offered.
  The owner checks Settings → scope shows `D:\Media\archive`, quarantine excluded, `*.mov`.
- [ ] **Step 4 (Review Focus 4):** With the GUI open, `scoop update vdf --force` → Scoop refuses (running
  process). Close the GUI.
- [ ] **Step 5:** `scoop update vdf --force` (reinstall) → afterwards Settings, `ai`, `bin` and the data are
  unchanged: the hashes of `persist\vdf\Settings.json` and `C:\Tools\data\vdf\ScannedFiles.db` are the same as
  before.
- [ ] **Step 6 (Review Focus 2):** Rename `C:\Tools\data\vdf` to `vdf.off` → `vdfdb db export …` refuses with a
  message naming the path. Rename it back. Note in the install log that the GUI itself would fall back silently,
  so the owner should launch only after updates have been verified.
- [ ] **Step 7:** Commit "Install log: VDF cut-over verified".

### Task 8: UniGetUI

- [ ] **Step 1 (owner, Claude guides):** In UniGetUI → Settings → Package managers → Scoop:
  - add the bucket `aston77` with URL `https://github.com/Aston77/scoop-bucket`;
  - confirm "cleanup apps" and "cleanup cache" are **off**;
  - confirm `vdf` appears under installed packages with its version.
- [ ] **Step 2:** Verify from UniGetUI's settings files under `%LOCALAPPDATA%\UniGetUI` (read-only) that
  `EnableScoopCleanupApps` and `EnableScoopCleanup` are not set. Record this in the install log; commit.

### Task 9: First scans (owner-run, Claude assists)

- [ ] **Step 1:** Confirm D: is mounted (`Test-Path D:\Media\archive`). Run `Save-VdfSnapshot` → a snapshot path
  is printed.
- [ ] **Step 2 (owner):** GUI database cleanup with "remember deleted content" on. Expected: about 75,092
  entries removed, about 495 tombstones kept. Record the counts from the log.
- [ ] **Step 3 (owner):** Phase 1 scan, using the current settings (6 GIFs to fingerprint, plus the AI passes).
  Pause/resume is allowed. Record the duration and results in the install log.
- [ ] **Step 4:** Phase 2 later. The owner turns off `FilterByFileSize` in the GUI (339 mp4 > 50 MB, about 33 GB).
  Out of scope for completion.

### Task 10: LosslessCut and CloudCompare

**Files:** Create `tools\CloudCompareTools.psm1`, `tools\Update-CloudCompare.ps1`, `tests\CloudCompareTools.Tests.ps1`;
modify `C:\Users\User\.claude.json` (`CLOUDCOMPARE_PATH`), `C:\Scans\CLAUDE.md` (Tools line) and the memory file
`C:\Users\User\.claude\projects\C--Scans\memory\cloudcompare-relocation.md`.

**Interfaces (Produces):**
- `Install-CloudCompareVersion -Source <dir|archive> -Version <string> -Root 'C:\Tools\CloudCompare' -> [string]`
  extracts or copies the build to `<Root>\<Version>\` and returns that path. It throws if the folder exists.
- `Test-CloudCompareSmoke -Exe <string> -> [bool]` runs, in silent mode on small fixtures in `$env:TEMP`
  (generated: a 1k-point PLY mesh, plus an OBJ):
  - open PLY and OBJ as a mesh;
  - `-EXTRACT_VERTICES`;
  - `-APPLY_TRANS`;
  - `-PLY_EXPORT_FMT BINARY_LE` save;
  - save to a path containing a space;
  - ICP on two `.bin` clouds.
  Each check asserts that its output file exists and is non-empty.
- `Set-CloudCompareCurrent -Root <string> -Version <string>`: re-points the `current` junction.
- `Update-CloudCompare.ps1 <archive> [-Version <tag>]`: Install, then Smoke on the new exe, then flip `current`
  only if all pass. It defaults the version to the latest pre-release tag from
  `gh release list -R CloudCompare/CloudCompare`.

- [ ] **Step 1:** `scoop bucket add extras`, then `scoop install extras/losslesscut`. Verify that it starts.
  Find its settings location (expected `%APPDATA%\LosslessCut`) and confirm it is outside the app folder. Record
  this in the install log.
- [ ] **Step 2:** Write failing Pester tests:
  - `Install-CloudCompareVersion` into `$TestDrive` with a fake folder → the path is returned and the files are
    copied; a second call throws;
  - `Set-CloudCompareCurrent` → the junction target equals the version folder;
  - `Update-CloudCompare` with a mocked smoke returning `$false` → `current` is unchanged.
- [ ] **Step 3:** Run → FAIL. Implement. Run → PASS.
- [ ] **Step 4:** `Install-CloudCompareVersion -Source C:\Users\User\Downloads\CloudCompare_v2.14.beta_bin_x64 -Version v2.14.beta-2026-09-26`
  (a copy), then `Test-CloudCompareSmoke` on it → `$true`. Then `Set-CloudCompareCurrent`.
- [ ] **Step 5:** Set `CLOUDCOMPARE_PATH` in `~/.claude.json` to `C:\Tools\CloudCompare\current\CloudCompare.exe`.
  Update the CloudCompare line in `C:\Scans\CLAUDE.md` the same way, and commit in `C:\Scans`. Rewrite the
  memory note to point at `C:\Tools\SETUP.md` and this method.
- [ ] **Step 6 (owner):** Restart Claude Code. Verify that `mcp__cloudcompare__get_cloudcompare_info` reports the
  new path.
- [ ] **Step 7:** Commit in the bucket repo "CloudCompare manual-update tools". Tell the owner about
  GitHub → CloudCompare/CloudCompare → Watch → Custom → Releases.

### Task 11: Retire the Downloads copies (owner go-ahead required)

Only after Task 9 step 3 has finished and the owner confirms.

- [ ] **Step 1:** Move the four VDF/LosslessCut/CloudCompare folders to `D:\Backups\Downloads-retired-2026-11\`
  with `robocopy /MOVE`. Check that the file counts and total bytes match before and after (the source is
  ~11 GB).
- [ ] **Step 2:** Record this in the install log; commit. Deleting them from `D:\Backups` later is the owner's call.
