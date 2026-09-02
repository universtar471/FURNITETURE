#!/usr/bin/env ruby
# encoding: UTF-8
# Packs the extension into an installable .rbz (a renamed zip).
# The archive root must hold prefab_structure_builder.rb and its support folder.
#
#   ruby tools/build.rb [output_dir]

require 'fileutils'

ROOT = File.expand_path('..', __dir__)
NAME = 'prefab_structure_builder'
VERSION = File.read(File.join(ROOT, "#{NAME}.rb"), encoding: 'UTF-8')[/EXTENSION\.version\s*=\s*'([^']+)'/, 1] || '0.0.0'

out_dir = ARGV[0] || File.join(ROOT, 'build')
FileUtils.mkdir_p(out_dir)
rbz = File.join(out_dir, "Prefab_Structure_Builder_v#{VERSION}.rbz")
FileUtils.rm_f(rbz)

entries = ["#{NAME}.rb"] + Dir.chdir(ROOT) { Dir.glob("#{NAME}/**/*") }.sort
entries.reject! { |e| File.basename(e).start_with?('.') }
files = entries.select { |e| File.file?(File.join(ROOT, e)) }

Dir.chdir(ROOT) do
  # -X drops platform extra fields; -q keeps the log readable.
  system('zip', '-q', '-X', '-r', rbz, *entries) or abort('zip failed')
end

puts "Built #{rbz}"
puts "  version #{VERSION}"
puts "  #{files.length} files, #{(File.size(rbz) / 1024.0).round(1)} KB"
puts "Install: SketchUp -> Extension Manager -> Install Extension"
