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
local sim           = ac.getSim()
local trackLength   = ac.getTrackLength()
local fastestLapMs  = 9999999
local timeSinceUpdate = 0

-- Drivers resolved each update cycle: ahead and behind the player
-- Each entry: { car, racePosition, driverName, nationCode, bestLapMs, lastLapMs, lapDelta, pitStops }
local driverAhead  = nil
local driverBehind = nil

-- Per-car pit tracking state: indexed by car index
-- { pitEntryFlag, pitStops, raceStartFlag }
local pitState = {}

-- ─── Initialization ───────────────────────────────────────────────────────────
-- (replaces acMain — runs once at script load)

for i = 0, sim.carsCount - 1 do
  pitState[i] = { pitEntryFlag = false, pitStops = 0, raceStartFlag = true }
end

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

-- Collect per-car data, detect pit events, sort standings, resolve ahead/behind.
-- Called from script.update(dt) on the configured interval.
-- TODO: implement
local function updateStandings()
  -- local session = ac.getSession(sim.currentSessionIndex)
  -- local isRace  = session and session.type == ac.SessionType.Race

  -- for i = 0, sim.carsCount - 1 do
  --   local car = ac.getCar(i)
  --   if car == nil or not car.isConnected then goto continue end
  --   local ps = pitState[i]
  --
  --   -- Update fastest lap
  --   local best = car.bestLapTimeMs
  --   if best > 0 and best < 9999999 and best < fastestLapMs then
  --     fastestLapMs = best
  --   end
  --
  --   -- Race-specific: race start spline correction and pit stop counting
  --   -- TODO: port raceStartFlag and pitEntryFlag logic
  --
  --   ::continue::
  -- end

  -- -- Find player position in leaderboard, then resolve ±1
  -- -- TODO: iterate ac.iterateCars.leaderboard(), find player (index 0), pick ahead/behind
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
