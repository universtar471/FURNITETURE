# encoding: UTF-8
#
# Prefab Structure Builder for SketchUp
# Copyright (c) KTS Hung
#
# Registration stub. Everything else lives in prefab_structure_builder/.

require 'sketchup.rb'
require 'extensions.rb'

module KTSHung
  module PrefabStructureBuilder
    # SketchUp 2021 is the first release shipping Ruby 2.7, which this code relies on.
    MINIMUM_SKETCHUP_VERSION = 21

    unless defined?(EXTENSION)
      EXTENSION = SketchupExtension.new(
        'Prefab Structure Builder',
        File.join('prefab_structure_builder', 'loader')
      )
      EXTENSION.description = 'Semantic prefab steel framing, material splitting, ' \
                              'connections, QA and BOM tools. Built for SketchUp 2026.'
      EXTENSION.version     = '1.1.0'
      EXTENSION.creator     = 'KTS Hung'
      EXTENSION.copyright   = "© #{Time.now.year} KTS Hung"

      if Sketchup.version.to_i >= MINIMUM_SKETCHUP_VERSION
        Sketchup.register_extension(EXTENSION, true)
      else
        ::UI.messagebox(
          "Prefab Structure Builder requires SketchUp 2021 or newer.\n" \
          "This copy of SketchUp reports version #{Sketchup.version}."
        )
      end
    end
  end
end
