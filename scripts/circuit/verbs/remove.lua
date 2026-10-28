-- Remove: retire the instance whose number is in the Instance signal,
-- exactly as a right-drag would. DONE once it is gone.

local const = require("scripts.const")
local instances = require("scripts.core.instances")
local answer = require("scripts.circuit.answer")

local remove = {}

function remove.start(b, request, input)
  local instance = storage.instances[input.virtual["seb-instance"] or 0]
  if not (instance and instance.force_index == b.entity.force.index) then return answer.fail(b, "not-found") end
  request.instance_id = instance.id
  instances.retire(instance)
  remove.tick(b, request)
end

function remove.tick(b, request)
  local instance = storage.instances[request.instance_id]
  if not instance or instance.state == const.STATE.retired then return answer.done(b) end
end

return remove
