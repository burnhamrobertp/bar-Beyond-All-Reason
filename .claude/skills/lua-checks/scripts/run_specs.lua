-- A busted stand-in for running this repo's specs under plain LuaJIT.
--
-- CI runs the real thing (`lx --lua-version 5.1 test`). This exists because lux and busted
-- are often not installed locally, and compiling a spec with loadfile only proves it parses.
--
--   luajit .claude/skills/lua-checks/scripts/run_specs.lua spec/path/a_spec.lua [more...]
--
-- Loads the repo's own spec/spec_helper.lua, so the Spring/VFS/Game stubs are the ones the
-- specs are written against rather than an approximation of them.

local paths = { ... }
if #paths == 0 then
	io.stderr:write("usage: luajit run_specs.lua <spec file> [...]\n")
	os.exit(2)
end

local passed, failed, skipped = 0, 0, 0
local failures = {}
local stack = {}
local beforeStack = {}
local afterStack = {}

local function render(v, seen)
	if type(v) ~= "table" then
		return type(v) == "string" and ("%q"):format(v) or tostring(v)
	end
	seen = seen or {}
	if seen[v] then
		return "<cycle>"
	end
	seen[v] = true
	local parts, n = {}, 0
	for _, item in ipairs(v) do
		n = n + 1
		parts[n] = render(item, seen)
	end
	for k, item in pairs(v) do
		if type(k) ~= "number" or k > n or k < 1 then
			parts[#parts + 1] = tostring(k) .. "=" .. render(item, seen)
		end
	end
	return "{" .. table.concat(parts, ", ") .. "}"
end

local function deepEqual(a, b)
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for k, v in pairs(a) do
		if not deepEqual(v, b[k]) then
			return false
		end
	end
	for k in pairs(b) do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local function fail(message)
	error(message, 3)
end

-- Only the assertions this repo's specs actually reach for. An unknown one raises rather
-- than silently passing, since a missing assertion that returns nil reads as a pass.
local assertions = {
	is_nil = function(v)
		if v ~= nil then
			fail("expected nil, got " .. render(v))
		end
	end,
	is_not_nil = function(v)
		if v == nil then
			fail("expected a value, got nil")
		end
	end,
	is_true = function(v)
		if v ~= true then
			fail("expected true, got " .. render(v))
		end
	end,
	is_false = function(v)
		if v ~= false then
			fail("expected false, got " .. render(v))
		end
	end,
	is_truthy = function(v)
		if not v then
			fail("expected truthy, got " .. render(v))
		end
	end,
	is_falsy = function(v)
		if v then
			fail("expected falsy, got " .. render(v))
		end
	end,
	is_table = function(v)
		if type(v) ~= "table" then
			fail("expected a table, got " .. type(v))
		end
	end,
	is_string = function(v)
		if type(v) ~= "string" then
			fail("expected a string, got " .. type(v))
		end
	end,
	is_number = function(v)
		if type(v) ~= "number" then
			fail("expected a number, got " .. type(v))
		end
	end,
	is_function = function(v)
		if type(v) ~= "function" then
			fail("expected a function, got " .. type(v))
		end
	end,
	has_error = function(fn, expected)
		local ok, err = pcall(fn)
		if ok then
			fail("expected an error, none raised")
		end
		if expected ~= nil and not tostring(err):find(tostring(expected), 1, true) then
			fail("expected error matching " .. render(expected) .. ", got " .. render(err))
		end
	end,
	no_error = function(fn)
		local ok, err = pcall(fn)
		if not ok then
			fail("expected no error, got " .. render(err))
		end
	end,
}

local equality = {
	equal = function(expected, actual)
		if expected ~= actual then
			fail("expected " .. render(expected) .. ", got " .. render(actual))
		end
	end,
	same = function(expected, actual)
		if not deepEqual(expected, actual) then
			fail("expected " .. render(expected) .. ", got " .. render(actual))
		end
	end,
	equals = function(expected, actual)
		if expected ~= actual then
			fail("expected " .. render(expected) .. ", got " .. render(actual))
		end
	end,
}

local unknown = setmetatable({}, {
	__index = function(_, key)
		return function()
			error("run_specs.lua does not implement assert." .. tostring(key) .. "; add it", 2)
		end
	end,
})

_G.assert = setmetatable({
	are = setmetatable(equality, { __index = unknown }),
	are_not = setmetatable({
		equal = function(expected, actual)
			if expected == actual then
				fail("expected something other than " .. render(expected))
			end
		end,
		same = function(expected, actual)
			if deepEqual(expected, actual) then
				fail("expected something other than " .. render(expected))
			end
		end,
	}, { __index = unknown }),
	is = setmetatable({}, { __index = assertions }),
	is_not = setmetatable({
		equal = function(expected, actual)
			if expected == actual then
				fail("expected something other than " .. render(expected))
			end
		end,
	}, { __index = unknown }),
	truthy = assertions.is_truthy,
	falsy = assertions.is_falsy,
	equals = equality.equal,
	not_equals = function(expected, actual)
		if expected == actual then
			fail("expected something other than " .. render(expected))
		end
	end,
	near = function(expected, actual, tolerance)
		if type(actual) ~= "number" or math.abs(actual - expected) > (tolerance or 0) then
			fail("expected " .. render(expected) .. " within " .. tostring(tolerance) .. ", got " .. render(actual))
		end
	end,
	matches = function(pattern, actual)
		if type(actual) ~= "string" or not actual:find(pattern) then
			fail("expected a string matching " .. render(pattern) .. ", got " .. render(actual))
		end
	end,
	equal = equality.equal,
	same = equality.same,
	has_error = assertions.has_error,
}, {
	__index = function(t, key)
		return assertions[key] or unknown[key]
	end,
	__call = function(_, v, message)
		if not v then
			error(message or "assertion failed", 2)
		end
		return v
	end,
})

_G.describe = function(name, body)
	stack[#stack + 1] = name
	beforeStack[#beforeStack + 1] = {}
	afterStack[#afterStack + 1] = {}
	local ok, err = pcall(body)
	if not ok then
		failed = failed + 1
		failures[#failures + 1] = { name = table.concat(stack, " / "), err = err }
	end
	-- Teardown runs even when the body blew up, since a spec that writes a temp file into
	-- the repo cleans it up here and leaving it behind dirties the working tree.
	for _, fn in ipairs(afterStack[#afterStack]) do
		pcall(fn)
	end
	afterStack[#afterStack] = nil
	beforeStack[#beforeStack] = nil
	stack[#stack] = nil
end
_G.context = _G.describe

_G.before_each = function(fn)
	local hooks = beforeStack[#beforeStack]
	if hooks then
		hooks[#hooks + 1] = fn
	end
end
_G.after_each = function(fn)
	local hooks = afterStack[#afterStack]
	if hooks then
		hooks[#hooks + 1] = fn
	end
end
_G.setup = _G.before_each
_G.teardown = _G.after_each
_G.lazy_setup, _G.strict_setup = _G.before_each, _G.before_each
_G.lazy_teardown, _G.strict_teardown = _G.after_each, _G.after_each

_G.it = function(name, body)
	local label = table.concat(stack, " / ") .. " / " .. name
	if body == nil then
		skipped = skipped + 1
		print("skip " .. label)
		return
	end

	for _, hooks in ipairs(beforeStack) do
		for _, fn in ipairs(hooks) do
			pcall(fn)
		end
	end

	local ok, err = pcall(body)

	for i = #afterStack, 1, -1 do
		for _, fn in ipairs(afterStack[i]) do
			pcall(fn)
		end
	end

	if ok then
		passed = passed + 1
		print("ok   " .. label)
	else
		failed = failed + 1
		failures[#failures + 1] = { name = label, err = err }
		print("FAIL " .. label)
	end
end
_G.pending = function(name)
	skipped = skipped + 1
	print("skip " .. table.concat(stack, " / ") .. " / " .. tostring(name))
end

dofile("spec/spec_helper.lua")

for _, path in ipairs(paths) do
	print("=== " .. path)
	local chunk, loadErr = loadfile(path)
	if not chunk then
		failed = failed + 1
		failures[#failures + 1] = { name = path, err = loadErr }
		print("FAIL " .. path .. " (did not load)")
	else
		local ok, err = pcall(chunk)
		if not ok then
			failed = failed + 1
			failures[#failures + 1] = { name = path, err = err }
			print("FAIL " .. path .. " (raised while running)")
		end
	end
end

if #failures > 0 then
	print("")
	for _, f in ipairs(failures) do
		print("FAIL " .. f.name)
		print("       " .. tostring(f.err))
	end
end

print(("\n%d passed, %d failed, %d skipped"):format(passed, failed, skipped))
os.exit(failed == 0 and 0 or 1)
