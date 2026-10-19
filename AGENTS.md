# Working on this repo with an AI assistant

Rules for Claude Code, OpenCode and any other AI assistant working here. For
Claude Code, `.claude/settings.json` and `tools/ai-guard.sh` enforce the
`data/` rules.

## Jagex's developer material

- The public developer docs (developer.runescape.com) may be read. Jagex's AI
  policy allows tools to access public documentation; the maintainer (Mark)
  reads its "provided by us" restriction as covering material shared through
  non-public channels.
- Never use material Jagex supplies through non-public channels: Jmod examples
  from Discord, private API or client internals. Never use other developers'
  code without their consent.
- No doc text or API notes in this repo. It's public. Link to the docs
  instead; API notes live in Mark's private notes, written as summaries with
  source links.

## Local client exports (`data/`)

- `data/` holds exports from the game client's console (e.g. `pan NPC`). It's
  gitignored: never commit it or copy it elsewhere in the repo.
- Only search it for specific entries, such as one NPC's ID: run
  `tools/data-lookup.sh PATTERN [EXPORT]` (at most 50 lines per file), or use
  the Grep tool with a specific pattern and a small `head_limit`. Don't read
  whole files, dump them in the shell, or copy large parts into notes.
- Don't build on entries that look unreleased.

## What plugins may do

Plugins help the player see, organise and track information the game already
shows them. They must never act for the player, reveal hidden or future
information, solve game mechanics, or export data about other players. Check
new ideas against this before writing code.

## Code and releases

- Commented, readable Lua 5.4. Mark reviews every line before release, and
  Jagex's moderators reject code that's hard to read.
- Globals the client provides are declared in `.luacheckrc`; add new ones there.
- Run `make check` before committing. Commits use Mark's GitHub noreply email.
- A plugin's version lives only in its `plugin.json`. Releases are tagged
  `<name>/v<version>`; CI builds the zip. mod.io uploads are done by hand, never
  automated.
