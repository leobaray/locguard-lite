# Why your exported game is not translated and the editor says everything is fine

You press Play and the game is in Portuguese. You export a build, hand it to a
tester, and the same screen is in English — or shows `GREET` where a sentence
should be. Nothing changed in the CSV, the locale or the code. The export
finished with no error.

The CSV is not what your game reads, and the project folder is not what your
player runs. Between them sits one file — the `.pck` data pack — and whether your
translations are inside it is decided by the export preset, which never mentions
translations anywhere in its interface.

Every claim below was measured by
[`verify_export_pack.sh`](verify_export_pack.sh) on Godot **4.2, 4.3, 4.4 and
4.7** stable, run on 2026-09-12. The script builds throwaway projects, exports a
real `.pck` with the engine's own exporter, then **runs that pack** and asks the
running game what it can show a player. The ids (`M1`, `M2`, …) are the ids the
script prints, so you can re-run any single line against your own binary. No
export template is needed: `--export-pack` writes the data part, which is the
part this page is about.

## The translations are in your project, not in your scenes

A Godot project declares its translations in one place: the
`internationalization/locale/translations` list in `project.godot`. No scene
references them. No script loads them. No resource has them as a dependency.

That is fine, until an export preset is set to **"Export selected scenes (and
dependencies)"** — the setting a team picks to keep test maps, tooling and work
files out of the shipped build. The exporter then walks the dependency graph of
the scenes you ticked. Nothing in that graph points at a `.translation`, so
nothing pulls it in.

The result, measured (`M3`): the pack contains no translation file at all, the
game boots, `TranslationServer.get_loaded_locales()` comes back **empty**, and
every `tr()` call returns its key. Your player reads `GREET`.

The same pack with the default preset — export all resources — translates
correctly (`M1`). One radio button, no other difference.

An exclude filter does it too. `*.translation` in the preset's exclude field
empties the game of every language just as completely (`M4`), and so does any
broader pattern that happens to match those generated names.

## The failure is invisible on both sides of the export

- **The export does not complain.** Both exports above finish with **exit code
  0**, and the word "translation" does not appear anywhere in the export log
  (`M5`). There is no warning in the editor's export dialog either: from the
  exporter's point of view nothing went wrong, because you told it which files
  to ship and it shipped them.
- **The project still works.** Run either broken project from the project
  directory and it translates perfectly (`M9`). Every test you run in the
  editor, including an automated one, passes. The defect exists only in the
  artifact you hand to players.
- **The only signal goes to a console nobody reads.** The packed game prints, at
  boot, `Failed loading resource: res://strings.en.translation` (`M6`) — the
  first locale the project declares — and then shows the key anyway. It goes to
  stdout, which a player double-clicking your game never sees. On 4.2, 4.3 and
  4.4 the line continues `Make sure resources have been imported by opening the
  project in the editor at least once`, which is wrong about the cause here: the
  project was imported and the generated file is on your disk — it is the export
  preset that left it out. 4.7 prints only the first sentence, so the misleading
  advice is gone and the remaining message says nothing about what to change.

## The worst version: leave out one language

Exclude a single locale instead of all of them (`*.pt.translation`) and the
symptom stops looking like a bug. The pack loads `en`, the game sets the locale
to `pt`, and the Portuguese player reads **`Hello`** (`M7`). No key, no empty
label, no missing glyph — the source language, in the right place, in a screen
that looks finished.

This is the same class of failure as a whole locale column importing to nowhere:
the screen the tester photographs looks correct, and `get_loaded_locales()` is
the only witness in the whole engine.

## Three things that are not the problem

- **Your `strings.csv` is not in the pack, and that is normal.** Even with all
  resources exported, the source table is left out and only the generated
  `.translation` ships (`M2`). Excluding `*.csv` from the export changes nothing
  for the player (`M11`), because the game never reads the CSV.
- **Exporting from a machine that never opened the editor is safe.** A tree with
  no `.godot/` and no `.translation` on disk — a fresh clone on a build server —
  still ships working translations, because the export runs its own import pass
  first (`M12`).
- **Grepping the `.pck` proves nothing.** `grep` finds the string
  `strings.pt.translation` inside a pack that does **not** contain that file
  (`M8`): the path is in the packed project settings whether or not the file
  came along. The only honest presence test is inside the running artifact, with
  `FileAccess.file_exists()` or `get_loaded_locales()`.

## How to check it in one line, and how to fix it

Run your own exported pack and ask it what it loaded:

```
godot --headless --main-pack /path/to/your/game.pck
```

with this in your main scene, or in an autoload behind a debug flag:

```gdscript
print("locales in the build: ", TranslationServer.get_loaded_locales())
```

An empty array, or an array missing a locale you shipped, is the whole bug.
Running it on every build is a two-line check that costs nothing and catches a
defect no editor test can see.

The fix, measured (`M10`): add `*.translation` to the preset's **include**
filter. The pack translates again, with no change to the CSV, the code, the
locales or the scene list.

## What LocGuard Lite does and does not cover

Stated honestly, as on every page here: Lite has two rules, `missing-key` and
`empty-translation`, and both of them read your CSV inside the editor. **Neither
of them can see an export preset, and no page on this repository claims
otherwise** — every project on this page passes Lite completely clean, because
the table is perfect. The file that fails is one the exporter did not copy.

LocGuard Pro does not cover this either, and neither does anything else we know
of on the market. The defence is the two-line check above, in your build script,
on the artifact. This page exists so that you know to write it.

## Reproducing

```
docs/verify_export_pack.sh /path/to/Godot_v4.2-stable_linux.x86_64
docs/verify_export_pack.sh /path/to/Godot_v4.3-stable_linux.x86_64
docs/verify_export_pack.sh /path/to/Godot_v4.4-stable_linux.x86_64
docs/verify_export_pack.sh /path/to/Godot_v4.7-stable_linux.x86_64
```

12 claim ids. Each one is measured either around the export (exit codes, the
export log, the bytes of the pack) or inside a running artifact, and the artifact
is the authority: the summary line is the gate, and a run that does not reach it
reports an error rather than a pass. `LG_SELFTEST=1` flips one expectation on
purpose so you can confirm the harness can fail.

One detail the script has to handle and your build script may too: 4.2 calls the
export platform `Linux/X11` and 4.3 renamed it to `Linux`. A preset naming a
platform the binary does not know is detected as **no preset at all**, and the
export then writes no pack while still exiting 0.
