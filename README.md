# LocGuard Lite

Free in-editor localization checker for Godot 4. Scans your project for
strings passed to `tr()` / `Tr()` / scene text properties and cross-checks
them against your translation CSV, flagging two things:

- **missing-key** (error) — a string is used in code/scenes but has no row
  in the translation CSV.
- **empty-translation** (warning) — a key exists in the CSV but a locale's
  value is blank.

Verified headless against Godot **4.3, 4.4 and 4.7** stable — run on 2026-09-07, the
seven stages of `verify.sh` report ALL VERIFICATION PASSED on each of the three binaries.

**4.2 is not claimed, and two separate things block it**, both measured in the same run:
the engine does not resolve the core script's `class_name` in a headless run (`Parse Error:
Identifier "LocGuardLiteCore" not declared in the current scope`), and the fixture's
`.translation` files are built by 4.7, so 4.2 refuses them for using resource format
version 6. Fixing only the first would not produce a green 4.2 run. Nothing on 4.2 has
been measured end to end.

## Install

**Godot Asset Library** (recommended) — search "LocGuard Lite" in the editor's
AssetLib tab, or install from
[the listing](https://godotengine.org/asset-library/asset/5378). The download
contains only `addons/locguard_lite/`, so nothing lands in your project root.

Or manually:

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


## More from the studio

- **[Blobsmith](https://blobsmith.itch.io/blobsmith)** — draw 6 tiles, get a full 47-blob autotile sheet + a wired Godot 4 TileSet ([free in-browser version](https://blobsmith.itch.io/blobsmith-lite))
- **[LocGuard](https://github.com/leobaray/locguard)** — localization QA linter for Godot 4: missing keys, placeholder drift, broken BBCode ([Pro: in-editor dock + CI gate](https://blobsmith.itch.io/locguard))
- **[Blobsmith Autotile Wirer](https://github.com/leobaray/blobsmith-autotile-wirer)** — free addon that wires a 47-blob sheet into a TileSet inside the editor
- **[The nine Godot 4 scanners, one zip](https://blobsmith.lbwma.com/godot-scanners/)** — free MIT Node scripts that read a Godot 4 project without opening it: missing font glyphs (project and CSV), frozen translations, plural forms the CSV cannot serve, POT gaps, tile seams, collision holes, draw order, and which tile terrain painting will choose. No install and no account
- **[blobsmith.lbwma.com](https://blobsmith.lbwma.com/)** — the studio site: every release in one place, plus free browser tools (nonogram solver, puzzle generators) and printable PDFs
