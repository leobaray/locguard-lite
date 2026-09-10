# Why a key that IS in your CSV still shows up untranslated

The key is in `strings.csv`. The locale is right. `print(tr("GREET"))` prints the
translated string. The label on screen still says `GREET`.

Every claim below was measured by
[`verify_auto_translate.sh`](verify_auto_translate.sh) on Godot **4.2, 4.3, 4.4
and 4.7** stable, run on 2026-09-09: 23/23 on 4.3 and 4.4, 24/24 on 4.7, and a
smaller 6/6 set on 4.2, which does not have the feature at all. The ids (`T1`,
`T2`, …) are the ids the script prints, so you can re-run any single line on your
own binary. Nothing here needs an imported CSV: the translations are built in
memory with `Translation.add_message()`, the same object the CSV importer
produces.

## `tr()` and the text on screen do not go through the same door

This is the whole thing.

- `tr()` **always** translates. It does not care about auto-translate. A node
  buried under an ancestor with auto-translate switched off still gets the
  translated string back from `tr()` (`T1`).
- The node's own `text` does **not** go through `tr()`. It goes through `atr()`,
  which does obey auto-translate. On the same node, in the same frame, with the
  same key, `atr()` returns the untranslated key (`T4`).

So one node answers two different things depending on which method you ask, and
the one you type into your script is the one that lies to you about what the
player sees. `TranslationServer.translate()` sides with `tr()` and ignores
auto-translate entirely (`T2`), as does `tr()` on a plain `Object`, which has no
tree to inherit from (`T3`).

There is no error. There is no warning. `atr()` on a key that is in no
translation at all returns that key unchanged too (`T19`), so "key on screen"
looks identical whether the row is missing from the CSV or the node was simply
told not to translate.

## What actually switches it off

`Node.auto_translate_mode` has three values, and this build reports them as
`INHERIT = 0`, `ALWAYS = 1`, `DISABLED = 2` (`T6`). A node you create is
`INHERIT`; the tree root is `ALWAYS` (`T5`). That is why things translate by
default: everything inherits its way up to a root that says yes.

Inheritance is transitive. Set one ancestor to `DISABLED` and every node under
it goes dark, at any depth (`T7`). One checkbox on one container takes out a
whole screen.

An explicit `ALWAYS` on a node in the middle brings that node back while its
parent stays dark (`T8`).

## The part that will cost you an afternoon

Changing `auto_translate_mode` reaches the node you changed immediately. It
reaches descendants that have **already resolved** their state only at the next
frame.

The consequence is that the order of two settings inside one frame is visible on
screen:

- Disable the top, then set `ALWAYS` on a node in the middle: in that frame the
  middle node translates and *its own child* does not (`T9`).
- Apply the exact same two settings in the opposite order: in that frame the
  child does translate (`T10`).

The cleanest form of it is two identical sibling subtrees. Build both, read
`atr()` on one child, then disable the ancestor of each. Same code, same frame,
opposite answers: the child that was read once is stale and its never-read twin
is not (`T11`, `T12`). Reading the state is what fixes it in place. One frame
later everything agrees again (`T13`).

In a running game every visible label has already been read, so the stale branch
is the normal one: toggle a container's auto-translate at runtime and its
children keep the old behaviour for a frame.

## The deprecated bool is a trap, not an alias

`auto_translate` is still there and still writable, and it is not a view of the
node's own setting.

- Read it on a node whose own mode is `INHERIT` under a disabled parent and it
  returns `false` — it reports the resolved state, not what this node is set to
  (`T14`).
- Write `false` and the mode becomes `DISABLED` (`T15`).
- Write `true` and the mode becomes `ALWAYS`, **not** back to `INHERIT` (`T16`).

That last one is the trap. Toggling the deprecated bool off and on again does not
restore the node: it permanently opts it out of its parent's setting. From then
on the container's checkbox no longer controls that node, and nothing in the
inspector reads as unusual.

## Windows

`Window.title` stores the raw key and is read through `atr()` like everything
else (`T17`), so a disabled window keeps the key as its visible title (`T18`).
Dialog titles fail exactly the same way, and they are easy to miss because you
rarely see them in the language you develop in.

## How to find it in your project

The mode is written to the scene file only when it is not the default. A
disabled node leaves a literal line and an inheriting node leaves nothing at all
(`T24`):

```
[node name="Disabled" type="Label" parent="."]
auto_translate_mode = 2
text = "GREET"
```

So the whole search is one command:

```
grep -rn "auto_translate_mode = 2" --include="*.tscn" .
```

Anything that turns up is a node, and a whole subtree under it, that will ship
the key no matter how correct your CSV is. Then re-check by hand: `= 1`
(`ALWAYS`) on a node is also worth a look, because it is what a round trip of
the deprecated bool leaves behind.

## Asking a node directly

`can_auto_translate()` exists only from 4.7 on (`T20`), where it answers `false`
for a node under a disabled ancestor (`T21`). On 4.3 and 4.4 there is no such
method: the only way to ask a node whether it will translate is to call `atr()`
on a key you know is translated and compare the result. The script does exactly
that, and says so in a `NOTE` when it runs on those builds.

## Version differences worth knowing

- **4.2** has neither `auto_translate_mode` nor `atr()`; both arrived in 4.3. On
  4.2, `auto_translate` is a plain bool that does not propagate — set it to
  `false` on a parent and the child still reads `true` (`T25`) —
  and no script-reachable method answers "will this node translate?" at all
  (`T26`). `tr_n()` there returns the singular message (`T27`).
- **`atr_n()` under a disabled node** hands back the singular key on 4.3 even
  when the count is 2, and the plural key from 4.4 on (`T22`).
- **`tr_n()` against a plain, non-PO translation** returns the singular *message*
  on 4.2, 4.3 and 4.4, and from 4.7 on returns the plural *key* and logs an
  engine error (`T23`). If you moved a project to 4.7 and plural strings started
  showing keys, this is why. The CSV path never supported plurals in the first
  place — that is measured separately in
  [why a row in `strings.csv` never reaches the player](why-a-row-in-strings-csv-never-reaches-the-player.md).

## What LocGuard Lite does not catch

Honestly: this one. [LocGuard Lite](../README.md) reads `text`, `title`,
`tooltip_text` and friends out of your scenes and cross-checks them against the
CSV. It never reads `auto_translate_mode`, so a node that will ship the key
passes the scan clean — the row *is* in the CSV, which is the only question the
scanner asks. The `grep` above is the check that covers it today.

## Related engine issues

Three open issues touch the same surface, confirmed open on 2026-09-09:

- [#109256](https://github.com/godotengine/godot/issues/109256) — POT generation
  ignores Auto Translate set to Disabled for an instanced Label with a text
  override.
- [#104574](https://github.com/godotengine/godot/issues/104574) — improving the
  editor's auto-translation.
- [#82833](https://github.com/godotengine/godot/issues/82833) — RichTextLabel
  does not translate strings placed in between tags.

Searching the tracker for `auto_translate_mode` in issue titles returns zero
results, which is roughly the point: the behaviour above is not a bug report
anybody filed, it is what the feature does.

## Run it yourself

```
docs/verify_auto_translate.sh /path/to/Godot_v4.7-stable_linux.x86_64
```

It builds a throwaway project in a temp directory and touches nothing of yours.
The engine's exit code is not the gate — Godot exits 0 on a GDScript parse error
— so the script gates on its own summary line instead. If a future build changes
one of these answers, it will tell you which line stopped holding.
