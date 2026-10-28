-- Each team's share of the server's time (DESIGN.md D44). Heavy work a team
-- asks for (a growth step, a builder's request, a design registered) is
-- charged to its force in estimated microseconds, and the force's account
-- refills at the map's rate per tick (seb-work-per-force, limits.lua). The
-- whole server's account is charged too, which the teams take in turns
-- (seb-work-per-tick, server_budget.lua). A piece of work may overdraw its
-- team's account, so nothing is ever too big to run; the team then waits
-- until the debt is paid. Over time a team uses about its share of each
-- tick, and all teams together about the server's; but a piece is charged
-- after it ran, so one big piece can still be a long tick: its own team
-- pays it off, and the others wait at most for the next run of the due-tick
-- queue. There is no timer: an account is brought up to date when read.

local limits = require("scripts.core.limits")
local server_budget = require("scripts.core.server_budget")

local budget = {}

-- Estimated microseconds per unit of work, measured on 2.1 headless
-- (spikes S5 and S6, the griefing review and its follow-up). 50 builders
-- taking a request every read with 346 signals on their inputs cost 1.6 ms
-- a tick more than with none; the 289 chunks of a 512-tile picture cell
-- took 35 to 40 ms to make; an 80,000-lamp blueprint, 526 kB, took 1.0 to
-- 1.2 s to export and 0.1 s to import (2.1 to 3.2 µs a byte together,
-- charged as 3); a book of 400 one-lamp blueprints registered at 0.45 ms
-- each on a quiet machine and 1.6 ms on a loaded one, of which their parts
-- and strings are charged 0.3 to 0.4 ms.
budget.COST = {
  check_part = 2,          -- checking where a part would go
  part_in_way = 10,        -- looking up what is in a part's way when anything is (11.5 µs a part in all, superforced)
  water_tile = 0.005,      -- looking over a tile of a footprint for water (1.3 ms for 512 x 512 tiles, D52)
  stamp_part = 10,         -- stamping a part as a ghost
  pole = 40,               -- an electric pole's ghost wiring itself to the poles in reach (28 µs each in a carpet of 1,000)
  register_part = 35,      -- preparing a part of a design that is registered (four calibration stamps, a picture)
  register_pole = 100,     -- the five pastes registering makes of an electric pole (85 µs each in a carpet of 1,000)
  register_design = 1500,  -- the fixed part of registering a design, whatever its size: those stamps and picture
  builder_read = 20,       -- reading a builder
  input_signal = 1,        -- copying a signal of a builder's input into Lua as it takes a request
  area_tile = 1,           -- looking at a tile of an area
  lab_chunk = 130,         -- making a chunk of a lab surface with what the engine lays out around it
  blueprint_byte = 3,      -- exporting and importing a byte of a blueprint string
  book_walk = 6000,        -- adding a book: looking at up to 1,000 children and pricing up to 250,000 parts
  spot = 20,               -- one design tried at one spot: placement, rules, preview room, terrain walk's fixed part
  chunk = 1,               -- a chunk of a footprint the terrain check looks at
  probe = 5,               -- a probe evaluated
  stamp = 80,              -- the fixed part of a stamp: its record, registrations, overlay (one chest took 90 µs)
  update_copy = 500,       -- the fixed part of updating one copy to a newer version
}

-- An idle force saves up at most this many ticks of work.
local SAVED_TICKS = 60

local function rate(force_index)
  return limits.of(force_index, "work")
end

local function account(force_index, r)
  storage.budgets = storage.budgets or {}
  local now = game.tick
  local a = storage.budgets[force_index]
  if not a then
    a = { level = r * SAVED_TICKS, tick = now }
    storage.budgets[force_index] = a
  end
  a.level = math.min(r * SAVED_TICKS, a.level + (now - a.tick) * r)
  a.tick = now
  return a
end

-- Whether the force may start more work now: its own account is not in
-- debt and the server's lets it.
function budget.ready(force_index)
  local r = rate(force_index)
  if r > 0 and account(force_index, r).level < 0 then return false end
  return server_budget.ready(force_index)
end

-- Charges `cost` microseconds of work to the force, and to the server.
function budget.charge(force_index, cost)
  if cost <= 0 then return end
  local r = rate(force_index)
  if r > 0 then
    local a = account(force_index, r)
    a.level = a.level - cost
  end
  server_budget.charge(force_index, cost)
end

-- Ticks until the force may work again: until its own debt is paid, or 1
-- when it may now or only the server holds it (its turn comes at a next
-- run of the queue).
function budget.wait(force_index)
  local r = rate(force_index)
  if r == 0 then return 1 end
  local level = account(force_index, r).level
  if level >= 0 then return 1 end
  return math.max(1, math.ceil(-level / r))
end

function budget.drop_force(force_index)
  if storage.budgets then storage.budgets[force_index] = nil end
  server_budget.drop_force(force_index)
end

return budget
