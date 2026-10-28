-- A project's open sockets: the frontier, plus the sockets parked because
-- no construction robots reach them. Coverage grows without an engine event
-- (roboports gain power and robots silently), so the project returns parked
-- sockets to the frontier on a slow timer.
--
-- project.frontier is every open socket in no particular order, the list
-- the window, the remote interface and the builder count. A socket leaves
-- it in constant time however many are open (a plan of a design with many
-- sockets holds thousands): the last one takes its place (socket.slot).
-- The order they are tried in is kept beside it, oldest first, in
-- project.frontier_queue ({first, last, [i] = socket}): breadth-first takes
-- the front, depth-first the back. Nearest-first, which only the remote
-- interface asks for, looks through them all; socket.seq says which of two
-- is older. Only this module changes project.frontier once it exists.

local const = require("scripts.const")
local geometry = require("scripts.core.geometry")
local scheduler = require("scripts.core.scheduler")

local frontier = {}

-- Just outside the middle of a footprint edge: where an implicit socket draws.
local function edge_point(box, toward)
  local c = geometry.box_center(box)
  if toward == geometry.EAST then return { x = box.right + 0.5, y = c.y } end
  if toward == geometry.WEST then return { x = box.left - 0.5, y = c.y } end
  if toward == geometry.SOUTH then return { x = c.x, y = box.bottom + 0.5 } end
  return { x = c.x, y = box.top - 0.5 }
end

-- The sockets a copy opens once it is finished: the drawn ones of the
-- version it was stamped from, or, for a version of the project's own
-- design without any, implicit ones toward each of the project's
-- directions. A plain design that a drawn socket names is an end piece and
-- opens nothing. The overlay draws them ahead of time (overlay.lua).
function frontier.sockets_of(project, instance)
  local list = {}
  if #instance.sockets == 0 then
    if instance.design_id ~= project.design_id then return list end
    for _, toward in ipairs(project.directions) do
      list[#list + 1] = {
        kind = "implicit", from = instance.id, toward = toward, direction = toward,
        position = edge_point(instance.footprint, toward),
      }
    end
    return list
  end
  for i, s in ipairs(instance.sockets) do
    list[#list + 1] = {
      kind = "drawn", from = instance.id, index = i, position = s.position, direction = s.direction, target = s.target,
    }
  end
  return list
end

-- A project's first socket (projects.lua makes the list) and a save from
-- before the queue are indexed on first use: their list is in the order
-- the sockets opened.
local function indexed(project)
  if project.frontier_seq then return end
  local queue = { first = 1, last = 0 }
  for i, socket in ipairs(project.frontier) do
    socket.slot, socket.seq, queue[i], queue.last = i, i, socket, i
  end
  project.frontier_seq = queue.last
  if project.order ~= "nearest" then project.frontier_queue = queue end
end

local function push(project, socket)
  local list, seq = project.frontier, project.frontier_seq + 1
  local n = #list + 1
  list[n], socket.slot, socket.seq, project.frontier_seq = socket, n, seq, seq
  local queue = project.frontier_queue
  if not queue then return end
  queue.last = queue.last + 1
  queue[queue.last] = socket
end

-- Opens a finished copy's sockets.
function frontier.open(project, instance)
  indexed(project)
  for _, socket in ipairs(frontier.sockets_of(project, instance)) do push(project, socket) end
end

-- Gaps (false) at either end of the queue go.
local function trim(queue)
  while queue.first <= queue.last and not queue[queue.first] do
    queue[queue.first], queue.first = nil, queue.first + 1
  end
  while queue.last >= queue.first and not queue[queue.last] do
    queue[queue.last], queue.last = nil, queue.last - 1
  end
end

-- The socket tried is at the end it was taken from, unless sockets opened
-- while it was tried (an event handler calling back in) went after it:
-- then its place is looked for and left as a gap.
local function unqueue(queue, socket)
  if queue[queue.first] == socket then
    queue[queue.first], queue.first = nil, queue.first + 1
  elseif queue[queue.last] == socket then
    queue[queue.last], queue.last = nil, queue.last - 1
  else
    for i = queue.first, queue.last do
      if queue[i] == socket then queue[i] = false break end
    end
  end
  trim(queue)
end

local function distance2(a, b)
  return (a.x - b.x) ^ 2 + (a.y - b.y) ^ 2
end

local function before(d, seq, entry)
  return d < entry.d or (d == entry.d and seq < entry.seq)
end

-- The `n` sockets nearest the seed, nearest first, the older of two as
-- near; with no seed, the oldest.
local function nearest(project, n)
  local seed, best = project.seed_position, {}
  for _, socket in ipairs(project.frontier) do
    local d, seq, i = seed and distance2(socket.position, seed) or 0, socket.seq, #best
    if i < n or (i > 0 and before(d, seq, best[i])) then
      while i > 0 and before(d, seq, best[i]) do best[i + 1], i = best[i], i - 1 end
      best[i + 1], best[n + 1] = { d = d, seq = seq, socket = socket }, nil
    end
  end
  local out = {}
  for i, entry in ipairs(best) do out[i] = entry.socket end
  return out
end

-- Where in the queue a project starts trying, where it ends and its step:
-- the oldest first (breadth-first, the default) or the newest first
-- (depth-first: one arm grows out before the next starts).
local function order_of(project, queue)
  if project.order == "depth" then return queue.last, queue.first, -1 end
  return queue.first, queue.last, 1
end

-- Up to `n` open sockets in the order they are tried in; nearest-first
-- tries the one nearest the seed (a compact blob). The overlay draws these.
function frontier.ahead(project, n)
  indexed(project)
  local queue = project.frontier_queue
  if not queue then return nearest(project, n) end
  local out, from, to, by = {}, order_of(project, queue)
  for i = from, to, by do
    if #out >= n then break end
    if queue[i] then out[#out + 1] = queue[i] end
  end
  return out
end

-- The socket a project tries next, or nil. The ends of the queue are never
-- gaps (trim).
function frontier.peek(project)
  indexed(project)
  local queue = project.frontier_queue
  if not queue then return nearest(project, 1)[1] end
  return queue[(order_of(project, queue))] or nil
end

-- Where that socket is in project.frontier, for its readers.
function frontier.next_index(project)
  local socket = frontier.peek(project)
  return socket and socket.slot
end

-- The socket tried leaves the frontier (it stamped, was planned, closed or
-- is parked); false when it had already gone (its project was stopped
-- while it was tried).
function frontier.take(project, socket)
  indexed(project)
  local list, i = project.frontier, socket.slot
  if not i or list[i] ~= socket then return false end
  local last = list[#list]
  list[i], last.slot = last, i
  list[#list], socket.slot = nil, nil
  if project.frontier_queue then unqueue(project.frontier_queue, socket) end
  return true
end

-- The socket tried goes to the parked list; the first one parked arms the
-- timer that brings them all back (kind "unpark", handled by loop.lua).
function frontier.park(project, socket)
  if not frontier.take(project, socket) then return end
  local parked = project.parked
  parked[#parked + 1] = socket
  if project.unpark_tick then return end
  project.unpark_tick = game.tick + const.NETWORK_RETRY
  scheduler.at(project.unpark_tick, { kind = "unpark", id = project.id })
end

-- Parked sockets go to the back of the frontier, to be tried again.
function frontier.unpark(project)
  indexed(project)
  project.unpark_tick = nil
  local parked = project.parked
  project.parked = {}
  for _, socket in ipairs(parked) do push(project, socket) end
end

-- Open sockets not yet tried for good, parked ones included.
function frontier.pending(project)
  return #project.frontier + #project.parked
end

function frontier.clear(project)
  project.frontier, project.parked = {}, {}
  project.frontier_seq = project.frontier_seq or 0
  project.frontier_queue = project.order ~= "nearest" and { first = 1, last = 0 } or nil
end

return frontier
