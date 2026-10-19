# RuneScape Plugins

Open-source plugins for the RuneScape client (Lua 5.4), one folder per plugin
in [`plugins/`](plugins). Each plugin is published separately on
[mod.io](https://mod.io/g/runescape) and runs on live worlds only after Jagex
approves it.

| Plugin | What it does |
|---|---|
| [hello-world](plugins/hello-world) | Test plugin for the development setup |

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
brew install lua@5.4 luarocks stylua lua-language-server
make setup                      # luacheck, busted, dkjson into .rocks/
make check                      # lint, format check, tests, manifest validation
make sync PLUGIN=hello-world    # copy into ~/Jagex/RuneScape-BETA/dev_plugins
```

Then, in the beta client's console (Alt + `): `prf` to rescan, `pon hello-world`
to enable. After each edit, run `make sync` again, then `prl hello-world` in game
(the client ignores symlinked folders, so plugins are copied in).

## Releasing

1. Bump `version` in the plugin's `plugin.json` (numbers and full stops only, e.g. `1.2.0`) and add a `CHANGELOG.md` entry.
2. Tag and push: `git tag hello-world/v1.2.0 && git push --tags`.
3. CI validates the plugin, builds `hello-world-1.2.0.zip`, and attaches it to a GitHub Release.
4. Upload the zip to the plugin's mod.io page by hand. Don't change a listing while it's in moderation.

## License

[MIT](LICENSE)
