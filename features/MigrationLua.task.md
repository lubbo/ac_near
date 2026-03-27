# NEAR: Python → CSP Lua Migration Checklist

## General plan

- [ ] Don't modify python app
- [ ] Create lua script in a dedicated 'lua' directory, at the same level of 'python' directory 

## 1. Project Setup

- [X] Create `apps/lua/near/` directory (replaces `apps/python/near/`)
- [X] Create `manifest.ini` with `[ABOUT]`, `[CORE]`, `[WINDOW_0]` (main HUD), and `[WINDOW_1]` (config panel) sections
- [X] Set `FUNCTION_MAIN = windowMain` and `FUNCTION_SETTINGS = windowSettings` in `manifest.ini`
- [X] Create `near.lua` as the main script entry point
- [ ] Move flag assets to `apps/lua/near/res/flags/` (PNGs, referenced directly by path — no preloading needed)
- [X] Install the CSP VSCode Lua extension for autocomplete (`acc-lua-sdk` `.vsix`)

---

## 2. Lifecycle & Entry Points

- [X] Remove `acMain()` — replace initialization logic with plain Lua at script load time
- [X] Remove `acUpdate(deltaT)` — replace with `script.update(dt)` for per-frame logic
- [X] Replace `onRenderCallbackConfig(deltaT)` with `script.windowSettings()` rendered inside the same script
- [X] Replace `acMain` car count polling with `ac.getSim().carsCount` read in `script.update`

---

## 3. Car & Session Data

- [X] Replace `ac.getCarsCount()` → `ac.getSim().carsCount`
- [X] Replace `ac.getCarLeaderboardPosition(i)` → `ac.getCar(i).racePosition`
- [X] Replace `ac.getCarState(i, acsys.CS.SpeedKMH)` → `ac.getCar(i).speedKmh`
- [X] Replace `ac.getCarBestLap(i)` → `ac.getCar(i).bestLapTimeMs`
- [X] Replace `ac.getCarLastLap(i)` → `ac.getCar(i).lastLapTimeMs`
- [X] Replace `ac.getCarPitCount(i)` → `ac.getCar(i).pitCount`
- [X] Replace `ac.getDriverName(i)` → `ac.getCar(i):driverName()`
- [X] Replace `ac.getDriverNationCode(i)` → `ac.getCar(i):driverNationCode()`
- [X] Replace `sim_info.py` graphics session type → `ac.getSession(ac.getSim().currentSessionIndex)`; compare against `ac.SessionType.Race`, `.Practice`, `.Qualify`
- [X] Replace spline position from `sim_info` → `ac.getCar(i).splinePosition`
- [X] Replace `ac.getCarIsInPit(i)` / pit lane detection → `ac.getCar(i).isInPit` / `.isInPitlane`
- [X] Replace lap count tracking → `ac.getCar(i).lapCount`
- [X] Remove `sim_info.py` entirely — all physics/graphics data is available via `ac.getCar()` and `ac.getSim()` FFI structs

---

## 4. Standings Sort Logic

- [X] Remove manual sort by spline position for race — use `ac.getCar.leaderboard(n)` iterator which already returns cars in race order
- [X] Remove manual sort for practice/qualify — `ac.iterateCars.leaderboard()` sorts by best lap time automatically
- [X] Rewrite "find driver ahead / behind player" logic using the leaderboard iterator and `car.racePosition` to find player's position, then index ±1

---

## 5. UI Rendering (Major Rewrite)

The entire rendering model changes from retained-mode to immediate-mode.

- [X] Remove `NearWindow` class — there are no persistent label/widget objects
- [X] Remove all `ac.newLabel()`, `ac.setLabelText()`, `ac.setPosition()`, `ac.setSize()` calls
- [X] Rewrite `NearWindow.updateView()` as drawing calls inside `script.windowMain(dt)`:
  - [X] Driver name: `ui.text(name)` with `ui.pushStyleColor` for coloring
  - [X] Position badge: `ui.text("#" .. pos)` or `ui.drawRectFilled` + `ui.text`
  - [X] Nation flag: `ui.image("res/flags/" .. nationCode .. ".png", vec2(w, h))`
  - [X] Lap times: `ui.text(timeToLabel(ms))` with color applied via `ui.pushStyleColor`
  - [X] Gap: `ui.text(deltaToLabel(gap))`
  - [X] Layout: replace absolute x/y pixel placement with `ui.sameLine()`, `ui.offsetCursorX()`, `ui.setCursorY()`, and `ui.availableSpaceX()`
- [X] Replace `ac.drawBorder` / window border toggling → `ui.WindowFlags` or `ui.pushStyleVar(ui.StyleVar.WindowBorderSize, 0)`
- [X] Replace background opacity setting → `ui.pushStyleVar(ui.StyleVar.Alpha, opacity)` or window background color

---

## 6. Config UI (Major Rewrite)

- [X] Remove `Near_config` class
- [X] Rewrite config panel as `script.windowSettings()` function using immediate-mode widgets:
  - [X] Each row: `ui.text(label)` + `ui.sameLine()` + `ui.slider(...)` or `ui.button("+")` / `ui.button("-")`
  - [X] Boolean toggles: `ui.checkbox(label, value)` returning new bool
  - [X] Unit cycle: `ui.combo(...)` or three `ui.radioButton(...)` calls
  - [X] Config preset selector: `ui.combo("Config", previewName, ...)` or +/- buttons
- [X] Remove all individual toggle callbacks (`toggleLogo`, `toggleTitle`, etc.) — widget return values replace them
- [X] Remove `refreshAndSaveConfig()` / `refreshConfig()` — use `ac.storage({...})` table which auto-persists, or `ac.INIConfig` if keeping `.ini` format

---

## 7. Configuration Persistence

- [X] **Option A (recommended):** Replace `config.ini` + `ConfigParser` with `ac.storage({})` — implemented as `cfg = ac.storage({...})` at script load; all writes auto-persist
- [~] **Option B (keep INI format):** skipped — Option A chosen
- [X] Preserve multi-preset support: `cfg.configIndex` stored in `ac.storage`; per-preset values stored as `p{n}_{field}` keys via `savePreset()`/`loadPreset()` helpers

---

## 8. Time Formatting & Color Logic

- [X] Port `timeToLabel(ms)` to Lua — implemented with `string.format("%d:%02d.%03d", ...)` and purple/green/white/grey color returns
- [X] Port `deltaTimeToLabel(ms, bestMs)` color logic — returns `(str, color)` or `nil`; red/green via `COL_RED`/`COL_GREEN`; applied with `ui.pushStyleColor`/`ui.popStyleColor` in `drawDriverRow`
- [X] Port `deltaToLabel(gap, unit)` — metric/imperial/time branches ported; uses `cfg.unit` and `trackLength`
- [X] Define `rgbm` color constants — `COL_GREY`, `COL_PURPLE`, `COL_GREEN`, `COL_RED`, `COL_WHITE`, `COL_LABEL` defined at module level

---

## 9. Nation Flags

- [X] Remove `getNationTexture()` cache function — CSP handles async texture caching automatically
- [X] Replace `ac.drawTexture(texture, ...)` calls → `ui.image(flagPath(entry.nationCode), vec2(w, h))` via `flagPath()` helper
- [X] Copy flag PNGs — not needed: `flagPath()` resolves to `ac.getFolder(ac.FolderID.Root) .. "/content/gui/NationFlags/{CODE}.png"`, reusing AC's own flag files
- [X] Verify nation code format — `car:driverNationCode()` returns uppercase (e.g. "ITA"); AC files are uppercase; `:lower()` removed

---

## 10. Refresh Rate / Throttling

- [ ] Remove `updateTime` timer logic that throttled Python `acUpdate` — the Lua `script.update(dt)` is called every frame by default at low cost
- [ ] If throttling is still desired (e.g. for leaderboard sort to reduce churn), use a simple accumulator: `local t = 0; t = t + dt; if t > 0.3 then t = 0; -- sort -- end`
- [ ] Keep `updateTime` as a user-configurable setting if desired, but it's less necessary

---
