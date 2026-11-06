# Bomb Defender

**Bomb Defender** is a single-player 2D bomber-style maze game built with **Godot 4**. Destroy crates, defeat enemies, discover a hidden power-up and find the secret exit door.

No API keys, paid services, account, or internet connection are required.
The Godot splash logo is disabled; the Windows executable and taskbar use the Bomb Defender icon.

## Features

- Procedurally generated arenas and enemies that approach placed bombs
- Exactly **one random hidden power-up** and **one separate hidden exit door** per level
- Level exit opens after all enemies are defeated and the power-up is collected
- Upgrades: blast range, bomb capacity, speed, health, remote detonation, bomb kicking, and walking through breakable crates
- Persistent upgrades across levels, chain reactions, score and sound effects
- Blast range starts at **1 tile**; explosion visuals and damage last **0.26 seconds**
- **No weather display, online APIs or network requests**

## Play from source

Open `project.godot` with **Godot 4.4.1 or another compatible Godot 4.x**, then press **F5**.

## Controls

| Key | Action |
|---|---|
| WASD / arrow keys | Move |
| Space | Place a bomb |
| E | Detonate the oldest bomb when remote detonation is unlocked |
| Walk into a bomb | Push the bomb when bomb kick is unlocked |
| P / Escape | Pause / resume |
| R | New game |
| Enter | Start |

## Windows download and export

**For players:** Download **`Bomb Defender.zip`** from the [latest GitHub Release](https://github.com/nailunluu/bomb-defender/releases/latest). Extract **both** `Bomb Defender.exe` and `Bomb Defender.pck` into the same folder, then open the EXE. There is no installer or network requirement.

**For maintainers:** This repository includes `export_presets.cfg` and `.github/workflows/windows.yml`. Pushing the source files to GitHub triggers a Windows build; download the packaged game from **Actions → Windows Build → latest successful run → Artifacts → Bomb-Defender-Windows**. Creating a version tag such as `v1.0.0` automatically publishes a GitHub Release with `Bomb Defender.zip`.

On Windows, you can also double-click `Build Windows.bat` if you have **Godot 4.4.1 + its export templates** installed. The script downloads and configures the small `rcedit` tool for the custom icon, then makes `dist/Bomb Defender.exe`, `dist/Bomb Defender.pck` and `dist/Bomb Defender.zip`.

**Local build:** The project was imported with Godot 4.4.1 and exported to `dist/`. That folder is excluded from version control; once you upload the source, the included GitHub Actions workflow creates the downloadable Windows ZIP.

## Repository structure

- `project.godot`, `main.tscn`, `main.gd` — Godot project
- `audio/` — sound effects
- `assets/` — game icon
- `export_presets.cfg` — Windows x64 export configuration
- `.github/workflows/windows.yml` — automated EXE build + release
- `Build Windows.bat` / `.ps1` — local build option
- `README_TR.md` — Turkish guide

*Built with Godot Engine — https://godotengine.org/*
