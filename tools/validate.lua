-- Checks each plugin folder against the rules Jagex's client and mod.io
-- submission enforce, so mistakes show up in CI instead of in moderation.
--
-- Usage: lua tools/validate.lua [--release] [plugin-dir ...]
--   With no dirs, checks every folder in plugins/.
--   --release also rejects placeholder contact emails.

local json = require("dkjson")

local M = {}

M.KNOWN_PERMISSIONS = {
	httpAccess = true,
	chatAccess = true,
	trackingAccess = true,
}

local function read_file(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local data = f:read("a")
	f:close()
	return data
end

local function is_ascii(s)
	return not s:find("[\128-\255]")
end

-- A list of strings, or a map of variable name -> plugin name.
local function check_dependencies(field, value, errors)
	if value == nil then
		return
	end
	if type(value) ~= "table" then
		errors[#errors + 1] = field .. " must be an array or an object"
		return
	end
	for k, v in pairs(value) do
		if type(v) ~= "string" or (type(k) ~= "number" and type(k) ~= "string") then
			errors[#errors + 1] = field .. " entries must be strings"
			return
		end
	end
end

local function check_permissions(field, value, errors)
	if value == nil then
		return
	end
	if type(value) ~= "table" then
		errors[#errors + 1] = field .. " must be an array"
		return
	end
	for _, p in ipairs(value) do
		if not M.KNOWN_PERMISSIONS[p] then
			errors[#errors + 1] = field .. ": unknown permission '" .. tostring(p) .. "'"
		end
	end
end

-- Returns a list of error messages for one plugin folder (empty when it's fine).
function M.check(dir, opts)
	opts = opts or {}
	local errors = {}
	local folder = dir:match("([^/]+)/*$")

	if folder:find("%s") then
		errors[#errors + 1] = "folder name '" .. folder .. "' must not contain spaces"
	end
	if not read_file(dir .. "/main.lua") then
		errors[#errors + 1] = "main.lua is missing"
	end

	local raw = read_file(dir .. "/plugin.json")
	if not raw then
		errors[#errors + 1] = "plugin.json is missing"
		return errors
	end
	local manifest, _, err = json.decode(raw)
	if type(manifest) ~= "table" then
		errors[#errors + 1] = "plugin.json is not valid JSON: " .. tostring(err)
		return errors
	end

	local name = manifest.name
	if type(name) ~= "string" or #name < 1 or #name > 50 or not is_ascii(name) then
		errors[#errors + 1] = "name must be 1-50 ASCII characters"
	end

	local version = manifest.version
	if
		type(version) ~= "string"
		or not version:match("^%d+[%d%.]*$")
		or version:find("%.%.")
		or version:find("%.$")
	then
		errors[#errors + 1] = "version must be numbers and full stops only, e.g. 1.2.0"
	end

	local email = manifest.contactEmailAddress
	if type(email) ~= "string" or not email:match("^[^@%s]+@[^@%s]+%.[^@%s]+$") then
		errors[#errors + 1] = "contactEmailAddress must be an email address"
	elseif opts.release and email:match("@example%.com$") then
		errors[#errors + 1] = "contactEmailAddress is still a placeholder"
	end

	check_dependencies("requiredDependencies", manifest.requiredDependencies, errors)
	check_dependencies("optionalDependencies", manifest.optionalDependencies, errors)
	check_permissions("requiredPermissions", manifest.requiredPermissions, errors)
	check_permissions("optionalPermissions", manifest.optionalPermissions, errors)

	if manifest.urls ~= nil then
		if type(manifest.urls) ~= "table" then
			errors[#errors + 1] = "urls must be an object"
		else
			for key, url in pairs(manifest.urls) do
				if type(url) ~= "string" or not url:match("^https?://") then
					errors[#errors + 1] = "urls." .. tostring(key) .. " must start with http:// or https://"
				end
			end
		end
	end

	return errors
end

local function list_plugin_dirs()
	local dirs = {}
	local p = io.popen("ls -d plugins/*/ 2>/dev/null")
	for line in p:lines() do
		dirs[#dirs + 1] = line:gsub("/$", "")
	end
	p:close()
	return dirs
end

local function main(args)
	local opts, dirs = {}, {}
	for _, a in ipairs(args) do
		if a == "--release" then
			opts.release = true
		else
			dirs[#dirs + 1] = a
		end
	end
	if #dirs == 0 then
		dirs = list_plugin_dirs()
	end

	local failed = false
	for _, dir in ipairs(dirs) do
		local errors = M.check(dir, opts)
		if #errors == 0 then
			print("ok    " .. dir)
		else
			failed = true
			for _, e in ipairs(errors) do
				print("FAIL  " .. dir .. ": " .. e)
			end
		end
	end
	os.exit(failed and 1 or 0)
end

-- Run as a script, or load as a module from the tests.
if not pcall(debug.getlocal, 4, 1) then
	main(arg)
end

return M
