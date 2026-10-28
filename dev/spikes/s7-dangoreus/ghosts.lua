-- Ghost creation of markers on plain ground, by script, and their boxes.
return function(report)
  local surface, force = game.surfaces.nauvis, game.forces.player
  for i, name in ipairs({ "seb-sensor", "seb-socket", "constant-combinator" }) do
    local g = surface.create_entity { name = "entity-ghost", inner_name = name, position = { 3.5, 1.5 + i * 2 }, force = force }
    report(name .. " ghost on plain ground", g and g.valid)
    if g then report(name .. " ghost box", serpent.line(g.bounding_box)) end
    local e = surface.create_entity { name = name, position = { 7.5, 1.5 + i * 2 }, force = force }
    if e then report(name .. " entity box", serpent.line(e.bounding_box)) end
  end
end
