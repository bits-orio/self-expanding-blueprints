-- Names, tag keys, states, reasons and tunables shared across the mod.

local const = {}

const.MOD = "self-expanding-blueprints"
const.GRAPHICS = "__" .. const.MOD .. "__/graphics/"   -- also read by the prototypes

-- Prototypes
const.SOCKET = "seb-socket"
const.ENTRY = "seb-entry"
-- Added to the mod's internal copy of every design so calibration has one
-- entity it can always find; players never see or place it.
const.ANCHOR = "seb-anchor"
-- Ore sensor: a design's copies open their sockets once the ore it watches
-- is gone. RADIUS_SIGNAL in it sets the square it watches.
const.SENSOR = "seb-sensor"
const.RADIUS_SIGNAL = "signal-R"
-- Probe: a fact that must hold on its tile before a design is stamped there.
const.PROBE = "seb-probe"
-- Port: marks the combinator under it as a copy's circuit mailbox.
const.PORT = "seb-port"
-- Keep clear: a tile the design needs empty (clearance.lua).
const.CLEAR = "seb-keep-clear"
const.MARKERS = {
  [const.SOCKET] = true, [const.ENTRY] = true, [const.SENSOR] = true, [const.PROBE] = true, [const.PORT] = true,
  [const.CLEAR] = true, [const.ANCHOR] = true,
}
-- Other mods' markers a design may carry, and what they mean here: Negative
-- Space's plain marker keeps its tile clear; its automatic belt and pipe
-- markers are left out (their logic runs only on a player's own paste).
const.FOREIGN_MARKERS = { ["negative-space"] = "clear", ["negative-space-auto"] = "drop" }
-- The blueprint builder and the hidden combinator that drives its output.
const.BUILDER = "seb-builder"
const.BUILDER_OUTPUT = "seb-builder-output"
const.TOOL = "seb-grow-tool"
const.CLEAR_TOOL = "seb-keep-clear-tool"
const.SENSOR_TOOL = "seb-sensor-tool"
-- The chosen design in hand while growing, inside a dashed frame of its own
-- entities (grow_cursor.lua).
const.GROW_BLUEPRINT = "seb-grow-blueprint"
const.FRAME = "seb-grow-frame"
-- Copies a plan made in the window lays out unless the player asks for more.
const.PLAN_COPIES = 5
-- Copies growth started from the window stops after unless the player sets
-- another count, or clears it for none.
const.GROW_COPIES = 4
const.TOGGLE = "seb-toggle-window"
const.CALIBRATION_SURFACE = "seb-calibration"
const.GALLERY_SURFACE = "seb-gallery"

-- The tag every stamped ghost carries; built events hand it back.
const.TAG = "seb_instance"

const.STATE = {
  building = "building",
  complete = "complete",
  incomplete = "incomplete",
  stalled = "stalled",
  retiring = "retiring",
  retired = "retired",
}

const.PROJECT_STATE = {
  growing = "growing",
  paused = "paused",
  finished = "finished",
  stopped = "stopped",
}

-- Why a socket closed, or why a stamp or request was refused.
const.REASON = {
  joined = "joined",
  -- A new project's first copy would stand on copies already there.
  seed_occupied = "seed-occupied",
  water = "water",
  cliff = "cliff",
  building = "building",
  uncharted = "uncharted",
  outside_area = "outside-area",
  count_reached = "count-reached",
  unknown_design = "unknown-design",
  invalid_design = "invalid-design",
  no_network = "no-network",
  missing_materials = "missing-materials",
  stamp_short = "stamp-short",
  ghost_removed = "ghost-removed",
  no_progress = "no-progress",
  no_resource = "no-resource",
  off_grid = "off-grid",
  misaligned = "misaligned",
  overlaps_parent = "overlaps-parent",
  parent_retired = "parent-retired",
  -- Gates that hold the head of a project's frontier.
  capacity = "capacity",
  chunks = "chunks",
  -- A finished copy whose ore sensors still see ore.
  ore_left = "ore-left",
  -- A socket whose next copy would stand on the copy it grows from, which is
  -- going for depletion: it waits, out of the frontier, until that copy is gone.
  parent_retiring = "parent-retiring",
  -- A probe of the design does not hold where it would land.
  probe = "probe",
  -- Land Title Registry: the land is not held well enough for a part.
  held_land = "held-land",
  -- Too close to enemy spawners or turrets (the enemy_distance rule).
  enemies = "enemies",
  -- A map setting caps the force's projects or copies in flight.
  too_many_projects = "too-many-projects",
  robots_busy = "robots-busy",
  -- Limits that keep one team from slowing the server for all (D44, D45):
  -- the team's share of server time is used up for now (a gate), it has
  -- as many designs as the map allows, or a design is too big to register.
  busy = "busy",
  too_many_designs = "too-many-designs",
  design_too_big = "design-too-big",
  -- A design draws more sockets than const.MAX_DESIGN_SOCKETS.
  too_many_sockets = "too-many-sockets",
  -- A design has more electric poles than const.MAX_DESIGN_POLES.
  too_many_poles = "too-many-poles",
}

-- Tunables (ticks unless named otherwise)
const.QUIET_TICKS = 30          -- recount once built/destroyed events go quiet this long
const.MAX_RECOUNT_WAIT = 120    -- ...but never later than this after the first event
const.STALL_TICKS = 3 * 3600    -- no progress for this long marks an instance stalled
const.MATERIALS_RETRY = 180     -- re-check a materials-gated socket this often
const.NETWORK_RETRY = 600       -- re-try sockets parked because no robots reach them
const.ADVANCE_BUDGET = 4        -- stamps attempted per project per scheduler run
const.MAX_BUILDING = 2          -- default instances in flight per project
const.MAX_BLOCKED_KEPT = 50     -- blocked sockets a project remembers for the overlay
const.ORE_CHECK_DELAY = 60      -- after ore runs out under a sensor, look again this much later
const.DRAIN_TICKS = 600         -- a copy whose drills ran dry retires this much later (output drains)
const.MAX_DESIGN_SPAN = 512     -- tiles a design (markers included) may reach across, either way
const.ENDED_PROJECTS_KEPT = 30  -- finished and stopped projects a force keeps; older ones are forgotten
const.MAX_DRAWN_SOCKETS = 100   -- open-socket arrows the overlay draws per project (and as many parked)
const.MAX_DESIGN_SOCKETS = 64   -- drawn sockets a design may have when it is registered
-- Electric poles a design may have when it is registered: a pole's ghost
-- wires itself to every pole in reach, so a carpet of them costs more the
-- bigger it is. One of 1,000 took 28 ms to stamp and 122 ms to register,
-- about what the biggest design without poles takes; one of 4,900 took
-- 546 ms and 2.4 s.
const.MAX_DESIGN_POLES = 1000
const.MAX_BOOK_CHILDREN = 1000  -- children a book walk looks at, inner books' too; a bigger book is refused
const.MAX_BOOK_PARTS = 250000   -- parts, tiles included, of the blueprints a book adds; copying more holds up the game
const.BOOK_CLICK_PARTS = 2000   -- parts of library blueprints exported on the click; the rest wait their turn
const.MAX_LIBRARY_DESIGNS = 30000   -- designs a force keeps whatever the setting (two library slots each)

return const
