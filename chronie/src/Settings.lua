local _, ns = ...

---What this installed copy of the addon has been asked to do.
---
---In the full Chronie this file is the channel between the addon and the desktop app, which
---rewrites it from its own Setup screen every time it starts. Chronie Lite has no other half,
---so this file is simply the settings: edit it in place, reload, and that is the whole of the
---configuration story.
---
---Everything in it is off, because everything in it costs the player something they did not
---ask for.
---@class ChronieSettings
---@field combatLogging boolean Whether to start combat logging at login. Off by default: a
---raid night of combat log is hundreds of megabytes, and nothing deletes it again yet.
---@field captureTriggers string[] Which things worth remembering take a picture of
---themselves — see ns.newCaptureTriggers for what each name means. Conservative rather than
---empty: "the first time this account ever did this" is rare enough to be worth a
---photograph every time, which "an achievement fired" is not.
---@field sync ChronieSyncSettings What runs by itself. Both off, and that is what Lite means.

---The work Chronie can do on its own account, off by default in this build.
---
---**Nothing here is missing — it is switched off.** Every module the two flags gate is in
---`src/` exactly as the full addon has it, wired into `Main.lua` exactly as the full addon
---wires it, and covered by the same tests. What Lite changes is that nothing provokes any of
---it unless somebody says so, because the walk behind `census` is thousands of client calls
---and a player who did not ask for it should not pay for it on every loading screen.
---
---Turn one on by editing this file and reloading (`/reload`). There is no in-game switch, on
---purpose: a setting that costs a minute of frame time is one somebody should have to mean.
---@class ChronieSyncSettings
---@field census boolean Whether a loading screen may provoke an account census. Off. The audit
---itself is a handful of calls and names nothing in the steady state, but the pass it provokes
---walks every mount, appearance and achievement id the client will answer for — thirteen
---thousand of the last alone. `/chronie census refresh` still walks on demand whatever this
---says, because a command somebody typed by name is not something running by itself.
---@field requests boolean Whether to carry out what the desktop app left in
---`src/CensusRequests.lua` and `src/CustomSetRequests.lua`. Off, and in Lite there is no app
---to write either file: both ship empty and stay that way. Kept wired rather than deleted so
---that a copy of this addon dropped back beside the app is one flag away from working.
ns.settings = {
    combatLogging = false,
    captureTriggers = { "accountFirstAchievement" },
    sync = {
        census = false,
        requests = false,
    },
}
