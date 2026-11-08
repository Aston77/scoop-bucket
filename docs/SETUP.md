# Portable tools: layout and updates

Design, 2026-11-07. Owner: Aston77 (GitHub). Status: draft, revised after an adversarial review and a builder
check (same day). Nothing built yet.

## Why

Three portable apps run straight out of `C:\Users\User\Downloads`, which gets cleared. Updating them means
unzipping a new copy and moving settings and data by hand. For Video Duplicate Finder (VDF) that has led to
three full copies of the program and its data (~11 GB), because its scan database is costly to rebuild
(days of hashing a ~1M-file archive on a USB hard disk) and VDF ships daily builds the owner likes to follow.

Goal: each app lives in one place, updates from its upstream release without hand-copying settings or data,
can roll back to the previous version, and VDF's computed data can be read by other programs through VDF's
own command-line tool (CLI).

## Goals

- Updates are found and installed without manual downloading, unzipping or copying settings.
- Settings and data survive every update untouched; updating never rebuilds VDF's database.
- The previous version stays available for rollback.
- VDF's GUI and CLI share one install and one data folder.
- Fits the owner's existing update tool, UniGetUI (github.com/Devolutions/UniGetUI).
- A method that can take more GitHub-released apps later (first candidate: better-ccflare).

## Non-goals

- Apps that already update themselves and keep data outside the program (Printventory).
- better-ccflare now. Added later, once this method is proven.
- The system FFmpeg on PATH (winget `Gyan.FFmpeg`, upgraded by the owner to 9.0.2 on 2026-11-07). VDF does not use it.

## Anti-goals (a failure even if everything "works")

- Losing or silently pruning VDF scan data, AI caches, "not a duplicate" marks, or settings.
- An update or rollback that lets a different VDF build rewrite the database with no copy to go back to.
- VDF silently starting an empty database somewhere else and the owner not noticing.
- Deleting the old Downloads folders before the new setup has completed a real scan.
- Several copies of VDF data that have to be kept in sync.

## Decided

### Mechanism: Scoop with a personal bucket, driven by UniGetUI

- Install **Scoop** per-user, root `C:\Tools\scoop` (owner accepted Scoop; root location is Claude's call).
  Scoop gives `apps\<app>\<version>\`, an `apps\<app>\current` junction, and `persist\<app>\` (directories as
  junctions, files as hard links; a pre-seeded persist target wins).
- A **public GitHub repo under Aston77** holds a personal Scoop bucket, created from ScoopInstaller/BucketTemplate.
  Its Excavator Action runs checkver/autoupdate (template default: every 4 h) and commits new versions.
- **UniGetUI** adds the bucket as a Scoop source and shows/applies updates. UniGetUI's Scoop support covers
  install, update and uninstall only: **no rollback**, and its "install version" option re-downloads the current
  asset under an old label. **UniGetUI's Scoop cleanup settings (`EnableScoopCleanupApps`, `EnableScoopCleanup`)
  must stay off**: they run `scoop cleanup --all` at startup and delete the old version folders rollback needs.

### Apps

| App | Decision |
|---|---|
| VDF daily build (main) | Own manifest, app name `vdf`. Installs **both** `GUI-win-x64.zip` and `CLI-win-x64.zip` from tag `4.1.x` into one version folder. Version label from the GUI asset's `updated_at` (format: builder's call). Hash from the GitHub API asset `digest` (sha256) so autoupdate never guesses. Note: the rolling build has not changed since 2026-10-09 (commit 4ab0e82); "daily" happens in bursts. |
| VDF numbered releases | Not installed alongside (Claude's call). If ever needed, install as a separate app pointed at a **snapshot copy**, never the live data folder. Do not reuse hoilc/scoop-lemon's manifest: GUI only, its own persist folder, and a relative `CustomDatabaseFolder: "data"` that breaks from the CLI. |
| LosslessCut | ScoopInstaller **Extras** `losslesscut` (current, 3.70.2). |
| CloudCompare | **Manual for now (owner, 2026-11-07), outside Scoop.** Why: cloudcompare.org answered automated requests with 403 (bot protection), the beta file name carries no build number, Extras tracks stable only, and GitHub releases carry source only. Method below. |

### VDF file locations (verified in source, commit 4ab0e82)

"App folder" means `apps\vdf\current`, which is physically the version folder. Anything written there is lost
when that version is cleaned up.

| Item | Where VDF puts it | Plan |
|---|---|---|
| `Settings.json` (GUI) | app folder (portable mode works through the junction) | persist as a file. **Pre-seed it before the first install**, or Scoop creates a *directory* named `Settings.json` |
| `ScannedFiles.db`, `UnionEmbeddings.db`, `DenseEmbeddings.db`, `BlacklistedGroups.json`, `ScannedFiles.fpheal1`, `scan-inflight-*` | `CustomDatabaseFolder` | **outside Scoop**: `C:\Tools\data\vdf` (Claude's call; on the SSD, as now). Not under `persist`, because `scoop uninstall -p` and UniGetUI's "remove data" (`--purge`) delete persist |
| `ai\` (ONNX runtime + model, ~38 MB) | app folder (`AiComponents.AiFolder = StateFolder\ai`) | persist `ai` (seed from `Downloads\GUI-win-x64\ai`). Each build pins both parts in code: runtime `RuntimeVersion` (1.23.2, checked against `ai\runtime.version`, so a bump re-downloads by itself) and the model `ModelSha256`. The model's hash is checked **only at download**; afterwards VDF only checks that the file exists. So a build that pinned a new model would silently keep the old persisted one. Requirement: the update step (or launch wrapper) compares the persisted model's SHA256 with the build's pinned value and deletes it on mismatch, so VDF fetches the new one. Builder's call how; the pin has not changed since AI landed on 2026-07-12. |
| `bin\` (FFmpeg) | app folder `bin` (lookup: `bin`, app folder, PATH; auto-download into `bin`) | persist `bin` |
| `log.txt` | app folder | lost per version; acceptable |

**Silent fallback risk:** if `CustomDatabaseFolder` doesn't exist, or the GUI settings fail to load (defaults,
empty folder), or the CLI runs without `--db`, VDF uses the app folder and starts an **empty** database there.
Mitigations:
- The data folder is created before VDF is first started.
- Every scripted CLI call passes `--db C:\Tools\data\vdf`. Provide a wrapper/shim that always does.
- After each update, check that the log shows the expected database path and entry count.

The CLI **cannot** use the GUI's `Settings.json`: `--settings` reads a different class (`IncludeList`,
`BlackList`, `UsePHashing` vs the GUI's `Includes`, `Blacklists`, `UsePHash`), and mismatched keys are silently
ignored. The CLI shares the **data folder** only. Scan settings for CLI scans are passed as options or as a
CLI-format settings file (builder's call). The `db` subcommands read only `--db`.

### FFmpeg seed

Copy from `Downloads\GUI-win-x64\bin` only the FFmpeg 8.x set: `avcodec-62`, `avdevice-62`, `avformat-62`,
`avutil-60`, `avfilter-11`, `swscale-9`, `swresample-6` (`.dll`), plus `ffmpeg.exe`, `ffprobe.exe`, `ffplay.exe`
(the exes import `avcodec-62`, `avformat-62`, `avutil-60`). Leave the 9.x/master set (`*-63`, `avutil-61`,
`avfilter-12`, `swscale-10`, `swresample-7`). When VDF moves to a new FFmpeg major, empty `bin` and VDF fetches
the match. Detection is the builder's call.

### VDF: which data carries forward (read-only comparison on copies, 2026-11-07)

| Folder in Downloads | Program | DB | Scope |
|---|---|---|---|
| `GUI-win-x64_Backup` | Aug 8 build | 985,293 entries, saved Aug 14 | all of `D:\Media\archive`, videos only, ≤50 MB |
| `GUI-win-x64` | Aug 23 build | 103,099 entries, Aug 17 | 17 day folders, `*.mp4`/`*.gif` only |
| `GUI-win-x64 - Copy` | Jul 23 build | Jul 22 | older full run; its `UnionEmbeddings.db` (Jul 21) is identical to Backup's |

Findings:
- The Aug 14 DB covers every file the newest one does: 98,601 shared, identical size and mtime.
- The newest adds fingerprints for only 204 files and audio fingerprints for 199.
- Its other 4,498 entries are `D:\Media\quarantine\vdf` paths, all but one gone.
- `DenseEmbeddings.db` (newest only, 49,270 records) and the newest `UnionEmbeddings.db` (69,066) are 100% valid
  against the Aug 14 DB (exact size + mtime ticks).
- 75,587 Aug 14 entries point at files VDF later moved to quarantine (75,583 found there by name and size).
  Only 495 of them carry fingerprints; the rest are never-fingerprinted images.
- About 751k Aug 14 entries are images that were never fingerprinted.
- 5,826 videos/GIFs on disk are fingerprinted by neither DB (545 skipped for being over 50 MB).

**Carry forward into `C:\Tools\data\vdf`:**
- `ScannedFiles.db` and `ScannedFiles.fpheal1` from `GUI-win-x64_Backup`
- `UnionEmbeddings.db` from `GUI-win-x64_Backup`
- `DenseEmbeddings.db` from `GUI-win-x64`
- `BlacklistedGroups.json`: merge the two copies (Backup: 12,318 B, Jul 13; newest: 10,300 B, Aug 17). Union of
  the entries, Claude's call: these are "not a duplicate" marks, and extra marks for gone files are harmless.
  The builder checks the format.
- Recomputing the ~200-file gap is accepted; no binary merge. Merging the 235 union records only the newest cache
  has is optional (builder's call).

The first save by the new build rewrites the DB in its current format. **The untouched Downloads folders are the
real backup of the old-format data until the cut-over is proven.**

**Settings.json carried forward** from `GUI-win-x64`, with:
- `FilePathContainsTexts`: `.mov` → `*.mov`. Owner agreed; verified that the old `.mov` matched nothing.
- `Blacklists` += `D:\Media\quarantine`. Quarantine is a holding area before deletion; nothing in it is scanned.
- `CustomDatabaseFolder` = `C:\Tools\data\vdf` (absolute)
- `HddMaxDegreeOfParallelism` = 1. Per the developer in #891; it applies only to drives VDF classifies as slow.
  The log showed D: as slow, so confirm in the log or set `DriveTypeOverrides`.
- Scope (owner, 2026-11-07): `Includes` = `D:\Media\archive`. No images other than GIFs (`IncludeImages` stays
  on only so GIFs are scanned; the path filter keeps other images out). Phases:
  - Phase 1: `*.gif`, `*.mov`, and `*.mp4` ≤ 50 MB (`FilterByFileSize` on, max 50).
  - Phase 2: the remainder (`*.mp4` > 50 MB; other video types if any appear).

  A directory walk on 2026-11-07 found phase 1 already fingerprinted in the Aug 14 DB except 6 GIFs:
  227,834 mp4 ≤ 50 MB, 5,036 GIFs and 122 .mov files. Phase 2 is 339 of 575 mp4 > 50 MB, about 33 GB to read.
  (The earlier "5,826 unfingerprinted" also counted quarantine.) The expensive remaining work is the AI passes,
  not fingerprinting. Dense keyframe sampling for visual partial detection has covered 49,270 videos so far.
  It reads each video, but it checkpoints (`ScanEngine_AiPartial.cs`), so it can be done in pieces.
- Later analysis (discussion #737, short clip → which long source). It needs **no new scan**:
  - Min clip ratio 2–5 %, audio similarity 88–90 % and visual similarity 90 % are compare-time thresholds.
  - pHash is computed from the stored grayscale fingerprints; 228,030 of 233,513 entries already carry it.
  - Audio fingerprints are built by the normal scans while partial-clip detection is on.

  It is a separate compare run, best saved as its own scan profile. Its visual check decodes frames from both
  files of each candidate pair. A lower min clip ratio means many more candidates, so expect much more disk
  reading on the USB drive during that run.

**Cleanup: no CLI `db clean`.** `vdf-cli db clean` calls `CleanupDatabase()` without tombstone preservation: it
removes every entry whose file is not visible, with **no drive-mounted check**. With D: asleep it would empty the
database, and the next save would prune the AI caches. The owner has `RememberDeletedContent = true`. The GUI's
cleanup honours it: it keeps tombstones (entries with fingerprints for deleted files, used to recognise
re-downloads), skips unmounted drives, and removes entries that are gone with no comparable data. Use the GUI's
cleanup, with D: confirmed mounted and after a snapshot. Expected effect: about 75,092 unfingerprinted gone images
removed, 495 fingerprinted tombstones kept.

### CloudCompare: manual update method

- **Layout:**
  - each version in its own folder, e.g. `C:\Tools\CloudCompare\v2.14.beta3\`, named after the GitHub tag;
  - a `C:\Tools\CloudCompare\current` junction that the MCP config and `C:\Scans\CLAUDE.md` point at;
  - the current Downloads build (exe dated 2026-09-26) is copied as is into a folder named for what it is,
    e.g. `v2.14.beta-2026-09-26`.
- **Knowing when there's a new one:** the CloudCompare/CloudCompare GitHub repo tags every beta as a pre-release
  (beta1 2026-09-28, beta2 2026-10-07, beta3 2026-11-03), though without Windows binaries. Watch that repo
  (GitHub → Watch → Custom → Releases) for an email per beta. Optionally a bucket Action or the scheduled task
  reports a new tag too (builder's call).
- **Updating:**
  1. The owner downloads the Windows 7z/zip from cloudcompare.org in a browser.
  2. They run `Update-CloudCompare.ps1 <archive>` (in the bucket repo's `tools\`). The script:
     - extracts the archive beside the old version;
     - runs the pipeline's smoke tests through the CloudCompare command line: open PLY/OBJ as mesh,
       `-EXTRACT_VERTICES`, `-APPLY_TRANS`, binary PLY save, save path with a space, ICP on `.bin` copies;
     - flips `current` only if all pass;
     - keeps the previous version folder.
  3. Rolling back means pointing the junction back. Settings are in the registry, so they carry over.

### Incremental scanning (verified in source)

Long VDF scans need not be one marathon:
- **Fingerprints are saved as the scan goes:** checkpoint every `DatabaseCheckpointIntervalMinutes` (5).
  **Pause** flushes the database ("safe to close the app; a later rescan resumes from the cache"). AI embeddings
  are persisted on cancel and on error too. A rescan skips files whose fingerprints are already stored.
- **Batching by folder:** scan the archive a few month folders at a time by changing Includes. Already-done
  folders cost only a quick listing.
- **Unattended hashing:** `vdf-cli scan --db C:\Tools\data\vdf --include <folder> ...` builds fingerprints and AI
  embeddings without comparing (`compare` is a separate step). It suits a nightly scheduled task working through
  a folder list, with `--parallelism 1` for the USB disk and the same AI options as the GUI (`--ai-matching`,
  `--ai-partial`, partial-clip options). The GUI also has a built-in scheduled scan (`EnableScheduledScan`,
  `ScheduledScanTime`).
- **What stays a single run:** the duplicate comparison over the chosen scope, including partial-clip
  verification, is where #865's hang was. It reuses all stored fingerprints, so it is compute, not disk reading.
  In #865 it ran about 8 h for 226k files and kept checkpointing the database meanwhile. Results are only
  complete when it finishes.

### Snapshots and rollback (Claude's call)

Reviewer findings:
- A manifest `pre_install` snapshot runs too late: after the old version is unlinked, and a failure leaves no
  `current`.
- `scoop reset` runs no hooks.
- Scoop already refuses update, reset and uninstall while VDF runs from the app folder.

So:
- Snapshots are made by a small **PowerShell script** in the bucket repo (`tools\`), not by a manifest hook.
  - Copies `C:\Tools\data\vdf` to `C:\Tools\data\vdf-snapshots\<timestamp>\` (~3.6 GB each).
  - Skips the copy when nothing has changed since the last snapshot (newest file time + sizes).
  - Keeps the last 2 snapshots.
  - Refuses to run while VDF is running.
  - A failure stops the operation before anything is changed.
- **Rollback script:** snapshot, then `scoop reset vdf@<older version>`. Rollback is the moment an older build
  meets a newer database, so if the older build cannot read it, restore the snapshot taken before the forward
  update.
- **Updates from UniGetUI cannot run the snapshot script first.** Two options for the builder, prefer the first:
  - a scheduled task that snapshots on a schedule (e.g. nightly while VDF is closed), so a recent snapshot always
    exists;
  - a `pre_uninstall` hook that copies but never throws.
- Old version folders: keep the last 2–3 (`scoop cleanup` only by hand). Daily assets are replaced upstream, so
  old daily builds cannot be re-downloaded.

### Cut-over order

1. Install Scoop. Create `C:\Tools\data\vdf`, copy in the carry-forward files, and pre-seed
   `persist\vdf\{Settings.json, ai\, bin\}`. **Copies only; Downloads stays untouched.**
2. Add the bucket and install `vdf`. Start the GUI, then confirm in its log:
   - the database path is `C:\Tools\data\vdf`;
   - 985,293 entries are loaded;
   - FFmpeg native binding loads from `bin`;
   - the AI components are found (no download).
3. Snapshot. Run the GUI cleanup (D: mounted). Then run the catch-up scan in the agreed scope.
4. After the scan succeeds, move the three Downloads folders to `D:\Backups` and delete them later. Their
   `scan-inflight-*.txt` (crash leftovers from #863/#865), `.pdb` files, `backup.scanresults` and
   `Scan-Results-*` archives go with them.
5. LosslessCut from Extras; remove the Downloads copy after first launch.
6. CloudCompare: copy the Downloads build into `C:\Tools\CloudCompare\<version>\`, create `current`, then point `CLOUDCOMPARE_PATH` in `~/.claude.json` and the Tools line in
   `C:\Scans\CLAUDE.md` at its `current` path. These are the only two references (checked 2026-11-07). Restart
   Claude Code, verify the MCP server, then remove the Downloads copy. Update the memory note
   `cloudcompare-relocation`.

## Constraints

- Windows 11, no admin (Scoop per-user). PowerShell available; system Python is not (use `uv`).
- Media on D: (USB 3.0 HDD, label "Backup"). Per-file stats are slow and a directory walk is much faster. The drive
  may sleep or be unplugged.
- VDF must not be running during install, update, snapshot, or rollback.
- Upstream background: the owner's issues #863, #865 and #891 (CUDA crash in partial-clip verification, hang with
  no checkpoint, FFmpeg timeouts from parallel reads on the HDD), all closed.

## Verify before calling it done

- The GUI and `vdf-cli` both run from `current`. Both use `C:\Tools\data\vdf` (log shows the path), FFmpeg from
  the persisted `bin` (native binding loads) and AI components from the persisted `ai`.
- A forced reinstall/update of `vdf` keeps settings, data, `ai`, `bin`.
- `scoop reset` to the previous version folder works.
- The snapshot script refuses while VDF runs, skips when nothing changed, and keeps 2 snapshots.
- `vdf-cli db export --db C:\Tools\data\vdf -o <file>` works from a script outside the app folder.
- Starting the GUI with the data folder renamed away gives a visible problem, not a silent empty database. If VDF
  can't be made to show it, a launch wrapper checks that the folder exists first.
- LosslessCut starts and keeps its settings across an update.
- UniGetUI lists the bucket's packages and applies an update; its Scoop cleanup options are off.
- CloudCompare (if moved), via the MCP server: open PLY/OBJ as mesh, `-EXTRACT_VERTICES`, `-APPLY_TRANS`, binary
  PLY save, save path with a space, ICP on `.bin` copies.

## Left to the builder

- Bucket repo name and layout
- Manifest details: checkver, version format, `digest`-based hash, the GUI + CLI two-URL install
- CLI scan-settings handling
- FFmpeg major-version detection
- Snapshot trigger for UniGetUI updates (preference stated above)
- The empty-database guard (wrapper or not)
- The `BlacklistedGroups.json` merge format

## Open questions for the owner

None. Scan scope and CloudCompare decided by the owner 2026-11-07.

## Install log

### 2026-11-07: Scoop, bucket, VDF data (Tasks 1-7)

- Scoop v0.6.0 in `C:\Tools\scoop` (user env `SCOOP`). Pester 6.2.0 and BuildHelpers for the bucket tests.
- Bucket `Aston77/scoop-bucket` (default branch `master`), cloned to `C:\Tools\scoop-bucket`; `tools\` is on the
  user PATH. CI and Excavator green.
- Seeded by `tools\Initialize-VdfData.ps1` (copies only, SHA256-verified): `C:\Tools\data\vdf\ScannedFiles.db`
  2,672,018,461 B, `UnionEmbeddings.db` 915,272,114 B, `DenseEmbeddings.db` 57,431,246 B, merged
  `BlacklistedGroups.json` 113 groups; persist `Settings.json`, `ai\` (6 files), `bin\` (10 FFmpeg 8.x files).
- `vdf` 4.1.20261009.1645 (upstream commit 4ab0e82) installed from the bucket. `Settings.json` is a hard link,
  `ai` and `bin` are junctions into `C:\Tools\scoop\persist\vdf`.
- Manifest hash check: a wrong-hash manifest aborts with "Hash check failed" and leaves no `current`.
  `scoop update` checks hashes before it uninstalls the old version (scoop-update.ps1), so a replaced daily asset
  keeps the old version.
- `Test-VdfAiModel` at 4ab0e82: persisted model matches the pinned SHA256.
- `vdfdb db export -o <file>`: "Database loaded: 985,293 entries", exported 985,293; `ScannedFiles.db` unchanged.
- `scoop update vdf --force`: `Settings.json`, `ai`, `bin` and `ScannedFiles.db` hashes unchanged.
- Data folder renamed to `vdf.off`: `vdfdb` refuses ("VDF data folder not found: C:\Tools\data\vdf ...") and writes
  nothing. The GUI itself would fall back silently to an empty database in the app folder, so launch the GUI only
  after an update has been checked (`Invoke-VdfPostUpdateCheck`, or the nightly task's `checks.log`).

### 2026-11-07: UniGetUI, LosslessCut, CloudCompare (Tasks 8, 10)

- UniGetUI (read-only check of `%LOCALAPPDATA%\UniGetUI\Configuration`): Scoop is enabled; no
  `EnableScoopCleanupApps` or `EnableScoopCleanup` setting exists (both off). The `aston77` bucket was added
  through Scoop, which UniGetUI reads.
- LosslessCut 3.70.2 from `extras/losslesscut` (Scoop also installed `7zip` 26.06 as a dependency). Settings live in
  `%APPDATA%\LosslessCut\config.json`, outside the app folder, shared with the old Downloads copy (which has no
  portable config).
- CloudCompare: Downloads build copied to `C:\Tools\CloudCompare\v2.14.beta-2026-09-26` (195 files, 390,050,850 B,
  same as the source); `current` is a junction to it. `Test-CloudCompareSmoke` passed all six checks.
  Finding: CloudCompare splits a `-SAVE_* FILE` name on spaces unless the argument itself contains quotes, so the
  command line needs `"\"C:\a b\out.ply\""`; `Invoke-CloudCompare` encodes this.
- `CLOUDCOMPARE_PATH` in `~/.claude.json` and the Tools line in `C:\Scans\CLAUDE.md` now point at
  `C:\Tools\CloudCompare\current\CloudCompare.exe`.
- New CloudCompare betas: watch GitHub CloudCompare/CloudCompare → Watch → Custom → Releases.

### 2026-11-07: first GUI start (Task 7 steps 3-4)

- The owner first opened an old Start-menu shortcut `VDF.lnk` that ran the Downloads copy; it was closed and the
  shortcut deleted. Use "Scoop Apps\Video Duplicate Finder".
- The Scoop GUI's `log.txt`: "Previously scanned files imported. 985,293 files". No database in the app folder, so
  it read `C:\Tools\data\vdf`. This build logs nothing at startup about FFmpeg or AI; check those at the first scan.
- With the GUI open, `scoop update vdf --force` refused ("still running ... skip updating") and changed nothing.
  Scoop exits 0 in this case, so scripts must not read success from the exit code.

### 2026-11-07: UniGetUI sees vdf (Task 8 step 1)

- UniGetUI had been running since before Scoop was installed, so it could not see Scoop. After a full quit and
  restart it lists `vdf` under installed packages. The Scoop cleanup settings are still unset (off).
- CloudCompare note: `current` is byte-identical to the Downloads build (exe 2026-09-26), not beta3.

- LosslessCut (Scoop copy) started from the Start menu with the owner's settings (owner check, 2026-11-07).

- After the Claude Code restart, the cloudcompare MCP server reports C:\Tools\CloudCompare\current\CloudCompare.exe, ready (Task 10 step 6).
