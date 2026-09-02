#!/usr/bin/env ruby
# encoding: UTF-8
# Offline regression tests for the parts of the extension that do not need a
# running SketchUp: unit conversion, stock splitting, profile geometry,
# member orientation, CSV escaping and source classification.
#
#   ruby test/run_tests.rb
#
# Geometry creation, undo behaviour and dialog wiring are NOT covered here and
# must still be exercised inside SketchUp.

require_relative 'sketchup_stub'

ROOT = File.expand_path('..', __dir__)
%w[
  core/units core/metadata core/project_store core/transaction
  framing/profile_library framing/member_factory
  project/preset_manager project/column_types
  rules/rule_engine core/tag_manager
  materials/material_library materials/stock_size
  source/scanner
  output/csv_exporter
].each { |rel| require File.join(ROOT, 'prefab_structure_builder', rel) }

PSB = KTSHung::PrefabStructureBuilder

$passed = 0
$failed = []

def check(name)
  ok = yield
  if ok
    $passed += 1
  else
    $failed << name
    puts "  FAIL  #{name}"
  end
rescue => e
  $failed << name
  puts "  ERROR #{name}: #{e.class}: #{e.message}"
  puts "        #{e.backtrace.first}"
end

def close?(a, b, tol = 1e-6)
  (a.to_f - b.to_f).abs <= tol
end

puts 'Core::Units'
check('mm -> inches') { close?(PSB::Core::Units.mm(25.4), 1.0) }
check('inches -> mm') { close?(PSB::Core::Units.to_mm(1.0), 25.4) }
check('nil is zero')  { PSB::Core::Units.to_mm(nil) == 0.0 && PSB::Core::Units.mm(nil) == 0.0 }
check('round trip')   { close?(PSB::Core::Units.to_mm(PSB::Core::Units.mm(6000)), 6000, 1e-9) }
check('clamp')        { PSB::Core::Units.clamp(120, 5, 95) == 95.0 && PSB::Core::Units.clamp(1, 5, 95) == 5.0 }
# The bug this guards: SketchUp defines Length#to_mm but not Numeric#to_mm, so
# any Float that reached .to_mm raised NoMethodError at runtime.
check('Float#to_mm is absent, as in SketchUp') { !1.0.respond_to?(:to_mm) }

puts 'Materials::StockSize'
SS = PSB::Materials::StockSize
check('exact fit is one FULL piece') do
  plan = SS.split_rectangle(1220, 2440, 1220, 2440, false)
  plan.length == 1 && plan.first[:status] == 'FULL'
end
check('oversize splits into a grid') do
  plan = SS.split_rectangle(2440, 4880, 1220, 2440, false)
  plan.length == 4 && plan.all? { |p| p[:status] == 'FULL' }
end
check('partial piece is marked CUT') do
  plan = SS.split_rectangle(1500, 2440, 1220, 2440, false)
  plan.length == 2 && plan.count { |p| p[:status] == 'CUT' } == 1
end
# Regression: score returned an Array and Array has no #<, so every rotatable
# preset (all Cemboard) crashed with NoMethodError.
check('allow_rotate does not raise') do
  SS.split_rectangle(2000, 1000, 1220, 2440, true).is_a?(Array)
end
check('rotation is chosen when it uses fewer sheets') do
  straight = SS.split_rectangle(2400, 1200, 1220, 2440, false)
  rotated  = SS.split_rectangle(2400, 1200, 1220, 2440, true)
  rotated.length < straight.length
end
check('score is numeric and orderable') do
  a = SS.score(SS.split_rectangle(1220, 2440, 1220, 2440, false))
  b = SS.score(SS.split_rectangle(5000, 5000, 1220, 2440, false))
  a.is_a?(Numeric) && b.is_a?(Numeric) && a < b
end
check('empty plan scores worst') { SS.score([]) == Float::INFINITY }
check('zero stock is rejected') do
  begin
    SS.split_rectangle(100, 100, 0, 2440, false)
    false
  rescue RuntimeError
    true
  end
end
check('stats add up') do
  st = SS.stats(SS.split_rectangle(1220, 2440, 1220, 2440, false))
  st[:pieces] == 1 && st[:full] == 1 && st[:cut].zero? && close?(st[:waste_m2], 0.0, 0.001)
end
check('violation? respects rotation') do
  SS.violation?(2440, 1220, 1220, 2440, false) == true &&
    SS.violation?(2440, 1220, 1220, 2440, true) == false
end

puts 'Framing::ProfileLibrary'
PL = PSB::Framing::ProfileLibrary
check('all eight profiles present') { PL.names.length == 8 }
check('every profile has a tag and colour') do
  PL::PROFILES.values.all? { |p| p[:tag].is_a?(String) && p[:color].length == 3 }
end
check('tags are unique') { PL::PROFILES.values.map { |p| p[:tag] }.uniq.length == 8 }
check('unknown profile returns nil') { PL['NOPE'].nil? }

puts 'Framing::MemberFactory'
MF = PSB::Framing::MemberFactory
check('RHS outline is a closed rectangle') do
  pts = MF.profile_points(PL['100x100'])
  pts.length == 4 && close?(pts.map { |x, _| x }.max - pts.map { |x, _| x }.min, PSB::Core::Units.mm(100))
end
check('I outline has twelve points') { MF.profile_points(PL['I200']).length == 12 }
check('I section height matches the library') do
  pts = MF.profile_points(PL['I200'])
  close?(pts.map { |_, y| y }.max - pts.map { |_, y| y }.min, PSB::Core::Units.mm(200))
end
check('I section width matches the library') do
  pts = MF.profile_points(PL['I200'])
  close?(pts.map { |x, _| x }.max - pts.map { |x, _| x }.min, PSB::Core::Units.mm(100))
end
check('outline is centred on the origin') do
  pts = MF.profile_points(PL['40x80'])
  close?(pts.map { |x, _| x }.sum, 0.0, 1e-9) && close?(pts.map { |_, y| y }.sum, 0.0, 1e-9)
end
# Regression: the :x case used to be a plain rotation about Y, which left the
# section height along global Y - an I-beam lying on its side.
check('axis transformations are defined for x, y and z') do
  %i[x y z].all? { |a| MF.axis_transformation(a).is_a?(Geom::Transformation) }
end

puts 'Source::Scanner'
SC = PSB::Source::Scanner
check('name match wins')            { SC.classify('COLUMN 3', nil) == ['column', '3'] }
check('separator variants')         { SC.classify('WALL_12', nil) == ['wall', '12'] }
check('legacy WINDOOW typo')        { SC.classify('WINDOOW 2', nil).first == 'window' }
check('bare type has no number')    { SC.classify('ROOF', nil) == ['roof', nil] }
check('tag fallback')               { SC.classify('Group#7', 'STRUCT_FLOOR') == ['floor', nil] }
check('unknown stays unknown')      { SC.classify('Sofa', 'Furniture') == [nil, nil] }
check('empty tag is not a match')   { SC.classify('', '') == [nil, nil] }
check('VOID and OPENING both map')  { SC.classify('VOID 1', nil).first == 'void' && SC.classify('OPENING', nil).first == 'void' }
# Regression: generated output carries Tags like STRUCT_WALL, so without the
# generated? filter the scanner re-detected its own output as new sources.
check('generated groups are excluded') do
  g = Sketchup::Group.new
  g.name = 'GEN_WALL_42'
  SC.generated?(g)
end
check('metadata flag marks generated') do
  g = Sketchup::Group.new
  g.name = 'WALL 1'
  PSB::Core::Metadata.stamp(g, type: 'wall')
  SC.generated?(g)
end
check('plain placeholder is not generated') do
  g = Sketchup::Group.new
  g.name = 'WALL 1'
  !SC.generated?(g)
end

puts 'Output::CSVExporter'
CE = PSB::Output::CSVExporter
check('plain value is untouched')  { CE.escape('STEEL') == 'STEEL' }
check('commas are quoted')         { CE.escape('a,b') == '"a,b"' }
check('quotes are doubled')        { CE.escape('say "hi"') == '"say ""hi"""' }
check('newlines are quoted')       { CE.escape("a\nb") == %("a\nb") }
check('nil becomes empty')         { CE.escape(nil) == '' }
check('row ends with CRLF')        { CE.line(%w[a b]) == "a,b\r\n" }

puts 'Rules::RuleEngine'
RE = PSB::Rules::RuleEngine
check('valid profile passes through') { RE.valid_profile('I200', '100x100') == 'I200' }
check('invalid profile falls back')   { RE.valid_profile('NOPE', '100x100') == '100x100' }
check('nil profile falls back')       { RE.valid_profile(nil, '50x50') == '50x50' }
check('wall rules default to AZ100')  { RE.wall('NOPE')[:id] == 'NOPE' && RE.wall('NOPE')[:frame] == '25x25' }
check('known wall system resolves')   { RE.wall('NANO')[:direction] == 'horizontal' }
check('floor rules resolve')          { RE.floor('UPPER_DECK')[:primary] == 'I200' }
check('unknown floor falls back')     { RE.floor('NOPE')[:primary] == '100x100' }
check('stock length is positive')     { RE.steel_stock[:length_mm] > 0 }
check('door defaults')                { RE.opening('door')[:height] == 2200.0 }
check('window has a sill')            { RE.opening('window')[:sill] == 900.0 }

puts 'Project::ColumnTypes'
CT = PSB::Project::ColumnTypes
check('default type is valid')      { CT.normalize({})['profile'] == '100x100' }
check('bad profile is corrected')   { CT.normalize('profile' => 'NOPE')['profile'] == '100x100' }
check('bad role is corrected')      { CT.normalize('structural_role' => 'X')['structural_role'] == CT::ROLES.first }
check('bad height mode corrected')  { CT.normalize('height_mode' => 'X')['height_mode'] == 'level' }
check('rotation wraps to 0..360')   { CT.normalize('rotation_deg' => 450)['rotation_deg'] == 90.0 }
check('blank name gets a default')  { CT.normalize('name' => '   ')['name'] == 'COLUMN' }
check('fixed height resolves')      { close?(CT.resolved_height({ 'height_mode' => 'fixed', 'height_mm' => 3000 }), PSB::Core::Units.mm(3000)) }
check('level height resolves')      { CT.resolved_height('height_mode' => 'level').to_f > 0 }

puts
if $failed.empty?
  puts "All #{$passed} checks passed."
  exit 0
else
  puts "#{$passed} passed, #{$failed.length} failed:"
  $failed.each { |f| puts "  - #{f}" }
  exit 1
end
