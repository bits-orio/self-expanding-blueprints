-- After a mod change the prototypes under a design may differ (entity sizes,
-- our own markers), so every design is prepared again. Not all in the one
-- tick of the change: each is marked stale, the due-tick queue prepares a
-- few per run, and one fetched for use before its turn is prepared on the
-- spot (library.get and library.find), so nothing stamps from an old
-- preparation. A design is fresh unless marked, so older saves need nothing.

local scheduler = require("scripts.core.scheduler")
local library = require("scripts.core.library")

local stale = {}

local KIND = "reprepare-designs"
local EVERY = 30     -- ticks between runs: anything used is prepared on the spot anyway
local PER_RUN = 8    -- designs prepared per run at most (and library.RUN_PARTS)

local function queue(tick)
  storage.reprepare_queued = true
  scheduler.at(tick, { kind = KIND })
end

-- The next few stale designs of any force, prepared again; the job ends
-- when none is left.
local function run(_, now)
  local count, parts = 0, 0
  for _, lib in pairs(storage.libraries) do
    for _, design in pairs(lib.designs) do
      if design.stale then
        if count == PER_RUN or parts >= library.RUN_PARTS then return queue(now + EVERY) end
        library.reprepare(design)
        count, parts = count + 1, parts + library.parts_of(design)
      end
    end
  end
  storage.reprepare_queued = nil
end
scheduler.register(KIND, run)

-- On configuration change: every design of every force needs preparing again.
function stale.mark_all()
  local any = false
  for _, lib in pairs(storage.libraries) do
    for _, design in pairs(lib.designs) do
      design.stale = true
      any = true
    end
  end
  if any and not storage.reprepare_queued then queue(game.tick + EVERY) end
end

return stale
