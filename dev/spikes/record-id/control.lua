-- Spike: blueprint library records. What identifies a record
-- (LuaRecord.shelf_index and record_id, 2.1.25), when the id changes, and
-- what on_gui_opened and on_gui_closed say about a record. See FINDINGS.md.
-- Every result is a log line starting "RP ".
--
-- A script cannot make a library record, so most of the probe is done by
-- hand in a client: this mod logs every on_gui_opened and on_gui_closed, and
-- the remote interface "rp" has the console helpers for the steps in
-- FINDINGS.md. Headless (run.sh), it lists the library once at tick 30.
local function say(s) log("RP " .. s) end

-- One record on one line. Each field is read through pcall, so a field the
-- engine does not have shows as ERR:<message> instead of stopping the probe.
local function describe(record)
  if record == nil then return "nil" end
  if not record.valid then return "invalid" end
  local out = {}
  local function field(key, read)
    local ok, value = pcall(read)
    out[#out + 1] = key .. "=" .. (ok and tostring(value) or ("ERR:" .. tostring(value):sub(1, 80)))
  end
  field("type", function() return record.type end)
  field("name", function() return record.name end)
  field("shelf_index", function() return record.shelf_index end)
  field("record_id", function() return record.record_id end)
  field("valid_for_write", function() return record.valid_for_write end)
  field("label", function() return record.label end)
  field("setup", function() return record.is_blueprint_setup and record.is_blueprint_setup() end)
  field("nent", function() return record.get_blueprint_entity_count() end)
  -- For a book: index:shelf_index/record_id/label of each record in it.
  field("contents", function()
    local t = {}
    for i, child in pairs(record.contents) do
      t[#t + 1] = i .. ":" .. child.shelf_index .. "/" .. child.record_id .. "/" .. tostring(child.label)
    end
    return table.concat(t, ",")
  end)
  return table.concat(out, " ")
end

-- The game shelf, then every player's own shelf and cursor record.
local function dump(tag)
  say(tag .. " game.blueprints n=" .. #game.blueprints)
  for i, record in ipairs(game.blueprints) do say("  G[" .. i .. "] " .. describe(record)) end
  for _, player in pairs(game.players) do
    say(tag .. " player " .. player.index .. " blueprints n=" .. #player.blueprints)
    for i, record in ipairs(player.blueprints) do say("  P" .. player.index .. "[" .. i .. "] " .. describe(record)) end
    say("  cursor_record=" .. describe(player.cursor_record))
  end
end

local function object_name(value)
  if type(value) ~= "userdata" then return type(value) end
  local ok, name = pcall(function() return value.object_name end)
  return ok and name or "userdata"
end

local function opened_info(player)
  local opened = player.opened
  local s = "opened=" .. object_name(opened) .. " opened_gui_type=" .. tostring(player.opened_gui_type)
  if opened and object_name(opened) == "LuaRecord" then s = s .. " [" .. describe(opened) .. "]" end
  return s
end

local EVENT_FIELDS = { "gui_type", "record", "item", "entity", "element", "inventory", "other_player" }

local function log_gui_event(name)
  return function(e)
    local shown = {}
    for _, key in pairs(EVENT_FIELDS) do
      local ok, value = pcall(function() return e[key] end)
      if ok and value ~= nil then
        if key == "record" then
          value = "{" .. describe(value) .. "}"
        elseif key == "item" then
          value = "item:" .. tostring(value.valid_for_read and value.name) .. " label=" .. tostring(value.valid_for_read and value.label)
        end
        shown[#shown + 1] = key .. "=" .. tostring(value)
      end
    end
    say(name .. " tick=" .. e.tick .. " p=" .. e.player_index .. " fields: " .. table.concat(shown, " ; "))
    say("   " .. opened_info(game.get_player(e.player_index)))
  end
end

script.on_event(defines.events.on_gui_opened, log_gui_event("on_gui_opened"))
script.on_event(defines.events.on_gui_closed, log_gui_event("on_gui_closed"))

script.on_event(defines.events.on_player_joined_game, function(e)
  say("joined p=" .. e.player_index .. " is_mp=" .. tostring(game.is_multiplayer()))
  dump("joined")
end)

local function log_gui_types()
  local list = {}
  for name, value in pairs(defines.gui_type) do list[#list + 1] = name .. "=" .. value end
  table.sort(list)
  say("gui_type enum: " .. table.concat(list, " "))
end

-- The first empty blueprint in the player's inventory.
local function empty_blueprint(player)
  local inventory = player.get_main_inventory()
  for i = 1, #inventory do
    local stack = inventory[i]
    if stack.valid_for_read and stack.name == "blueprint" and not stack.is_blueprint_setup() then return stack end
  end
end

local function one_entity(name) return { { entity_number = 1, name = name, position = { 0.5, 0.5 } } } end

-- Console helpers: /c remote.call("rp", "<name>", ...)
remote.add_interface("rp", {
  -- Lists both shelves under a tag of your choice.
  dump = function(tag) dump(tag or "dump") end,

  -- Three labelled blueprints (BP-A, BP-B, BP-C) and a book (BOOK-1) holding
  -- one blueprint (BP-IN-BOOK) into the player's inventory, to be put into
  -- the library by hand.
  give = function(player_index)
    local player = game.get_player(player_index or 1)
    if player.cursor_stack then player.cursor_stack.clear() end
    for _, spec in pairs { { "BP-A", "iron-chest" }, { "BP-B", "wooden-chest" }, { "BP-C", "steel-chest" } } do
      player.insert { name = "blueprint" }
      local stack = empty_blueprint(player)
      stack.set_blueprint_entities(one_entity(spec[2]))
      stack.label = spec[1]
    end
    player.insert { name = "blueprint-book" }
    local inventory = player.get_main_inventory()
    for i = 1, #inventory do
      local stack = inventory[i]
      if stack.valid_for_read and stack.name == "blueprint-book" then
        stack.label = "BOOK-1"
        local pages = stack.get_inventory(defines.inventory.item_main)
        pages.insert { name = "blueprint" }
        pages[1].set_blueprint_entities(one_entity("small-lamp"))
        pages[1].label = "BP-IN-BOOK"
        break
      end
    end
  end,

  -- A copy of library record <slot> as a new blueprint item in the inventory
  -- (export_record, then import_stack), to be put into the library by hand.
  duplicate = function(player_index, slot)
    local player = game.get_player(player_index or 1)
    local exported = player.blueprints[slot or 3].export_record()
    say("DUP export len=" .. #exported)
    player.insert { name = "blueprint" }
    local stack = empty_blueprint(player)
    stack.import_stack(exported)
    say("DUP imported label=" .. tostring(stack.label))
  end,

  -- Edits the first game-shelf record from script: new entities, a new
  -- label, then cleared.
  edit_game_record = function()
    local record = game.blueprints[1]
    record.set_blueprint_entities {
      { entity_number = 1, name = "small-lamp", position = { 0.5, 0.5 } },
      { entity_number = 2, name = "iron-chest", position = { 2.5, 0.5 } },
    }
    record.label = "GAME-EDITED"
    say("GEDIT rid=" .. record.record_id .. " shelf=" .. record.shelf_index .. " nent=" .. record.get_blueprint_entity_count())
    record.clear_blueprint()
    say("GEDIT cleared setup=" .. tostring(record.is_blueprint_setup()) .. " rid=" .. record.record_id
      .. " valid=" .. tostring(record.valid))
  end,

  -- What every book on the player's shelf holds.
  book = function(player_index)
    for _, record in ipairs(game.get_player(player_index or 1).blueprints) do
      if record.type == "blueprint-book" then
        say("BOOKC book rid=" .. record.record_id .. " size=" .. record.contents_size)
        for i, child in pairs(record.contents) do
          say("BOOKC idx=" .. i .. " type=" .. child.type .. " shelf=" .. child.shelf_index .. " rid=" .. child.record_id
            .. " label=" .. tostring(child.label))
        end
      end
    end
  end,
})

script.on_init(function()
  -- A character at once in freeplay, for the steps done by hand.
  if remote.interfaces.freeplay then
    remote.call("freeplay", "set_skip_intro", true)
    remote.call("freeplay", "set_disable_crashsite", true)
  end
end)

-- After a save is loaded: the enum and both shelves, on the first tick.
local just_loaded = false
script.on_load(function()
  just_loaded = true
  log("RP on_load ran")
end)

-- script.test_arg throws before 2.1.24.
local arg_ok, test_arg = pcall(function() return script.test_arg end)
if not arg_ok then test_arg = nil end

script.on_event(defines.events.on_tick, function(e)
  if just_loaded then
    just_loaded = false
    log_gui_types()
    dump("afterload tick=" .. e.tick)
  end
  -- Headless (run.sh): list the library once and end the run.
  if test_arg == "dump" and e.tick == 30 then
    log_gui_types()
    dump("t30")
    say("DONE")
    script.finish_test(true)
  end
end)
