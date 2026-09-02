# Prefab Structure Builder — SketchUp 2026

A SketchUp extension for semantic prefab steel framing: you model rough
placeholder groups (`COLUMN 1`, `WALL 2`, `ROOF 1`, `DOOR 1`…), the plugin reads
them and generates framed columns, walls, floors, roofs, opening frames,
connections, tags, QA reports and a BOM / cut list.

Version **1.1.0** — targets SketchUp 2026, minimum SketchUp 2021.

## Install

```
ruby tools/build.rb
```

produces `build/Prefab_Structure_Builder_v1.1.0.rbz`. Install it with
**SketchUp → Extensions → Extension Manager → Install Extension**.

Commands land under **Extensions → Prefab Structure Builder** and in the
*Prefab Structure Builder* toolbar.

## Workflow

```
Project preset → Scan Model → set parameters → Generate
      → Update Changed → Model Check → Finalize Project → BOM / Cut List / Report
```

1. **PROJECT** — set the code prefix, revision, default profiles, stock length and kerf. Stored in the model; exportable as JSON.
2. **SOURCE** — scan for placeholder Groups/Components. Recognised by name first, then by Tag.
3. **COLUMN** — define reusable column types (profile, material, height mode, rotation, base/top level, role) and storey levels, then generate from the selection.
4. **WALL / OPENING / FLOOR / ROOF** — generate each system from its placeholders.
5. **MATERIAL** — sheet stock presets; oversized areas split into FULL/CUT pieces.
6. **CONNECTION** — auto-classify member intersections into plate/bolt/weld nodes.
7. **TAG** — create/repair the tag and colour system.
8. **UPDATE** — regenerate only the sources whose geometry, name, tag or transform changed.
9. **CHECK / PRODUCTION** — model rule QA, then Finalize (tags, marks, baseline, revision).
10. **BOM** — bill of materials, steel cut list, stock-bar estimate, sheet summary; CSV export.

## Supported profiles

`100x100`, `25x25`, `50x50`, `40x80`, `30x60`, `50x100` (RHS) and `I150`, `I200`
(I-sections). Each owns a Tag and a colour.

## Engineering boundary

The plugin automates semantic modelling, framing layout rules, material
splitting, metadata, connection *representations*, update tracking, checking and
quantity reporting.

It does **not** certify load capacity, connection design, weld size, bolt design,
foundation design, local building-code compliance or fabrication safety. Those
remain the responsibility of the structural engineer and fabricator.

## Development

```
ruby tools/syntax_check.rb    # parse every Ruby file
ruby test/run_tests.rb        # 61 unit checks (pure logic)
ruby test/run_integration.rb  # 105 end-to-end checks against a SketchUp simulator
ruby tools/build.rb           # package the .rbz
```

`test/sketchup_stub.rb` is a minimal API stand-in for the unit tests.
`test/sketchup_sim.rb` is a fuller simulator — real 4×4 transformation maths,
bounding boxes that follow their group's transform, faces with normals and
pushpull, entity collections, layers, materials, selection, attribute
dictionaries, and an operation stack that raises on nesting — so
`run_integration.rb` can actually execute every generator and every dialog
callback.

Neither can tell you whether solids are watertight, whether the model looks
right, whether undo behaves in the UI, or whether the HtmlDialog and toolbar
register. **Those must be verified inside SketchUp** — `CHANGELOG.md` carries
the manual checklist.

## Layout

```
prefab_structure_builder.rb        registration stub
prefab_structure_builder/
  loader.rb                        requires, menu and toolbar
  core/       units, metadata, project store, transaction, tag manager
  framing/    profile library, member factory
  project/    project preset, column types and levels
  rules/      unified rule engine
  source/     semantic source scanner
  structure/  column, wall, opening, floor, roof engines
  materials/  material library, stock size, sheet layout, stock checker
  connections/ registry, geometry, auto/manual engine
  update/     source signature tracking and regeneration
  validation/ model checker
  production/ production QA and finalizer
  output/     BOM, cut list, numbering, report, CSV exporter
  ui/         HtmlDialog (Gui::Dialog) + web/ panel
  icons/      toolbar icons
```
