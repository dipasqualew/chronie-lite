local _, ns = ...

---Which faction the game means by a name, for the one question the client will not answer.
---@class FactionIndex
---@field resolve fun(name: string?): integer? The faction's own id, or nil while nothing knows.
---Asking about a name nothing has answered for is what provokes the walk below, so a caller
---that asks again later gets an answer it could not have had the first time.
---@field ready fun(): boolean Whether the walk has finished, so a miss can be trusted as a "no"
---rather than read as "not yet".

---@class FactionIndexDeps
---@field reputation table? The client's `C_Reputation`.
---@field after fun(seconds: number, callback: fun()) The client's `C_Timer.After`, injected so a
---spec can drive the walk without a game running.
---@field budget integer? How many ids one slice asks about. Default `DEFAULT_BUDGET`.
---@field last integer? The highest id to ask about. Default `LAST_FACTION_ID`.

---How many ids one slice asks the client about, and how long between slices. Both are the
---census's, deliberately: this is the same walk over the same ids, and a second set of numbers
---for it would be two answers to one question about how much of a frame Chronie may take.
local DEFAULT_BUDGET = 200
local SLICE_DELAY = 0

---The highest faction id the walk asks about.
---
---The same range and the same reasoning as the reputation census's own — `Faction` on build
---12.0.5.67823 runs to 2793, and this is that with half again of headroom. Spelled here rather
---than shared with `CensusDomains.lua` because the two walks are independent: this one runs on a
---build where the census is switched off, and a constant reached across files is a constant that
---has to be found before either can be read.
local LAST_FACTION_ID = 4000

---Every faction in the game, filed under the name the client prints for it.
---
---A reputation gain is announced in chat and nowhere else, and a chat line carries a localised
---name rather than an id — so everything downstream that files a standing has to turn that name
---into the id it is filed under. `C_Reputation.GetFactionDataByName` is the call for that and it
---is not on every build (it was already missing in issue #44); what is left is a walk of the
---reputation *pane*, and the pane hides what the player has collapsed and every legacy faction
---besides. A faction that neither road reaches arrives as a name and a number and nothing else:
---no id, so no account rollup and no standing, so no bar under the row, no tooltip over it and
---nothing for a click to open. That is not a small hole — it is most of the game's factions.
---
---`GetFactionDataByID` has no such blind spot. It answers for an arbitrary id whether the pane
---is drawing it, hiding it, or has it folded away, and touches nothing the player arranged. So
---the name is answered by walking the ids once and remembering what each one is called.
---
---**Provoked, never scheduled.** The walk starts the first time a name cannot be answered any
---other way, which on a build with `GetFactionDataByName` is never — and it runs once per
---session rather than being written to disk, because a name is only localised until the player
---changes their language and an index on disk is one more thing that can be stale about a client
---it was not taken from.
---@param deps FactionIndexDeps
---@return FactionIndex
function ns.newFactionIndex(deps)
    deps = deps or {}
    local budget = deps.budget or DEFAULT_BUDGET
    local last = deps.last or LAST_FACTION_ID
    ---@type table<string, integer>
    local ids = {}
    local walking = false
    local walked = false

    ---Walks one slice of the range and asks for the next, until the range runs out.
    ---
    ---A slice per frame for the same reason the census takes one: the walk is thousands of
    ---client calls, and all of them in one frame is a visible stutter at the exact moment the
    ---player is being told they gained reputation.
    ---@param from integer
    local function slice(from)
        local byID = ns.callable(deps.reputation, "GetFactionDataByID")
        -- A build without the call, and a caller that handed over no clock to spread the walk
        -- across, are the same answer: there is nothing this can do, and saying so once is what
        -- stops every later miss asking again. Neither is an error — the two roads either side
        -- of this one in `findFaction` still work, exactly as they did before it existed.
        if not byID or type(deps.after) ~= "function" then
            walking, walked = false, true
            return
        end

        local stop = math.min(from + budget - 1, last)
        for id = from, stop do
            local data = byID(id)
            local name = type(data) == "table" and data.name
            -- The first id a name is found under wins. A name held by two factions is the very
            -- ambiguity the id exists to end, and nothing about a chat line says which of them
            -- was meant — so the tie is broken the one way that does not depend on the order
            -- anything happened to be walked in, and the answer is at least always the same one.
            if type(name) == "string" and name ~= "" and type(data.factionID) == "number"
                and ids[name] == nil then
                ids[name] = data.factionID
            end
        end

        if stop >= last then
            walking, walked = false, true
            return
        end
        deps.after(SLICE_DELAY, function()
            slice(stop + 1)
        end)
    end

    return {
        ---@return boolean
        ready = function()
            return walked
        end,

        ---@param name string?
        ---@return integer?
        resolve = function(name)
            if type(name) ~= "string" or name == "" then
                return nil
            end
            local id = ids[name]
            if id then
                return id
            end
            -- The miss is what starts the walk, and only the first one does: asking again while
            -- it is under way must not lay a second chain of slices over the first.
            if not walking and not walked then
                walking = true
                slice(1)
            end
            return nil
        end,
    }
end
