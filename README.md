# RuneScape Plugins

Open-source plugins for the RuneScape client (Lua 5.4), one folder per plugin
in [`plugins/`](plugins). Each plugin is published separately on
[mod.io](https://mod.io/g/runescape) and runs on live worlds only after Jagex
approves it.

| Plugin | What it does |
|---|---|
| [preset-vault](plugins/preset-vault) | Keeps more bank presets than the game's 15 and highlights what to withdraw (in progress) |

## Layout

```
plugins/<name>/     one plugin: main.lua, plugin.json, README.md, CHANGELOG.md, resources/
spec/               unit tests (busted)
tools/validate.lua  checks every plugin.json against the client and mod.io rules
tools/package.sh    builds the mod.io upload zip
```

Each plugin's README doubles as its mod.io description, and its
`plugin.json` is the only place its version number lives.

## Development (macOS)

```sh
brew install lua@5.4 luarocks stylua lua-language-server fswatch
make setup                      # luacheck, busted, dkjson into .rocks/
make check                      # lint, format check, tests, manifest validation
make watch PLUGIN=preset-vault   # copy into ~/Jagex/RuneScape-BETA/dev_plugins on every save
```

Then, in the beta client's console (Alt + `): `prf` to rescan, `pon preset-vault`
to enable. Leave `make watch` running; after each save, run `prl preset-vault` in
game. (The client ignores symlinked folders, so plugins are copied in. `make sync`
does a one-off copy.)

### VS Code

Opening the folder suggests the extensions this repo uses (Claude Code, Lua,
StyLua) and formats Lua on save. Under **Terminal → Run Task**: *Watch plugin*
runs `make watch`, *Check* runs `make check`, *Package plugin* builds the zip.

## Releasing

1. Bump `version` in the plugin's `plugin.json` (numbers and full stops only, e.g. `1.2.0`) and add a `CHANGELOG.md` entry.
2. Tag and push: `git tag preset-vault/v1.2.0 && git push --tags`.
3. CI validates the plugin, builds `preset-vault-1.2.0.zip`, and attaches it to a GitHub Release.
4. Upload the zip to the plugin's mod.io page by hand. Don't change a listing while it's in moderation.

## License

[MIT](LICENSE)
