# AGENTS.md

Instructions for agents working on NPC Battle Cleanup ("NBC"), a Garry's Mod addon that removes NPC corpses, dropped weapons, items, debris, decals, and supported addon leftovers.

## Context

- Entry point: `lua/autorun/nbc_init.lua`; it owns the `NBC` namespace, CVar defaults, realms, load order, and includes.
- Before behavior changes, read the affected files: `sv_hooks.lua`, `sv_remove.lua`, `sv_util.lua`, `sh_networking.lua`, `cl_menu.lua`, `addon.json`, and `TODO.txt`.
- Use the Facepunch wiki for uncertain GLua/GMod behavior, realms, hooks, entities, ConVars, networking, Derma, loading, or Workshop packaging: https://wiki.facepunch.com/gmod

## Coding Rules

- Make small GLua changes compatible with Sandbox-derived gamemodes.
- Keep project state under `NBC`; avoid loose globals unless GMod requires them.
- Respect realms and loading: server code under `if SERVER`, UI under `if CLIENT`, shared files sent with `AddCSLuaFile` before client `include`, and `nbc_init.lua` as the top-level loader.
- Preserve CVar names unless migration is requested. New user-editable settings must be added to `NBC.CVarDefaults`, exposed through `NBC.CVar`, and wired through networking/menu code.
- Keep cleanup conservative: remove only configured, filtered, ownership-safe entities; do not remove player-owned or intentionally spawned entities unless an explicit CVar allows it.
- Guard delayed/removable entities with `IsValid`; many death leftovers spawn after hooks fire and may be removed by the engine, timers, or addons first.
- Keep hot paths cheap; avoid broad `ents.GetAll()` scans unless genuinely needed.
- Use unique `NBC_` hook, timer, and net names, and remove temporary runtime state when done.
- Preserve existing compatibility patterns for VJ Base, TFA, M9K, CW2, ArcCW, ARC9, Melee Arts, and similar bases.
- Keep special cases readable: barnacles, striders, helicopters, gunships, burning corpses, ragdoll attachments, and thrown entities can differ from normal NPC deaths.
- Client-to-server networking must stay narrow, admin-checked, whitelist-based, and server-authoritative. Do not run client-provided console commands unless explicitly validated.
- Prefer plain Lua/GMod APIs over dependencies. Keep comments short and useful.

## Language

- Reply to users in their language.
- Keep code comments, identifiers, technical docs, menu text, and default commit messages in concise English unless asked otherwise.

## Runtime Workflow

- Runtime testing belongs in Garry's Mod with this addon mounted under `garrysmod/addons/nbc` or equivalent. Baseline: multiplayer/LAN Sandbox on `gm_flatgrass`; singleplayer can hide realm, prediction, pause, and tick issues.
- Lua hotloads on save. For larger edits, draft/review if useful, then apply final changes to the mounted addon. Save providers before consumers: `lua/ai/`, playground, shared/network/util, removal, hooks, then menu/UI. Save `nbc_init.lua` before new defaults/includes, but after dependencies for initialization-flow changes.
- New live include files require reopening the game.
- Hooks/timers survive hotload; manually remove deleted or renamed runtime state with `hook.Remove`, `timer.Remove`, or the matching cleanup.
- Remove temporary probes/debug hooks before delivery unless asked to keep them.
- To confirm GMod is open and the mounted addon is loaded, prefer a tiny hotload probe in `lua/ai/sh_playground.lua` that writes a timestamped JSON file under `data/nbc_tests`. Do not rely on sandboxed `ps`; it may only see the Codex sandbox, not the host game process.

## AI/Test Helpers

- `lua/ai/` modules load in both realms and must define functions only; never auto-run tests on load.
- `lua/ai/sh_playground.lua` is the shared AI/dev scratchpad. Use it temporarily, then restore it to its first comment line before delivery. This is the main file to be used by the AI to execute tests.
- Error helpers: `lua/ai/sh_error_capture.lua` batches `GM:OnLuaError`; `lua/ai/sh_error_capture_tests.lua` runs simple and 180-tick synthetic validation.

```lua
-- Deletes temporary DATA/nbc_tests artifacts. Input: optional options { dataDir, keep }. Returns: result table with removed/skipped counts.
NBC.AI.Files.Cleanup()
-- Installs the OnLuaError capture hook and flush timer. Input: none. Returns: nil.
NBC.AI.ErrorCapture.Install()
-- Writes captured Lua errors to data/nbc_tests/lua_errors.json. Input: force boolean. Returns: nil.
NBC.AI.ErrorCapture.Flush(true)
-- Removes the error capture hook and flush timer. Input: none. Returns: nil.
NBC.AI.ErrorCapture.Cleanup()
-- Starts synthetic error capture validation in the current realm. Input: none. Returns: nil.
NBC.AI.ErrorCaptureTests.Run()
-- Removes synthetic validation hooks/timers. Input: none. Returns: nil.
NBC.AI.ErrorCaptureTests.Cleanup()
-- Opens Utilities > Admin > NBCOptions on the client. Input: optional timing/cursor options. Returns: true when queued, false on wrong realm.
NBC.AI.Menu.OpenNBCOptions()
-- Opens/captures the NBC options panel to PNG plus JSON metadata. Input: optional capture/open options. Returns: true when queued, false on wrong realm.
NBC.AI.Menu.CaptureNBCOptions()
-- Serializes the active control panel tree. Input: optional { panel, maxDepth, path, save, printTree }. Returns: tree table or false.
NBC.AI.Menu.GetActiveControlPanelTree({ printTree = true })
-- Removes pending menu automation timers/hooks. Input: none. Returns: nil.
NBC.AI.Menu.Cleanup()
-- Downloads a Workshop addon GMA on the client and extracts it to garrysmod/data/nbc_tests. Input: numeric Workshop ID string plus optional options. Returns: true when queued, false on setup error.
NBC.AI.Workshop.DownloadAndExtract("addonWsid")
-- WorldCapture installs server-side PVS support automatically on load.
-- Captures an offscreen screenshot centered on an entity. Input: Entity plus optional capture options. Returns: true when queued, false on setup error.
NBC.AI.WorldCapture.CaptureEntity(ent)
-- Captures the first entity matching filters. Input: filter table plus optional capture options. Returns: true when queued, false on setup error.
NBC.AI.WorldCapture.CaptureFirst({ class = "prop_ragdoll", near = Vector(0, 0, 0), radius = 512 })
-- Captures a world point from an auto or supplied camera. Input: target Vector plus optional capture options. Returns: true when queued, false on setup error.
NBC.AI.WorldCapture.CapturePoint(Vector(0, 0, 64), { cameraOrigin = Vector(160, 0, 96) })
-- Captures from an explicit camera origin/angle. Input: camera Vector, Angle, optional capture options. Returns: true when queued, false on setup error.
NBC.AI.WorldCapture.CaptureAt(Vector(160, 0, 96), Angle(10, 180, 0))
```

- Test artifacts in `data/nbc_tests` are temporary; call `NBC.AI.Files.Cleanup()` before a new runtime test run unless you intentionally need prior screenshots or JSON outputs for comparison.
- Structured test output goes to the game's `data/nbc_tests/lua_errors.json`; keep only that active file. Hook `GM:OnLuaError(error, realm, stack, name, id)` in each tested realm. Expected synthetic result: one simple error, 180 tick errors in both realms, only `lua_errors.json`, and a responsive game.
- Menu automation output goes to the game's `data/nbc_tests/menu_open.json`; expected result includes `found = true`, `opened = true`, `menu_initialized = true`, and `Utilities` / `Admin` / `NBCOptions` metadata.
- Menu screenshot output goes to `data/nbc_tests/menu_nbc_options.png` plus `menu_nbc_options.json`; the capture should crop to the visible active control panel, not the full screen.
- Menu tree output goes to `data/nbc_tests/menu_tree.json`; use the returned `tree.panels[id]` references for follow-up UI interactions after inspecting the printed/serialized structure.
- Workshop inspection output goes to `data/nbc_tests/workshop_<id>_inspect.json`, stores the downloaded GMA as `workshop_<id>.dat`, and extracts files under `data/nbc_tests/workshop_<id>_<timestamp>/files/` with `.dat` suffixes plus an index mapping original paths.
- World capture output defaults to `data/nbc_tests/world_capture.png` plus `world_capture.json`; keep it generic by passing an entity, entity index, target filter, world point, explicit camera, or camera offset for the situation being tested. Do not hard-code addon-specific target models inside the helper.

- To reopen GMod, if needed:

```sh
pkill -TERM -x hl2_linux
pkill -TERM -x gmod
sleep 3
steam -applaunch 4000 -console -novid +sv_lan 1 +maxplayers 2 +gamemode sandbox +map gm_flatgrass
```

Check if the game is running (avoid ps):

```lua
timer.Simple(0.1, function()
    file.CreateDir("nbc_tests")
    file.Write("nbc_tests/hotload_probe_" .. (SERVER and "SERVER" or "CLIENT") .. ".json", os.date("!%Y-%m-%dT%H:%M:%SZ"))
end)
```

## How to start

1) Evaluate old `data/nbc_tests` artifacts.
2) Ensure the game is running.
3) Set up your lua error monitoring and keep an eye on it.
4) Evaluate the need of in-game tests to cofirm states and validate changes. Consider using AI/Test Helpers.
5) Start.

## Validation

- Always read logs from NBC.AI.ErrorCapture.Install() to fix your script errors.
- When testing entities, place them near the player (near = around 160 units), near the player spawn, or in a suitable position in the world.
- If players can interfere with the test, make the entities ignore them.

```sh
git diff --check
lua-language-server --check=. --check_format=pretty --checklevel=Warning --logpath=/tmp/nbc-luals-log
```

- Prefer LuaLS with `.luarc.json` or `--configpath`, LuaJIT/Lua 5.1 + GLua syntax, `include`/`IncludeCS` runtime specials, and GLua definitions such as `luttje/glua-api-snippets`. Without GLua config, treat LuaLS as syntax/noise only; use `luac -p` only as a fallback parser smoke check.
- If `lua-language-server` is not available on `PATH`, suggest installing it from the VS Code extension maintained at https://github.com/LuaLS/lua-language-server. If the extension is already installed, look for the binary at a path such as `/home/$USER/.vscode-oss/extensions/sumneko.lua-*/server/bin/lua-language-server`; when found, run LuaLS directly from that absolute path and suggest creating a stable system-wide symlink, for example: `sudo ln -sfn /home/$USER/.vscode-oss/extensions/sumneko.lua-3.18.2-linux-x64/server/bin/lua-language-server /usr/local/bin/lua-language-server`.
- Manual checklist: no startup Lua errors; AI helpers/playground load in both realms when used; Utilities > Admin > NPC Battle Cleanup opens and updates CVars; configured corpses/weapons/items/debris/decals clean after delay; changed player-death, addon compatibility, TODO edge cases, and multiplayer admin protections still work.

## Delivery

- Report changed files, summary, validation, and remaining risk.
- Explicitly say when Garry's Mod manual testing was not run.
- Do not make commits, tags, releases, Workshop updates, or `.gma` artifacts unless requested; keep release work separate and intentional.
