-- Preset storage for Preset Vault. This file doesn't call the game client, so
-- it can be unit tested outside the game (see spec/preset_vault_spec.lua).
--
-- A preset is a table like this (empty slots are left out):
--   {
--     name = "Slayer: Abyssal demons",
--     inventory = { [1] = { itemId = 385, quantity = 1 }, ... },  -- key = backpack slot
--     equipment = { [1] = { itemId = 1163, quantity = 1 }, ... }, -- key = worn-equipment slot
--     bob = { [1] = { itemId = 12183, quantity = 1 }, ... },      -- key = beast of burden slot
--   }
-- Slots are numbered from 1, the way the client numbers inventory slots. A
-- preset saved without a familiar out has an empty `bob`.

local presets = {}

-- The sections of a preset. When matching what the player has against a
-- preset, sections are filled in this order: worn items first, then the
-- backpack, then the beast of burden.
presets.SECTIONS = { "equipment", "inventory", "bob" }

-- The same names as a set, for checking whether a saved line is a section.
local IS_SECTION = {}
for _, section in ipairs(presets.SECTIONS) do
	IS_SECTION[section] = true
end

-- First line of the saved text. Change it if the format changes, so old saves
-- can be recognised and upgraded.
local FORMAT_HEADER = "preset-vault 1"

-- Returns a new, empty preset with the given name.
function presets.new(name)
	return { name = name, inventory = {}, equipment = {}, bob = {} }
end

-- Returns the slot numbers that hold an item, in order. Use it to walk a
-- preset's inventory or equipment from the first slot to the last.
function presets.filledSlots(slots)
	local slotNumbers = {}
	for slot in pairs(slots) do
		slotNumbers[#slotNumbers + 1] = slot
	end
	table.sort(slotNumbers)
	return slotNumbers
end

-- Returns the position of the preset with this name in the list, or nil.
function presets.find(list, name)
	for index, preset in ipairs(list) do
		if preset.name == name then
			return index
		end
	end
	return nil
end

-- Adds a preset to the list, replacing any existing preset with the same name.
-- Returns its position in the list.
function presets.save(list, preset)
	local index = presets.find(list, preset.name) or #list + 1
	list[index] = preset
	return index
end

-- Renames the preset at `index`. Returns false if another preset already has
-- that name.
function presets.rename(list, index, newName)
	local existing = presets.find(list, newName)
	if existing and existing ~= index then
		return false
	end
	list[index].name = newName
	return true
end

-- Removes the preset at `index`.
function presets.remove(list, index)
	table.remove(list, index)
end

-- Adds up how many of each item a set of slots holds: { [itemId] = quantity }.
function presets.slotTotals(slots)
	local totals = {}
	for _, item in pairs(slots) do
		totals[item.itemId] = (totals[item.itemId] or 0) + item.quantity
	end
	return totals
end

-- Adds up how many of each item a preset holds, across all its sections.
-- Returns { [itemId] = quantity }.
function presets.totals(preset)
	local totals = {}
	for _, section in ipairs(presets.SECTIONS) do
		for itemId, quantity in pairs(presets.slotTotals(preset[section])) do
			totals[itemId] = (totals[itemId] or 0) + quantity
		end
	end
	return totals
end

-- Works out what's still missing to rebuild `preset`, given what the player
-- currently has on them (`carried`, in the same shape as presets.totals).
-- Returns { [itemId] = quantity still needed }; items already covered are left out.
function presets.neededItems(preset, carried)
	local needed = {}
	for itemId, quantity in pairs(presets.totals(preset)) do
		local missing = quantity - (carried[itemId] or 0)
		if missing > 0 then
			needed[itemId] = missing
		end
	end
	return needed
end

-- Works out which of a preset's slots still need an item, given what the
-- player has in each section now (`current`, e.g. { inventory = <slots>,
-- equipment = <slots>, bob = <slots> }, each as read from the game).
--   With `strictSlots`, a slot is done only if that same slot holds the
--   item, in at least the preset's quantity.
--   Without it, each section is matched by count: items in that section fill
--   the preset's slots for them in order, wherever they sit.
-- Either way, a section is only matched against what's in that same section,
-- so essence in a familiar never fills the backpack's essence slots.
-- Returns { inventory = { [slot] = true }, equipment = ..., bob = ... }.
function presets.slotsStillNeeded(preset, current, strictSlots)
	local stillNeeded = {}
	for _, section in ipairs(presets.SECTIONS) do
		stillNeeded[section] = {}
		local currentSlots = current[section] or {}
		local available = presets.slotTotals(currentSlots)
		local slots = preset[section]
		for _, slot in ipairs(presets.filledSlots(slots)) do
			local item = slots[slot]
			if strictSlots then
				local there = currentSlots[slot]
				if not (there and there.itemId == item.itemId and there.quantity >= item.quantity) then
					stillNeeded[section][slot] = true
				end
			else
				local have = available[item.itemId] or 0
				if have >= item.quantity then
					available[item.itemId] = have - item.quantity
				else
					-- A part stack doesn't fill the slot; use it up and mark the slot needed.
					available[item.itemId] = 0
					stillNeeded[section][slot] = true
				end
			end
		end
	end
	return stillNeeded
end

-- Compares what's in one section of the player's slots now (`current`, e.g.
-- their backpack) with the same section of a preset (`section`, e.g.
-- "inventory"), slot by slot. Returns the slots holding the wrong thing:
--   { [slot] = "wrongSlot" | "notInPreset" }
--   "notInPreset": the preset doesn't use this item anywhere.
--   "wrongSlot":   the preset uses this item, but not here: it belongs in
--                  another section (always flagged), or, with `strictSlots`,
--                  in another slot of this section.
-- An empty slot that should hold something isn't an error: it's still needed.
function presets.layoutErrors(preset, section, current, strictSlots)
	local inPreset = presets.totals(preset)
	local inSection = presets.slotTotals(preset[section])
	local errors = {}
	for slot, item in pairs(current) do
		local expected = preset[section][slot]
		if not inPreset[item.itemId] then
			errors[slot] = "notInPreset"
		elseif not inSection[item.itemId] then
			errors[slot] = "wrongSlot"
		elseif strictSlots and (not expected or expected.itemId ~= item.itemId) then
			errors[slot] = "wrongSlot"
		end
	end
	return errors
end

-- Shortens a stack size the way the game's item icons do: as-is up to 99,999,
-- then thousands ("100K") up to 9,999,999, then millions ("10M").
function presets.formatQuantity(quantity)
	if quantity < 100000 then
		return tostring(quantity)
	elseif quantity < 10000000 then
		return (quantity // 1000) .. "K"
	end
	return (quantity // 1000000) .. "M"
end

-- Saving and loading ------------------------------------------------------
--
-- Presets are saved as plain text, one line per preset or item, with fields
-- separated by tabs:
--   preset-vault 1
--   preset    Slayer: Abyssal demons
--   inventory 1    385     1
--   equipment 1    1163    1
--   bob       1    12183   1
-- It's read back without ever running it as code. (PersistentDB can also
-- store tables; text keeps the format under our control and easy to test.)

-- Names are stored between tabs on one line, so tabs and line breaks in a
-- name become spaces.
local function cleanName(name)
	return (name:gsub("[\t\r\n]", " "))
end

-- Adds one line per filled slot, in slot order.
local function addItemLines(lines, kind, slots)
	for _, slot in ipairs(presets.filledSlots(slots)) do
		local item = slots[slot]
		lines[#lines + 1] = string.format("%s\t%d\t%d\t%d", kind, slot, item.itemId, item.quantity)
	end
end

-- Turns a list of presets into text for saving.
function presets.encode(list)
	local lines = { FORMAT_HEADER }
	for _, preset in ipairs(list) do
		lines[#lines + 1] = "preset\t" .. cleanName(preset.name)
		for _, section in ipairs(presets.SECTIONS) do
			addItemLines(lines, section, preset[section])
		end
	end
	return table.concat(lines, "\n")
end

-- Splits a line into its tab-separated fields.
local function splitFields(line)
	local fields = {}
	for field in (line .. "\t"):gmatch("(.-)\t") do
		fields[#fields + 1] = field
	end
	return fields
end

-- Turns saved text back into a list of presets. Nothing saved yet (nil or "")
-- gives an empty list. Returns nil and a message if the text isn't a save
-- from this plugin.
function presets.decode(text)
	local list = {}
	if text == nil or text == "" then
		return list
	end

	local lines = {}
	for line in (text .. "\n"):gmatch("(.-)\n") do
		lines[#lines + 1] = line
	end
	if lines[1] ~= FORMAT_HEADER then
		return nil, "unrecognised save format: " .. tostring(lines[1])
	end

	local current -- the preset that item lines belong to
	for i = 2, #lines do
		local fields = splitFields(lines[i])
		local kind = fields[1]
		if kind == "preset" then
			current = presets.new(fields[2] or "")
			list[#list + 1] = current
		elseif current and IS_SECTION[kind] then
			local slot, itemId, quantity = tonumber(fields[2]), tonumber(fields[3]), tonumber(fields[4])
			-- Lines with missing or broken numbers are skipped rather than guessed at.
			if slot and itemId and quantity then
				current[kind][slot] = { itemId = itemId, quantity = quantity }
			end
		end
	end
	return list
end

return presets
