std = "lua54"
-- .rocks/ is where `make setup` installs tools locally; CI installs them into
-- .lua/ and .luarocks/. None of it is our code.
exclude_files = { ".rocks/**", ".lua/**", ".luarocks/**" }

files["spec/**"] = { std = "+busted" }

-- Globals the RuneScape client provides to plugins. Add new ones here as the
-- tutorials introduce them, so luacheck still catches real typos. Keep the
-- "diagnostics.globals" list in .luarc.json (used by the editor) in step.
files["plugins/**"] = {
	read_globals = {
		"config", -- static game config, e.g. config.NPC.DOG_STRAY
		"Event", -- game events, e.g. Event.ServerLogic.Subscribe(id, fn)
		"formatStr", -- fills {} placeholders in order, e.g. formatStr("{} is {}", a, b)
		"id", -- ID tables, e.g. id.Component.*
		"Inventory", -- item containers, e.g. Inventory.Find(config.Inv.INV)
		"log", -- writes a line to the client console
		"Mouse", -- mouse position, e.g. Mouse.GetPosition()
		"NPCList", -- NPCs currently near the player, e.g. NPCList.ByName(name)
		"PersistentDB", -- saved key/value storage, e.g. PersistentDB:Get(key)
		"Player", -- the local player (you), e.g. Player.GetLevelGameplay(skill)
		"SkillType", -- skill IDs, e.g. SkillType.ATTACK
		"ui", -- client UI, e.g. ui.Interfaces
		"var", -- player and client variables, e.g. var.VarPlayer.NAME.value
		"Vector4", -- 4-number vector, e.g. RGBA colours
	},
	-- Functions a plugin defines for the client to call by name.
	globals = {
		"PluginShutdown", -- called when the plugin shuts down
	},
}
