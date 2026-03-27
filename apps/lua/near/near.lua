-- Near for Assetto Corsa (CSP Lua)
-- Displays the driver immediately ahead and behind in standings,
-- with lap times, gap, and nation flags.
--
-- Globals: ac, ui, render, sim, car, etc. are injected by the CSP runtime
-- before this script runs — no require/import needed. They are the Lua
-- equivalent of the Python `ac` and `acsys` modules in the old plugin system.
-- Install the acc-lua-sdk VSCode extension for autocomplete and inline docs.

-- ─── Config defaults ──────────────────────────────────────────────────────────
-- Persisted automatically by ac.storage; edit defaults here for first run.
local cfg = ac.storage({
  updateTime   = 300,     -- refresh interval in ms
  showLogo     = false,
  showTitle    = false,
  showBorder   = true,
  showBadge    = false,
  opacity      = 50,      -- 0–100
  zoom         = 1.2,
  padding      = 10,
  hspace       = 0,       -- horizontal spacing between columns
  fontSizeName = 12,
  fontSizeTitle = 8,
  fontSizeTime = 16,
  fontSizeGap  = 28,
  colorAt      = 250,     -- distance threshold in meters for gap color
  unit         = "time",  -- "metric" | "imperial" | "time"
  configIndex  = 1,       -- active preset index
})

-- ─── Runtime state ────────────────────────────────────────────────────────────
local sim             = ac.getSim()
local trackLength     = ac.getTrackLength()
local fastestLapMs    = 9999999
local timeSinceUpdate = 0

-- Nation flag path helper.
-- Reuses the flags already shipped with AC at content/gui/NationFlags/{CODE}.png
-- (uppercase 3-letter ISO, e.g. "ITA"), so no file copy into res/ is needed.
-- ac.getFolder(ac.FolderID.Root) returns the AC installation root at runtime.
local acRoot = ac.getFolder(ac.FolderID.Root)
local function flagPath(nationCode)
  return acRoot .. "/content/gui/NationFlags/" .. nationCode .. ".png"
end

-- Snapshots resolved each update cycle, consumed by script.windowMain.
-- Fields: carIndex, driverName, nationCode, bestLapMs, lastLapMs, lapTimeMs,
--         splinePos, lapCount, distance, speedMs, pitStops, isInPit
local driverAhead  = nil   -- driver immediately ahead of player in standings
local driverBehind = nil   -- driver immediately behind player in standings
local playerEntry  = nil   -- player's own snapshot (for gap/delta reference)

-- Per-car race-start spline correction state, keyed by car index.
-- Initialised lazily in updateStandings so late-joining cars are handled.
-- { raceStartFlag: bool } — true until the car has clearly crossed the start line
local pitState = {}

-- ─── Colors ───────────────────────────────────────────────────────────────────

local COL_GREY   = rgbm(0.555, 0.555, 0.555, 1)  -- invalid / no data
local COL_PURPLE = rgbm(0.8,   0,     1,     1)   -- fastest overall
local COL_GREEN  = rgbm(0,     1,     0,     1)   -- personal best / faster
local COL_RED    = rgbm(1,     0,     0,     1)   -- slower
local COL_WHITE  = rgbm(1,     1,     1,     1)   -- normal
local COL_LABEL  = rgbm(0.314, 0.337, 0.369, 1)   -- "BEST" / "LAST" title text

-- ─── Helpers ──────────────────────────────────────────────────────────────────

-- Format milliseconds to "M:SS.mmm" string.
-- Returns (str, color): purple = fastest overall, green = personal best,
-- white = normal, grey = invalid.
local function timeToLabel(ms, personalBestMs)
  if ms <= 0 or ms == 9999999 then
    return "-:--.---", COL_GREY
  end
  local color
  if ms <= fastestLapMs then
    color = COL_PURPLE
  elseif personalBestMs and ms <= personalBestMs then
    color = COL_GREEN
  else
    color = COL_WHITE
  end
  local m   = math.floor(ms / 60000)
  local s   = math.floor((ms % 60000) / 1000)
  local mil = ms % 1000
  return string.format("%d:%02d.%03d", m, s, mil), color
end

-- Compute signed lap time delta between two drivers (ms1 − ms2).
-- Returns (str, color) or nil if either time is invalid.
-- Positive = ms1 is slower (red); negative = faster (green).
local function deltaTimeToLabel(ms1, ms2)
  if ms1 <= 0 or ms1 == 9999999 or ms2 <= 0 or ms2 == 9999999 then return nil end
  local delta = ms1 - ms2
  if delta == 0 then return nil end
  return string.format("(%+.1f)", delta / 1000), delta > 0 and COL_RED or COL_GREEN
end

-- Convert a normalized spline-position delta to a gap string.
-- cfg.unit: "metric" → metres, "imperial" → ft/mi, "time" → seconds.
local function deltaToLabel(delta, speedAvgMs)
  if delta > 100 then delta = 0 end
  local distance = delta * trackLength
  if delta > -1 and delta < 1 and trackLength > 0 then
    if cfg.unit == "metric" then
      return string.format("%+.0f m", distance)
    elseif cfg.unit == "imperial" then
      if distance < 1609 then
        return string.format("%+.0f ft", distance * 3.28)
      else
        return string.format("%+.1f mi", distance / 1609)
      end
    else  -- "time"
      local spd = math.max(speedAvgMs, 15)
      return string.format("%+.1f s", -distance / spd)
    end
  elseif delta > -2 and delta < 2 then
    return string.format("%+.1f lap", delta)
  else
    return string.format("%+.1f laps", delta)
  end
end

-- Draw a single driver row (ahead or behind the player).
-- Layout (two groups side by side):
--
--   LEFT group                        RIGHT group
--   [pos]  [flag]  [Driver Name]      [GAP  large]
--          LAST  1:23.456  (+0.3)
--          BEST  1:22.123  (-0.1)
--
-- entry     — snapshot table from updateStandings (nil = player is at boundary)
-- playerEnt — player snapshot for delta/gap reference
-- isRace    — true when session type is Race
local function drawDriverRow(entry, playerEnt, isRace)
  local z       = cfg.zoom
  local flagH   = math.floor(cfg.fontSizeName * z)
  local flagW   = math.floor(flagH * 1.5)

  -- ── Left group: position + flag + name + lap times ────────────────────────
  ui.beginGroup()

  if entry == nil then
    -- Player is first (no one ahead) or last (no one behind) in a race
    ui.pushFont(ui.Font.Small)
    ui.pushStyleColor(ui.Col.Text, COL_GREY)
    ui.text("-.")
    ui.sameLine(0, 4 * z)
    ui.dummy(vec2(flagW, flagH))
    ui.sameLine(0, 4 * z)
    ui.text("---")
    ui.popStyleColor()
    ui.popFont()

    ui.pushFont(ui.Font.Tiny)
    ui.pushStyleColor(ui.Col.Text, COL_LABEL) ui.text("LAST") ui.popStyleColor()
    ui.popFont()
    ui.sameLine(0, 4)
    ui.pushFont(ui.Font.Small)
    ui.pushStyleColor(ui.Col.Text, COL_GREY) ui.text("-:--.---") ui.popStyleColor()
    ui.popFont()

    ui.pushFont(ui.Font.Tiny)
    ui.pushStyleColor(ui.Col.Text, COL_LABEL) ui.text("BEST") ui.popStyleColor()
    ui.popFont()
    ui.sameLine(0, 4)
    ui.pushFont(ui.Font.Small)
    ui.pushStyleColor(ui.Col.Text, COL_GREY) ui.text("-:--.---") ui.popStyleColor()
    ui.popFont()
  else
    -- Position number
    ui.pushFont(ui.Font.Small)
    ui.text(string.format("%d.", entry.racePos or 0))
    ui.sameLine(0, 4 * z)
    -- Nation flag — references AC's own NationFlags directory via absolute path.
    -- CSP handles async texture load; first frame may show nothing.
    -- No getNationTexture() cache needed — CSP caches internally.
    ui.image(flagPath(entry.nationCode), vec2(flagW, flagH))
    ui.sameLine(0, 4 * z)
    ui.text(entry.driverName)
    ui.popFont()

    -- LAST lap row
    local lastStr, lastCol = timeToLabel(entry.lastLapMs, entry.bestLapMs)
    ui.pushFont(ui.Font.Tiny)
    ui.pushStyleColor(ui.Col.Text, COL_LABEL) ui.text("LAST") ui.popStyleColor()
    ui.popFont()
    ui.sameLine(0, 4)
    ui.pushFont(ui.Font.Small)
    ui.pushStyleColor(ui.Col.Text, lastCol) ui.text(lastStr) ui.popStyleColor()
    local ldStr, ldCol = deltaTimeToLabel(entry.lastLapMs, playerEnt.lastLapMs)
    if ldStr then
      ui.sameLine(0, 4)
      ui.pushStyleColor(ui.Col.Text, ldCol) ui.text(ldStr) ui.popStyleColor()
    end
    ui.popFont()

    -- BEST lap row
    local bestStr, bestCol = timeToLabel(entry.bestLapMs, entry.bestLapMs)
    ui.pushFont(ui.Font.Tiny)
    ui.pushStyleColor(ui.Col.Text, COL_LABEL) ui.text("BEST") ui.popStyleColor()
    ui.popFont()
    ui.sameLine(0, 4)
    ui.pushFont(ui.Font.Small)
    ui.pushStyleColor(ui.Col.Text, bestCol) ui.text(bestStr) ui.popStyleColor()
    local bdStr, bdCol = deltaTimeToLabel(entry.bestLapMs, playerEnt.bestLapMs)
    if bdStr then
      ui.sameLine(0, 4)
      ui.pushStyleColor(ui.Col.Text, bdCol) ui.text(bdStr) ui.popStyleColor()
    end
    ui.popFont()
  end

  ui.endGroup()

  -- ── Right group: gap (large, vertically centered) ─────────────────────────
  ui.sameLine(0, cfg.hspace * z)
  ui.beginGroup()

  if entry ~= nil then
    local gapDelta = isRace
      and (entry.distance  - playerEnt.distance)
      or  (entry.splinePos - playerEnt.splinePos)
    local gapStr = deltaToLabel(gapDelta, (entry.speedMs + playerEnt.speedMs) / 2)
    if gapStr then
      -- Offset down to vertically center the large gap text within the row height.
      -- Row height ≈ nameRow + 2 × timeRow; gap font is ~2× name font.
      ui.offsetCursorY(flagH * 0.5)
      ui.pushFont(ui.Font.Huge)
      ui.text(gapStr)
      ui.popFont()
    end
  else
    ui.pushFont(ui.Font.Huge)
    ui.pushStyleColor(ui.Col.Text, COL_GREY) ui.text("---") ui.popStyleColor()
    ui.popFont()
  end

  ui.endGroup()
end

-- ─── Preset helpers ───────────────────────────────────────────────────────────
-- Presets are stored as flat keys in ac.storage: "p{n}_{field}".
-- This mirrors Python's numbered INI sections [1], [2], etc.

local PRESET_FIELDS = {
  "updateTime", "showLogo", "showTitle", "showBorder", "showBadge",
  "opacity", "zoom", "padding", "hspace",
  "fontSizeName", "fontSizeTitle", "fontSizeTime", "fontSizeGap",
  "colorAt", "unit",
}

local function savePreset(idx)
  for _, k in ipairs(PRESET_FIELDS) do
    ac.storage["p" .. idx .. "_" .. k] = cfg[k]
  end
end

-- Load a preset into cfg. Falls back to current cfg value if no stored value
-- exists yet (e.g. first time a new preset index is used).
local function loadPreset(idx)
  for _, k in ipairs(PRESET_FIELDS) do
    local v = ac.storage["p" .. idx .. "_" .. k]
    if v ~= nil then cfg[k] = v end
  end
end

-- ─── Update logic ─────────────────────────────────────────────────────────────

-- Snapshot of one driver's data captured during updateStandings.
local function makeEntry(car, distance)
  return {
    carIndex   = car.index,
    driverName = car:driverName(),       -- ac.StateCar method call (CSP FFI)
    nationCode = car:driverNationCode(), -- 3-letter ISO, e.g. "ITA"
    bestLapMs  = car.bestLapTimeMs,      -- replaces ac.getCarState(i, acsys.CS.BestLap)
    lastLapMs  = car.lastLapTimeMs,      -- replaces ac.getCarState(i, acsys.CS.LastLap)
    lapTimeMs  = car.lapTimeMs,          -- replaces ac.getCarState(i, acsys.CS.LapTime)
    splinePos  = car.splinePosition,     -- replaces acsys.CS.NormalizedSplinePosition
    lapCount   = car.lapCount,           -- replaces acsys.CS.LapCount
    distance   = distance,               -- lapCount + splinePos (corrected at race start)
    speedMs    = car.speedKmh / 3.6,    -- replaces acsys.CS.SpeedMS
    pitStops   = car.pitCount,           -- native CSP field; replaces manual pit entry/exit tracking
    isInPit    = car.isInPit,            -- replaces ac.isCarInPit(i)
  }
end

-- Iterates the CSP-sorted leaderboard, builds snapshots, and resolves the
-- driver immediately ahead and behind the player (car index 0).
--
-- Replaces Python's acUpdate sort logic:
--   - ac.iterateCars.leaderboard() already sorts by distance in race and by
--     best lap time in practice/qualify — no manual sort needed.
--   - All car data comes from ac.StateCar FFI fields — no sim_info.py needed.
local function updateStandings()
  local session = ac.getSession(sim.currentSessionIndex)
  local isRace  = session ~= nil and session.type == ac.SessionType.Race

  local leaderboard  = {}
  local playerPosIdx = -1   -- 1-based index of the player inside leaderboard[]

  for _, car in ac.iterateCars.leaderboard() do
    if not car.isConnected then goto continue end

    -- Track session-wide fastest lap (used for purple colour in timeToLabel)
    local best = car.bestLapTimeMs
    if best > 0 and best < 9999999 and best < fastestLapMs then
      fastestLapMs = best
    end

    -- Race start spline correction (port of Python raceStartFlag logic):
    -- At lap 0, a car just past the start line has splinePosition > 0.7,
    -- which would incorrectly rank it behind cars at ~0.1 on the next lap.
    -- Subtracting 1 normalises its effective distance until it clears the zone.
    local distance = car.lapCount + car.splinePosition
    if isRace then
      if not pitState[car.index] then
        pitState[car.index] = { raceStartFlag = true }
      end
      local ps = pitState[car.index]
      if ps.raceStartFlag and car.lapCount == 0 then
        if car.splinePosition > 0.7 then
          distance = distance - 1.0
        elseif car.splinePosition > 0.3 then
          ps.raceStartFlag = false
        end
      else
        ps.raceStartFlag = false
      end
    else
      -- Reset each non-race session so the flag is ready for the next race
      if pitState[car.index] then
        pitState[car.index].raceStartFlag = true
      end
    end

    local entry = makeEntry(car, distance)
    table.insert(leaderboard, entry)

    if car.index == 0 then
      playerPosIdx = #leaderboard
      playerEntry  = entry
    end

    ::continue::
  end

  -- Pick the adjacent entries in sorted order
  driverAhead  = (playerPosIdx > 1)            and leaderboard[playerPosIdx - 1] or nil
  driverBehind = (playerPosIdx < #leaderboard) and leaderboard[playerPosIdx + 1] or nil
end

-- ─── Script entry points ──────────────────────────────────────────────────────

-- Called every graphics frame. Throttled internally to cfg.updateTime.
function script.update(dt)
  timeSinceUpdate = timeSinceUpdate + dt * 1000 -- convert to ms
  if timeSinceUpdate < cfg.updateTime then return end
  timeSinceUpdate = 0

  updateStandings()
end

-- Draws the main HUD window. Called every frame by CSP (immediate-mode).
-- Replaces NearWindow.updateView() — no retained widgets, no ac.setText calls.
function script.windowMain(dt)
  if playerEntry == nil then
    ui.pushStyleColor(ui.Col.Text, COL_GREY)
    ui.text("Waiting for session data...")
    ui.popStyleColor()
    return
  end

  -- Apply opacity from config (equivalent to ac.setBackgroundOpacity)
  ui.pushStyleVar(ui.StyleVar.Alpha, cfg.opacity / 100)

  local session = ac.getSession(sim.currentSessionIndex)
  local isRace  = session ~= nil and session.type == ac.SessionType.Race

  -- In race: wrap around (first has no one ahead, last has no one behind).
  -- In practice/qualify: there is always a driver to show (sorted by best lap).
  drawDriverRow(driverAhead,  playerEntry, isRace)

  ui.separator()

  drawDriverRow(driverBehind, playerEntry, isRace)

  ui.popStyleVar()
end

-- Draws the settings panel (opened via the gear icon in the window header).
-- Replaces Near_config class + all individual toggle/plus/minus callbacks.
-- ac.storage auto-persists cfg values; no explicit save call needed.
function script.windowSettings()
  local w = 180   -- slider width in pixels

  -- ── Preset selector ────────────────────────────────────────────────────────
  -- Saves current cfg into the active preset slot, then switches and loads.
  ui.text("Preset:")
  ui.sameLine(0, 8)
  if ui.button(" < ") and cfg.configIndex > 1 then
    savePreset(cfg.configIndex)
    cfg.configIndex = cfg.configIndex - 1
    loadPreset(cfg.configIndex)
  end
  ui.sameLine(0, 6)
  ui.text(tostring(cfg.configIndex))
  ui.sameLine(0, 6)
  if ui.button(" > ") then
    savePreset(cfg.configIndex)
    cfg.configIndex = cfg.configIndex + 1
    loadPreset(cfg.configIndex)
  end

  ui.separator()

  -- ── Visibility toggles (replaces toggleLogo/toggleTitle/toggleBorder) ─────
  cfg.showLogo   = ui.checkbox("Show logo",   cfg.showLogo)
  cfg.showTitle  = ui.checkbox("Show title",  cfg.showTitle)
  cfg.showBorder = ui.checkbox("Show border", cfg.showBorder)
  cfg.showBadge  = ui.checkbox("Show badge",  cfg.showBadge)

  ui.separator()

  -- ── Numeric sliders ────────────────────────────────────────────────────────
  -- ui.itemEdited() returns true only on the frame the user releases/commits,
  -- avoiding constant writes to storage while dragging.
  local v
  ui.setNextItemWidth(w)
  v = ui.slider("Opacity",   cfg.opacity,    0,   100,  "%.0f %%")
  if ui.itemEdited() then cfg.opacity    = math.floor(v) end

  ui.setNextItemWidth(w)
  v = ui.slider("Zoom",      cfg.zoom,       0.5, 3.0,  "x %.2f")
  if ui.itemEdited() then cfg.zoom       = v end

  ui.setNextItemWidth(w)
  v = ui.slider("Padding",   cfg.padding,    0,   40,   "%.0f px")
  if ui.itemEdited() then cfg.padding    = math.floor(v) end

  ui.setNextItemWidth(w)
  v = ui.slider("H-Spacing", cfg.hspace,     0,   150,  "%.0f px")
  if ui.itemEdited() then cfg.hspace     = math.floor(v) end

  ui.setNextItemWidth(w)
  v = ui.slider("Color at",  cfg.colorAt,    0,   2000, "%.0f m")
  if ui.itemEdited() then cfg.colorAt    = math.floor(v) end

  ui.setNextItemWidth(w)
  v = ui.slider("Refresh",   cfg.updateTime, 50,  1000, "%.0f ms")
  if ui.itemEdited() then cfg.updateTime = math.floor(v) end

  ui.separator()

  -- ── Font sizes ─────────────────────────────────────────────────────────────
  ui.setNextItemWidth(w)
  v = ui.slider("Font: name",  cfg.fontSizeName,  6,  32, "%.0f")
  if ui.itemEdited() then cfg.fontSizeName  = math.floor(v) end

  ui.setNextItemWidth(w)
  v = ui.slider("Font: title", cfg.fontSizeTitle, 6,  24, "%.0f")
  if ui.itemEdited() then cfg.fontSizeTitle = math.floor(v) end

  ui.setNextItemWidth(w)
  v = ui.slider("Font: time",  cfg.fontSizeTime,  8,  40, "%.0f")
  if ui.itemEdited() then cfg.fontSizeTime  = math.floor(v) end

  ui.setNextItemWidth(w)
  v = ui.slider("Font: gap",   cfg.fontSizeGap,   12, 60, "%.0f")
  if ui.itemEdited() then cfg.fontSizeGap   = math.floor(v) end

  ui.separator()

  -- ── Gap unit cycle (replaces toggleUnits callback) ─────────────────────────
  local unitLabel = { metric = "Metric", imperial = "Imperial", time = "Time (est.)" }
  local unitCycle = { metric = "imperial", imperial = "time", time = "metric" }
  ui.text("Gap unit:")
  ui.sameLine(0, 8)
  if ui.button(unitLabel[cfg.unit] or cfg.unit) then
    cfg.unit = unitCycle[cfg.unit] or "metric"
  end
end
