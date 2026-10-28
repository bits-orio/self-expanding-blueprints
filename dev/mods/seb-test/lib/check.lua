-- Assertions that log instead of throwing, so one broken case never hides
-- the rest. dev/run-tests.sh greps the SEB_TEST lines.

local check = {}

local function say(line)
  log("SEB_TEST " .. line)
end

local function tally(key)
  storage.tally = storage.tally or { pass = 0, fail = 0 }
  storage.tally[key] = storage.tally[key] + 1
end

function check.pass(case)
  tally("pass")
  say("PASS " .. case)
end

function check.fail(case, detail)
  tally("fail")
  say("FAIL " .. case .. ": " .. tostring(detail))
end

function check.info(text)
  say("INFO " .. text)
end

local function show(value)
  if type(value) == "table" then return serpent.line(value, { sortkeys = true, comment = false }) end
  return tostring(value)
end
check.show = show

function check.eq(case, got, want)
  if got == want then return check.pass(case) end
  check.fail(case, "got " .. show(got) .. ", want " .. show(want))
end

-- Deep equality through a canonical serialisation: good enough for the plain
-- data tables the contract returns.
function check.same(case, got, want)
  if show(got) == show(want) then return check.pass(case) end
  check.fail(case, "got " .. show(got) .. ", want " .. show(want))
end

function check.near(case, got, want, tolerance)
  if type(got) == "number" and math.abs(got - want) <= (tolerance or 1e-6) then return check.pass(case) end
  check.fail(case, "got " .. show(got) .. ", want " .. show(want) .. " +- " .. show(tolerance or 1e-6))
end

function check.truthy(case, value, detail)
  if value then return check.pass(case) end
  check.fail(case, detail or ("got " .. show(value)))
end

-- Runs one case body; an error inside it becomes a FAIL line with its message.
function check.run(case, body)
  local ok, err = pcall(body)
  if not ok then check.fail(case, "error: " .. tostring(err)) end
end

function check.done()
  local t = storage.tally or { pass = 0, fail = 0 }
  say(string.format("DONE pass=%d fail=%d", t.pass, t.fail))
end

return check
