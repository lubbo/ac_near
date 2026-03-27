# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

NEAR is an Assetto Corsa (AC) Python plugin that displays HUD standings info — the driver immediately ahead and behind the player — with lap times, gaps, and driver details.

## Running & Deployment

There is no traditional build or test process. The plugin runs inside Assetto Corsa's Python runtime:

- **Deploy:** Zip the `apps/` directory and drop the `.zip` into Content Manager, or unzip directly into the AC installation directory.
- **Activate:** Enable the app in AC settings in-game.
- **Testing:** Manual only — run inside AC. Logs are written via `ac.log()` and visible in the AC log output.

The main entry points called by AC are `acMain(ac_version)` (initialization) and `acUpdate(deltaT)` (per-frame update).

## Architecture

All application logic lives in a single file: `apps/python/near/near.py`.

**Runtime environment:** Python 2.7 (AC's embedded interpreter). Imports `ac` and `acsys` — these are AC-provided modules unavailable outside the game. Platform-specific `_ctypes.pyd` binaries are in `stdlib/` (32-bit) and `stdlib64/` (64-bit) for shared memory access.

**Key classes:**

- `NearWindow` — Renders the main HUD. Manages two sets of AC labels (ahead/behind driver), including name, position, nation flag, best/last lap times, and gap. Layout is driven by zoom, padding, font sizes, and `hspace` (horizontal spacing).
- `Near_config` — Configuration UI window with 10 rows of labeled +/- controls. Changes are previewed live and persisted to `config/config.ini`.

**Global state:** ~20 global variables hold the current config values and are read by both windows. `refreshConfig()` reads the INI; `refreshAndSaveConfig()` writes it back.

**Data flow:**
1. `acMain()` initializes windows, loads config, queries initial car count.
2. `acUpdate()` polls all drivers, sorts standings (by track distance in race, by lap position in practice/qualifying), and calls `updateView()` on `NearWindow`.
3. `sim_info.py` maps AC shared memory pages (`SPageFilePhysics`, `SPageFileGraphic`) via ctypes for low-level telemetry not exposed through the `ac` API.

**Session logic:**
- Race: sorted by track spline position; pit detection (entry/exit transitions) is tracked per car.
- Practice/Qualifying: sorted by lap position; gap displayed as time delta to best lap.

**Time/color coding:**
- `timeToLabel()` formats milliseconds → `M:SS.mmm`.
- `deltaTimeToLabel()` computes delta and colors: purple = fastest ever, green = improvement, red = slower, gray = invalid/no data.
- `deltaToLabel()` converts gap to metric distance, imperial distance, or time depending on the `unit` config.

## Configuration

**File:** `apps/python/near/config/config.ini`

The file has a `[GLOBAL]` section (active config index) and numbered preset sections `[1]`, `[2]`, etc. Key parameters per preset:

| Key | Description |
|---|---|
| `updateTime` | UI refresh interval in ms |
| `zoom` | Overall scale factor |
| `opacity` | Background opacity 0–100 |
| `padding` | UI padding in px |
| `hspace` | Horizontal spacing between columns |
| `fontSizeName/Title/Time/Gap` | Font sizes for each text element |
| `colorAt` | Distance threshold (meters) for gap color changes |
| `unit` | `metric`, `imperial`, or `time` |
| `showLogo/Title/Border/Badge` | Boolean visibility toggles |

Multiple presets allow switching layouts without restarting AC.
