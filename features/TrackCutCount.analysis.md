# Track Cut Count – Integration Analysis

## Goal

Understand how Real Penalty (v1.05.01) stores track-cut and penalty data, and determine the feasible approach for the `near` app to read: current cut count, max allowed cuts, and penalty applied per driver.

---

## Real Penalty Architecture

Real Penalty is an **online-only** app. It works exclusively when the player is connected to a server running the Real Penalty server-side plugin.

### Startup sequence

1. `RealPenalty.py` is a thin Python wrapper that instantiates `Wrapper` from `wrapper.pyd`.
2. `Wrapper._ac_main()` calls `_set_connection()` to locate the Real Penalty server plugin UDP port (HTTP port + 27).
3. On successful connection it downloads a set of **server-provided modules** (`_get_modules_thread` → `modules.online`) via encrypted TCP socket (AES-CBC-256).
4. The downloaded `online` module is loaded at runtime and handles all real-time penalty logic.

### Key binaries

| File | Role |
|---|---|
| `wrapper.pyd` | TCP communication, module download, AES encryption/decryption, AC lifecycle hooks |
| `offline.pyd` | Stub shown when not on a Real Penalty server ("Not active offline!") |
| `ac_sim_info.pyd` | Reads AC's built-in shared memory pages (standard `acpmf_*` mmap regions) |

---

## Where Real Penalty Data Lives

### Server-side

The Real Penalty **server plugin** is authoritative for:
- Track-cut counting per driver
- Maximum allowed cuts (server configuration)
- Penalty assignment (drive-through, stop-and-go, etc.)

This data is pushed to each client app via the TCP connection established at join time.

### Client-side (in-process only)

The downloaded `online` module processes the incoming TCP data and maintains state **entirely in memory within the RealPenalty.py Python process**. No evidence was found of Real Penalty writing cut-count or penalty state to any external file or named shared-memory region.

String analysis of `wrapper.pyd` confirms the only files read/written are:
- `{Documents}/Assetto Corsa/cfg/race.ini` – race config (read)
- `{Documents}/Assetto Corsa/logs/log.txt` – AC log (read, to extract Steam GUID)
- `{AppDir}/settings/connection_settings.ini` – connection settings (read)

No JSON, CSV, or data-export path was found.

---

## AC Native Shared Memory (what `near` currently reads)

`sim_info.py` maps three mmap regions provided by AC itself:

| Region | Relevant penalty fields |
|---|---|
| `acpmf_graphics` | `penaltyTime` (float), `flag` (AC_FLAG_TYPE: 0–6) |
| `acpmf_static` | `penaltiesEnabled` (int) |
| `acpmf_physics` | (no penalty fields) |

**Critical limitation:** These regions expose data for the **player's car only**. There is no per-opponent penalty field in AC's shared memory.

### AC Python API (`ac` module)

The following calls are available per car index (including opponents):

```python
ac.getCarState(index, acsys.CS.BestLap)
ac.getCarState(index, acsys.CS.NormalizedSplinePosition)
ac.isCarInPit(index)
ac.isCarInPitline(index)
```

There is **no** `ac.getCarCutCount()`, `ac.getCarPenalty()`, or similar call that would return Real Penalty-specific data.

---

## Findings Summary

| Data Point | Source | Accessible to `near`? |
|---|---|---|
| Current track cuts | Real Penalty server → `online` module (in-process RAM) | **No** – no export mechanism found |
| Max allowed cuts | Real Penalty server config → `online` module (in-process RAM) | **No** |
| Penalty applied | Real Penalty server → `online` module (in-process RAM) | **No** |
| AC penalty flag (player only) | `acpmf_graphics.flag` | Yes, player-only |
| AC penalty time (player only) | `acpmf_graphics.penaltyTime` | Yes, player-only |

---

## Possible Integration Approaches

### Option A – Request a public data-sharing API from the Real Penalty author

Real Penalty's author (Davide Bolognesi, contact via Discord: https://discord.com/invite/syVQEG9) could expose cut/penalty data by writing a JSON file to a known path (e.g. `apps/python/RealPenalty/data/state.json`) that `near` polls each update cycle.

**Pros:** Clean, authoritative data. No reverse engineering.
**Cons:** Requires author cooperation; not available now.

### Option B – Inspect Real Penalty runtime files during an online session

During an online session on a Real Penalty server, the downloaded `online` module may write log or data files to `apps/python/RealPenalty/logs/` or similar paths. These would need to be identified by inspecting a live session.

**Pros:** No author cooperation needed if files exist.
**Cons:** Speculative; file format would be undocumented and fragile.

### Option C – Implement independent track-cut detection in `near`

Use existing AC API data already collected in `acUpdate()`:
- `ac.getCarState(index, acsys.CS.NormalizedSplinePosition)` – detects when a car leaves the valid track spline
- `ac.getCarState(index, acsys.CS.LapTime)` – detects invalid laps (AC marks cut laps)
- `ac.isCarInPit(index)` / `ac.isCarInPitline(index)` – excludes pit activity

`near` would maintain its own per-car cut counter, independent of Real Penalty. This would not match Real Penalty's server-side counts exactly (different detection algorithm, thresholds unknown), but would provide a reasonable approximation.

**Pros:** Self-contained, works offline and online without Real Penalty.
**Cons:** Cannot show max allowed cuts or penalty type (server config values); count may differ from Real Penalty's.

### Option D – Named shared memory (Windows mmap)

If Real Penalty (or a future version) creates a named Windows shared memory region (e.g. `CreateFileMapping("acpmf_realpenalty")`), `near` could map it with `mmap.mmap(0, size, "acpmf_realpenalty")`. No such region was found in the current binary.

**Pros:** Real-time, low-overhead.
**Cons:** Not implemented by Real Penalty today; would require author cooperation.

---

## Recommendation

**Short term:** Pursue **Option A** – contact the Real Penalty author to request a file-based export (JSON written each update cycle) with fields like `car_index`, `cuts`, `max_cuts`, `penalty`. This is the only way to get authoritative server-side data.

**If Option A is blocked:** Use **Option C** as a best-effort approximation for cut detection, and omit max-allowed-cuts and penalty-type fields (those require server config data).

---

## References

- `Real Penalty - App - v.1.05.01/apps/python/RealPenalty/RealPenalty.py` – entry point
- `Real Penalty - App - v.1.05.01/apps/python/RealPenalty/utilities/Lib64/wrapper.pyd` – main logic (compiled Cython)
- `Real Penalty - App - v.1.05.01/apps/python/RealPenalty/utilities/Lib64/ac_sim_info.pyd` – AC shared memory reader
- `apps/python/near/near_lib/sim_info.py` – near's existing mmap implementation
- `apps/python/near/near.py` – near's AC API usage patterns
