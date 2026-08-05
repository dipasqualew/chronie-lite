local loader = require("addon_loader")

describe("ns.newFactionIndex", function()
    local ns = loader.load()

    ---A stand-in for the client's `C_Reputation`, answering `GetFactionDataByID` off a table of
    ---rows keyed by the id the client hands each one over under.
    ---
    ---It counts what it was asked, because the count is half of what this module is about. The
    ---walk is thousands of calls into the client, and every decision in it — the slice, the
    ---budget, the once-per-session — is a decision about how many of those calls happen in one
    ---frame. A fake that only answered would agree just as happily with an index that asked
    ---about the whole four-thousand-id range between one chat line and the next.
    ---@param rows table Keyed by faction id; each value is what `GetFactionDataByID` answers.
    ---@return table `{ client, asked }` — the `C_Reputation` stand-in and how often it was asked.
    local function newReputation(rows)
        local asked = 0
        return {
            client = {
                GetFactionDataByID = function(id)
                    asked = asked + 1
                    return rows[id]
                end,
            },
            asked = function()
                return asked
            end,
        }
    end

    ---A stand-in for `C_Timer.After` that runs nothing by itself.
    ---
    ---A slice hands the next one to the clock rather than calling it, so holding the callbacks
    ---here and releasing them a frame at a time is what lets a test stand between two slices and
    ---look at how much of the range has been walked so far. A real timer would only make the
    ---same assertions slow and flaky, and there is no frame here to spread anything across.
    ---@return table `{ after, pending, tick, drain }`
    local function newClock()
        local queue = {}

        ---Runs everything waiting right now, once each. The queue is taken away before anything
        ---in it is called, because a slice schedules the next slice while it runs — walking the
        ---live queue would run the whole chain inside one tick and hide the slicing entirely.
        local function tick()
            local due = queue
            queue = {}
            for _, callback in ipairs(due) do
                callback()
            end
        end

        ---Runs slices until nothing is left waiting, which is the walk having reached the end of
        ---the range. The guard is there because "never stops scheduling" is a real way for this
        ---to be wrong, and a spec that hangs says far less than one that fails.
        ---@return integer ticks How many frames the walk took.
        local function drain()
            local ticks = 0
            while #queue > 0 do
                ticks = ticks + 1
                assert.is_true(ticks < 1000, "the walk never stopped scheduling slices")
                tick()
            end
            return ticks
        end

        return {
            after = function(_, callback)
                queue[#queue + 1] = callback
            end,
            pending = function()
                return #queue
            end,
            tick = tick,
            drain = drain,
        }
    end

    it("is exported by the addon files", function()
        assert.is_function(ns.newFactionIndex)
    end)

    -- The one question the whole module exists to answer, and the reason it cannot be answered
    -- by where the row was found: a chat line carries a localised name, everything downstream
    -- files the standing under an id, and the id a faction reports is its own rather than the
    -- position anything happened to reach it at.
    it("answers a name in the walked range with the faction's own id, not where it was found",
        function()
            local reputation = newReputation({
                [7] = { name = "The Consortium", factionID = 933 },
            })
            local clock = newClock()
            local index = ns.newFactionIndex({ reputation = reputation.client, after = clock.after,
                last = 10 })

            index.resolve("The Consortium")
            clock.drain()

            assert.equal(933, index.resolve("The Consortium"))
        end)

    -- Provoked, never scheduled. On a build with `GetFactionDataByName` nothing ever misses, and
    -- a walk that started at login on that build would be four thousand client calls spent to
    -- answer a question already answered.
    it("asks the client nothing until a name it cannot place is asked about", function()
        local reputation = newReputation({ [7] = { name = "The Consortium", factionID = 933 } })
        local clock = newClock()
        local index = ns.newFactionIndex({ reputation = reputation.client, after = clock.after,
            last = 10 })

        assert.equal(0, reputation.asked())
        assert.equal(0, clock.pending())
        assert.is_false(index.ready())
    end)

    -- The miss is the whole trigger, and the first answer to it is honestly nil: the walk has
    -- not run yet and nothing in the addon knows what this name means. What matters is that the
    -- same question asked later gets an answer it could not have had the first time — that is
    -- what lets a row with no bar under it repair itself instead of staying dead all session.
    it("answers the first miss with nothing and the same name with an id once it has walked",
        function()
            local reputation = newReputation({
                [512] = { name = "Argent Dawn", factionID = 529 },
            })
            local clock = newClock()
            local index = ns.newFactionIndex({ reputation = reputation.client, after = clock.after,
                budget = 200, last = 600 })

            assert.is_nil(index.resolve("Argent Dawn"))
            assert.is_false(index.ready())

            clock.drain()

            assert.equal(529, index.resolve("Argent Dawn"))
            assert.is_true(index.ready())
        end)

    -- A slice per frame, and the budget is what one slice costs. All of it in one frame is a
    -- visible stutter at the exact moment the player is being told they gained reputation, which
    -- is the one moment the addon has no business being noticed.
    it("asks about no more than one budget of ids before handing the frame back", function()
        local reputation = newReputation({})
        local clock = newClock()
        local index = ns.newFactionIndex({ reputation = reputation.client, after = clock.after,
            budget = 200, last = 500 })

        index.resolve("Argent Dawn")

        assert.equal(200, reputation.asked())
        assert.equal(1, clock.pending())
        assert.is_false(index.ready())
    end)

    it("spreads the range over as many frames as it takes, a budget at a time", function()
        local reputation = newReputation({})
        local clock = newClock()
        local index = ns.newFactionIndex({ reputation = reputation.client, after = clock.after,
            budget = 200, last = 500 })

        index.resolve("Argent Dawn")
        clock.tick()

        assert.equal(400, reputation.asked())
        assert.equal(1, clock.pending())

        clock.tick()

        -- The last slice is the short one: the range ends at 500 rather than at a round multiple
        -- of the budget, and walking past the end would be a hundred calls about ids that are
        -- not factions on any build.
        assert.equal(500, reputation.asked())
        assert.equal(0, clock.pending())
        assert.is_true(index.ready())
    end)

    -- Every gain in a raid night misses at first, and each of them provokes `resolve`. A second
    -- chain of slices laid over the first would double the client calls per frame for the rest
    -- of the walk, and a fiftieth would be the stutter the slicing was for in the first place.
    it("lays one chain of slices however many misses arrive while it is walking", function()
        local reputation = newReputation({})
        local clock = newClock()
        local index = ns.newFactionIndex({ reputation = reputation.client, after = clock.after,
            budget = 200, last = 600 })

        index.resolve("Argent Dawn")
        index.resolve("Timbermaw Hold")
        index.resolve("The Consortium")

        assert.equal(200, reputation.asked())
        assert.equal(1, clock.pending())

        clock.drain()

        -- Six hundred ids asked about once each, rather than three walks of the same range.
        assert.equal(600, reputation.asked())
    end)

    -- Once per session, and a session is a long time: a name that was not in the range is not
    -- going to appear in it later, so re-walking on every later miss would be four thousand
    -- client calls spent to reach the same nil. The walk is not written to disk either — a name
    -- is only localised until the player changes their language.
    it("does not walk again for a name the walk it already ran could not place", function()
        local reputation = newReputation({})
        local clock = newClock()
        local index = ns.newFactionIndex({ reputation = reputation.client, after = clock.after,
            budget = 200, last = 400 })

        index.resolve("Argent Dawn")
        clock.drain()
        local walked = reputation.asked()

        assert.is_nil(index.resolve("Bilgewater Cartel"))

        assert.equal(walked, reputation.asked())
        assert.equal(0, clock.pending())
        assert.is_true(index.ready())
    end)

    -- A name two factions share is the very ambiguity the id exists to end, and a chat line says
    -- nothing about which of them was meant. The tie goes to the lower id whichever slice the
    -- rows fell in, so the same client always answers the same way — an index that answered
    -- differently depending on where a frame boundary landed would file the same gain under two
    -- different factions on two different logins.
    for _, case in ipairs({
        { what = "found in the same slice", budget = 200 },
        { what = "found in slices a frame apart", budget = 1 },
    }) do
        it("answers a name two factions share with the lower id, " .. case.what, function()
            local reputation = newReputation({
                [3] = { name = "Ravenholdt", factionID = 349 },
                [9] = { name = "Ravenholdt", factionID = 910 },
            })
            local clock = newClock()
            local index = ns.newFactionIndex({ reputation = reputation.client, after = clock.after,
                budget = case.budget, last = 10 })

            index.resolve("Ravenholdt")
            clock.drain()

            assert.equal(349, index.resolve("Ravenholdt"))
        end)
    end

    -- Most of a four-thousand-id range is not a faction at all, and `GetFactionDataByID` is
    -- `MayReturnNothing` in the client's own documentation. Nothing, and a half-filled row, are
    -- both answers the walk has to survive rather than index under a key nobody can ask about.
    it("walks past the ids that are not factions without indexing anything under them", function()
        local reputation = newReputation({
            [1] = nil,
            [2] = "not a table at all",
            [3] = { factionID = 100 },
            [4] = { name = "", factionID = 101 },
            [5] = { name = "Nameless Ones" },
            [6] = { name = "Wrong Sort Of Id", factionID = "102" },
            [7] = { name = "Argent Dawn", factionID = 529 },
        })
        local clock = newClock()
        local index = ns.newFactionIndex({ reputation = reputation.client, after = clock.after,
            last = 10 })

        index.resolve("Argent Dawn")
        clock.drain()

        assert.equal(529, index.resolve("Argent Dawn"))
        assert.is_nil(index.resolve(""))
        assert.is_nil(index.resolve("Nameless Ones"))
        assert.is_nil(index.resolve("Wrong Sort Of Id"))
    end)

    -- A row the client will not describe properly does not get to claim the name for good: the
    -- faction that reports both a name and an id is the one the name means, whether it is walked
    -- first or last.
    it("lets a complete row claim a name a broken row was found under first", function()
        local reputation = newReputation({
            [3] = { name = "Argent Dawn" },
            [4] = { name = "Argent Dawn", factionID = 529 },
        })
        local clock = newClock()
        local index = ns.newFactionIndex({ reputation = reputation.client, after = clock.after,
            last = 10 })

        index.resolve("Argent Dawn")
        clock.drain()

        assert.equal(529, index.resolve("Argent Dawn"))
    end)

    -- Nothing to ask about is not a miss, so it must not be what starts a four-thousand-call
    -- walk: a chat line that parsed into no faction name at all should cost nothing.
    it("is not provoked by being asked about nothing", function()
        local reputation = newReputation({})
        local clock = newClock()
        local index = ns.newFactionIndex({ reputation = reputation.client, after = clock.after })

        assert.is_nil(index.resolve(nil))
        assert.is_nil(index.resolve(""))
        assert.is_nil(index.resolve(529))

        assert.equal(0, reputation.asked())
        assert.equal(0, clock.pending())
    end)

    -- The lesson of #44 in the newest place it could be forgotten: a call this build does not
    -- define is a faction nobody can look up, not a Lua error out of a chat handler. The two
    -- roads either side of this one in `findFaction` still work exactly as they did before the
    -- index existed, so the honest answer here is nil, said once and said forever.
    describe("on a client it cannot walk", function()
        for _, case in ipairs({
            {
                what = "a build with no GetFactionDataByID to walk with",
                deps = function(clock)
                    return { reputation = {}, after = clock.after, last = 10 }
                end,
            },
            {
                what = "a caller that handed over no clock to spread the walk across",
                deps = function()
                    return { reputation = { GetFactionDataByID = print }, last = 10 }
                end,
            },
            {
                what = "no dependencies whatsoever",
                deps = function()
                    return nil
                end,
            },
        }) do
            it("answers nothing and raises nothing given " .. case.what, function()
                local clock = newClock()
                local index = ns.newFactionIndex(case.deps(clock))

                assert.is_false(index.ready())
                assert.is_nil(index.resolve("Argent Dawn"))

                -- Ready, because a miss that will never be answered has to be trusted as a "no":
                -- a caller told "not yet" forever would ask again at every gain for the session.
                assert.is_true(index.ready())
                assert.equal(0, clock.pending())
                assert.is_nil(index.resolve("Argent Dawn"))
            end)
        end
    end)
end)
