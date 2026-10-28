-- Q4 marker direction: a marker stored with direction D, stamped with
-- direction d, should give a ghost facing (D + d) % 16 at the rigid position.
local fmt = require("lib.fmt")
local G = require("lib.geom")
local B = require("lib.bp")
local A = require("lib.analysis")
local D = require("lib.designs")
local Q = {id = "Q4"}

local DIRS = {0, 4, 8, 12}

function Q.run()
  local bp = B.new(D.q4)
  local s = game.surfaces.nauvis
  local all_ok = true
  for _, d in ipairs(DIRS) do
    for _, P in ipairs({{x = 0, y = 0}, {x = 3, y = -5}, {x = -20, y = 17}}) do
      local rec = B.stamp(bp, s, P, d)
      local r = A.rigid(bp, rec)
      for _, g in pairs(rec.ghosts) do
        if g.name == "seb-spike-marker" then
          local e = bp.ents[g.i]
          local D0 = e.direction or 0
          local expect = (D0 + d) % 16
          local pos_pred = G.add(r.t, G.rot(e.position, d))
          local ok = g.dir == expect and G.same(pos_pred, g.pos) and g.in_ret
          all_ok = all_ok and ok
          fmt.verdict("Q4 d=" .. d .. " P=" .. fmt.p(P) .. " D=" .. D0, ok, "ghost_dir=" .. g.dir,
            "expect=" .. expect, "pos=" .. fmt.p(g.pos), "pos_pred=" .. fmt.p(pos_pred),
            "in_returned_array=" .. tostring(g.in_ret), "stamp_rigid=" .. tostring(r.rigid))
        end
      end
    end
  end
  fmt.verdict("Q4.summary", all_ok)
  bp.inv.destroy()
end

return Q
