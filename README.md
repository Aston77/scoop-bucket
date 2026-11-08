# aston77 Scoop bucket

[![Tests](https://github.com/Aston77/scoop-bucket/actions/workflows/ci.yml/badge.svg)](https://github.com/Aston77/scoop-bucket/actions/workflows/ci.yml) [![Excavator](https://github.com/Aston77/scoop-bucket/actions/workflows/excavator.yml/badge.svg)](https://github.com/Aston77/scoop-bucket/actions/workflows/excavator.yml)

Personal [Scoop](https://scoop.sh) bucket for portable apps that have no good manifest elsewhere, starting with the
Video Duplicate Finder daily build (`vdf`, GUI + CLI). Helper scripts for VDF data and CloudCompare are in `tools\`.
Design and plan: `docs\SETUP.md`, `docs\plans\`.

```pwsh
scoop bucket add aston77 https://github.com/Aston77/scoop-bucket
scoop install aston77/vdf
```

`vdf` needs its persist folder seeded first (`tools\Initialize-VdfData.ps1`); see `docs\SETUP.md`.
