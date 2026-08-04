# Chronie Lite

**Install.** Run this from your World of Warcraft `AddOns` folder. It downloads the
addon and replaces whatever `chronie` folder is there. Run it again to update.

```bash
cd "/Applications/World of Warcraft/_retail_/Interface/AddOns" && curl -fsSL https://raw.githubusercontent.com/dipasqualew/chronie-lite/main/install.sh | bash
```

<details>
<summary>Windows PowerShell, or a game installed somewhere else</summary>

The `cd` is the only part that differs. On Windows, in PowerShell:

```powershell
cd "C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns"; iwr -useb https://raw.githubusercontent.com/dipasqualew/chronie-lite/main/install.sh | bash
```

That needs a `bash` — Git for Windows ships one, and so does WSL. Without one, download
[the repository as a zip](https://github.com/dipasqualew/chronie-lite/archive/refs/heads/main.zip),
open it, and copy the `chronie` folder inside it into `AddOns` yourself. That is all the
script does.

Battle.net lets the game live anywhere, so `D:\World of Warcraft` or
`/Volumes/Games/World of Warcraft` are ordinary rather than exotic. The folder you want is
the one with `Interface` and `WTF` in it, under the flavour you play — `_retail_`,
`_classic_`, `_classic_era_`.

</details>

The script refuses to run anywhere that is not called `AddOns`, because installing an addon
into the wrong directory fails silently — the game simply never sees it. Pass `--force` if
you know better.

## What this is

Chronie Lite is the [Chronie](https://github.com/dipasqualew/chronie) addon on its own: no
desktop app, no collector, nothing that talks to anything outside the game. It keeps a
cross-character record of your lockouts, and it files what an evening actually contained —
where you were, what you killed, what dropped, what it was worth, what you collected — as a
segment per place per session.

Everything it records goes into `ChronieDB`, the game's own SavedVariables file for the
addon, which the client writes when you log out.

### And what it does not do

The full Chronie takes an **account census**: a walk over every mount, appearance,
achievement, toy, heirloom, title, currency and reputation id the client will answer for,
so that the record covers what you collected before the addon was ever installed. It is
provoked by a loading screen, it is thousands of client calls, and a patch makes every
loading screen the first one again.

**In Lite that walk is switched off, not removed.** So is the channel the desktop app used
to leave requests in — a file in the addon folder asking the game to take a fresh census or
to save an outfit into your wardrobe. Every module behind both is still in `chronie/src`,
still wired into `Main.lua`, still covered by the same tests. What changed is that nothing
provokes any of it by itself.

Two flags in [`chronie/src/Settings.lua`](chronie/src/Settings.lua) say so, and both ship
off:

| Flag | Off means | On means |
| --- | --- | --- |
| `sync.census` | No loading screen ever starts a census. | The audit runs ten seconds after each loading screen and walks whatever it distrusts. |
| `sync.requests` | `CensusRequests.lua` and `CustomSetRequests.lua` are never read. | The desktop app can ask for a census, and can write outfits into your transmog sets. |

Edit the file and `/reload` to change either. There is no in-game switch on purpose: a
setting that costs a minute of frame time is one you should have to mean.

`/chronie census refresh` still walks everything, whatever the flags say — a command you
typed by name is not something running by itself. It takes about a minute of ordinary play,
runs a slice per frame, and is written down when you log out.

## In game

| Command | What it does |
| --- | --- |
| `/chronie locks` | Every character's raid and dungeon lockouts, in one table. |
| `/chronie results` | What the segment you are playing has earned so far. |
| `/chronie segments` | Every segment already filed, filterable, and openable one at a time. Also the minimap button. |
| `/chronie currency` | Which items to count as currency. Drag one onto the window to track it. |
| `/chronie note [text]` | Mark this moment with something worth remembering. Without text, a box appears and waits. |
| `/chronie census` | What the census knows, per domain, beside what the client itself counts. |
| `/chronie census refresh` | Walk every collection again, now. |
| `/chronie log` | Whether combat logging is actually on, as the client reports it. |
| `/chronie events` | Which events this client build refused, so a missing feature is visible. |

Pressing your own screenshot key files the picture as an entry against wherever you were
standing, and offers you a sentence to go with it. Chronie binds no keys of its own.

Combat logging is off until you turn it on in `chronie/src/Settings.lua`: a raid night is
hundreds of megabytes and nothing deletes it again.

## Working on it

Lua 5.1 / LuaJIT, which is what the game runs. There is no `require` and no standard library
beyond what Blizzard exposes.

```bash
./scripts/check.sh
```

That is luacheck over everything the client loads, then busted. Zero warnings and zero
failures, always.

- `chronie/` is the addon, and is exactly what `install.sh` drops into `AddOns`.
- `chronie/chronie.toc` is the load order, and is the source of truth — a file missing from
  it fails the tests as well as the game.
- `chronie/Main.lua` is the only place allowed to touch WoW globals. It collects them into a
  `WowEnv` table and injects it, so every module is drivable from the fakes in
  `spec/helpers/fake_wow.lua` without monkey patching.
- `spec/` sits beside the addon rather than inside it, so what ships is what the client
  loads and nothing else.
- `docs/` is the reasoning the comments point at, carried over from the full Chronie —
  [why the census exists and what it costs](docs/account-census.md) is the one to read
  before turning `sync.census` on. See [`docs/README.md`](docs/README.md) for what in there
  describes a half this repository does not have.

Modules are `ns.newThing(deps)` factories returning a table of closures. Frame code stays
thin and the logic goes into a pure module beside it — the pure module is where the tests
earn their keep.
