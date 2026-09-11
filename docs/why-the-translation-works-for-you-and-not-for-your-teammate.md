# Why the translation works for you and not for your teammate

It works on your machine. Your teammate pulls, runs the game, and the screen is
full of `MENU_START` and `OPTION_AUDIO`. Or worse: it runs, it is in the right
language, and it shows text you deleted from the CSV a week ago.

The advice you will find is "open the project in the editor once", "delete
`.godot/`", "commit your `.import` files", "don't commit your `.import` files".
Some of that is right. None of it says which file the running game actually
reads, and that is the only question here — because **the game never reads your
CSV.**

Everything below is measured, not remembered. The claim ids (`M1`…`M17`) are
the checks that run inside the engine, in
[`verify_generated_files.gd`](verify_generated_files.gd), plus the four
cross-version ones (`M11`, `M15`, `M16`, `M17`) that compare whole files and
therefore live in the shell script itself. Run
[`verify_generated_files.sh`](verify_generated_files.sh) against your own
binaries and it will print the same list with PASS/FAIL for your versions:

```
docs/verify_generated_files.sh /path/to/Godot_v4.7-stable_linux.x86_64
docs/verify_generated_files.sh /path/to/4.2 /path/to/4.3 /path/to/4.4 /path/to/4.7
```

Four of the claims compare one engine's output against another engine, so a
single binary measures 14 of the 18 and reports the rest as SKIP rather than
quietly dropping them.

**Measured on Godot 4.2, 4.3, 4.4 and 4.7 stable (official Linux builds),
2026-09-11: 14/14 on each of the four separately, 18/18 with all four passed
together.** Every import in the run is done by those same binaries running as a
headless editor, so "what the importer does" is the real importer.

---

## 1. What the import actually puts on your disk

Drop `strings.csv` into a project, let the editor import it, and look at the
project directory — not at `.godot/`, at the directory itself:

```
project.godot
strings.csv
strings.csv.import
strings.en.translation      <- new
strings.pt.translation      <- new
```

One `.translation` per language column, written **next to the CSV, inside your
project** (`M1`). Alongside them, `strings.csv.import` (`M2`). The only thing
the import leaves under `.godot/` is a single `.md5` stamp (`M2`).

This is the part that catches people who came from Godot 3, where generated
import products lived in a folder you were told to ignore. Here two of the three
generated files are ordinary files in your source tree, and your version control
treats them as ordinary files, because they are.

`project.godot` names those generated files and never names the CSV (`M3`):

```
[internationalization]

locale/translations=PackedStringArray("res://strings.en.translation", "res://strings.pt.translation")
```

The `uid://` that identifies the resource is minted at the first import and
stored in `strings.csv.import`. It is not in the CSV (`M14`).

## 2. What the running game reads

Four deletions, four launches of the game with no editor pass at all. This is
the whole answer to "which file matters":

| What is missing from the clone | `tr("GREETING")` | |
|---|---|---|
| nothing was ever imported | `GREETING` | `M4` |
| `.godot/` only | `Hello` | `M5` |
| `.godot/` and the `.translation` files | `GREETING` | `M6` |
| `.godot/` and `strings.csv.import` | `Hello` | `M7` |
| `.godot/` and `strings.csv` itself | `Hello` | `M8` |

Read the last two rows again. You can delete the `.import` file, and you can
delete **the CSV**, and the game still translates. The `.translation` files are
the product; everything else is scaffolding for regenerating them.

And the first row is the one that surprises people: in a project that was never
imported, `ResourceLoader.exists("res://strings.csv")` is `false` while the file
is sitting right there in the directory listing (`M4b`). Unimported means
invisible, not merely unconverted.

When the `.translation` files are the thing that is missing, the engine is at
least loud about it (`M6`):

```
ERROR: Cannot open file 'res://strings.en.translation'.
ERROR: Failed loading resource: res://strings.en.translation. Make sure
       resources have been imported by opening the project in the editor at
       least once.
```

That message is the friendly failure. The next section is the unfriendly one.

## 3. The failure with no error at all

Put a `.translation` from last week next to a CSV you edited today, and run the
game without an editor pass. The CSV on disk says `BRAND NEW TEXT`. The screen
says `Hello` (`M9`). No error, no warning, nothing in the Output panel. The
editor, meanwhile, shows you the CSV — the file that is not being read.

One editor pass regenerates the file and the new text appears (`M10`). That is
why this bug is invisible to the person who has the editor open all day and
permanent for everyone who does not: a build server, a test runner invoked as
`godot --headless --path . --script`, a teammate who only ever pressed play.

The two ways to arrive here are both ordinary:

- the `.translation` files are tracked, someone edited the CSV, and the commit
  that carried the CSV did not carry the regenerated binaries;
- the `.translation` files are tracked, two branches touched the CSV, and the
  binary conflict was resolved by keeping one side while the CSV kept the other.

## 4. Your teammate's engine is not your engine

Import the same two-language table with four engine versions and you get four
different files (`M11`) — different bytes, same table, same uid. Hand each of
those files to each of the other engines and the compatibility is one-directional:

| generated by | 4.2 reads it | 4.3 reads it | 4.4 reads it | 4.7 reads it |
|---|---|---|---|---|
| 4.2 | — | yes | yes | yes |
| 4.3 | **no** | — | yes | yes |
| 4.4 | **no** | yes | — | yes |
| 4.7 | **no** | yes | yes | — |

A newer engine reads an older engine's file (`M13`). An older engine refuses a
newer one's and falls back to the key (`M12`):

```
ERROR: File 'res://strings.en.translation' can't be loaded, as it uses a format
       version (6) or engine version (4.4) which are not supported by your
       engine version (4.2).
```

Nine of the twelve cross-version loads in that table succeed; the three refusals
are all 4.2 reading something newer. Pinning the uid does not help — the same
uid still produces four different files across the four versions (`M17`).

So "it works on my machine" has a literal reading here. If you are on 4.4 and
your teammate is still on 4.2, the generated file you commit is one your
teammate's engine will not open, and the failure surfaces as untranslated keys.

## 5. What the diff looks like, and why 4.2 and 4.3 are worse

If you track the `.translation` files, it matters whether importing the same CSV
twice produces the same bytes. It depends on the version, and this is the
divergence worth knowing:

| | two fresh projects, same table | three reimports of one project |
|---|---|---|
| 4.2 | different uid, different bytes | **three different files** |
| 4.3 | different uid, different bytes | **three different files** |
| 4.4 | different uid, different bytes | one file, three times |
| 4.7 | **same uid, identical bytes** | one file, three times |

On 4.4 and 4.7 the import is reproducible: same input and same uid in, same
bytes out, every time (`M16`). Two projects still differ on 4.4 because each
mints its own uid, and the generated files then differ by exactly the eight
bytes that carry it (`M15`). On 4.7 even that is gone — two independent projects
importing the same table at the same path got the same uid and byte-identical
files (`M15`).

On 4.2 and 4.3 it is not reproducible. Three reimports of one project, with the
uid unchanged in `strings.csv.import` the whole time, wrote three different
files (`M16`). Thirteen bytes move, and the uid is not among them — it is
identical in all three.

The practical consequence: on 4.2 and 4.3, if the `.translation` files are
tracked, *opening the editor* is enough to produce a binary diff. Every
contributor generates one on every branch, and every one of them is a conflict
that git cannot merge and that a human cannot read.

## 6. So what do you actually do

There is no arrangement where nothing is generated. Pick which problem you want:

**Track the `.translation` files.** The clone runs with no editor pass (`M5`),
which is what a build server and a test runner need. The cost is the binary
churn of section 5 and the version trap of section 4. Viable if everyone is
pinned to one engine version, and much more comfortable from 4.4 on, where the
bytes are stable.

**Do not track them, and make the editor pass mandatory.** Add `*.translation`
next to `.godot/` in `.gitignore`, keep `strings.csv.import` tracked so the uid
stays put, and accept that a fresh clone shows keys until someone opens the
editor. Then make sure the build server does it: an import pass is
`godot --headless --path . --editor --quit-after 300`, and it exits 0 whether or
not it imported anything, so check that the `.translation` files exist
afterwards rather than trusting the exit code.

Either way, two checks are worth wiring into CI, because both failures are
silent:

1. after a fresh clone and whatever import step you chose, assert that
   `tr()` of a known key does **not** return the key;
2. assert that a string you changed in the CSV today comes back changed — that
   is the only thing that catches section 3.

---

*Part of [LocGuard Lite](https://github.com/leobaray/locguard-lite), a free
Godot localization addon. The measurements on this page were produced by the
script in this directory; run it against your own binary before believing any
of it.*
