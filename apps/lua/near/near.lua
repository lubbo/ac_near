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
local cfg             = ac.storage({
  updateTime    = 300, -- refresh interval in ms
  zoom          = 1.2,
  hspace        = 0,  -- horizontal spacing between columns
  fontSizeName  = 12,
  fontSizeTitle = 8,
  fontSizeTime  = 16,
  fontSizeGap   = 28,
  configIndex   = 1, -- active preset index
})

-- ─── Runtime state ────────────────────────────────────────────────────────────
local sim              = ac.getSim()
local fastestLapMs     = 9999999
local lastSessionIndex = -1 -- keeps fastestLapMs scoped to the current session
local timeSinceUpdate  = 0

-- Nation flag path helper.
-- Reuses the flags already shipped with AC at content/gui/NationFlags/{CODE}.png
-- (uppercase 3-letter ISO, e.g. "ITA"), so no file copy into res/ is needed.
-- ac.getFolder(ac.FolderID.Root) returns the AC installation root at runtime.
local acRoot          = ac.getFolder(ac.FolderID.Root)
local function flagPath(nationCode)
  return nationCode ~= nil and acRoot .. "/content/gui/NationFlags/" .. nationCode .. ".png" or nil
end

-- Snapshots resolved each update cycle, consumed by script.windowMain.
-- Fields: carIndex, driverName, nationCode, bestLapMs, lastLapMs, lapTimeMs,
--         splinePos, lapCount, pitStops, isInPit
local driverAhead  = nil -- driver immediately ahead of player in standings
local driverBehind = nil -- driver immediately behind player in standings
local playerEntry  = nil -- player's own snapshot (for gap/delta reference)

-- Per-car race-start spline correction state, keyed by car index.
-- Initialised lazily in updateStandings so late-joining cars are handled.
-- { raceStartFlag: bool } — true until the car has clearly crossed the start line
local pitState     = {}

-- ─── Colors ───────────────────────────────────────────────────────────────────

local COL_GREY     = rgbm(0.555, 0.555, 0.555, 1) -- invalid / no data
local COL_PURPLE   = rgbm(0.8, 0, 1, 1)         -- fastest overall
local COL_GREEN    = rgbm(0, 1, 0, 1)           -- personal best / faster
local COL_RED      = rgbm(1, 0, 0, 1)           -- slower
local COL_WHITE    = rgbm(1, 1, 1, 1)           -- normal
local COL_LABEL    = rgbm(0.314, 0.337, 0.369, 1) -- "BEST" / "LAST" title text

-- ─── Helpers ──────────────────────────────────────────────────────────────────

-- Format milliseconds to "M:SS.mmm" string.
-- Returns (str, color): purple = fastest overall, green = personal best,
-- white = normal, grey = invalid.
local function timeToLabel(ms, personalBestMs)
  if ms == nil or ms <= 0 or ms == 9999999 then
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

  return ac.lapTimeToString(ms, true), color
  -- local m   = math.floor(ms / 60000)
  -- local s   = math.floor((ms % 60000) / 1000)
  -- local mil = ms % 1000
  -- return string.format("%d:%02d.%03d", m, s, mil), color
end

-- Compute signed lap time delta between two drivers (ms1 − ms2).
-- Always returns (str, color): empty string + grey when unavailable, empty
-- string + white when equal. Positive = ms1 slower (red), negative = faster (green).
-- Positive = ms1 is slower (red); negative = faster (green).
local function deltaTimeToLabel(ms1, ms2)
  if ms1 == nil or ms2 == nil or ms1 <= 0 or ms1 == 9999999 or ms2 <= 0 or ms2 == 9999999 then return "", COL_GREY end
  local delta = ms1 - ms2
  if delta == 0 then return "", COL_WHITE end
  return string.format("(%+.1f)", delta / 1000), delta > 0 and COL_RED or COL_GREEN
end

-- Returns the time gap between two cars as a formatted string (e.g. "+2.3 s").
-- Uses ac.getGapBetweenCars(playerIdx, otherIdx) which returns seconds directly.
-- Returns nil if the gap is unavailable (e.g. no completed lap yet — returns math.huge).
local function deltaToLabel(playerEnt, entry)
  if entry == nil or playerEnt == nil then return nil end

  local session     = ac.getSession(sim.currentSessionIndex)
  local isRace      = session ~= nil and session.type == ac.SessionType.Race

  local delta       = isRace
      and ((entry.lapCount or entry.sessionLapCount) + entry.splinePos - ((playerEnt.lapCount or playerEnt.sessionLapCount) + playerEnt.splinePos))
      or (entry.splinePos - playerEnt.splinePos)

  local trackLength = ac.getSim().trackLengthM
  local speedAvgMs  = (entry.speedMs + playerEnt.speedMs) / 2
  if delta > 100 then delta = 0 end
  local distance = delta * trackLength
  if delta > -1 and delta < 1 and trackLength > 0 then
    local spd = math.max(speedAvgMs, 15)
    return string.format("%+.1f s", -distance / spd)
  elseif delta > -2 and delta < 2 then
    return string.format("%+.1f lap", delta)
  else
    return string.format("%+.1f laps", delta)
  end

  -- local gap = ac.getGapBetweenCars(entry.idx,playerEnt.idx)
  -- if gap == nil then return "-" end
  -- return string.format("%+.1f s", gap)
end

-- local placeholderLast  = '--:--.---'
-- local placeholderBest  = '--:--.---'
-- local placeholderGap   = '+ --.-- s'

local function computeScaleForWindow()
  local sz = ui.windowSize()
  local sx = sz.x / 200
  local sy = sz.y / 300

  -- Use the smaller axis so text always fits.
  -- Optionally clamp to avoid insane sizes.
  local s = math.min(sx, sy, 2.0)

  return s
end

local function prepareLayout(entry, playerEnt)
  ui.pushDWriteFont('@System')

  local otherDriver = entry or {}

  local zoom                      = cfg.zoom
  local horizontalSpacer          = 4 * zoom
  local nameFontSize              = cfg.fontSizeName * zoom
  local titleFontSize             = cfg.fontSizeTitle * zoom
  local timeFontSize              = cfg.fontSizeTime * zoom
  local gapFontSize               = cfg.fontSizeGap * zoom

  local name                      = otherDriver.driverName or ""
  local position                  = otherDriver.racePosition ~= nil and string.format("%d.", otherDriver.racePosition or 0) or "-."
  local best, bestColor           = timeToLabel(otherDriver.bestLapMs, otherDriver.bestLapMs)
  local bestDelta, bestDeltaColor = deltaTimeToLabel(playerEnt.bestLapMs, otherDriver.bestLapMs)
  local last, lastColor           = timeToLabel(otherDriver.lastLapMs, otherDriver.bestLapMs)
  local lastDelta, lastDeltaColor = deltaTimeToLabel(playerEnt.lastLapMs, otherDriver.lastLapMs)

  local gap                       = deltaToLabel(playerEnt, entry)
  local gapColor                  = COL_WHITE
  local positionSize              = ui.measureDWriteText(position, nameFontSize)
  local nameSize                  = ui.measureDWriteText(name, nameFontSize)
  local flagSize                  = vec2(math.floor(nameSize.y), math.floor(math.floor(nameSize.y) * 1.2))
  local driverSize                = vec2(nameSize.x + positionSize.x + horizontalSpacer * 2 + flagSize.x, nameSize.y)

  local titleSize                 = ui.measureDWriteText("BEST", titleFontSize)

  local bestSize                  = ui.measureDWriteText(best, timeFontSize)
  local bestDeltaSize             = ui.measureDWriteText(bestDelta, timeFontSize)
  local bestLineSize              = vec2(bestSize.x + horizontalSpacer + bestDeltaSize.x,
    math.max(bestSize.y, bestDeltaSize.y))

  local lastSize                  = ui.measureDWriteText(last, timeFontSize)
  local lastDeltaSize             = ui.measureDWriteText(lastDelta, timeFontSize)
  local lastLineSize              = vec2(lastSize.x + horizontalSpacer + lastDeltaSize.x,
    math.max(lastSize.y, lastDeltaSize.y))

  local leftSectionSize           = vec2(
    math.max(titleSize.x, bestLineSize.x, lastLineSize.x),
    titleSize.y + bestLineSize.y + titleSize.y + lastLineSize.y)

  ui.popDWriteFont()

  local result = {
    zoom = zoom,
    horizontalSpacer = horizontalSpacer,
    name = name,
    position = position,
    flagPath = flagPath(otherDriver.nationCode),
    flagSize = flagSize,
    best = best,
    bestColor = bestColor,
    bestDelta = bestDelta,
    bestDeltaColor = bestDeltaColor,
    last = last,
    lastColor = lastColor,
    lastDelta = lastDelta,
    lastDeltaColor = lastDeltaColor,
    gap = gap,
    gapColor = gapColor,


    nameFontSize = nameFontSize,
    titleFontSize = titleFontSize,
    timeFontSize = timeFontSize,
    gapFontSize = gapFontSize,

    titleSize = titleSize,
    driverSize = driverSize,
    leftSectionSize = leftSectionSize
  }

  return result
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
local function drawDriverRow(layout, previousLayout)
  ui.pushDWriteFont('@System')

  -- ── Left group: position + flag + name + lap times ────────────────────────
  ui.beginGroup()

  ui.dwriteText(layout.position, layout.nameFontSize, COL_WHITE)
  ui.sameLine(0, layout.horizontalSpacer)
  ui.image(layout.flagPath, layout.flagSize)
  ui.sameLine(0, layout.horizontalSpacer)
  ui.dwriteText(layout.name, layout.nameFontSize, COL_WHITE)

  -- LAST lap row
  ui.dwriteText("LAST", layout.titleFontSize, COL_LABEL)
  ui.dwriteText(layout.last, layout.timeFontSize, layout.lastColor)
  if layout.lastDelta ~= nil and layout.lastDelta ~= "" then
    ui.sameLine(0, layout.horizontalSpacer)
    ui.dwriteText(layout.lastDelta, layout.timeFontSize, layout.lastDeltaColor)
  end

  -- BEST lap row
  ui.dwriteText("BEST", layout.titleFontSize, COL_LABEL)
  ui.dwriteText(layout.best, layout.timeFontSize, layout.bestColor)
  if layout.bestDelta ~= nil and layout.bestDelta ~= "" then
    ui.sameLine(0, layout.horizontalSpacer)
    ui.dwriteText(layout.bestDelta, layout.timeFontSize, layout.bestDeltaColor)
  end

  ui.endGroup()

  local maxLeftSectionWitdh = previousLayout.leftSectionSize ~= nil and
  math.max(previousLayout.leftSectionSize.x, layout.leftSectionSize.x) or layout.leftSectionSize.x
  ui.sameLine(maxLeftSectionWitdh, cfg.hspace * layout.zoom)
  local gapText = layout.gap or "-"
  local maxGapSizeWidth = previousLayout.gap ~= nil and
  math.max(ui.measureDWriteText(previousLayout.gap, previousLayout.gapFontSize).x,
    ui.measureDWriteText(gapText, layout.gapFontSize).x) or ui.measureDWriteText(gapText, layout.gapFontSize).x

  ui.beginGroup()
  ui.offsetCursorY(layout.titleSize.y * 2)

  ui.dwriteTextAligned(
    gapText,
    layout.gapFontSize,
    ui.Alignment.End,
    ui.Alignment.Center,
    vec2(maxGapSizeWidth, layout.leftSectionSize.y),
    false,
    layout.gap ~= nil and layout.gapColor or COL_GREY
  )

  ui.endGroup()

  ui.popDWriteFont()
end


-- ─── Preset helpers ───────────────────────────────────────────────────────────
-- Presets are stored as flat keys in ac.storage: "p{n}_{field}".
-- This mirrors Python's numbered INI sections [1], [2], etc.

local PRESET_FIELDS = {
  "updateTime",
  "zoom", "hspace",
  "fontSizeName", "fontSizeTitle", "fontSizeTime", "fontSizeGap",
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
local function makeEntry(car)
  -- ac.log("p",car.index, car.racePosition, car:driverName())
  return {
    carIndex                          = car.index,
    racePosition                      = car.racePosition,
    driverName                        = car:driverName(),                      -- ac.StateCar method call (CSP FFI)
    nationCode                        = car:driverNationCode(),                -- 3-letter ISO, e.g. "ITA"
    bestLapMs                         = car.bestLapTimeMs,                     -- replaces ac.getCarState(i, acsys.CS.BestLap)
    lastLapMs                         = car.previousLapTimeMs,                 -- replaces ac.getCarState(i, acsys.CS.LastLap)
    lapTimeMs                         = car.lapTimeMs,                         -- replaces ac.getCarState(i, acsys.CS.LapTime)
    splinePos                         = car.splinePosition,                    -- replaces acsys.CS.NormalizedSplinePosition
    lapCount                          = car.lapCount or 0,                          -- replaces acsys.CS.LapCount
    sessionLapCount                   = car.sessionLapCount or 0,                          -- replaces acsys.CS.LapCount
    isInPit                           = car.isInPit,                           -- replaces ac.isCarInPit(i)
    estimatedLapTimeMs                = car.estimatedLapTimeMs,                -- integer @Based on best lap and performance meter (delta of this lap time vs best lap time).
    performanceMeter                  = car.performanceMeter,                  -- number @Performance meter comparing this lap with best, seconds.
    performanceMeterSpeedDifferenceMs = car.performanceMeterSpeedDifferenceMs, -- number @In AC performance app, there is that red/green bar, it shows this value.
    speedMs                           = car.speedMs,
  }
end

local function updateStandings()
  local session      = ac.getSession(sim.currentSessionIndex)
  local isRace       = session ~= nil and session.type == ac.SessionType.Race

  local leaderboard  = {}
  local playerPosIdx = -1 -- 1-based index of the player inside leaderboard[]

  -- Session-wide fastest lap (purple). Reset when the session changes, then
  -- recompute from every car — including cars in the pits — so the value can
  -- never go stale between practice / qualifying / race.
  local sessionIndex = sim.currentSessionIndex
  if sessionIndex ~= lastSessionIndex then
    fastestLapMs     = 9999999
    lastSessionIndex = sessionIndex
  end

  local cars = {}
  for _, car in ac.iterateCars.leaderboard() do
    cars[#cars + 1] = car
    local best = car.bestLapTimeMs
    if best ~= nil and best > 0 and best < 9999999 and best < fastestLapMs then
      fastestLapMs = best
    end
  end

  local filteredCars = table.filter(cars, function(a,_)
    return not a.isInPit
  end)

  
  table.sort(filteredCars, function(a, b)
    if isRace then
      return (a.lapCount or a.sessionLapCount) + a.splinePosition > (b.lapCount or b.sessionLapCount) + b.splinePosition
    else
      return a.splinePosition > b.splinePosition
    end
  end)
  
  for idx, car in ipairs(filteredCars) do
    if isRace then
      if not pitState[car.index] then
        pitState[car.index] = { raceStartFlag = true }
      end
      local ps = pitState[car.index]
      if ps.raceStartFlag and car.lapCount == 0 then
        if car.splinePosition > 0.3 then
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

    local entry = makeEntry(car)
    table.insert(leaderboard, entry)
    
    if car.index == 0 then
      playerPosIdx = idx
      playerEntry  = entry
    end
  end
  
  -- Pick the adjacent entries in sorted order
  driverAhead  = (playerPosIdx > 1) and leaderboard[playerPosIdx - 1] or nil
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
    ui.textColored("Waiting for session data...", COL_GREY)
    return
  end

  local aheadLayout = prepareLayout(driverAhead ~= nil and driverAhead or nil, playerEntry)
  local behindLayout = prepareLayout(driverBehind ~= nil and driverBehind or nil, playerEntry)

  drawDriverRow(aheadLayout ~= nil and aheadLayout or {}, {})

  ui.separator()

  drawDriverRow(behindLayout ~= nil and behindLayout or {}, aheadLayout)
end

-- Draws the settings panel (opened via the gear icon in the window header).
-- Replaces Near_config class + all individual toggle/plus/minus callbacks.
-- ac.storage auto-persists cfg values; no explicit save call needed.
function script.windowSettings()
  local w = 180 -- slider width in pixels

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
  ui.separator()

  local v, changed

  ui.setNextItemWidth(w)
  v, changed = ui.slider("Zoom", cfg.zoom, 0.5, 3.0, "x %.2f")
  if changed then cfg.zoom = v end

  ui.setNextItemWidth(w)
  v, changed = ui.slider("H-Spacing", cfg.hspace, 0, 150, "%.0f px")
  if changed then cfg.hspace = math.floor(v) end

  ui.setNextItemWidth(w)
  v, changed = ui.slider("Refresh", cfg.updateTime, 50, 1000, "%.0f ms")
  if changed then cfg.updateTime = math.floor(v) end

  ui.separator()

  -- ── Font sizes ─────────────────────────────────────────────────────────────
  ui.setNextItemWidth(w)
  v, changed = ui.slider("Font: name", cfg.fontSizeName, 6, 32, "%.0f")
  if changed then cfg.fontSizeName = math.floor(v) end

  ui.setNextItemWidth(w)
  v, changed = ui.slider("Font: title", cfg.fontSizeTitle, 6, 24, "%.0f")
  if changed then cfg.fontSizeTitle = math.floor(v) end

  ui.setNextItemWidth(w)
  v, changed = ui.slider("Font: time", cfg.fontSizeTime, 8, 40, "%.0f")
  if changed then cfg.fontSizeTime = math.floor(v) end

  ui.setNextItemWidth(w)
  v, changed = ui.slider("Font: gap", cfg.fontSizeGap, 12, 60, "%.0f")
  if changed then cfg.fontSizeGap = math.floor(v) end
end
