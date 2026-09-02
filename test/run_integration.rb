#!/usr/bin/env ruby
# encoding: UTF-8
#
# Executes every generator against the SketchUp simulator in test/sketchup_sim.rb.
#
#   ruby test/run_integration.rb
#
# This runs the real code paths: source scanning, column/wall/opening/floor/roof
# generation, connections, update tracking, model check, numbering, BOM, cut
# list, finalize, and the whole HtmlDialog callback surface.
#
# It CANNOT tell you whether the geometry is watertight, whether it looks right,
# whether undo behaves in the SketchUp UI, or whether the panel renders. Those
# need a real SketchUp 2026 (see CHANGELOG.md).

require 'timeout'
require 'tmpdir'
require_relative 'sketchup_sim'

ROOT = File.expand_path('..', __dir__)
module KTSHung; module PrefabStructureBuilder; end; end
KTSHung::PrefabStructureBuilder.const_set(:ROOT, File.join(ROOT, 'prefab_structure_builder'))

%w[
  core/units core/metadata core/project_store core/transaction
  framing/profile_library framing/member_factory
  project/preset_manager project/column_types
  rules/rule_engine core/tag_manager
  materials/material_library materials/stock_size materials/sheet_layout materials/material_checker
  source/scanner
  structure/column_engine structure/wall_engine structure/opening_engine
  structure/floor_engine structure/roof_engine
  connections/connection_geometry connections/connection_registry connections/connection_engine
  update/source_tracker update/update_manager
  validation/model_checker
  output/bom output/cut_list output/csv_exporter output/numbering output/report
  production/production_checker production/finalizer
  ui/dialog
].each { |rel| require File.join(ROOT, 'prefab_structure_builder', rel) }

P = KTSHung::PrefabStructureBuilder

$passed = 0
$failed = []
$section = ''

def section(name)
  $section = name
  puts name
end

def check(name)
  ok = yield
  if ok
    $passed += 1
    puts "  ok    #{name}"
  else
    $failed << "#{$section} / #{name}"
    puts "  FAIL  #{name}"
  end
rescue => e
  $failed << "#{$section} / #{name}"
  puts "  ERROR #{name}"
  puts "        #{e.class}: #{e.message}"
  e.backtrace.first(4).each { |l| puts "        #{l.sub(ROOT + '/', '')}" }
end

def mm(v); P::Core::Units.mm(v); end

# Builds a placeholder group as a solid box, the way a user would draw one.
def placeholder(name, x0, y0, z0, dx, dy, dz, tag = nil)
  model = Sketchup.active_model
  g = model.entities.add_group
  g.name = name
  face = g.entities.add_face([[x0, y0, z0], [x0 + dx, y0, z0], [x0 + dx, y0 + dy, z0], [x0, y0 + dy, z0]])
  face.pushpull(dz)
  g.layer = model.layers.add(tag) if tag
  g
end

def reset_model!
  Sketchup.active_model.reset!
  UI.reset!
end

def gen_roots(type = nil)
  Sketchup.active_model.entities.grep(Sketchup::Group).select do |g|
    next false unless P::Core::Metadata.get(g, 'generated', false)
    type.nil? || P::Core::Metadata.get(g, 'type', '') == type
  end
end

def no_open_operation?
  !Sketchup.active_model.operation_open?
end

# ---------------------------------------------------------------- scanning
section 'Source scanning'
reset_model!
col1 = placeholder('COLUMN 1',   0,      0,      0, mm(200),  mm(200),  mm(3000))
col2 = placeholder('COLUMN 1',   mm(5000), 0,    0, mm(200),  mm(200),  mm(3000))
col3 = placeholder('COLUMN 2',   0,      mm(4000), 0, mm(200), mm(200), mm(3000))
wall1 = placeholder('WALL 1',    0,      0,      0, mm(5000), mm(150),  mm(3000))
floor1 = placeholder('FLOOR 1',  0,      0,      0, mm(5000), mm(4000), mm(200))
roof1 = placeholder('ROOF 1',    0,      0,      mm(3000), mm(5000), mm(4000), mm(200))
door1 = placeholder('DOOR 1',    mm(1000), 0,    0, mm(900),  mm(150),  mm(2200))
win1  = placeholder('WINDOW 1',  mm(3000), 0,    mm(900), mm(1200), mm(150), mm(1400))
tagged = placeholder('Group#99', mm(8000), 0,    0, mm(200), mm(200), mm(3000), 'STRUCT_COLUMN')

rows = P::Source::Scanner.scan
check('finds all placeholder types') do
  rows.map { |r| r[:type] }.sort == %w[column column column door floor roof wall window]
end
check('groups COLUMN 1 x2 into one row of quantity 2') do
  rows.find { |r| r[:name] == 'COLUMN 1' }[:quantity] == 2
end
check('classifies an unnamed group by its Tag') do
  P::Source::Scanner.source_type(tagged) == 'column'
end
check('scan is stable when run twice') { P::Source::Scanner.scan.length == rows.length }

# ---------------------------------------------------------------- tags
section 'Tags'
check('setup! creates every tag in one operation') do
  P::Core::TagManager.setup!
  Sketchup.active_model.layers.length >= 23 && no_open_operation?
end
check('ensure_tags! does not open an operation') do
  Sketchup.active_model.start_operation('outer', true)
  P::Core::TagManager.ensure_tags!(Sketchup.active_model)
  ok = Sketchup.active_model.operation_open?
  Sketchup.active_model.commit_operation
  ok
end

# ---------------------------------------------------------------- columns
section 'Column generation'
Sketchup.active_model.selection.clear
Sketchup.active_model.selection.add(col1, col2, col3)
made = P::Structure::ColumnEngine.generate_from_selected('')
check('generates one column per selected placeholder') { made == 3 }
check('operation is closed afterwards') { no_open_operation? }
check('columns are stamped as type=column') { gen_roots('column').length == 3 }
check('column height matches the level delta (3000 mm)') do
  g = gen_roots('column').first
  (P::Core::Units.to_mm(g.bounds.depth) - 3000).abs < 1.0
end
check('column sits on its placeholder centre') do
  g = gen_roots('column').find { |x| P::Core::Metadata.get(x, 'source_id') == col1.entityID }
  (g.bounds.center.x - col1.bounds.center.x).abs < mm(1)
end
check('column section is 100x100') do
  g = gen_roots('column').first
  (P::Core::Units.to_mm(g.bounds.width) - 100).abs < 1.0
end
check('column carries a mark-able profile and tag') do
  g = gen_roots('column').first
  P::Core::Metadata.get(g, 'profile') == '100x100' && g.layer.name == 'STEEL_100x100'
end
check('generated columns are NOT rescanned as sources') do
  # 2x COLUMN 1 + 1x COLUMN 2 + 1 Tag-classified group = 4 sources, never more.
  P::Source::Scanner.scan.select { |r| r[:type] == 'column' }.sum { |r| r[:quantity] } == 4
end

section 'Column types'
check('a fixed-height type is honoured') do
  P::Project::ColumnTypes.save_all([
    P::Project::ColumnTypes.default_type.merge('name' => 'SHORT', 'height_mode' => 'fixed', 'height_mm' => 1500)
  ])
  Sketchup.active_model.selection.clear
  Sketchup.active_model.selection.add(col1)
  gen_roots('column').each(&:erase!)
  P::Structure::ColumnEngine.generate_from_selected('SHORT')
  (P::Core::Units.to_mm(gen_roots('column').first.bounds.depth) - 1500).abs < 1.0
end
check('an I-profile column keeps its 200 mm depth upright') do
  P::Project::ColumnTypes.save_all([
    P::Project::ColumnTypes.default_type.merge('name' => 'IBEAM', 'profile' => 'I200',
                                               'height_mode' => 'fixed', 'height_mm' => 3000)
  ])
  gen_roots('column').each(&:erase!)
  Sketchup.active_model.selection.clear
  Sketchup.active_model.selection.add(col1)
  P::Structure::ColumnEngine.generate_from_selected('IBEAM')
  bb = gen_roots('column').first.bounds
  (P::Core::Units.to_mm(bb.height) - 200).abs < 1.0 && (P::Core::Units.to_mm(bb.depth) - 3000).abs < 1.0
end
check('an unknown type name is rejected without generating') do
  gen_roots('column').each(&:erase!)
  Sketchup.active_model.selection.clear
  Sketchup.active_model.selection.add(col1)
  P::Structure::ColumnEngine.generate_from_selected('DOES_NOT_EXIST')
  gen_roots('column').empty? && no_open_operation?
end

# ---------------------------------------------------------------- walls
section 'Wall generation'
gen_roots.each { |g| g.erase! if g.valid? }
Sketchup.active_model.selection.clear
Sketchup.active_model.selection.add(wall1)
check('AZ100 wall generates') { P::Structure::WallEngine.generate_from_selected('AZ100', 500) && no_open_operation? }
wall_root = gen_roots('wall').first
check('wall root exists and is tagged') { wall_root && wall_root.layer.name == 'STRUCT_WALL' }
check('studs at <=500 mm over 5000 mm gives 11 studs') do
  wall_root.entities.grep(Sketchup::Group).count { |g| P::Core::Metadata.get(g, 'role') == 'wall_stud' } == 11
end
check('panels at 400 mm over 5000 mm gives 13 panels') do
  wall_root.entities.grep(Sketchup::Group).count { |g| P::Core::Metadata.get(g, 'type') == 'panel' } == 13
end
check('NANO wall generates horizontal rails') do
  gen_roots('wall').each(&:erase!)
  P::Structure::WallEngine.generate_from_selected('NANO', 500)
  gen_roots('wall').first.entities.grep(Sketchup::Group).count { |g| P::Core::Metadata.get(g, 'role') == 'wall_rail' } > 0
end
check('PANEL100 generates panels but no frame') do
  gen_roots('wall').each(&:erase!)
  P::Structure::WallEngine.generate_from_selected('PANEL100', 500)
  r = gen_roots('wall').first
  members = r.entities.grep(Sketchup::Group).count { |g| P::Core::Metadata.get(g, 'type') == 'member' }
  panels = r.entities.grep(Sketchup::Group).count { |g| P::Core::Metadata.get(g, 'type') == 'panel' }
  members.zero? && panels > 0
end

# ---------------------------------------------------------------- openings
section 'Opening generation'
gen_roots.each { |g| g.erase! if g.valid? }
Sketchup.active_model.selection.clear
Sketchup.active_model.selection.add(wall1)
P::Structure::WallEngine.generate_from_selected('AZ100', 500)
check('generate_all builds door and window frames') do
  P::Structure::OpeningEngine.generate_all
  gen_roots('door').length == 1 && gen_roots('window').length == 1 && no_open_operation?
end
check('door frame has 2 jambs and a header, no sill') do
  d = gen_roots('door').first
  roles = d.entities.grep(Sketchup::Group).map { |g| P::Core::Metadata.get(g, 'role') }
  roles.count('opening_jamb') == 2 && roles.count('opening_header') == 1 && roles.count('opening_sill').zero?
end
check('window frame also has a sill') do
  w = gen_roots('window').first
  w.entities.grep(Sketchup::Group).map { |g| P::Core::Metadata.get(g, 'role') }.count('opening_sill') == 1
end
check('an I-profile frame no longer collapses to 40 mm') do
  along, depth = P::Structure::OpeningEngine.frame_section('I200')
  (P::Core::Units.to_mm(along) - 100).abs < 0.1 && (P::Core::Units.to_mm(depth) - 200).abs < 0.1
end
check('zero clear width is refused, not drawn') do
  P::Structure::OpeningEngine.generate_one(Sketchup.active_model, door1, 'door', 'DOOR 9',
                                           'width' => 0, 'height' => 2200, 'sill' => 0, 'frame' => '40x80') == false
end

# ---------------------------------------------------------------- floors
section 'Floor generation'
gen_roots.each { |g| g.erase! if g.valid? }
Sketchup.active_model.selection.clear
Sketchup.active_model.selection.add(floor1)
check('Cemboard ground floor generates (this used to raise on Array#<)') do
  P::Structure::FloorEngine.generate_from_selected('GROUND_STEEL_CEMBOARD', '100x100', '40x80', 500, 'auto')
  gen_roots('floor').length == 1 && no_open_operation?
end
floor_root = gen_roots('floor').first
check('perimeter has 4 primary beams') do
  floor_root.entities.grep(Sketchup::Group).count { |g| P::Core::Metadata.get(g, 'role') == 'primary_beam' } == 4
end
check('secondary beams are distributed') do
  floor_root.entities.grep(Sketchup::Group).count { |g| P::Core::Metadata.get(g, 'role') == 'secondary_beam' } > 0
end
check('cemboard sheets are split and recorded') do
  sheets = floor_root.entities.grep(Sketchup::Group).select { |g| P::Core::Metadata.get(g, 'type') == 'sheet' }
  sheets.length > 1 && sheets.all? { |s| P::Core::Metadata.get(s, 'stock_width').to_f > 0 }
end
check('no sheet exceeds its stock size') do
  floor_root.entities.grep(Sketchup::Group)
            .select { |g| P::Core::Metadata.get(g, 'type') == 'sheet' }
            .all? do |s|
    P::Materials::StockSize.violation?(
      P::Core::Metadata.get(s, 'actual_width').to_f, P::Core::Metadata.get(s, 'actual_length').to_f,
      P::Core::Metadata.get(s, 'stock_width').to_f, P::Core::Metadata.get(s, 'stock_length').to_f, true
    ) == false
  end
end
check('I-beams running along X stand upright (200 mm tall, 100 mm wide)') do
  gen_roots.each { |g| g.erase! if g.valid? }
  P::Structure::FloorEngine.generate_from_selected('UPPER_I_CEMBOARD', 'I200', 'I200', 1000, 'y')
  beam = gen_roots('floor').first.entities.grep(Sketchup::Group)
                .find { |g| P::Core::Metadata.get(g, 'role') == 'primary_beam' && g.name == 'PRIMARY_X1' }
  bb = beam.bounds
  (P::Core::Units.to_mm(bb.depth) - 200).abs < 1.0 && (P::Core::Units.to_mm(bb.height) - 100).abs < 1.0
end
check('I-beams running along Y stand upright too') do
  beam = gen_roots('floor').first.entities.grep(Sketchup::Group)
                .find { |g| g.name == 'PRIMARY_Y1' }
  bb = beam.bounds
  (P::Core::Units.to_mm(bb.depth) - 200).abs < 1.0 && (P::Core::Units.to_mm(bb.width) - 100).abs < 1.0
end
check('balcony WPC floor generates') do
  gen_roots.each { |g| g.erase! if g.valid? }
  P::Structure::FloorEngine.generate_from_selected('BALCONY_WPC', '100x100', '40x80', 500, 'auto')
  gen_roots('floor').length == 1
end
check('deck floor generates') do
  gen_roots.each { |g| g.erase! if g.valid? }
  P::Structure::FloorEngine.generate_from_selected('UPPER_DECK', 'I200', 'I150', 1000, 'auto')
  gen_roots('floor').length == 1
end

# ---------------------------------------------------------------- roofs
section 'Roof generation'
gen_roots.each { |g| g.erase! if g.valid? }
Sketchup.active_model.selection.clear
Sketchup.active_model.selection.add(roof1)
check('mono roof generates') do
  P::Structure::RoofEngine.generate_from_selected('MONO', 1200, 300, 1200, 50, 'x+', 600, 600, 600, 600, 1000, 'CORRUGATED', true)
  gen_roots('roof').length == 1 && no_open_operation?
end
roof_root = gen_roots('roof').first
check('mono roof has a perimeter, secondaries and a cover') do
  roles = roof_root.entities.grep(Sketchup::Group).map { |g| P::Core::Metadata.get(g, 'role') }
  roles.count('perimeter_beam') == 4 && roles.count('secondary_roof_frame') > 0 && roles.any? { |r| r.to_s.include?('cover') }
end
check('overhang extends the footprint by 600 mm each side') do
  (P::Core::Units.to_mm(roof_root.bounds.width) - (5000 + 1200)).abs < 60
end
check('gable roof generates with a ridge') do
  gen_roots('roof').each(&:erase!)
  P::Structure::RoofEngine.generate_from_selected('GABLE', 1200, 300, 1200, 50, 'x+', 600, 600, 600, 600, 1000, 'TILE', true)
  gen_roots('roof').first.entities.grep(Sketchup::Group).any? { |g| P::Core::Metadata.get(g, 'role') == 'ridge' }
end
check('gable roof splits the cover into two planes') do
  names = gen_roots('roof').first.entities.grep(Sketchup::Group).map(&:name)
  names.include?('ROOF_COVER_A') && names.include?('ROOF_COVER_B')
end
check('HIP_FACES on a group with faces generates without raising') do
  gen_roots('roof').each(&:erase!)
  P::Structure::RoofEngine.generate_from_selected('HIP_FACES', 1200, 300, 1200, 50, 'x+', 600, 600, 600, 600, 1000, 'CORRUGATED', false)
  gen_roots('roof').length == 1 && no_open_operation?
end
check('every roof slope direction works') do
  %w[x+ x- y+ y-].all? do |dir|
    gen_roots('roof').each(&:erase!)
    P::Structure::RoofEngine.generate_from_selected('MONO', 1200, 300, 1200, 50, dir, 600, 600, 600, 600, 1000, 'CORRUGATED', true)
    gen_roots('roof').length == 1
  end
end

# ---------------------------------------------------------------- connections
section 'Connections'
reset_model!
P::Core::TagManager.setup!
c1 = placeholder('COLUMN 1', 0, 0, 0, mm(200), mm(200), mm(3000))
f1 = placeholder('FLOOR 1',  0, 0, mm(3000), mm(5000), mm(4000), mm(200))
Sketchup.active_model.selection.clear
Sketchup.active_model.selection.add(c1)
P::Structure::ColumnEngine.generate_from_selected('100x100')
Sketchup.active_model.selection.clear
Sketchup.active_model.selection.add(f1)
P::Structure::FloorEngine.generate_from_selected('UPPER_I_CEMBOARD', 'I200', 'I150', 1000, 'auto')
check('collect_structural_records finds members without infinite recursion') do
  P::Connections::ConnectionEngine.collect_structural_records.length > 4
end
check('auto_generate runs in concept mode') do
  P::Connections::ConnectionEngine.auto_generate('concept')
  no_open_operation?
end
check('auto_generate runs in fabrication mode (bolt geometry)') do
  P::Connections::ConnectionEngine.auto_generate('fabrication')
  no_open_operation?
end
check('connection parts are not re-collected as structural members') do
  before = P::Connections::ConnectionEngine.collect_structural_records.length
  P::Connections::ConnectionEngine.auto_generate('concept')
  P::Connections::ConnectionEngine.collect_structural_records.length == before
end
check('an unknown rule id is refused') do
  P::Connections::ConnectionEngine.connect_selected('NOT_A_RULE', 'concept') == nil ||
    Sketchup.active_model.operation_open? == false
end
check('every registry rule builds geometry') do
  model = Sketchup.active_model
  P::Connections::ConnectionRegistry::RULES.keys.all? do |rule|
    model.start_operation('t', true)
    g = model.entities.add_group
    a = { id: 1, profile: 'I200', role: 'primary_beam', system: 'floor', bbox: c1.bounds }
    b = { id: 2, profile: '100x100', role: 'primary_column', system: 'structure', bbox: c1.bounds }
    P::Connections::ConnectionEngine.create_connection(g.entities, rule, c1.bounds.center, a, b, 'fabrication')
    model.commit_operation
    true
  end
end

# ---------------------------------------------------------------- update
section 'Update tracking'
check('baseline marks every source clean') do
  P::Update::UpdateManager.baseline!
  P::Update::SourceTracker.report.none? { |r| r[:changed] } && no_open_operation?
end
check('moving a source marks it changed') do
  c1.transform!(Geom::Transformation.translation([mm(500), 0, 0]))
  P::Update::SourceTracker.changed?(c1)
end
check('update_changed rebuilds only the changed source') do
  before = gen_roots('floor').first.entityID
  P::Update::UpdateManager.update_changed
  no_open_operation? && gen_roots('floor').first.entityID == before
end
check('the rebuilt column follows the moved placeholder') do
  g = gen_roots('column').first
  (g.bounds.center.x - c1.bounds.center.x).abs < mm(1)
end
check('no duplicate generated roots after update') do
  ids = gen_roots.map { |g| [P::Core::Metadata.get(g, 'source_id'), P::Core::Metadata.get(g, 'system')] }
  ids.length == ids.uniq.length
end

# ---------------------------------------------------------------- validation
section 'Model check'
check('model checker runs and returns issues with ids') do
  issues = P::Validation::ModelChecker.report
  issues.is_a?(Array) && issues.all? { |i| i[:issue_id] =~ /^CHK-\d{3}$/ }
end
check('no false STOCK_SIZE errors on un-stocked surfaces') do
  P::Validation::ModelChecker.report.none? { |i| i[:code] == 'STOCK_SIZE' }
end
check('production QA runs and reuses precomputed checks') do
  base = P::Validation::ModelChecker.report
  qa = P::Production::ProductionChecker.report(Sketchup.active_model, base)
  qa.length >= base.length && qa.all? { |i| i[:issue_id] =~ /^QA-\d{3}$/ }
end
check('reusing base issues does not mutate them') do
  base = P::Validation::ModelChecker.report
  first_id = base.first && base.first[:issue_id]
  P::Production::ProductionChecker.report(Sketchup.active_model, base)
  base.first.nil? || base.first[:issue_id] == first_id
end

# ---------------------------------------------------------------- output
section 'BOM, cut list, numbering'
check('BOM rows are produced') { P::Output::BOM.rows.any? }
check('containers are excluded from the BOM') do
  P::Output::BOM.generated_entities.none? { |e| %w[wall floor roof system connection].include?(P::Core::Metadata.get(e, 'type', '')) }
end
check('a column is counted exactly once') do
  P::Output::BOM.generated_entities.count { |e| P::Core::Metadata.get(e, 'type') == 'column' } == gen_roots('column').length
end
check('steel length is positive') { P::Output::BOM.summary[:steel_length_m] > 0 }
check('cut list groups by profile and length') { P::Output::CutList.grouped.any? }
check('stock plan packs bars') { P::Output::CutList.stock_plan.all? { |r| r[:bars] >= 1 } }
check('with_cache returns the same set and clears afterwards') do
  a = nil; b = nil
  P::Output::BOM.with_cache { a = P::Output::BOM.generated_entities.length; b = P::Output::BOM.generated_entities.length }
  a == b && P::Output::BOM.generated_entities.length == a
end
check('numbering assigns unique marks') do
  P::Core::Transaction.run('t') { P::Output::Numbering.apply }
  marks = P::Output::BOM.generated_entities.map { |e| P::Core::Metadata.get(e, 'mark') }.compact.reject(&:empty?)
  marks.any? && marks.length == marks.uniq.length
end
check('marks carry prefix, group, sequence and revision') do
  P::Output::BOM.generated_entities.map { |e| P::Core::Metadata.get(e, 'mark') }.compact
                .reject(&:empty?).all? { |m| m =~ /^PFB-[A-Z-]+-\d{3}-R[A-Z0-9]+$/ }
end
check('no duplicate marks reported') { P::Output::Numbering.duplicate_marks.empty? }
check('re-running numbering preserves existing marks') do
  before = P::Output::BOM.generated_entities.map { |e| P::Core::Metadata.get(e, 'mark') }
  P::Core::Transaction.run('t') { P::Output::Numbering.apply }
  P::Output::BOM.generated_entities.map { |e| P::Core::Metadata.get(e, 'mark') } == before
end
check('report by system and marked items build') do
  P::Output::Report.by_system.any? && P::Output::Report.marked_items.any?
end
check('CSV writes and round-trips through the escaper') do
  path = File.join(Dir.tmpdir, 'psb_test.csv')
  P::Output::CSVExporter.write(path, [%w[a b], ['x,1', 'say "hi"']])
  body = File.read(path, encoding: 'UTF-8')
  File.delete(path)
  body.include?('"x,1"') && body.include?('"say ""hi"""') && body.include?("\r\n")
end

# ---------------------------------------------------------------- finalize
section 'Finalize'
check('finalize runs without nesting operations') do
  result = P::Production::Finalizer.run
  result && result[:numbering] && no_open_operation?
end
check('finalize records version and revision') do
  P::Core::ProjectStore.get('finalized_version') == P::Core::Metadata::VERSION &&
    !P::Core::ProjectStore.get('finalized_at').nil?
end
check('project status reports counts') do
  s = P::Output::Report.project_status(0)
  s[:generated_count] > 0 && s[:source_count] > 0 && s[:qa_issues] == 0
end

# ---------------------------------------------------------------- dialog
section 'HtmlDialog callbacks'
dlg = P::Gui::Dialog.build
P::Gui::Dialog.instance_variable_set(:@dialog, dlg)
dlg.show
check('every callback the page calls is registered') do
  page = File.read(File.join(ROOT, 'prefab_structure_builder/ui/web/app.js'), encoding: 'UTF-8')
  used = page.scan(/call\('([a-zA-Z]+)'/).flatten.uniq
  missing = used - dlg.callbacks.keys
  puts "        missing: #{missing.inspect}" unless missing.empty?
  missing.empty?
end
check('every window.render* the Ruby side calls exists in the page') do
  page = File.read(File.join(ROOT, 'prefab_structure_builder/ui/web/app.js'), encoding: 'UTF-8')
  ruby = File.read(File.join(ROOT, 'prefab_structure_builder/ui/dialog.rb'), encoding: 'UTF-8')
  called = ruby.scan(/call_js\('window\.(\w+)'/).flatten.uniq
  missing = called.reject { |f| page.include?("window.#{f} =") || page.include?("window.#{f}=") }
  puts "        missing: #{missing.inspect}" unless missing.empty?
  missing.empty?
end
check('every panel id in the rail has a matching section') do
  html = File.read(File.join(ROOT, 'prefab_structure_builder/ui/web/index.html'), encoding: 'UTF-8')
  panels = html.scan(/data-panel="(\w+)"/).flatten
  missing = panels.reject { |p| html.include?(%(id="panel-#{p}")) }
  puts "        missing: #{missing.inspect}" unless missing.empty?
  missing.empty? && panels.length == 14
end
check('every button id used by app.js exists in index.html') do
  html = File.read(File.join(ROOT, 'prefab_structure_builder/ui/web/index.html'), encoding: 'UTF-8')
  js = File.read(File.join(ROOT, 'prefab_structure_builder/ui/web/app.js'), encoding: 'UTF-8')
  ids = js.scan(/on\('(\w+)'/).flatten.uniq
  missing = ids.reject { |i| html.include?(%(id="#{i}")) }
  puts "        missing: #{missing.inspect}" unless missing.empty?
  missing.empty?
end
%w[ready scan getTags getColumnTypes getOpenings getMaterials getConnections
   getUpdateStatus checkModel getBOM getProject getRules productionCheck].each do |name|
  check("callback '#{name}' runs and pushes JS") do
    before = dlg.scripts.length
    dlg.invoke(name)
    dlg.scripts.length > before && no_open_operation?
  end
end
check('zoomEntity selects and zooms') do
  dlg.invoke('zoomEntity', c1.entityID)
  Sketchup.active_model.active_view.zoom_calls.any?
end
check('zoomEntity on a missing id is harmless') { dlg.invoke('zoomEntity', 999_999) == false }
check('saveColumnTypes accepts JSON from the page') do
  dlg.invoke('saveColumnTypes', JSON.generate([{ 'name' => 'C1', 'profile' => 'I150' }]))
  P::Project::ColumnTypes['C1']['profile'] == 'I150'
end
check('saveLevels accepts JSON from the page') do
  dlg.invoke('saveLevels', JSON.generate([{ 'name' => 'GF', 'elevation_mm' => 0 },
                                          { 'name' => 'L1', 'elevation_mm' => 3600 }]))
  P::Project::ColumnTypes.level_elevation('L1') == 3600.0
end
check('saveProjectPreset accepts JSON from the page') do
  dlg.invoke('saveProjectPreset', JSON.generate('project_name' => 'Villa', 'steel_stock_mm' => 12_000))
  P::Project::PresetManager.current[:project_name] == 'Villa' &&
    P::Project::PresetManager.current[:steel_stock_mm] == 12_000
end
check('previewStock returns a plan for a rotatable preset') do
  before = dlg.scripts.length
  dlg.invoke('previewStock', 'CEMBOARD_1220_2440_16', 5200, 7600)
  dlg.scripts.length > before && dlg.scripts.last.include?('renderStockPreview')
end
check('a malformed payload is caught, not propagated') do
  UI.reset!
  dlg.invoke('saveColumnTypes', 'not json at all')
  UI.messages.any? && no_open_operation?
end
check('scripts pushed to the page are valid JSON payloads') do
  dlg.scripts.select { |s| s.start_with?('window.render') }.all? do |s|
    body = s[/\((.*)\);\z/m, 1]
    begin
      JSON.parse("[#{body}]")
      true
    rescue JSON::ParserError
      false
    end
  end
end

# ---------------------------------------------------------------- robustness
section 'Robustness'
check('generators on an empty selection warn instead of raising') do
  reset_model!
  P::Structure::ColumnEngine.generate_from_selected('100x100')
  P::Structure::WallEngine.generate_from_selected('AZ100', 500)
  P::Structure::FloorEngine.generate_from_selected('GROUND_STEEL_CEMBOARD', '', '', 0, 'auto')
  P::Structure::RoofEngine.generate_from_selected('MONO', 1200, 300, 1200, 50, 'x+', 0, 0, 0, 0, 1000, 'CORRUGATED', false)
  UI.messages.length == 4 && no_open_operation?
end
check('a flat, zero-height placeholder is skipped, not drawn') do
  reset_model!
  P::Core::TagManager.setup!
  flat = placeholder('WALL 1', 0, 0, 0, mm(3000), mm(100), mm(3000))
  flat.entities.grep(Sketchup::Face).first.instance_variable_set(:@extruded, [])
  Sketchup.active_model.selection.clear
  Sketchup.active_model.selection.add(flat)
  P::Structure::WallEngine.generate_from_selected('AZ100', 500)
  no_open_operation?
end
check('a self-referencing component does not hang the scanner') do
  reset_model!
  model = Sketchup.active_model
  defn = Sketchup::ComponentDefinition.new('COLUMN 1')
  inst = model.entities.add_instance(defn, Geom::Transformation.new)
  inst.name = 'COLUMN 1'
  inner = defn.entities.add_instance(defn, Geom::Transformation.new)
  inner.name = 'COLUMN 1'
  Timeout.timeout(10) { P::Source::Scanner.scan.is_a?(Array) }
end
check('a self-referencing component does not hang the BOM or checker') do
  Timeout.timeout(10) do
    P::Output::BOM.generated_entities.is_a?(Array) &&
      P::Validation::ModelChecker.report.is_a?(Array) &&
      P::Connections::ConnectionEngine.collect_structural_records.is_a?(Array)
  end
end
check('no operation was left open by anything above') { no_open_operation? }

puts
if $failed.empty?
  puts "All #{$passed} integration checks passed."
  exit 0
else
  puts "#{$passed} passed, #{$failed.length} FAILED:"
  $failed.each { |f| puts "  - #{f}" }
  exit 1
end
