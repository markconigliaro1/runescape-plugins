-- Preset Vault: keeps more bank presets than the game's 15, as a reference
-- for rebuilding them by hand. Save what you're carrying and wearing, browse
-- your saved setups as item icons, and turn on "Show what's missing" to fade
-- out what you already have and see what your bank is short of.
--
-- It only reads and displays your own items. It never withdraws, equips or
-- loads anything for you.

local presets = require("presets")

-- Keys used in PersistentDB.
local STORAGE_KEY = "presets"
local WINDOW_X_KEY = "windowX"
local WINDOW_Y_KEY = "windowY"
local STRICT_SLOTS_KEY = "strictSlots"
local SHOW_FAMILIAR_KEY = "showFamiliar"

-- The inventories the plugin reads (see config.Inv in the API docs).
local BACKPACK = config.Inv.INV
local BANK = config.Inv.BANK
-- Not named in the docs; found in a `pan Inv` export (INV, WORN and BANK are
-- IDs 93, 94 and 95).
local EQUIPMENT = config.Inv.WORN
-- The beast of burden's inventory, also found in the export and checked in game
-- (it reports 32 slots, the largest BoB, whichever familiar is out).
local BOB = config.Inv.LORE_BOB

-- Layout, in interface units. The window's size is worked out from the icon
-- grids, so icons keep their shape whatever the inventory sizes are.
local ICON_WIDTH = 44
local ICON_HEIGHT = 40
local BACKPACK_COLUMNS = 4
local EQUIPMENT_COLUMNS = 3
local BOB_COLUMNS = 5 -- 5 x 7 holds the BoB's 32 slots at the backpack grid's height
local LIST_WIDTH = 170
local MARGIN = 10
local GAP = 14
local HEADER_HEIGHT = 30 -- our own title bar
local LINE_HEIGHT = 24 -- one line of text
local NAME_ROW_GAP = 10 -- space between the preset name row and the item icons
local BUTTON_HEIGHT = 30
local TITLE_BUTTON_WIDTH = 30 -- the move grip and the X, at the right of the title bar

-- Colours, matched by eye to the game's bank interface.
local WINDOW_COLOUR = Vector4.new(0.11, 0.09, 0.07, 1.0) -- dark brown body
local TITLE_BAR_COLOUR = Vector4.new(0.17, 0.13, 0.09, 1.0) -- the title bar, a shade lighter
local BORDER_COLOUR = Vector4.new(0.55, 0.44, 0.27, 1.0) -- bronze frame
local SLOT_COLOUR = Vector4.new(0.06, 0.05, 0.04, 1.0) -- recessed item slots
local SLOT_EDGE_COLOUR = Vector4.new(0.24, 0.20, 0.15, 1.0) -- their faint edge

-- How faded an icon is when the player already has that item (0 = invisible,
-- 1 = solid).
local FADED_ALPHA = 0.3

-- Loading saved presets ----------------------------------------------------

local savedPresets, loadError = presets.decode(PersistentDB:Get(STORAGE_KEY))
if not savedPresets then
	-- Don't overwrite a save we can't read; start empty and say why.
	print("Preset Vault: couldn't read saved presets (" .. loadError .. ")")
	savedPresets = {}
end

-- Settings (changed from the plugin's settings icon in the Plugin Hub) ------

-- Whether items must be in the same slots as in the preset. On by default;
-- when off, only items the preset doesn't use at all are flagged.
local strictSlots = PersistentDB:Get(STRICT_SLOTS_KEY)
if strictSlots == nil then
	strictSlots = true
end

-- Saves every preset straight away after each change, so nothing is lost if
-- the client closes without running PluginShutdown.
local function storePresets()
	PersistentDB:Set(STORAGE_KEY, presets.encode(savedPresets))
end

-- Reading the game ---------------------------------------------------------

-- Returns the live inventory for an InvType, or nil if the client doesn't
-- have it right now (e.g. the bank before it's been opened).
local function findInventory(invType)
	local inv = Inventory.Find(invType)
	if inv and inv.isValid then
		return inv
	end
	return nil
end

-- Reads an inventory into { [slot] = { itemId = ..., quantity = ... } }.
-- Gives an empty table if the inventory isn't available.
local function readSlots(invType)
	local items = {}
	local inv = findInventory(invType)
	if not inv then
		return items
	end
	for slot = 1, inv.slotCount do
		local invSlot = inv:GetSlot(slot)
		-- The docs don't say how empty slots look, so skip anything without an item.
		if invSlot and invSlot.obj and invSlot.count > 0 then
			items[slot] = { itemId = invSlot.obj.id, quantity = invSlot.count }
		end
	end
	return items
end

-- Adds up the items in the given sections of what the player has (each as
-- read by readSlots): { [itemId] = quantity }.
local function carriedItems(...)
	local carried = {}
	for _, slots in ipairs({ ... }) do
		for _, item in pairs(slots) do
			carried[item.itemId] = (carried[item.itemId] or 0) + item.quantity
		end
	end
	return carried
end

-- Returns an item's display name.
local function itemName(itemId)
	local item = config.Obj.FromID(itemId)
	return item and item.name or ("Item " .. itemId)
end

-- Window -------------------------------------------------------------------

local gameWindow = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)

-- A see-through canvas over the whole game for the bank highlights. Created
-- before the window so the window draws on top of it, and click-through so it
-- never blocks clicks on the bank.
local highlights = ui.Canvas.new(gameWindow)
highlights:SetSize(0, 0, 1.0, 1.0)
highlights.clickthrough = true

-- Where everything goes. Positions inside the window are measured from its
-- top-left corner; the content starts below our own title bar.
local backpackRows = math.ceil(BACKPACK.size / BACKPACK_COLUMNS)
local equipmentRows = math.ceil(EQUIPMENT.size / EQUIPMENT_COLUMNS)
local bobRows = math.ceil(BOB.size / BOB_COLUMNS)
local gridHeight = math.max(backpackRows, equipmentRows, bobRows) * ICON_HEIGHT

local backpackX = MARGIN + LIST_WIDTH + GAP
local equipmentX = backpackX + BACKPACK_COLUMNS * ICON_WIDTH + GAP
local bobX = equipmentX + EQUIPMENT_COLUMNS * ICON_WIDTH + GAP
-- The window has two widths: with the familiar (BoB) section closed, it ends
-- after the worn grid; open, after the BoB grid. `rightWidth` is the width of
-- the right-hand column (title, grids, status line) for each.
local closedWidth = equipmentX + EQUIPMENT_COLUMNS * ICON_WIDTH + MARGIN
local openWidth = bobX + BOB_COLUMNS * ICON_WIDTH + MARGIN
local function rightWidthFor(width)
	return width - MARGIN - backpackX
end

local contentY = HEADER_HEIGHT + MARGIN
local gridY = contentY + LINE_HEIGHT + NAME_ROW_GAP
local statusY = gridY + gridHeight + 6
local buttonY = statusY + LINE_HEIGHT + 6

local windowHeight = buttonY + BUTTON_HEIGHT + MARGIN

-- The window's shadow, styled after the game's own: a soft dark glow on every
-- side, nudged a little downwards. It's made of see-through dark rectangles on
-- the plugin layer, created before the window so they're drawn behind it, and
-- kept around it by placeWindow. (They can't be inside the window, which
-- doesn't draw anything outside its own edges.) Each layer spreads `spread`
-- units past the window's edges; wide faint layers under narrow darker ones
-- give a soft edge.
local SHADOW_DROP = 2 -- how far the whole shadow sits below the window
local SHADOW_LAYERS = {
	{ spread = 7, alpha = 0.12 },
	{ spread = 4, alpha = 0.22 },
	{ spread = 2, alpha = 0.35 },
}
local shadows = {}
for _, layer in ipairs(SHADOW_LAYERS) do
	local shadow = ui.Rectangle.new(gameWindow)
	shadow.colour = Vector4.new(0, 0, 0, layer.alpha)
	shadow.fill = true
	shadow.hidden = true
	shadows[#shadows + 1] = { rectangle = shadow, spread = layer.spread }
end

-- The "Preset Vault" button shown on the bank (see "Bank button" below). It's
-- created here, before the window, so the window is drawn on top of it.
local bankButton = ui.Button.new(gameWindow)
bankButton.label = "Preset Vault"
bankButton.stylesheetID = id.StyleSheet.BUTTON_DEFAULT
bankButton.hidden = true

local window = ui.GroupBox.new(gameWindow)
-- (Sized by layoutWidth, at the end of the window code.)
-- No built-in header: it has no background in this client, so the window
-- draws its own title bar (below) instead.
window:SetHeaderLayout(0, 0, 0, 0, 0)

-- This client has no GROUPBOX_DEFAULT stylesheet (it reads as -1, though the
-- docs list it), so the window has no background. Add a solid dark one,
-- created first so it sits behind everything else.
local background = ui.Rectangle.new(window)
background:SetSize(0, 0, 1.0, 1.0)
background.colour = WINDOW_COLOUR
background.fill = true

-- Stop clicks on the window from passing through to the game behind it (e.g.
-- walking your character when you meant to click the window).
window.clickthrough = false
background.clickthrough = false

-- The title bar's strip across the top, behind its title and buttons.
local titleBar = ui.Rectangle.new(window)
titleBar.colour = TITLE_BAR_COLOUR
titleBar.fill = true
titleBar.clickthrough = false

-- Borders: a lighter line under the title bar, and a thin outline round the
-- whole window, so it stands out from the game behind it.
local titleBarEdge = ui.Rectangle.new(window)
titleBarEdge:SetPos(0, HEADER_HEIGHT - 1)
titleBarEdge.colour = BORDER_COLOUR
titleBarEdge.fill = true

local windowEdge = ui.Rectangle.new(window)
windowEdge.colour = BORDER_COLOUR
windowEdge.fill = false

-- Put the window where the player last dragged it, or at a default spot.
local savedX, savedY = PersistentDB:Get(WINDOW_X_KEY), PersistentDB:Get(WINDOW_Y_KEY)
if savedX and savedY then
	window:SetPos(savedX, savedY)
else
	window:SetPos(0, 0, 0.6, 0.3)
end

-- Adds a button. `style` is one of the id.StyleSheet button styles.
local function addButton(label, style, onPress)
	local button = ui.Button.new(window)
	button.label = label
	button.stylesheetID = style
	button:Subscribe(ui.Hook.ONBUTTONPRESSED, onPress)
	return button
end

-- Left column: the saved presets, a name box and Save / Delete.

local presetList = ui.List.new(window)
presetList.stylesheetID = id.StyleSheet.DROPDOWN_DEFAULT
presetList.dropdownMaxVisibleEntries = 0 -- 0 = an ordinary scrolling list, not a dropdown
-- The list runs from the top down to the Strict slot order tick box. Below
-- that is the name box, level with the status line on the right.
presetList:SetSize(LIST_WIDTH, statusY - contentY - LINE_HEIGHT - 12)
presetList:SetPos(MARGIN, contentY)

local nameInput = ui.InputField.new(window)
nameInput.stylesheetID = id.StyleSheet.INPUT_DEFAULT
nameInput:Setup(ui.TextContentVisibilityMode.VISIBLE, ui.InputFieldFilterMode.NONE, 40)
nameInput:SetSize(LIST_WIDTH, LINE_HEIGHT)
nameInput:SetPos(MARGIN, statusY)

-- Right column: the selected preset's name, its backpack and worn items as
-- icons, a status line and the "Show what's missing" button.

local title = ui.Text.new(window)
title.font = id.Font.MUSEO_SANS_15PT_REGULAR
title:SetPos(backpackX, contentY) -- sized by layoutWidth, beside the familiar button

-- Shows or hides the familiar (BoB) section. Closed by default, as few
-- presets use a beast of burden; the choice is remembered. Its label is kept
-- up to date by refresh, and setFamiliarShown is defined further down.
local FAMILIAR_BUTTON_WIDTH = 130
local showFamiliar = PersistentDB:Get(SHOW_FAMILIAR_KEY) == true
local setFamiliarShown
local familiarButton = addButton("Show familiar", id.StyleSheet.BUTTON_DEFAULT, function()
	setFamiliarShown(not showFamiliar, true)
end)

-- Creates a grid with one cell per slot of `invType`, its top-left corner at
-- x, y, every cell ICON_WIDTH by ICON_HEIGHT. `makeCell` creates what goes in
-- each cell. Returns the cells, indexed by slot number, and the grid.
local function addGrid(invType, columns, x, y, makeCell)
	local rows = math.ceil(invType.size / columns)
	local grid = ui.Grid.new(window)
	grid:SetColumnRows(columns, rows)
	grid:SetSize(columns * ICON_WIDTH, rows * ICON_HEIGHT)
	grid:SetPos(x, y)

	local cells = {}
	for slot = 1, invType.size do
		local cell = makeCell(grid)
		cell:SetSize(0, 0, 1.0, 1.0) -- fill its grid cell; the grid doesn't size children
		cell.hidden = true
		cells[slot] = cell
	end
	return cells, grid
end

local function makeIcon(grid)
	return ui.Sprite.new(grid)
end

-- The client's SetAssociatedObject only takes an item ID (it rejected every
-- form with a quantity, though the docs list one), so stack sizes are drawn
-- as text in a second grid laid exactly over the icons.
local function makeQuantity(grid)
	local quantity = ui.Text.new(grid)
	quantity.font = id.Font.MUSEO_SANS_15PT_REGULAR
	quantity.colour = Vector4.new(1.0, 1.0, 0.0, 1.0) -- yellow, like the game's own
	quantity.isShadowed = true
	quantity:AlignTo(ui.AlignMode.TOPLEFT)
	return quantity
end

-- Colours that mark a slot holding the wrong thing (see presets.layoutErrors).
local ERROR_COLOURS = {
	notInPreset = Vector4.new(1.0, 0.2, 0.2, 1.0), -- red: not part of the preset
	wrongSlot = Vector4.new(1.0, 0.6, 0.1, 1.0), -- orange: right item, wrong slot
}

-- A frame around a slot, shown when that slot in the player's own backpack or
-- worn equipment holds the wrong thing.
local function makeErrorMark(grid)
	local mark = ui.Rectangle.new(grid)
	mark.fill = false
	return mark
end

-- Draws a recessed well behind every slot of a grid, like the bank's own item
-- slots: a dark square with a faint edge, a couple of units in from the
-- cell's edges so neighbouring wells have a gap between them. Placed by exact
-- position (not in a Grid) so the gap is guaranteed. Returns the rectangles.
local SLOT_INSET = 2
local function addSlotWells(invType, columns, x, y)
	local parts = {}
	for slot = 1, invType.size do
		local column, row = (slot - 1) % columns, (slot - 1) // columns
		local wellX = x + column * ICON_WIDTH + SLOT_INSET
		local wellY = y + row * ICON_HEIGHT + SLOT_INSET
		local width, height = ICON_WIDTH - 2 * SLOT_INSET, ICON_HEIGHT - 2 * SLOT_INSET

		local well = ui.Rectangle.new(window)
		well:SetSize(width, height)
		well:SetPos(wellX, wellY)
		well.colour = SLOT_COLOUR
		well.fill = true

		local edge = ui.Rectangle.new(window)
		edge:SetSize(width, height)
		edge:SetPos(wellX, wellY)
		edge.colour = SLOT_EDGE_COLOUR
		edge.fill = false
		parts[#parts + 1] = well
		parts[#parts + 1] = edge
	end
	return parts
end

-- Each slot of the backpack, worn and BoB grids: a recessed well, an icon,
-- its quantity text and an error frame, laid exactly over each other (later
-- ones are drawn on top). Returns the slots, and a list of every component
-- made (so a whole section can be hidden at once).
local function addSlots(invType, columns, x, y)
	local parts = addSlotWells(invType, columns, x, y)
	local icons, iconGrid = addGrid(invType, columns, x, y, makeIcon)
	local quantities, quantityGrid = addGrid(invType, columns, x, y, makeQuantity)
	local marks, markGrid = addGrid(invType, columns, x, y, makeErrorMark)
	parts[#parts + 1] = iconGrid
	parts[#parts + 1] = quantityGrid
	parts[#parts + 1] = markGrid
	local slots = {}
	for slot = 1, invType.size do
		slots[slot] = { icon = icons[slot], quantity = quantities[slot], mark = marks[slot] }
	end
	return slots, parts
end

local backpackSlots = addSlots(BACKPACK, BACKPACK_COLUMNS, backpackX, gridY)
local equipmentSlots = addSlots(EQUIPMENT, EQUIPMENT_COLUMNS, equipmentX, gridY)
local bobSlots, bobParts = addSlots(BOB, BOB_COLUMNS, bobX, gridY)

local status = ui.Text.new(window)
status.font = id.Font.MUSEO_SANS_15PT_REGULAR
status:SetPos(backpackX, statusY)

-- What's shown -------------------------------------------------------------

-- Position in savedPresets of the preset on screen (nil when there are none).
local selected = #savedPresets > 0 and 1 or nil

-- Whether "Show what's missing" is turned on.
local showingMissing = false

-- Shows a preset's items in a grid of slots. Slots in `stillNeeded` stay
-- solid; the rest fade when `fadeHave` is true. Empty slots are hidden.
-- Slots in `errors` (from presets.layoutErrors) get a coloured frame.
local function showSlots(gridSlots, items, stillNeeded, fadeHave, errors)
	for slot, cell in ipairs(gridSlots) do
		local problem = errors[slot]
		cell.mark.hidden = problem == nil
		if problem then
			cell.mark.colour = ERROR_COLOURS[problem]
		end

		local item = items[slot]
		if item then
			local alpha = (fadeHave and not stillNeeded[slot]) and FADED_ALPHA or 1
			cell.icon:SetAssociatedObject(item.itemId)
			cell.icon.alpha = alpha
			cell.icon.hidden = false
			-- Like the game, only stacks of more than one show a number.
			cell.quantity.content = presets.formatQuantity(item.quantity)
			cell.quantity.alpha = alpha
			cell.quantity.hidden = item.quantity <= 1
		else
			cell.icon.hidden = true
			cell.quantity.hidden = true
		end
	end
end

-- Describes which of the needed items the bank is short of, if it's open.
local function bankStatus(preset, carried)
	local needed = presets.neededItems(preset, carried)
	if next(needed) == nil then
		return "You have everything."
	end
	local bank = findInventory(BANK)
	if not bank then
		return "Open your bank to check what it has."
	end
	local short = {}
	for itemId, quantity in pairs(needed) do
		if bank:GetTotal(itemId) < quantity then
			short[#short + 1] = itemName(itemId)
		end
	end
	if #short == 0 then
		return "Everything you still need is in your bank."
	end
	return "Not enough in bank: " .. table.concat(short, ", ")
end

-- What to mark in the bank, filled in by refresh while "Show what's missing"
-- is on and empty otherwise:
--   itemsToHighlight: { [itemId] = quantity still needed }, outlined green
--   backpackErrors:   { [slot] = "wrongSlot" | "notInPreset" }, outlined in
--                     the bank's view of the backpack
local itemsToHighlight = {}
local backpackErrors = {}

-- Labels the familiar button: what pressing it does, plus how many BoB items
-- the shown preset has, so a preset with a BoB is noticeable while it's closed.
local function labelFamiliarButton(preset)
	local count = preset and #presets.filledSlots(preset.bob) or 0
	local label = showFamiliar and "Hide familiar" or "Show familiar"
	familiarButton.label = count > 0 and formatStr("{} ({})", label, count) or label
end

local function refresh()
	local preset = selected and savedPresets[selected]
	labelFamiliarButton(preset)
	itemsToHighlight, backpackErrors = {}, {}
	if not preset then
		title.content = "No saved presets yet"
		status.content = "Set up your gear, type a name and press Save."
		showSlots(backpackSlots, {}, {}, false, {})
		showSlots(equipmentSlots, {}, {}, false, {})
		showSlots(bobSlots, {}, {}, false, {})
		return
	end

	title.content = preset.name
	local stillNeeded = { inventory = {}, equipment = {}, bob = {} }
	local wornErrors, bobErrors = {}, {}
	status.content = ""
	if showingMissing then
		local backpack, worn, bob = readSlots(BACKPACK), readSlots(EQUIPMENT), readSlots(BOB)
		local carried = carriedItems(backpack, worn, bob)
		stillNeeded =
			presets.slotsStillNeeded(preset, { inventory = backpack, equipment = worn, bob = bob }, strictSlots)
		itemsToHighlight = presets.neededItems(preset, carried)
		backpackErrors = presets.layoutErrors(preset, "inventory", backpack, strictSlots)
		-- Each worn item can only go in its own slot, so worn slots are always strict.
		wornErrors = presets.layoutErrors(preset, "equipment", worn, true)
		-- A preset saved without a familiar doesn't care what's in the BoB.
		if next(preset.bob) ~= nil then
			bobErrors = presets.layoutErrors(preset, "bob", bob, strictSlots)
		end

		status.content = bankStatus(preset, carried)
		local wrongCount = #presets.filledSlots(backpackErrors)
			+ #presets.filledSlots(wornErrors)
			+ #presets.filledSlots(bobErrors)
		if wrongCount > 0 then
			status.content = formatStr("{} slot(s) wrong. {}", wrongCount, status.content)
		end
	end
	showSlots(backpackSlots, preset.inventory, stillNeeded.inventory, showingMissing, backpackErrors)
	showSlots(equipmentSlots, preset.equipment, stillNeeded.equipment, showingMissing, wornErrors)
	showSlots(bobSlots, preset.bob, stillNeeded.bob, showingMissing, bobErrors)
end

-- Returns the position in savedPresets of the preset the list has highlighted,
-- found by its name, or nil if nothing is highlighted. Going by name means the
-- window always shows the highlighted preset, whatever numbering the list uses
-- for entry IDs (in testing, highlighting by ID from code picked the wrong
-- entry, so the list and the window disagreed until a preset was clicked).
local function highlightedPreset()
	local entry = presetList.selectedEntries and presetList.selectedEntries[1]
	return entry and presets.find(savedPresets, entry.text)
end

-- Refills the list of preset names, highlights the selected one, then makes
-- `selected` match whatever the list actually highlighted.
local function refreshList()
	presetList:SetEntries({})
	for index, preset in ipairs(savedPresets) do
		presetList:Add(preset.name, index)
	end
	if selected then
		presetList:SetEntrySelected(selected, true)
		-- If that highlighted the wrong entry, the list is probably numbering
		-- entries from 0 here, so try once more on that basis.
		if highlightedPreset() ~= selected then
			presetList:SetEntrySelected(selected - 1, true)
		end
		selected = highlightedPreset() or selected
	end
end

presetList:Subscribe(ui.Hook.ONSELECTIONCHANGED, function(_list, entryID, change)
	if change == ui.SelectionChangeEvent.SELECTED then
		selected = highlightedPreset() or entryID
		refresh()
	end
end)

-- The text in the name box. The docs don't say when `content` updates, so it's
-- tracked from the field's change hook, which passes the new text each time.
local typedName = ""
nameInput:Subscribe(ui.Hook.ONCONTENTCHANGED, function(_field, _reason, newContents)
	typedName = newContents or ""
end)

-- Buttons ------------------------------------------------------------------

-- Saves what the player has on them now, under the typed name (or a numbered
-- one if the box is empty). Saving under an existing name replaces it.
local function saveCurrent()
	-- Spaces at either end are dropped, so "  " counts as no name.
	local name = typedName:match("^%s*(.-)%s*$")
	if name == "" then
		name = "Preset " .. (#savedPresets + 1)
	end
	local preset = presets.new(name)
	preset.inventory = readSlots(BACKPACK)
	preset.equipment = readSlots(EQUIPMENT)
	preset.bob = readSlots(BOB) -- empty when no familiar is out
	selected = presets.save(savedPresets, preset)
	nameInput.content = ""
	typedName = ""
	storePresets()
	refreshList()
	refresh()
end

-- Delete takes two presses, so one stray click can't lose a preset.
local deleteButton
local confirmingDelete = false

local function deleteSelected()
	if not selected then
		return
	end
	if not confirmingDelete then
		confirmingDelete = true
		deleteButton.label = "Press again"
		return
	end
	confirmingDelete = false
	deleteButton.label = "Delete"
	presets.remove(savedPresets, selected)
	storePresets()
	if #savedPresets == 0 then
		selected = nil
	else
		selected = math.min(selected, #savedPresets)
	end
	refreshList()
	refresh()
end

local missingButton

local function toggleMissing()
	showingMissing = not showingMissing
	missingButton.label = showingMissing and "Show whole preset" or "Show what's missing"
	-- The BoB is part of what's being checked, so open the familiar section if
	-- this preset has one (without changing the player's saved preference).
	local preset = selected and savedPresets[selected]
	if showingMissing and not showFamiliar and preset and next(preset.bob) ~= nil then
		setFamiliarShown(true, false)
	end
	refresh()
end

local saveButton = addButton("Save", id.StyleSheet.BUTTON_DEFAULT, saveCurrent)
saveButton:SetSize((LIST_WIDTH - 6) // 2, BUTTON_HEIGHT)
saveButton:SetPos(MARGIN, buttonY)

deleteButton = addButton("Delete", id.StyleSheet.BUTTON_DEFAULT, deleteSelected)
deleteButton:SetSize((LIST_WIDTH - 6) // 2, BUTTON_HEIGHT)
deleteButton:SetPos(MARGIN + (LIST_WIDTH + 6) // 2, buttonY)

missingButton = addButton("Show what's missing", id.StyleSheet.BUTTON_DEFAULT, toggleMissing)
missingButton:SetPos(backpackX, buttonY)

-- Moving the window --------------------------------------------------------
-- Neither the client's drag events nor clicks on the window itself moved it,
-- so moving works through a small grip button next to the X in the title bar:
-- click it and the window follows the mouse; the grip stays under the cursor,
-- so clicking it again drops the window there. (The docs list mouse button
-- state as "TODO", so a true press-and-drag isn't possible yet.)

-- While moving: where the mouse and window were when it started.
local move = nil

-- Moves the window to follow the mouse, kept fully inside the game area.
-- Puts the window at x, y, pushed back inside the game area if any part of
-- it would stick out.
local function placeWindow(x, y)
	x = math.floor(math.max(0, math.min(x, gameWindow.width - window.width)))
	y = math.floor(math.max(0, math.min(y, gameWindow.height - window.height)))
	window:SetPos(x, y)
	for _, shadow in ipairs(shadows) do
		local spread = shadow.spread
		shadow.rectangle:SetSize(window.width + 2 * spread, window.height + 2 * spread)
		shadow.rectangle:SetPos(x - spread, y - spread + SHADOW_DROP)
	end
end

-- Moves the window to follow the mouse.
local function followMouse()
	if not move then
		return
	end
	local mouseX, mouseY = Mouse.GetX(), Mouse.GetY() -- nil without a mouse
	if not (mouseX and mouseY) then
		return
	end
	placeWindow(move.windowX + (mouseX - move.mouseX), move.windowY + (mouseY - move.mouseY))
end
Event.Draw.Subscribe("presetVaultMove", followMouse)

local TITLE = "Preset Vault"

-- The title, centred in the title bar.
local titleText = ui.Text.new(window)
titleText.font = id.Font.MUSEO_SANS_15PT_REGULAR
titleText.content = TITLE
titleText:AlignTo(ui.AlignMode.CENTRE)
titleText.isShadowed = true

local function toggleMove()
	if move then
		-- Drop the window here and remember the spot for next time.
		move = nil
		titleText.content = TITLE
		PersistentDB:SetInt(WINDOW_X_KEY, window.x)
		PersistentDB:SetInt(WINDOW_Y_KEY, window.y)
		return
	end
	local mouseX, mouseY = Mouse.GetX(), Mouse.GetY()
	if not (mouseX and mouseY) then
		print("Preset Vault: can't move the window without a mouse position")
		return
	end
	move = { mouseX = mouseX, mouseY = mouseY, windowX = window.x, windowY = window.y }
	titleText.content = "Click :: again to drop"
end

-- The move grip, just left of the X at the right end of the title bar. "::"
-- stands in for a grip icon, as the game's font may not have one.
local moveGrip = addButton("::", id.StyleSheet.BUTTON_DEFAULT, toggleMove)
moveGrip:SetSize(TITLE_BUTTON_WIDTH, HEADER_HEIGHT - 6)

-- Opening and closing ------------------------------------------------------
-- The window starts closed. The button Preset Vault adds to the bank opens
-- and closes it, and so does the X in the window's title bar.

local function setWindowOpen(open)
	window.hidden = not open
	for _, shadow in ipairs(shadows) do
		shadow.rectangle.hidden = not open
	end
	if open then
		-- A position saved when the window was smaller (or on a bigger screen)
		-- could leave part of it off-screen, including the Move button.
		placeWindow(window.x, window.y)
		refresh()
	elseif move then
		toggleMove() -- closing while moving drops the window where it is
	end
end

-- The X at the right end of the title bar.
local closeButton = addButton("X", id.StyleSheet.BUTTON_DEFAULT, function()
	setWindowOpen(false)
end)
closeButton:SetSize(TITLE_BUTTON_WIDTH, HEADER_HEIGHT - 6)

-- Familiar section and window width ------------------------------------------

-- Sizes and places everything that depends on the window's width, for the
-- familiar section open or closed, and shows or hides that section.
local function layoutWidth()
	local width = showFamiliar and openWidth or closedWidth
	local rightWidth = rightWidthFor(width)

	window:SetSize(width, windowHeight)
	titleBar:SetSize(width, HEADER_HEIGHT)
	titleBarEdge:SetSize(width, 1)
	windowEdge:SetSize(width, windowHeight)
	titleText:SetSize(width, HEADER_HEIGHT)
	moveGrip:SetPos(width - 2 * TITLE_BUTTON_WIDTH - 8, 3)
	closeButton:SetPos(width - TITLE_BUTTON_WIDTH - 4, 3)

	title:SetSize(rightWidth - FAMILIAR_BUTTON_WIDTH - 6, LINE_HEIGHT)
	familiarButton:SetSize(FAMILIAR_BUTTON_WIDTH, LINE_HEIGHT)
	familiarButton:SetPos(backpackX + rightWidth - FAMILIAR_BUTTON_WIDTH, contentY)
	status:SetSize(rightWidth, LINE_HEIGHT)
	missingButton:SetSize(rightWidth, BUTTON_HEIGHT)

	for _, part in ipairs(bobParts) do
		part.hidden = not showFamiliar
	end
end

-- Opens or closes the familiar section. `remember` saves the choice for next
-- time; it's false when the section opens by itself.
setFamiliarShown = function(shown, remember)
	showFamiliar = shown
	if remember then
		PersistentDB:SetBool(SHOW_FAMILIAR_KEY, shown)
	end
	layoutWidth()
	placeWindow(window.x, window.y) -- re-fit the shadow, and keep it on screen
	refresh()
end

layoutWidth()

window.hidden = true

-- Strict slot order setting ------------------------------------------------
-- The setting has a tick box in the window, and another in the plugin's
-- settings page (plugin.json sets "hasSettingsIcon", which should put a
-- settings icon on Preset Vault in the Plugin Hub's Manage tab; it hasn't
-- appeared for the dev copy, hence the one in the window). Both change the
-- same saved value.

local windowStrictCheck -- the tick box in the window, kept in step

local function setStrictSlots(on)
	strictSlots = on
	PersistentDB:SetBool(STRICT_SLOTS_KEY, on)
	windowStrictCheck.value = on
	refresh()
end

-- Creates a Strict slot order tick box in `parent`.
local function addStrictCheck(parent, label)
	local check = ui.Check.new(parent)
	-- Only use the check box style if this client has it (missing ones read as
	-- -1 and make the component draw nothing).
	if id.StyleSheet.CHECKBOX_DEFAULT ~= -1 then
		check.stylesheetID = id.StyleSheet.CHECKBOX_DEFAULT
	end
	check.label = label
	check.value = strictSlots
	check:Subscribe(ui.Hook.ONBUTTONPRESSED, function(_check, ticked)
		setStrictSlots(ticked)
	end)
	return check
end

windowStrictCheck = addStrictCheck(window, "Strict slot order")
windowStrictCheck:SetSize(LIST_WIDTH, LINE_HEIGHT)
windowStrictCheck:SetPos(MARGIN, statusY - LINE_HEIGHT - 6)

-- Opening the settings page fires SettingsLayerReady with an empty component.
Event.SettingsLayerReady.Subscribe("presetVaultSettings", function(event)
	local check = addStrictCheck(
		event.component,
		"Strict slot order: flag preset items in the wrong backpack or beast of burden slot"
	)
	check:SetSize(0, LINE_HEIGHT, 1.0, 0)
	check:SetPos(MARGIN, MARGIN)
end)

-- Keeping up to date -------------------------------------------------------

-- Whenever an inventory changes (withdrawing, equipping, the bank arriving),
-- redraw so faded icons and the bank line follow what the player has.
local function onInventoryChanged()
	if showingMissing then
		refresh()
	end
end
Event.InventoryUpdated.Subscribe("presetVaultInventory", onInventoryChanged)
Event.InventoryAdded.Subscribe("presetVaultInventory", onInventoryChanged)

-- Bank highlighting --------------------------------------------------------
-- The bank's item slots are the children of BANK__BANK_INV. The docs don't
-- list the bank's components; this was found by walking id.Component in game.
-- Each slot is an icon whose associatedObjectID is the item it shows. The
-- bank also shows the backpack, as the children of BANK__INVENTORY_CLICK.

local HIGHLIGHT_COLOUR = Vector4.new(0.2, 1.0, 0.2, 1.0) -- bright green
local HIGHLIGHT_THICKNESS = 2
local HIGHLIGHT_INTERVAL = 0.1 -- seconds between redraws, so scrolling is followed

-- Reads a property that only some kinds of component have (e.g. `scrollable`,
-- which only containers have), giving nil instead of an error.
local function tryProperty(component, property)
	local ok, value = pcall(function()
		return component[property]
	end)
	if ok then
		return value
	end
	return nil
end

-- Finds the container that scrolls the bank's slots: the nearest of the slot
-- container and its parents whose scroll content is taller than itself. (Every
-- one of them reports `scrollable`, so that flag alone doesn't tell. In
-- testing it was the slot container's parent: 799 tall, scrolling 7,085.)
-- When nothing needs scrolling (a small tab), that parent is still the
-- visible window, so it's used as the fallback.
local function findScroller(bankSlots)
	local candidate = bankSlots
	for _ = 1, 4 do
		if not candidate then
			break
		end
		local contentHeight = tryProperty(candidate, "scrollHeight") or 0
		if contentHeight > candidate.height then
			return candidate
		end
		candidate = candidate.parent
	end
	return bankSlots.parent
end

-- Draws an outline around a component on the highlights canvas. `x` and `y`
-- are its on-screen position; the canvas draws relative to its own corner.
local function outline(x, y, component, colour)
	local origin = highlights.xyGlobal
	highlights:AddOutline(x - origin.x, y - origin.y, component.width, component.height, HIGHLIGHT_THICKNESS, colour)
end

-- Outlines (green) every bank slot on screen holding an item in itemsToHighlight.
local function outlineNeededInBank()
	local bankSlots = ui.Interfaces:GetComponent(id.Component.BANK__BANK_INV)
	local scroller = bankSlots and findScroller(bankSlots)
	if not scroller then
		return -- the bank isn't open
	end

	-- Slots report where they'd be if the bank weren't scrolled, so subtract
	-- the scroll, and only draw slots inside the scrolling container's edges.
	local corner = scroller.xyGlobal
	local left, top = corner.x, corner.y
	local right, bottom = left + scroller.width, top + scroller.height
	local scrollX, scrollY = scroller.scrollX, scroller.scrollY

	-- The iterator's own "visible" flag proved unreliable, so it's ignored;
	-- visibleGlobal is false for slots in other bank tabs.
	bankSlots:IterateDynamicComponents(function(slot)
		if itemsToHighlight[slot.associatedObjectID] and slot.visibleGlobal then
			local x = slot.xyGlobal.x - scrollX
			local y = slot.xyGlobal.y - scrollY
			if x >= left and y >= top and x + slot.width <= right and y + slot.height <= bottom then
				outline(x, y, slot, HIGHLIGHT_COLOUR)
			end
		end
	end)
end

-- Outlines (red or orange) the slots of the bank's view of the backpack that
-- hold the wrong thing, from backpackErrors. The 28 icons are the children of
-- BANK__INVENTORY_CLICK, and icon N is backpack slot N + 1 (checked in game).
local function outlineBackpackErrors()
	local icons = ui.Interfaces:GetComponent(id.Component.BANK__INVENTORY_CLICK)
	if not icons then
		return -- the bank isn't open
	end
	icons:IterateDynamicComponents(function(icon)
		local slot = icon.dynamicID + 1
		local problem = backpackErrors[slot]
		if problem and icon.visibleGlobal then
			local position = icon.xyGlobal
			outline(position.x, position.y, icon, ERROR_COLOURS[problem])
		end
	end)
end

-- Redraws all bank marks: needed items in the bank, and wrong backpack slots.
-- Draws nothing when "Show what's missing" is off, or the window or bank is
-- closed.
local function drawBankHighlights()
	highlights:Clear()
	if window.hidden then
		return -- no marks while the window is closed
	end
	if next(itemsToHighlight) ~= nil then
		outlineNeededInBank()
	end
	if next(backpackErrors) ~= nil then
		outlineBackpackErrors()
	end
end

-- Bank button --------------------------------------------------------------
-- While the bank is open, a "Preset Vault" button sits directly above the
-- bank's Transfer and Presets tabs, spanning both. The Presets tab is
-- BANK__SIDE_TAB_PRESETS (found by listing the bank's components in game; the
-- docs don't list them). The button lives on the plugin layer and follows the
-- tabs; the game's own tabs can't be resized to make room beside them.

local TAB_GAP = 2 -- space between the tabs, and between the tabs and the button

-- (The button itself is created before the window, so it's drawn behind it.)
bankButton:Subscribe(ui.Hook.ONBUTTONPRESSED, function()
	setWindowOpen(window.hidden) -- opens it if closed, closes it if open
end)

-- Looks up a bank component by name, or nil if the client has no such name
-- or the component isn't loaded.
local function findBankComponent(name)
	local ok, component = pcall(function()
		return ui.Interfaces:GetComponent(id.Component[name])
	end)
	if ok then
		return component
	end
	return nil
end

-- Shows the bank button above the Transfer and Presets tabs, as wide as both,
-- while they're on screen; hides it otherwise.
local function placeBankButton()
	local presetsTab = findBankComponent("BANK__SIDE_TAB_PRESETS")
	if not (presetsTab and presetsTab.visibleGlobal) then
		bankButton.hidden = true
		return
	end
	local tabCorner = presetsTab.xyGlobal
	local right = tabCorner.x + presetsTab.width

	-- The Transfer tab's name is a guess based on the Presets tab's; if it's
	-- wrong, assume it mirrors the Presets tab just to its left.
	local transferTab = findBankComponent("BANK__SIDE_TAB_TRANSFER")
	local left = transferTab and transferTab.xyGlobal.x or (tabCorner.x - TAB_GAP - presetsTab.width)

	-- On-screen position, made relative to the plugin layer the button is on.
	local origin = gameWindow.xyGlobal
	bankButton:SetSize(math.floor(right - left), presetsTab.height)
	bankButton:SetPos(math.floor(left - origin.x), math.floor(tabCorner.y - TAB_GAP - presetsTab.height - origin.y))
	bankButton.hidden = false
end

-- Redraw a few times a second rather than every frame: often enough to
-- follow scrolling, without walking all the bank's slots 60 times a second.
local sinceLastHighlight = 0
Event.Draw.Subscribe("presetVaultHighlights", function(event)
	sinceLastHighlight = sinceLastHighlight + event.timeDeltaSecs
	if sinceLastHighlight >= HIGHLIGHT_INTERVAL then
		sinceLastHighlight = 0
		drawBankHighlights()
		placeBankButton()
	end
end)

refreshList()
refresh()
