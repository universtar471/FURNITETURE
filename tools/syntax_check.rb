#!/usr/bin/env ruby
# encoding: UTF-8
# Parses every Ruby file in the extension. Catches syntax errors without SketchUp.
require 'open3'

root = File.expand_path('..', __dir__)
files = Dir.glob(File.join(root, '**', '*.rb')).reject { |f| f.include?('/tools/') }
failed = []

files.sort.each do |file|
  out, status = Open3.capture2e(RbConfig.ruby, '-c', file)
  rel = file.sub("#{root}/", '')
  if status.success?
    puts "  ok   #{rel}"
  else
    failed << rel
    puts "  FAIL #{rel}\n#{out}"
  end
end

puts "\n#{files.length - failed.length}/#{files.length} files parsed."
exit(failed.empty? ? 0 : 1)
