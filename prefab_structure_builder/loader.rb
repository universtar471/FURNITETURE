# encoding: UTF-8
require 'sketchup.rb'
require 'json'

module KTSHung
  module PrefabStructureBuilder
    ROOT = File.dirname(__FILE__) unless const_defined?(:ROOT)

    %w[
      core/units
      core/metadata
      core/project_store
      core/transaction
      framing/profile_library
      framing/member_factory
      project/preset_manager
      project/column_types
      rules/rule_engine
      core/tag_manager
      materials/material_library
      materials/stock_size
      materials/sheet_layout
      materials/material_checker
      source/scanner
      structure/column_engine
      structure/wall_engine
      structure/opening_engine
      structure/floor_engine
      structure/roof_engine
      connections/connection_geometry
      connections/connection_registry
      connections/connection_engine
      update/source_tracker
      update/update_manager
      validation/model_checker
      output/bom
      output/cut_list
      output/csv_exporter
      output/numbering
      output/report
      production/production_checker
      production/finalizer
      ui/dialog
    ].each { |rel| require File.join(ROOT, rel) }

    # Menu and toolbar entries. Registered exactly once per SketchUp session.
    module Commands
      module_function

      # Every menu/toolbar entry funnels through here so a raised exception
      # reaches the Ruby Console with a backtrace instead of silently
      # leaving the toolbar button dead.
      def safely(label)
        yield
      rescue => e
        warn("[Prefab Structure Builder] #{label}: #{e.class}: #{e.message}")
        warn(e.backtrace.first(8).join("\n"))
        ::UI.messagebox("#{label} failed:\n#{e.message}")
        nil
      end

      def definitions
        [
          ['Open Panel',      'panel.png',      'Open Prefab Structure Builder',   -> { Gui::Dialog.show }],
          ['Scan Model',      'scan.png',       'Scan semantic source groups',     -> { Gui::Dialog.show_and_scan }],
          ['Setup Tags',      'tag.png',        'Create or repair prefab Tags',    -> { Core::TagManager.setup!; Gui::Dialog.refresh_if_open }],
          ['Column',          'column.png',     'Open column tools',               -> { Gui::Dialog.show_panel('column') }],
          ['Wall',            'wall.png',       'Open wall tools',                 -> { Gui::Dialog.show_panel('wall') }],
          ['Opening',         'opening.png',    'Open door/window tools',          -> { Gui::Dialog.show_panel('opening') }],
          ['Floor',           'floor.png',      'Open floor tools',                -> { Gui::Dialog.show_panel('floor') }],
          ['Roof',            'roof.png',       'Open roof tools',                 -> { Gui::Dialog.show_panel('roof') }],
          ['Material',        'material.png',   'Open material and stock tools',   -> { Gui::Dialog.show_panel('material') }],
          ['Connections',     'connection.png', 'Generate/check steel connections', -> { Gui::Dialog.show_panel('connection') }],
          ['Update Changed',  'update.png',     'Update changed source objects',   -> { Update::UpdateManager.update_changed; Gui::Dialog.show_and_scan }],
          ['Check Model',     'check.png',      'Validate prefab model',           -> { Gui::Dialog.show_panel('check'); Gui::Dialog.send_checks }],
          ['BOM / Cut List',  'bom.png',        'BOM, Cut List and material summary', -> { Gui::Dialog.show_panel('bom'); Gui::Dialog.send_bom }],
          ['Project Report',  'project.png',    'Project preset and report',       -> { Gui::Dialog.show_panel('project'); Gui::Dialog.send_project }]
        ]
      end

      def build_command(label, icon, tip, action)
        cmd = ::UI::Command.new(label) { safely(label, &action) }
        icon_path = File.join(ROOT, 'icons', icon)
        if File.exist?(icon_path)
          cmd.small_icon = icon_path
          cmd.large_icon = icon_path
        end
        cmd.tooltip = label
        cmd.status_bar_text = tip
        cmd
      end

      def install!
        menu = ::UI.menu('Extensions').add_submenu('Prefab Structure Builder')
        definitions.each { |label, icon, tip, action| menu.add_item(build_command(label, icon, tip, action)) }
        menu.add_separator
        menu.add_item(build_command('Finalize Project', 'check.png',
                                    'Tags, marks, baseline and production QA',
                                    -> { Gui::Dialog.show_panel('production'); Gui::Dialog.finalize_project }))

        toolbar = ::UI::Toolbar.new('Prefab Structure Builder')
        definitions.each { |label, icon, tip, action| toolbar.add_item(build_command(label, icon, tip, action)) }
        toolbar.restore
        toolbar
      end
    end

    unless file_loaded?(__FILE__)
      Commands.install!
      file_loaded(__FILE__)
    end
  end
end
