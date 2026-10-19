local validate = require("tools.validate")

-- Builds a throwaway plugin folder with the given manifest.
local function make_plugin(folder, manifest, opts)
	opts = opts or {}
	local dir = os.tmpname() .. "-dir/" .. folder
	os.execute("mkdir -p '" .. dir .. "'")
	if opts.main ~= false then
		local f = assert(io.open(dir .. "/main.lua", "w"))
		f:write("print('hi')\n")
		f:close()
	end
	local f = assert(io.open(dir .. "/plugin.json", "w"))
	f:write(manifest)
	f:close()
	return dir
end

local GOOD = [[{"name": "Test", "version": "1.0.0", "contactEmailAddress": "dev@example.com"}]]

local function has_error(errors, fragment)
	for _, e in ipairs(errors) do
		if e:find(fragment, 1, true) then
			return true
		end
	end
	return false
end

describe("validate.check", function()
	it("accepts a minimal plugin", function()
		assert.same({}, validate.check(make_plugin("good", GOOD)))
	end)

	it("rejects spaces in the folder name", function()
		assert.is_true(has_error(validate.check(make_plugin("bad name", GOOD)), "spaces"))
	end)

	it("requires main.lua", function()
		assert.is_true(has_error(validate.check(make_plugin("nomain", GOOD, { main = false })), "main.lua"))
	end)

	it("rejects versions that aren't numbers and full stops", function()
		for _, v in ipairs({ "1.0-beta", "v1.0", "1..0", "1.0." }) do
			local m = GOOD:gsub("1%.0%.0", v)
			assert.is_true(has_error(validate.check(make_plugin("ver", m)), "version"), v)
		end
	end)

	it("rejects placeholder emails only for releases", function()
		local dir = make_plugin("email", GOOD)
		assert.same({}, validate.check(dir))
		assert.is_true(has_error(validate.check(dir, { release = true }), "placeholder"))
	end)

	it("rejects unknown permissions", function()
		local m = [[{"name": "T", "version": "1", "contactEmailAddress": "a@b.co",
			"requiredPermissions": ["httpAccess", "godMode"]}]]
		assert.is_true(has_error(validate.check(make_plugin("perm", m)), "godMode"))
	end)

	it("rejects non-http urls", function()
		local m = [[{"name": "T", "version": "1", "contactEmailAddress": "a@b.co",
			"urls": {"ok": "https://runescape.wiki/", "bad": "ftp://x.com"}}]]
		local errors = validate.check(make_plugin("urls", m))
		assert.is_true(has_error(errors, "urls.bad"))
		assert.is_false(has_error(errors, "urls.ok"))
	end)

	it("reports invalid JSON", function()
		assert.is_true(has_error(validate.check(make_plugin("json", "{nope")), "not valid JSON"))
	end)
end)
