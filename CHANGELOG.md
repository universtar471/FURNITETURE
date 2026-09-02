# Changelog

## 1.1.0 — SketchUp 2026 fix & completion pass

Reviewed against the v1.0.0 RBZ. Every item below was a defect in that build.

### Crashes

- **`UI` module shadowed SketchUp's `::UI`.** The extension defined
  `KTSHung::PrefabStructureBuilder::UI`, so every unqualified `UI` lookup that
  started inside the namespace resolved to the extension's own module.
  `UI.start_timer` in the dialog (menu *Scan Model*, toolbar Scan, both Update
  commands) and `UI.messagebox` in `TagManager` raised
  `NoMethodError: undefined method 'start_timer' for module …::UI`.
  The module is now `Gui`, and every SketchUp UI call is written `::UI`.
- **`StockSize.score` returned an Array** and compared two plans with `<`.
  `Array` does not implement `<`, so splitting any rotatable sheet raised
  `NoMethodError`. Cemboard presets are rotatable, so *Generate Floor System*
  crashed on the default ground floor. Score is now a single numeric.
- **`OpeningEngine` called `Array#to_f`** — `depth=[p[:h]||80,80].to_f.mm` —
  which does not exist, so *Generate All Frames* always raised. Frame section
  sizing is now `frame_section`, which also picks up `:b` for I-profiles instead
  of silently falling back to 40 mm.
- **Nested `start_operation`.** `Finalizer` opened a transaction and then called
  `TagManager.setup!`, which opened and committed its own — closing the outer
  operation and splitting Finalize across several undo steps. Tag creation is
  now `ensure_tags!` (transaction-free) with `setup!` kept as the standalone
  menu entry point.
- **Unguarded `pushpull` on a possibly-nil face.** `add_face` returns nil for a
  degenerate outline; every generator then raised on `nil.pushpull`. All face
  creation is now checked and the partial group erased.
- **Unbounded component recursion.** The scanner, connection engine, model
  checker, production checker, material checker and BOM all walked component
  definitions with no cycle guard; a definition containing an instance of itself
  recursed until the stack blew. All walkers are now depth-limited and
  definition-guarded.
- **`Float#to_mm`.** SketchUp defines `Length#to_mm` but not `Numeric#to_mm`, and
  `Length` arithmetic degrades to `Float` (`Length * Float`, `Length - Float`).
  Several roof and floor spans reached `.to_mm` as plain Floats. All millimetre
  conversion now goes through `Core::Units`.

### Geometry

- **I-sections ran flat along X.** `add_profile_member` rotated the section 90°
  about Y for the `:x` axis, which leaves the section height along global Y — an
  I-beam lying on its side. Orientation now uses explicit axis frames so the
  section height is vertical for both `:x` and `:y` members.
- **Extrusion direction** was not checked against the face normal, so a face
  SketchUp returned reversed extruded backwards from its insertion point.
- **Bolts shared one entities collection** and merged into each other. Each bolt
  is now its own group, and its extrusion follows the circle normal.

### Logic

- **The scanner re-detected its own output as source placeholders.** Generated
  systems carry Tags such as `STRUCT_WALL` and `STRUCT_ROOF`, which the Tag
  fallback matched on, so every generated wall/floor/roof was counted as a new
  placeholder — inflating the scan, source tracking and QA. Anything carrying
  the `generated` flag (or a `GEN_`/`PREFAB_CONNECTIONS` name) is now skipped.
- **Stock checker flagged every un-stocked surface.** Deck, WPC and wall skins
  have no recorded stock size; comparing against 0×0 marked them all `ERROR`.
- **Custom material presets were unreadable.** They round-trip through JSON with
  String keys while built-ins use Symbols, so `preset[:allow_rotate]` was always
  nil for a user preset. Keys are normalised in `MaterialLibrary.all`.
- **`Apply Numbering` and `Save Baseline` mutated the model outside any
  operation**, producing hundreds of ungrouped undo entries. Both are wrapped now.
- **Unknown connection rule** dereferenced a nil config; **unknown column
  profile** passed a nil profile hash into the column generator. Both guarded.
- **Columns double-counted in the BOM** would have followed from the new member
  factory path, so column geometry is drawn directly into its group.
- **Duplicate fabrication marks.** The numbering counter was keyed on the whole
  `[code, material, system]` group, but only `code` reaches the mark, so an
  AZ100 wall panel and a Cemboard floor sheet both counted from 001 and emitted
  the same `PFB-SHT-001-RA`. Every finalized project then reported
  `DUPLICATE_MARK` errors against itself. Found by the integration suite; the
  counter is now keyed on the code alone.
- **`source_name` assumed a non-nil definition**, which an erased entity does
  not have.
- `require 'csv'` removed — `csv` is a bundled gem in newer Rubies and is not
  guaranteed loadable inside SketchUp. CSV writing (with quoting and a UTF-8 BOM
  for Excel) is now local.

### Performance

- A panel refresh walked the whole model up to eight times and ran the model
  checker three times. `BOM.with_cache` shares one traversal per refresh and the
  check result is computed once and reused by the CHECK, PRODUCTION and PROJECT
  panels. Traversals also skip edges and faces instead of calling
  `get_attribute` on every primitive.

### New

- **Column Type Manager** — named, reusable column types (profile, material,
  height mode, rotation, base/top level, tag, colour, structural role,
  description) plus editable storey levels, stored in the model.
- **Tag panel** — shows the tag/colour system and whether each tag exists.
- **Rebuilt panel UI** — left sidebar navigation, per-panel cards, no inline
  event handlers, all output HTML-escaped.
- Toolbar/menu commands are wrapped so a failure reports to the Ruby Console
  instead of leaving a dead button; the toolbar uses `restore` so it honours the
  user's last visibility choice.
- `tools/build.rb` (RBZ packer), `tools/syntax_check.rb`, and `test/run_tests.rb`
  with a SketchUp API stub — 61 offline checks.

## Verification performed

- `ruby tools/syntax_check.rb` — 40/40 files parse.
- `ruby test/run_tests.rb` — 61/61 unit checks (units, stock splitting, profile
  geometry, source classification, CSV escaping, rule engine, column types).
- `ruby test/run_integration.rb` — **105 end-to-end checks** against
  `test/sketchup_sim.rb`, a SketchUp API simulator with real 4×4 transformation
  maths, transform-following bounding boxes, faces with normals and pushpull,
  entity collections, layers, materials, selection, attribute dictionaries and
  an operation stack that *raises on nesting*. It actually executes: source
  scanning, column/wall/opening/floor/roof generation, connections in both
  detail modes, update tracking, model check, production QA, numbering, BOM,
  cut list, finalize, and all 40 HtmlDialog callbacks.
  Measured there, among others: columns land on their placeholder centre at the
  right height; I-sections stay 200 mm tall and 100 mm wide running along both
  X and Y; a 5000 mm AZ100 wall yields 11 studs and 13 panels; no Cemboard sheet
  exceeds stock; roof overhang extends the footprint by 600 mm per side; no
  generated object is ever rescanned as a source; no operation is left open; a
  self-referencing component does not hang any walker.
- `node --check` on `app.js`; cross-checks that every `sketchup.*` call in the
  page has a Ruby callback, every `window.render*` the Ruby side calls exists in
  the page, every rail panel has a section, and every button id exists.
- RBZ builds and its archive layout is correct.

## NOT verified — please test inside SketchUp 2026

SketchUp has no Linux build, so none of this ran against a real SketchUp. The
simulator executes the code and measures bounding boxes, but it cannot tell you
whether solids are watertight, whether anything looks right on screen, whether
undo behaves in the UI, whether the HtmlDialog actually renders, or whether the
toolbar registers. Those need the real application:

1. Install the RBZ; confirm the toolbar and menu appear and the panel opens.
2. Setup Tags, then check the TAG panel lists all 23 tags with colours.
3. Draw placeholders `COLUMN 1`, `WALL 1`, `FLOOR 1`, `ROOF 1`, `DOOR 1`,
   `WINDOW 1`; press Scan Model and confirm the counts.
4. Generate each system. Confirm one undo step per command, and that Ctrl+Z
   leaves no partial geometry.
5. Confirm I150/I200 floor beams stand upright in **both** X and Y directions.
6. Generate a Cemboard ground floor — this is the path that used to crash.
7. Generate door and window frames — the other path that used to crash.
8. Rescan after generating: the source list must not grow.
9. Auto Connections in both concept and fabrication mode.
10. Move a placeholder, run Update Changed, confirm only that system rebuilds.
11. Apply Numbering, then undo once — all marks should revert together.
12. Finalize Project, then export BOM / cut list / report CSV and open in Excel.
13. Repeat in a model whose units are set to feet/inches.
14. Repeat with placeholders nested inside a parent group.

## 1.0.0

Initial production milestone (see the original release notes).
