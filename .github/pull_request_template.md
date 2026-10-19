## What and why

<!-- What does this change, and why? Name the plugin(s) it touches. -->

## Testing

<!-- How was it tested in the beta client? What did you check by hand?
     Screenshots help for anything visual. -->

## Checklist

- [ ] `make check` passes (lint, format, tests, manifest validation).
- [ ] Tested in the beta client (`prl <name>`), with no errors in the console.
- [ ] Code is commented and readable, and I've reviewed every line.
- [ ] Plugin rules: it only helps the player see, organise or track
      information the game already shows them. It never acts for the player,
      reveals hidden or future information, solves mechanics, or stores or
      exports data about other players.
- [ ] No Jagex documentation text, API notes or client exports (`data/`) in
      the change.
- [ ] Plugin `README.md` (the mod.io description) still matches what it does.
- [ ] If releasing: version bumped in `plugin.json` and a `CHANGELOG.md` entry
      added.
