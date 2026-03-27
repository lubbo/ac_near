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

-- ─── Helpers ──────────────────────────────────────────────────────────────────

-- Format milliseconds to "M:SS.mmm" string.
-- Returns the formatted string and an rgbm color:
--   purple  = fastest overall, green = personal best, white = normal, grey = invalid
-- TODO: implement (port from Python timeToLabel)
local function timeToLabel(ms, personalBestMs)
  -- if ms <= 0 or ms == 9999999 then return "-:--.---", rgbm(0.555, 0.555, 0.555, 1) end
  -- local color
  -- if ms <= fastestLapMs      then color = rgbm(0.8, 0, 1, 1)   -- purple: fastest
  -- elseif ms <= personalBestMs then color = rgbm(0, 1, 0, 1)    -- green: personal best
  -- else                             color = rgbm(1, 1, 1, 1) end -- white: normal
  -- local m   = math.floor(ms / 60000)
  -- local s   = math.floor((ms % 60000) / 1000)
  -- local mil = ms % 1000
  -- return string.format("%d:%02d.%03d", m, s, mil), color
end

-- Compute the delta between two lap times and return a signed string and color.
-- Positive delta = time1 is slower (red); negative = faster (green).
-- TODO: implement (port from Python deltaTimeToLabel)
local function deltaTimeToLabel(ms1, ms2)
  -- if ms1 <= 0 or ms1 == 9999999 or ms2 <= 0 or ms2 == 9999999 then return "" end
  -- local delta = ms1 - ms2
  -- local color = delta > 0 and rgbm(1, 0, 0, 1) or rgbm(0, 1, 0, 1)
  -- if delta == 0 then return "" end
  -- return string.format("(%+.1f)", delta / 1000), color
end

-- Convert a spline-position delta to a human-readable gap string.
-- unit: "metric" → metres, "imperial" → ft/mi, "time" → seconds.
-- TODO: implement (port from Python deltaToLabel)
local function deltaToLabel(delta, speedAvgMs)
  -- if delta > 100 then delta = 0 end
  -- local distance = delta * trackLength
  -- if delta > -1 and delta < 1 and trackLength > 0 then
  --   if cfg.unit == "metric" then
  --     return string.format("%+.0f m", distance)
  --   elseif cfg.unit == "imperial" then
  --     if distance < 1609 then return string.format("%+.0f ft", distance * 3.28)
  --     else                     return string.format("%+.1f mi", distance / 1609) end
  --   elseif cfg.unit == "time" then
  --     local spd = math.max(speedAvgMs, 15)
  --     return string.format("%+.1f s", -distance / spd)
  --   end
  -- elseif delta > -2 and delta < 2 then
  --   return string.format("%+.1f lap", delta)
  -- else
  --   return string.format("%+.1f laps", delta)
  -- end
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

-- Draws the main HUD window. Called every frame by CSP.
-- TODO: implement — draw driverAhead and driverBehind panels side by side
function script.windowMain(dt)
  -- if driverAhead == nil and driverBehind == nil then
  --   ui.text("No data")
  --   return
  -- end

  -- Draw ahead driver row
  -- TODO: drawDriverRow(driverAhead, "▲")

  -- ui.separator()

  -- Draw behind driver row
  -- TODO: drawDriverRow(driverBehind, "▼")
end

-- Draws the settings panel (gear icon in window header).
-- TODO: implement — sliders/checkboxes for each cfg field, preset switcher
function script.windowSettings()
  -- local changed = false

  -- changed = ui.checkbox("Show border", cfg.showBorder) or changed
  -- changed = ui.checkbox("Show badge",  cfg.showBadge)  or changed
  -- changed = ui.checkbox("Show logo",   cfg.showLogo)   or changed
  -- changed = ui.checkbox("Show title",  cfg.showTitle)  or changed

  -- cfg.opacity      = ui.slider("Opacity",     cfg.opacity,      0,   100, "%.0f%%")
  -- cfg.zoom         = ui.slider("Zoom",        cfg.zoom,         0.5, 3.0, "%.1f")
  -- cfg.padding      = ui.slider("Padding",     cfg.padding,      0,   30,  "%.0f px")
  -- cfg.hspace       = ui.slider("H-Spacing",   cfg.hspace,       0,   100, "%.0f px")
  -- cfg.colorAt      = ui.slider("Color at",    cfg.colorAt,      0,   1000,"%.0f m")
  -- cfg.updateTime   = ui.slider("Refresh",     cfg.updateTime,   100, 1000,"%.0f ms")
  -- cfg.fontSizeName = ui.slider("Font: name",  cfg.fontSizeName, 8,   32,  "%.0f")
  -- cfg.fontSizeTime = ui.slider("Font: time",  cfg.fontSizeTime, 8,   32,  "%.0f")
  -- cfg.fontSizeGap  = ui.slider("Font: gap",   cfg.fontSizeGap,  8,   48,  "%.0f")

  -- Unit toggle
  -- TODO: ui.combo or radioButton for cfg.unit ("metric" / "imperial" / "time")

  -- Preset selector
  -- TODO: cfg.configIndex +/- buttons with ac.storage preset tables
end
