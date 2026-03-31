# CSP Lua API for Assetto Corsa Apps

## Overview

Custom Shaders Patch (CSP) exposes a rich Lua API that allows creating in‑game apps, HUDs, debug tools, and integrations on top of Assetto Corsa’s engine. The core API is distributed with CSP itself (in `assettocorsa/extension/internal/lua-sdk`) and mirrored as source in the `ac-custom-shaders-patch/acc-lua-sdk` repository.[1][2][3]

Lua apps live in `assettocorsa/apps/lua/<AppName>` and are discovered via a `manifest.ini` plus one or more Lua scripts (typically `<AppName>.lua`). CSP loads the standard `ac_common` library and then a script‑type‑specific library, which together expose namespaces like `ac.*`, `ui.*`, `render.*`, `physics.*`, and helpers defined in the SDK.[2][3][1]

## Documentation and SDK layout

The canonical API reference is generated as EmmyLua definition files and shipped in the `extension/internal/lua-sdk` folder of every CSP installation; these are intended to be consumed by editors such as VS Code with the Sumneko/Lua language server. The GitHub repo `ac-custom-shaders-patch/acc-lua-sdk` contains the same logic and type stubs, split into common libraries (`common/ac_*.lua`) and per‑script‑type entry modules (`ac_apps.lua`, `ac_track_script.lua`, `ac_wfx_impl.lua`, etc.).[1][2]

Additional reference material and getting‑started guides are available on the CSP Lua SDK wiki and the community "cheesy-lua" wiki, which both document app manifests, callbacks, and the main namespaces. Example scripts for cars, physics modules, online scripts, and tracks are collected in the `ac-custom-shaders-patch/acc-lua-examples` repository.[3][4][5][2]

## App folder and manifest.ini

### Folder layout

A minimal app looks like this (under `assettocorsa/apps/lua`):[3]

```text
MyFirstApp/
  manifest.ini
  MyFirstApp.lua
  icon.png          # optional, used in the apps taskbar
  res/...           # optional assets (shaders, images, audio, etc.)
```

Built‑in CSP apps such as App Shelf, CSP Debug, and Mumble follow the same pattern and are shipped in `acc-lua-internal/included-apps` for reference.[6]

### [ABOUT] section

The `[ABOUT]` section provides metadata shown in the Content Manager UI and in‑game app list:[5][3]

```ini
[ABOUT]
NAME = Hello World App
AUTHOR = YourName
VERSION = 1.0
DESCRIPTION = My first Lua app for Assetto Corsa
REQUIRED_VERSION = 0        ; minimal CSP build ID
URL = https://example.com   ; optional link to source or homepage
```

Example apps using this pattern:[6]

- **App Shelf** ("Install more apps") in `acc-lua-internal/included-apps/AppShelf`.[6]
- **CSP Debug** ("Show lights and physics outlines, debug VAO and more") in `acc-lua-internal/included-apps/CspDebug`.[6]
- **Mumble** ("Direct Mumble voice chat integration to CSP") in `acc-lua-internal/included-apps/Mumble`.[6]

### [CORE] section: lifecycle and flags

The `[CORE]` section controls how and when CSP loads your app script:[5][3]

```ini
[CORE]
LAZY = FULL           ; NONE | PARTIAL | FULL
PREPROCESS = 0/1      ; force Lua preprocessor (mainly for testing)
FLAGS = DISABLED_OFFLINE ; optional app‑wide flags
```

Key `LAZY` modes:[3][5]

- `NONE` / `0`: load when AC starts, keep script alive until the game exits.
- `PARTIAL` / `1`: load when any app window is first opened, keep it alive for the session.
- `FULL` / `2`: load when the app is opened; unload completely when all its windows are closed.

Apps that should always be available in online sessions but can be disabled offline (for performance or UX) use the `DISABLED_OFFLINE` core flag. The built‑in Mumble app demonstrates a `CORE` configuration that keeps the app disabled offline and unloads it automatically when voice integration is not configured for the current session.[2][5]

### [WINDOW_*] sections: windows and flags

Each `[WINDOW_...]` section describes a single ImGui‑based window and its callbacks.[5][3]

```ini
[WINDOW_...]
ID = main                    ; internal window ID
NAME = Hello World           ; title bar and taskbar label
ICON = icon.png              ; icon within the app folder
SIZE = 400, 200              ; default size
MIN_SIZE = 200, 80           ; optional minimum size
MAX_SIZE = ∞, ∞              ; optional maximum size
PADDING = 8, 8               ; optional padding override
FLAGS = SETTINGS, AUTO_RESIZE, MAIN, FADING, ...
FUNCTION_MAIN = windowMain   ; per‑frame draw function
FUNCTION_SETTINGS = windowSettings ; optional settings UI
FUNCTION_ON_SHOW = onShow    ; called once when window opens
FUNCTION_ON_HIDE = onHide    ; called once when window closes
FUNCTION_ICON = drawIcon     ; optional, draw dynamic window icon
TAGS = ...                   ; optional tags for grouping
```

Important flags include:[3][5]

- `MAIN`: marks the main window if there are multiple windows.
- `SETTINGS`: adds a settings button that opens the settings window (`FUNCTION_SETTINGS`).
- `AUTO_RESIZE`: resizes the window automatically to fit its content.
- `FIXED_SIZE`: disallows user resizing.
- `FADING`: fades the window when inactive (used by Mumble’s main window).
- `HIDDEN_OFFLINE` / `HIDDEN_ONLINE`: hide this window in offline or online sessions.
- `NO_BACKGROUND`, `NO_TITLE_BAR`, `NO_SCROLLBAR`, `NO_SCROLL_WITH_MOUSE`, etc., to tweak visuals and behavior.

Example usages:[3][6]

- **App Shelf**: single main window with `FLAGS = SETTINGS`, `MIN_SIZE` and `SIZE` tuned for a scrollable list of apps.
- **CSP Debug**: multiple `[WINDOW_...]` entries, including a developer window and a separate "View & Video Settings" window with `AUTO_RESIZE` and grouping into developer/settings categories.
- **Mumble**: a main "Voice Chat" window using `HIDDEN_OFFLINE`, `SETTINGS`, and `FADING` for contextual visibility and UI style.[6]

### SIM, render, and UI callbacks

The manifest can register callbacks that are not tied to a particular window.[3]

Simulation callbacks:

```ini
[SIM_CALLBACKS]
FRAME_BEGIN = fn   ; called before scene rendering begins (camera manipulation, etc.)
UPDATE = fn        ; called after a full simulation step
```

Render callbacks:

```ini
[RENDER_CALLBACKS]
OPAQUE = fn        ; after opaque geometry is rendered
TRANSPARENT = fn   ; after transparent geometry is rendered
```

These are intended for debug overlays and helpers in world space, not for heavy custom geometry; loading additional KN5 models is done via `ac.SceneReference` utilities rather than direct mesh emission.[3]

Fullscreen UI callbacks:

```ini
[UI_CALLBACKS]
IN_GAME = fn       ; called before ImGui apps are rendered, for full‑screen HUDs
```

Such callbacks are used to build full‑screen HUDs or overlays (virtual mirrors, custom HUD replacements, etc.), typically starting from a custom window opened in the callback and then drawing with `ui.*` inside. The built‑in Mumble app registers `IN_GAME = fullscreenUI` and uses `script.fullscreenUI` to render an overlay for voice chat status.[7][2][3]

## Script entry points and lifecycle

### Standard app callbacks

The Lua side of an app defines functions under the global `script` table; CSP looks them up once on load and then calls them on every relevant frame.[1][3]

Typical entry points for a basic app:

```lua
function script.windowMain(dt)
  ui.text('Hello world!')
end

function script.windowSettings(dt)
  -- optional settings UI
end

function script.Draw3D(dt)
  -- optional 3D debug drawing from TRANSPARENT/OPAQUE callbacks
end

function script.update(dt)
  -- per-frame logic, even if no window is visible
end
```

This pattern is shown in the official Lua apps wiki Hello World example and reused in internal apps such as CSP Debug and Mumble, which define `script.windowMain`, `script.windowSettings`, `script.update`, and, where needed, `script.fullscreenUI` or `script.windowOnHide`.[2][3]

### App loading and unloading

CSP binds callbacks during app initialization based on the manifest and then holds references for performance, so replacing functions at runtime is not supported. When an app unloads (due to `LAZY = FULL`, explicit calls, or session conditions), its Lua state is discarded and only data stored via `ac.connect`, `ac.storage`, or `ac.store` persists.[8][1][3]

Apps can request unloading and hide themselves programmatically, for example if prerequisites are not met. The Mumble app checks whether the current race is online and whether the server provides Mumble integration; if not, it calls `ac.unloadApp()` and `ac.setAppWindowVisible('Mumble', '?', false)` and replaces its window callbacks with a simple "not configured" message.[2]

## Core namespaces for apps

### ac.* – simulation, game, system, and logging

The `ac` namespace exposes simulation state, cars, game/session data, storage, logging, audio, and many CSP‑specific extensions; its implementations are broken down into files such as `ac_game.lua`, `ac_physics.lua`, `ac_state.lua`, `ac_storage.lua`, and others in the SDK. Key capabilities relevant to apps include:[1]

- **Simulation and cars**: `ac.getSim()` and `ac.getCar(index)` provide read‑only state for the session and individual cars (speed, gear, inputs, focus, etc.), used heavily in debug and telemetry apps.[2][3]
- **Event hooks**: `ac.onOnlineWelcome(fn)` lets apps react to server welcome messages and configuration blocks, used by the Mumble app to read a `[MUMBLE_INTEGRATION]` section from server‑side configuration before connecting to a voice server.[2]
- **Storage**: helpers defined via `ac_storage.lua` (`ac.storage`, `ac.store`, `ac.connect`) allow apps to persist small bits of state across reloads and sessions or to share state with CSP modules.[8][1]
- **Logging and diagnostics**: `ac.log` writes messages to CSP’s log and is the preferred way to emit debug output from Lua code, used throughout internal scripts and physics examples.[9][10]
- **Audio**: `ac.setAudioVolume(channel, value)` and the `ac.AudioChannel` enum expose per‑channel volume controls, demonstrated in Mumble’s debug mode where game audio is attenuated while voice chat is active.[2]
- **Debug visualizations**: CspDebug uses `ac.setPhysicsDebugLines`, `ac.debugLights`, and enums like `ac.LightsDebugMode` and `ac.VAODebugMode` to render wireframes and light gizmos over the scene for tuning and debugging CSP lighting and VAO data.[11][6]

Example apps using `ac.*` heavily:[4][6][2]

- **CSP Debug** (`included-apps/CspDebug`): simulation and lighting debug visualizations via `ac.getSim`, `ac.getCar`, and various debug calls.
- **Mumble** (`included-apps/Mumble`): session inspection (`ac.getSim`, `ac.getCar`), online welcomes, server IP/ports, and audio channel control.
- **Online examples** (`acc-lua-examples/online/admin_with_teleporter`): server‑side tools built on CSP’s online scripting API, handling admin commands and teleportation.

#### Debug logging from Lua apps

Lua scripts can still use the standard `print()` function, but the most reliable way to get output into CSP’s logs is `ac.log`. Typical patterns include:[12][13]

```lua
ac.log('MyApp', 'Initialized windowMain')
ac.log('GapApp', string.format('Ahead gap: %.3f', aheadGap))
```

Messages appear in CSP’s log files and can be viewed via Content Manager’s log viewer, which is how internal scripts record configuration issues and runtime errors. For quick one‑off debugging, `print('value', x)` also works, but routing and formatting are less consistent than with `ac.log` on many setups.[13][12][9]

### ui.* – immediate-mode UI

The `ui` namespace provides an immediate‑mode API built on top of Dear ImGui for drawing 2D UI, both in standard app windows and custom full‑screen overlays. Core primitives include text (`ui.text`, `ui.textWrapped`), buttons (`ui.button`, `ui.modernButton`), images (`ui.image`), layout helpers (`ui.sameLine`, `ui.beginGroup`, `ui.offsetCursor`, `ui.availableSpaceX`), fonts (`ui.Font.*`, `ui.pushFont` / `ui.popFont`), and style control (`ui.StyleVar`, `ui.pushStyleVar`, `ui.popStyleVar`).[7][5][3]

Internal apps showcase more advanced widgets:[7][6]

- **Notification badges** and counters (e.g., `ui.notificationCounter`, `ac.setWindowNotificationCounter`).
- **Modal dialogs** (`ui.modalDialog`) for confirmation and details panes.
- **Hyperlinks** (`ui.textHyperlink`) and tooltips (`ui.setTooltip`) for external links and context.[6][2]
- **Outline and fading** (`ui.beginOutline`, `ui.endOutline`, `ac.windowFading`) to highlight temporary messages in Mumble when voice is not configured.[2]

Example apps focused on UI patterns:[6][2]

- **App Shelf**: demonstrates complex list layout with images, buttons, progress indicators, and notification counters for newly available apps.
- **CSP Debug**: multiple tool windows with grouped controls for toggling physics and lighting debug modes.
- **Mumble**: simple, state‑driven UI that delegates most layout to a separate `MumbleWrapper` module and uses fading outlines for user feedback.

### UI text, layout, and scaling in detail

UI code for apps typically runs in one of two contexts: a standard window callback (`script.windowMain(dt)`) configured with `FUNCTION_MAIN = windowMain` in `manifest.ini`, or a fullscreen UI callback registered via `[UI_CALLBACKS]` (for example, `IN_GAME = fullscreenUI`). In both cases CSP calls the Lua function every rendered frame and expects the code to fully rebuild the UI from scratch using `ui.*` calls in immediate‑mode style.[7][3]

The simplest way to render text is `ui.text('Some text')`, which draws at the current cursor position and advances the cursor vertically; apps usually combine this with data from `ac.getSim()` or `ac.getCar()` to show live telemetry such as session time, speed, or gear. For multi‑line content or paragraphs that should wrap to the window width, `ui.textWrapped` automatically inserts line breaks, as used extensively in App Shelf and Mumble for descriptions and status messages.[7][6][2]

Interactive elements follow the same pattern: `ui.button('Label')` draws a clickable button and returns `true` on the frame in which it is clicked, so app code branches on the return value to update its own state (for example, toggling a debug flag or starting an install). More specialized buttons such as `ui.modernButton` add icon support and styling hints, and are used in App Shelf to implement "Install", "Update", and "Uninstall" actions with different visual states.[7][6]

Layout is controlled implicitly by the order of `ui.*` calls and explicitly via helpers such as `ui.sameLine` (to keep the next widget on the same row), `ui.offsetCursor` and `ui.offsetCursorY` (to add padding), and `ui.beginGroup` / `ui.endGroup` (to treat a block of widgets as a single layout item). Internal apps also rely on `ui.availableSpaceX` and `ui.setNextItemWidth` to size sliders, inputs, and buttons to fill the available width, which is especially visible in the CSP Debug app’s light‑debug controls.[7][6]

#### DirectWrite fonts: ui.DWriteFont, ui.pushDWriteFont, ui.dwriteText / ui.dwriteTextAligned

For high‑quality text rendering with advanced font features (weight, stretch, variable font axes, emojis, etc.), CSP provides a DirectWrite font pipeline exposed via `ui.DWriteFont` and related helpers.[8][1]

- `ui.DWriteFont(name, dir?)` constructs a `ui.DWriteFont` descriptor for a given font family or TTF file, optionally scanning a custom directory for font files.[8]
- The returned object has chainable methods:
  - `:weight(weight)` to pick a specific weight (or emulate it),
  - `:style(style)` for italic/oblique,
  - `:stretch(stretch)` for condensed/expanded styles,
  - `:axis(key, value)` or `:axis{ weight = ..., width = ..., slant = ..., opticalSize = ..., italic = ... }` to configure variable font axes,
  - `:allowRealSizes(allow)` to disable font size rounding (with a warning that changing real sizes every frame creates many font atlases, and that scaling via `ui.beginScale`/`ui.endScale` is preferred for animations),
  - `:allowEmoji(allow)` to toggle color emoji rendering.[8]

There are two main ways to use DirectWrite fonts in apps:[14][8]

1. **Scoped font push with size in the draw call**:

   ```lua
   local MyFont = ui.DWriteFont('Best Font', './fonts')
                      :weight(ui.DWriteFont.Weight.Bold)
                      :stretch(ui.DWriteFont.Stretch.Condensed)

   ui.pushFont(MyFont)
   ui.dwriteText('Hello world!', 14)
   ui.popFont()
   ```

   This pattern, shown in the SDK documentation comment, uses `ui.pushFont(MyFont)` to activate the DirectWrite font for subsequent text calls and `ui.dwriteText(text, size)` to render a single line at the current cursor with the given point size.[8]

2. **Explicit DirectWrite font selection plus aligned block drawing**:

   Some scripts instead use `ui.pushDWriteFont` to select a font directly by a composite string (family, font path, weight, etc.) and then draw a block of text aligned within a rectangle using `ui.dwriteTextAligned`.[14]

   Example from a countdown app:

   ```lua
   ui.pushDWriteFont('Arkitech:\\fonts;Weight=Regular')
   ui.setCursor(vec2(centerx - scale(400), centery - scale(240)))
   ui.dwriteTextAligned(textToWrite, scale(160), ui.Alignment.Center, ui.Alignment.Center,
                        scaledVec2(800, 480), false, rgbm.colors.white)
   ui.popDWriteFont()
   ```

   Here, `ui.pushDWriteFont` activates a specific font face, `ui.dwriteTextAligned` draws the text centered in an 800×480 rectangle at a given cursor position, with horizontal/vertical alignment controlled by `ui.Alignment.*` enums and color passed as a `rgbm` value.[14]

In both cases CSP encourages animating apparent text size by coupling these APIs with `ui.beginScale` / `ui.endScale(scale)` instead of changing the DirectWrite size (`14`, `scale(160)`, etc.) every frame, to avoid creating many distinct font atlases. For layouts where text should adapt to window size, app code typically:[8]

- Computes a scale factor from `ui.windowSize()` or `ui.availableSpace()`,
- Wraps the DirectWrite text call in `ui.beginScale()` / `ui.endScale(scale)`, and
- Uses `ui.dwriteText` or `ui.dwriteTextAligned` so that high‑quality glyphs are rendered into the appropriately scaled region.

#### Scaling text with ui.beginScale / ui.endScale

The `ui.DWriteFont:allowRealSizes` comment in the SDK recommends animating text size with `ui.beginScale()` / `ui.endScale()` instead of changing the underlying font size every frame, to avoid generating excessive font atlases. These functions work as a wrapper: everything drawn between `ui.beginScale()` and `ui.endScale(scale)` is multiplied by the scalar you pass to `ui.endScale`, but CSP does not automatically derive that `scale` from the window size.[8]

Internal apps such as App Shelf call `ui.beginScale()` immediately before drawing text that should adapt to its container, then end with a fixed scale like `ui.endScale(0.9)`; the scale value is manually chosen to fit typical layouts. To make text truly reactive to window size, app code must compute an appropriate `scale` factor from `ui.windowSize()` or `ui.availableSpace()` and pass that value to `ui.endScale(scale)` every frame.[6]

A common pattern is to define a design size and scale relative to it:

```lua
local DESIGN_WIDTH  = 300
local DESIGN_HEIGHT = 400

local function computeScaleForWindow()
  local sz = ui.windowSize()
  local sx = sz.x / DESIGN_WIDTH
  local sy = sz.y / DESIGN_HEIGHT
  return math.min(sx, sy, 2.0)  -- clamp if needed
end

function script.windowMain(dt)
  local s = computeScaleForWindow()
  ui.beginScale()
  ui.textAligned('--:--.---', 0.5, ui.availableSpace(), true)
  ui.endScale(s)
end
```

With this approach, increasing the window size increases `sx`/`sy` and thus the scale, while shrinking the window reduces it; text size tracks window size because the script recomputes and feeds `s` into `ui.endScale` each frame.[7]

In fullscreen callbacks, app code typically opens a custom window (for example, a borderless one anchored to the screen) and then draws text, buttons, and images using the same `ui.*` primitives, allowing HUD‑style overlays that coexist with standard side apps. The Mumble app illustrates this by combining a normal `script.windowMain` for configuration and status with a `script.fullscreenUI` callback that renders an overlay for in‑race voice‑chat state.[2][7]

### render.*, vector and color types

Rendering helpers in `common/ac_render.lua` and primitive/vector libraries (`ac_primitive_vec*`, `ac_primitive_rgbm`, etc.) back the `render.*` and math APIs available to Lua scripts. Common patterns in apps include:[1]

- **Extra canvases**: `ui.ExtraCanvas(width, height)` creates an off‑screen render target that can be updated with a shader and then drawn as an image; in the Mumble app, this is used to drive a speaker icon with peak volume visualized in real time.[2]
- **Render target management**: `render.backupRenderTarget()` / `render.restoreRenderTarget()` ensure that custom drawing to off‑screen surfaces does not disturb the main framebuffer, especially in VR.[3][2]
- **Basic shapes and images**: `ui.drawRectFilled`, `ui.drawImage`, and related helpers overlay debug gizmos or status indicators in both app windows and full‑screen HUDs.[3][2]

The Lua apps wiki’s example HelloWorld app mentions video‑rendering tests and full‑screen UI, showing how an app can combine `ExtraCanvas`, shaders, and custom cameras.[3]

### os.*, io.*, and integration helpers

Standard LuaJIT is extended with system integration helpers exposed through `os.*`, `io.*`, and CSP‑specific libraries such as `lib_web.lua` and `lib_onlineevent.lua` in the SDK repo.[15][1]

Typical uses in CSP apps include:

- **Opening URLs and folders**: App Shelf uses `os.openURL` and `os.openInExplorer` from button clicks to open external documentation or the app installation folder.[15][2]
- **Spawning or managing processes**: Mumble’s debug path uses `os.execute` and `io.copyFile` to deploy and restart a helper plugin executable bundled with CSP.[2]
- **File existence and copying**: `io.fileExists` and `io.copyFile` are used before launching helper processes or loading external resources.[2]

These capabilities are powerful but should be used conservatively in public apps for security and portability reasons.

## Feature-by-feature guide with example apps

### Basic windowed app (Hello World)

Key pieces:[3][2]

- `manifest.ini` with a single `[WINDOW_main]` section and `FUNCTION_MAIN = windowMain`.
- `script.windowMain(dt)` drawing a bit of UI with `ui.text`, `ui.button`, etc.
- Optional `script.update(dt)` for per‑frame logic independent of window visibility.

Documentation and examples:[3][2]

- **Lua apps wiki**: step‑by‑step "Hello World" app tutorial with a ready manifest and script skeleton.[3]
- **CSP Lua getting started guide** (`cheesy-lua`): repeats and expands the manifest options and basic callbacks for apps.[5][2]

### Complex multi-window tools (CSP Debug)

CSP Debug demonstrates how to build multi‑window tools with groups, categories, and heavy use of simulation data:[11][6]

- Multiple `[WINDOW_...]` entries for main and settings windows.
- Window grouping with `GROUP = DEVELOPER` or `GROUP = SETTINGS`.
- `script.windowMain` and `script.windowSettings` providing different UIs.
- A `RENDER_CALLBACKS` section that hooks `TRANSPARENT = draw3D` and a `script.draw3D` function that draws in world space.
- Use of `ac.getSim`, `ac.getCar`, `ac.setPhysicsDebugLines`, `ac.debugLights`, and flags/enums to switch various debug overlays.

This app is the primary reference for advanced debug overlays, VAO and light debugging, and integration with CSP’s internal debug modes.[11][6]

### App discovery and background services (App Shelf)

App Shelf implements an app catalogue and installer:[15][6]

- A main window listing available Lua apps, with icons, descriptions, versioning, and install/update/uninstall buttons.
- Use of `ui.modernButton`, `ui.notificationCounter`, font and style helpers to create a modern UI.[6]
- Background update logic driven by a service script and triggers, allowing CSP to periodically refresh the app list and notify users of new apps.
- Integration with OS helpers to open URLs and folders for installed apps.

Although its internal helper modules are specific to CSP’s distribution infrastructure, the App Shelf app is a good blueprint for any app that must download, install, or manage other content based on remote metadata.[15][6]

### Voice chat and online integration (Mumble)

The Mumble app shows how to integrate with external services based on server configuration and how to manage full‑screen UI in tandem with a standard window.[16][2]

Key patterns:[2]

- Reading simulation state to decide whether the app should be active (e.g., disable in offline sessions or when no car is present).
- Hooking `ac.onOnlineWelcome` to receive a configuration blob from the server (here, a `[MUMBLE_INTEGRATION]` section) and parsing it into connection parameters.
- Connecting to an external voice server via a Lua wrapper module (`MumbleWrapper`), and updating it each frame from `script.update(dt)`.
- Using `script.windowMain`, `script.windowSettings`, and `script.fullscreenUI` so that both a regular app window and a HUD overlay can present voice state.
- Temporarily altering audio channel volumes via `ac.setAudioVolume` for better voice clarity.

This app is the canonical example for integrating Lua apps with online server scripts and third‑party services while respecting per‑session configuration.[16][2]

### Online tools and admin utilities

Beyond in‑car apps, CSP exposes server‑side and online scripting. The `acc-lua-examples` repo provides several small but focused examples:[4]

- **admin_with_teleporter** (`online/admin_with_teleporter`): demonstrates handling admin commands and teleporting cars, showcasing basic online callbacks and car manipulation helpers.[4]
- **lemans_start** (`online/lemans_start`): shows how to orchestrate special race start procedures via Lua.

These scripts reuse the same SDK (`ac_*` libraries) but run in the server/online context rather than as UI apps.[4]

### Car, physics, and track scripts as references

While not "apps" in the UI sense, car, car‑physics, and track scripts use the same API surface and are excellent references for what `ac.*`, `physics.*`, and related namespaces expose.[4][1]

Examples from `acc-lua-examples`:[4]

- **dash_display_8100** (`cars/dash_display_8100`): a full Lua‑driven digital dash overlay that reads car state and renders a custom instrument cluster.
- **weight_shift**, **turbo_map**, **modules** under `cars_physics`: show how to implement additional physics behaviors via Lua.
- **ford_model_t** (`cars_physics/ford_model_t`): a complete custom physics implementation for a vintage car.

All of these reuse the same `ac_common` base library and common primitives as apps, so their patterns are directly applicable when building richer in‑car HUDs or telemetry apps.[1][4]

## Recommended workflow for new apps

1. **Install a recent CSP build** and ensure the `extension/internal/lua-sdk` folder is present; this folder contains the EmmyLua definitions used by the SDK.[1][2]
2. **Set up VS Code** with the Sumneko Lua extension and configure it to use the `lua-sdk` folder as an additional library path; this enables inline API documentation and autocompletion.[1][2]
3. **Start from the Hello World manifest and script** in the Lua apps wiki and adapt it to your use case, adding windows and callbacks as needed.[2][3]
4. **Study internal apps** in `acc-lua-internal/included-apps` (App Shelf, CSP Debug, Mumble) and the `acc-lua-examples` repository for concrete, production‑grade patterns.[4][6]
5. **Use the CSP Lua Debug app** and developer apps panel to inspect script errors, performance, and live state while iterating.[15][2]

Following these steps ensures that new apps stay compatible with current CSP builds, make full use of the available namespaces, and follow established patterns from the official and example repositories.[1][6][2]