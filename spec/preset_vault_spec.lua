-- The editor doesn't know busted's assert.* functions; luacheck still checks this file.
---@diagnostic disable: undefined-field, need-check-nil
package.path = "plugins/preset-vault/?.lua;" .. package.path
local presets = require("presets")

-- A small preset to test with: two food in the inventory and a helmet.
local function samplePreset(name)
	local preset = presets.new(name or "Slayer")
	preset.inventory[1] = { itemId = 385, quantity = 1 }
	preset.inventory[5] = { itemId = 385, quantity = 1 }
	preset.equipment[1] = { itemId = 1163, quantity = 1 }
	return preset
end

-- The sample preset plus a beast of burden carrying two pure essence.
local function presetWithBob()
	local preset = samplePreset("Runecrafting")
	preset.bob[1] = { itemId = 7936, quantity = 1 }
	preset.bob[2] = { itemId = 7936, quantity = 1 }
	return preset
end

describe("presets.save / find / rename / remove", function()
	it("adds new presets to the end", function()
		local list = {}
		assert.equal(1, presets.save(list, presets.new("A")))
		assert.equal(2, presets.save(list, presets.new("B")))
		assert.equal(2, presets.find(list, "B"))
	end)

	it("replaces a preset with the same name", function()
		local list = {}
		presets.save(list, presets.new("A"))
		local replacement = samplePreset("A")
		assert.equal(1, presets.save(list, replacement))
		assert.equal(1, #list)
		assert.equal(replacement, list[1])
	end)

	it("refuses to rename onto another preset's name", function()
		local list = { presets.new("A"), presets.new("B") }
		assert.is_false(presets.rename(list, 2, "A"))
		assert.is_true(presets.rename(list, 2, "C"))
		assert.equal("C", list[2].name)
	end)

	it("removes a preset", function()
		local list = { presets.new("A"), presets.new("B") }
		presets.remove(list, 1)
		assert.same({ "B" }, { list[1].name })
	end)
end)

describe("presets.filledSlots", function()
	it("lists filled slots in order, skipping gaps", function()
		assert.same({ 1, 5 }, presets.filledSlots(samplePreset().inventory))
	end)
end)

describe("presets.neededItems", function()
	it("counts items across inventory and equipment", function()
		assert.same({ [385] = 2, [1163] = 1 }, presets.totals(samplePreset()))
	end)

	it("leaves out what the player already has", function()
		local needed = presets.neededItems(samplePreset(), { [385] = 1, [1163] = 1 })
		assert.same({ [385] = 1 }, needed)
	end)

	it("is empty once everything is carried", function()
		assert.same({}, presets.neededItems(samplePreset(), { [385] = 5, [1163] = 1 }))
	end)
end)

describe("presets.slotsStillNeeded", function()
	it("marks every slot when the player has nothing", function()
		assert.same(
			{ inventory = { [1] = true, [5] = true }, equipment = { [1] = true }, bob = {} },
			presets.slotsStillNeeded(samplePreset(), {})
		)
	end)

	it("fills each section's slots in order from what's in that section", function()
		-- One food in the backpack and the helmet worn: the helmet slot and the
		-- first food slot are covered.
		local current = {
			inventory = { [9] = { itemId = 385, quantity = 1 } },
			equipment = { [1] = { itemId = 1163, quantity = 1 } },
		}
		assert.same(
			{ inventory = { [5] = true }, equipment = {}, bob = {} },
			presets.slotsStillNeeded(samplePreset(), current)
		)
	end)

	it("counts a part stack as still needed", function()
		local preset = presets.new("Arrows")
		preset.inventory[1] = { itemId = 892, quantity = 100 }
		assert.same(
			{ inventory = { [1] = true }, equipment = {}, bob = {} },
			presets.slotsStillNeeded(preset, { inventory = { [1] = { itemId = 892, quantity = 40 } } })
		)
	end)
end)

describe("presets.slotsStillNeeded with strict slot order", function()
	-- Essence in backpack slots 1 to 3; the player has three essence, but in
	-- slots 4 to 6.
	local preset = presets.new("Essence")
	for slot = 1, 3 do
		preset.inventory[slot] = { itemId = 7936, quantity = 1 }
	end
	local current = { inventory = {} }
	for slot = 4, 6 do
		current.inventory[slot] = { itemId = 7936, quantity = 1 }
	end

	it("counts them as done when order doesn't matter", function()
		assert.same({}, presets.slotsStillNeeded(preset, current, false).inventory)
	end)

	it("still needs every slot when order matters", function()
		assert.same({ [1] = true, [2] = true, [3] = true }, presets.slotsStillNeeded(preset, current, true).inventory)
	end)

	it("needs a slot whose stack is too small", function()
		local short = { inventory = { [1] = { itemId = 7936, quantity = 1 } } }
		local wantsTen = presets.new("Stack")
		wantsTen.inventory[1] = { itemId = 7936, quantity = 10 }
		assert.same({ [1] = true }, presets.slotsStillNeeded(wantsTen, short, true).inventory)
	end)
end)

describe("presets.layoutErrors", function()
	local preset = samplePreset() -- food in backpack slots 1 and 5, helmet worn

	it("finds nothing wrong when the layout matches", function()
		local current = { [1] = { itemId = 385, quantity = 1 }, [5] = { itemId = 385, quantity = 1 } }
		assert.same({}, presets.layoutErrors(preset, "inventory", current, true))
	end)

	it("ignores slots that are still empty", function()
		assert.same({}, presets.layoutErrors(preset, "inventory", { [1] = { itemId = 385, quantity = 1 } }, true))
	end)

	it("flags items the preset doesn't use", function()
		local current = { [2] = { itemId = 999, quantity = 1 } }
		assert.same({ [2] = "notInPreset" }, presets.layoutErrors(preset, "inventory", current, true))
	end)

	it("ignores wrong slots when slot order isn't strict", function()
		local current = { [2] = { itemId = 999, quantity = 1 }, [3] = { itemId = 385, quantity = 1 } }
		assert.same({ [2] = "notInPreset" }, presets.layoutErrors(preset, "inventory", current, false))
	end)

	it("flags preset items in the wrong slot, including worn items in the backpack", function()
		local current = { [3] = { itemId = 385, quantity = 1 }, [4] = { itemId = 1163, quantity = 1 } }
		assert.same({ [3] = "wrongSlot", [4] = "wrongSlot" }, presets.layoutErrors(preset, "inventory", current, true))
	end)
end)

describe("presets.formatQuantity", function()
	it("shortens stacks the way the game does", function()
		assert.equal("1", presets.formatQuantity(1))
		assert.equal("99999", presets.formatQuantity(99999))
		assert.equal("100K", presets.formatQuantity(100000))
		assert.equal("9999K", presets.formatQuantity(9999999))
		assert.equal("10M", presets.formatQuantity(10000000))
	end)
end)

describe("beast of burden section", function()
	it("counts BoB items in the totals", function()
		assert.same({ [385] = 2, [1163] = 1, [7936] = 2 }, presets.totals(presetWithBob()))
	end)

	it("doesn't let essence in the BoB fill the backpack's essence slots", function()
		-- The preset wants essence in both. The player's BoB is full but their
		-- backpack has none, so it's the backpack slot that's still needed.
		local preset = presetWithBob()
		preset.inventory[2] = { itemId = 7936, quantity = 1 }
		local current = {
			inventory = { [1] = { itemId = 385, quantity = 1 }, [5] = { itemId = 385, quantity = 1 } },
			equipment = { [1] = { itemId = 1163, quantity = 1 } },
			bob = { [1] = { itemId = 7936, quantity = 1 }, [2] = { itemId = 7936, quantity = 1 } },
		}
		assert.same({ inventory = { [2] = true }, equipment = {}, bob = {} }, presets.slotsStillNeeded(preset, current))
	end)

	it("flags backpack items put in the BoB even without strict slot order", function()
		local current = { [3] = { itemId = 385, quantity = 1 } } -- food belongs in the backpack
		assert.same({ [3] = "wrongSlot" }, presets.layoutErrors(presetWithBob(), "bob", current, false))
	end)

	it("round-trips through saving", function()
		local list = { presetWithBob() }
		assert.same(list, presets.decode(presets.encode(list)))
	end)

	it("loads saves from before BoBs with an empty BoB", function()
		local text = "preset-vault 1\npreset\tOld\ninventory\t1\t385\t1"
		assert.same({}, presets.decode(text)[1].bob)
	end)
end)

describe("presets.encode / decode", function()
	it("treats nothing saved as an empty list", function()
		assert.same({}, presets.decode(nil))
		assert.same({}, presets.decode(""))
	end)

	it("round-trips presets", function()
		local list = { samplePreset("Slayer"), presets.new("Empty") }
		assert.same(list, presets.decode(presets.encode(list)))
	end)

	it("turns tabs and line breaks in names into spaces", function()
		local decoded = presets.decode(presets.encode({ presets.new("Bad\tname\nhere") }))
		assert.equal("Bad name here", decoded[1].name)
	end)

	it("rejects text that isn't one of its saves", function()
		local list, err = presets.decode("something else")
		assert.is_nil(list)
		assert.truthy(err:find("unrecognised"))
	end)

	it("skips item lines with broken numbers", function()
		local text = "preset-vault 1\npreset\tA\ninventory\t1\tabc\t1\ninventory\t2\t385\t1"
		assert.same({ [2] = { itemId = 385, quantity = 1 } }, presets.decode(text)[1].inventory)
	end)
end)
