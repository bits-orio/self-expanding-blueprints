-- Park-Miller generator so random designs are reproducible run to run.
local Rng = {}
Rng.__index = Rng

function Rng.new(seed)
  return setmetatable({s = seed}, Rng)
end

function Rng:next()
  self.s = (self.s * 16807) % 2147483647
  return self.s
end

function Rng:int(lo, hi)
  return lo + (self:next() % (hi - lo + 1))
end

function Rng:pick(list)
  return list[self:int(1, #list)]
end

return Rng
