# LocGuard Lite

Free in-editor localization checker for Godot 4. Scans your project for
strings passed to `tr()` / `Tr()` / scene text properties and cross-checks
them against your translation CSV, flagging two things:

- **missing-key** (error) — a string is used in code/scenes but has no row
  in the translation CSV.
- **empty-translation** (warning) — a key exists in the CSV but a locale's
  value is blank.

Verified headless against Godot 4.7.

## Install

1. Copy `addons/locguard_lite` into your project's `addons/` folder.
2. Project Settings → Plugins → enable "LocGuard Lite".
3. Open the "LocGuard Lite" dock (bottom-right by default) and click
   **Scan project**. Double-click a finding to open the offending file.

## What LocGuard Pro adds

LocGuard Lite is a trimmed-down slice of
[LocGuard Pro](https://blobsmith.itch.io/locguard). Pro adds:

- **placeholder drift** — catches `%d`/`%s`/`{0}`/`{name}` mismatches between
  locales.
- **BBCode checks** — flags unclosed/mismatched/stray `[b]`, `[color]`, etc.
- **orphan keys** — CSV rows that are never referenced in code or scenes.
- **CLI + CI** — a headless command-line runner so the same checks gate
  your pull requests, not just the editor.

Get it: https://blobsmith.itch.io/locguard

## License

MIT — see [LICENSE](LICENSE).
