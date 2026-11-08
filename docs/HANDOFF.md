# Handoff: portable tools (2026-11-08)

Start here in a new session. The design is `docs\SETUP.md` (top part) and the plan is
`docs\plans\2026-11-07-portable-tools.md`. Everything done so far is in the "Install log" at the end of
`docs\SETUP.md`. The executor's ledger is `C:\Tools\.sdd\portable-tools\progress.md` (rulings, per-task results).

## State

- Tasks 1-8 and 10 are done and verified (Scoop, bucket, `vdf` install, snapshots and nightly task, guards,
  UniGetUI, LosslessCut, CloudCompare move). Tests: `bin\test.ps1` 52/52; GitHub CI and Excavator green.
- Task 9 (first scans): step 1 snapshot and step 2 cleanup done. The live DB has 910,201 entries after
  "Prune ghost entries" removed 75,092. The snapshot `C:\Tools\data\vdf-snapshots\20261107-225346` is the DB from
  before any cleanup (985,293 entries).
- The nightly task `VDF data snapshot` (04:30) runs `tools\vdf-nightly.ps1`: snapshot (refused while VDF is open,
  logged in `vdf-snapshots\snapshot.log`), then `Invoke-VdfPostUpdateCheck` (`vdf-snapshots\checks.log`).

## Remaining work

1. **CloudCompare beta3.** The owner downloads the Windows build from cloudcompare.org in a browser (scripted
   downloads get 403; GitHub releases carry source only). Then run
   `pwsh -NoProfile -File C:\Tools\scoop-bucket\tools\Update-CloudCompare.ps1 <archive>`. The version defaults to the
   newest GitHub pre-release tag (`v2.14.beta3`). It installs to `C:\Tools\CloudCompare\v2.14.beta3`, runs six
   smoke tests and flips `current` only if all pass. Afterwards check `mcp__cloudcompare__get_cloudcompare_info` and
   log the result in `docs\SETUP.md`. Old folder `v2.14.beta-2026-09-26` stays for rollback.
2. **Task 9 step 3: phase 1 scan (owner runs it in the GUI).** Before it: VDF closed, D: mounted, take a snapshot
   (`Save-VdfSnapshot -DataFolder C:\Tools\data\vdf -SnapshotRoot C:\Tools\data\vdf-snapshots`). Optionally turn on
   "always retry failed sampling" so the 1,716 thumbnail-error entries (folders 02-26 to 03-25, from the old
   FFmpeg timeouts) are retried. After it, read `C:\Tools\scoop\apps\vdf\current\log.txt` and record: duration,
   results, that the native FFmpeg binding loaded from `bin` and that no AI download happened (this build logs
   neither at startup). Pause/resume is safe (checkpoints every 5 min).
3. **Task 9 step 4 (later, out of scope):** phase 2, the owner turns off `FilterByFileSize` (339 mp4 > 50 MB).
4. **Task 11 (owner go-ahead required):** after the phase 1 scan, `robocopy /MOVE` the four Downloads folders
   (`GUI-win-x64`, `GUI-win-x64_Backup`, `GUI-win-x64 - Copy`, `LosslessCut-win-x64`) and
   `CloudCompare_v2.14.beta_bin_x64` to `D:\Backups\Downloads-retired-2026-11\`, checking file counts and bytes.
5. **Wrap-up:** collect the ledger's `Ruling:` and `minor (deferred)` lines for the owner, then delete
   `C:\Tools\.sdd`. Offered and not yet asked for: an independent code review of the bucket repo; draft upstream
   issues for VDF (below).

## Things learned the hard way

- **VDF "Clean database" ignores "Remember deleted content"** unless a scan or thumbnail load has run in the
  session (`SyncCoreSettings()` is not called at startup). Use **"Prune ghost entries"**. It checks every file
  twice (count, then prune after the confirm), about 2 h on the USB disk, with no progress shown. The button is not
  disabled while running.
- The GUI's Setup screen walks every include folder at each start (per-file size reads, slow on USB). It is only
  for display: scanning right away cancels it. No setting turns it off.
- Scoop 0.6 writes `scoop-manifest.json` in the app folder (not `manifest.json`).
- Scoop exits 0 when it refuses an update because the app is running.
- CloudCompare `-SAVE_* FILE` paths with a space need literal quotes inside the argument;
  `Start-Process -ArgumentList` adds no quotes at all.
- Windows PowerShell 5.1 runs in CI: no `? :` ternary or other PS7-only syntax in repo scripts.
- Every repo file must be CRLF, end with a newline, no trailing whitespace (Scoop's file tests);
  `C:\Tools\.sdd\normalize.ps1 <files>` fixes that.
- In Claude Code, `!` commands run in bash: wrap PowerShell as `pwsh -NoProfile -c '...'` with single quotes.
  Auto mode blocks running downloaded installers, creating public repos, registering scheduled tasks and
  starting/stopping GUI apps; hand those to the owner.

## Draft upstream issues (offered, not written)

1. GUI "Clean database" runs without tombstone preservation until a scan has started (495 tombstones lost here).
2. Setup-screen folder counting stats every file (`new FileInfo(file).Length`); use the enumeration's
   `FileInfo`, skip drives classified slow, or persist the count.
3. "Prune ghost entries" can run twice at once (button not disabled; command created per property access).
