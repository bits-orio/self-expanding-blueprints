-- A due-tick task queue run from on_tick. Tasks are named functions in
-- S.tasks, so storage only holds names and plain arguments.
local S = {tasks = {}}

function S.at(tick, task, arg)
  storage.todo = storage.todo or {}
  local list = storage.todo[tick]
  if not list then
    list = {}
    storage.todo[tick] = list
  end
  list[#list + 1] = {task = task, arg = arg}
end

function S.run(tick)
  local list = storage.todo and storage.todo[tick]
  if not list then return end
  storage.todo[tick] = nil
  for _, item in ipairs(list) do
    local fn = S.tasks[item.task]
    if not fn then error("sched: no task " .. tostring(item.task)) end
    fn(item.arg)
  end
end

return S
