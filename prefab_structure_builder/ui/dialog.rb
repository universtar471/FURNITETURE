# encoding: UTF-8
module KTSHung
  module PrefabStructureBuilder
    # Named Gui, not UI. A module called UI inside this namespace shadows
    # SketchUp's toplevel ::UI for every constant lookup that starts inside
    # KTSHung::PrefabStructureBuilder, which is what made UI.start_timer and
    # UI.messagebox raise NoMethodError from inside the extension.
    module Gui
      module Dialog
        WIDTH = 940
        HEIGHT = 780

        module_function

        def dialog
          @dialog
        end

        def open?
          !@dialog.nil? && @dialog.visible?
        rescue StandardError
          false
        end

        def show
          @dialog = build unless @dialog
          @dialog.show unless open?
          @dialog
        end

        # Remembers the requested panel even when the page has not finished
        # loading yet; the 'ready' callback applies it.
        def show_panel(panel)
          @pending_panel = panel.to_s
          show
          apply_pending_panel
          schedule_refresh
        end

        def apply_pending_panel
          return false unless @pending_panel
          return false unless call_js('window.showPanel', @pending_panel)
          @pending_panel = nil
          true
        end

        def show_and_scan
          show
          schedule_refresh
        end

        def refresh_if_open
          refresh_all if open?
        end

        def close
          @dialog.close if open?
          @dialog = nil
        end

        # Single funnel for every push into the page. Guards against a dialog the
        # user already closed, and reports callback failures to the Ruby Console
        # instead of leaving the panel silently blank.
        def call_js(fn, *args)
          return false if @dialog.nil?
          @dialog.execute_script("#{fn}(#{args.map { |a| JSON.generate(a) }.join(',')});")
          true
        rescue => e
          warn("[Prefab Structure Builder] #{fn}: #{e.message}")
          false
        end

        def build
          d = ::UI::HtmlDialog.new(
            dialog_title: 'Prefab Structure Builder',
            preferences_key: 'kts_hung_prefab_structure_builder',
            scrollable: true, resizable: true,
            width: WIDTH, height: HEIGHT,
            min_width: 720, min_height: 520,
            style: ::UI::HtmlDialog::STYLE_DIALOG
          )
          d.set_file(File.join(ROOT, 'ui', 'web', 'index.html'))
          register_callbacks(d)
          d.set_on_closed do
            @dialog = nil
            @pending_panel = nil
          end
          d
        end

        # Every callback body is wrapped: an exception escaping an HtmlDialog
        # callback is swallowed by SketchUp and the button just appears dead.
        def guard(name)
          yield
        rescue => e
          warn("[Prefab Structure Builder] callback #{name}: #{e.class}: #{e.message}")
          warn(e.backtrace.first(8).join("\n"))
          ::UI.messagebox("#{name} failed:\n#{e.message}")
          nil
        end

        def register_callbacks(d)
          cb = lambda do |name, &body|
            d.add_action_callback(name) { |*args| guard(name) { body.call(*args[1..-1]) } }
          end

          cb.call('ready')          { apply_pending_panel; refresh_all }
          cb.call('scan')           { send_scan; send_openings }
          cb.call('setupTags')      { Core::TagManager.setup!; send_tags; send_scan }
          cb.call('getTags')        { send_tags }

          # --- Column types
          cb.call('getColumnTypes')  { send_column_types }
          cb.call('saveColumnTypes') { |json| Project::ColumnTypes.save_all(JSON.parse(json.to_s)); send_column_types }
          cb.call('saveLevels')      { |json| Project::ColumnTypes.save_levels(JSON.parse(json.to_s)); send_column_types }
          cb.call('generateColumns') { |type_name| Structure::ColumnEngine.generate_from_selected(type_name.to_s); send_scan; send_bom }

          # --- Walls / openings
          cb.call('generateWalls') do |wall_type, spacing|
            Structure::WallEngine.generate_from_selected(wall_type.to_s, spacing.to_f)
            send_scan
          end
          cb.call('getOpenings')      { send_openings }
          cb.call('saveOpenings')     { |json| Structure::OpeningEngine.save_types(json); send_openings }
          cb.call('generateOpenings') do |json|
            Structure::OpeningEngine.save_types(json)
            Structure::OpeningEngine.generate_all
            send_scan
            send_openings
          end

          # --- Floor / roof
          cb.call('generateFloor') do |floor_type, primary, secondary, spacing, direction|
            Structure::FloorEngine.generate_from_selected(floor_type.to_s, primary.to_s, secondary.to_s,
                                                          spacing.to_f, direction.to_s)
            send_scan
          end
          cb.call('generateRoof') do |roof_type, high, low, ridge, ridge_pos, direction,
                                      front, back, left, right, spacing, cover, soffit|
            Structure::RoofEngine.generate_from_selected(
              roof_type.to_s, high.to_f, low.to_f, ridge.to_f, ridge_pos.to_f, direction.to_s,
              front.to_f, back.to_f, left.to_f, right.to_f, spacing.to_f, cover.to_s,
              truthy?(soffit)
            )
            send_scan
          end

          # --- Materials
          cb.call('getMaterials') { send_materials }
          cb.call('saveMaterial') { |id, json| Materials::MaterialLibrary.save_custom(id.to_s, JSON.parse(json.to_s)); send_materials }
          cb.call('checkStock')   { send_stock_report }
          cb.call('previewStock') do |preset_id, w, l|
            preset = Materials::MaterialLibrary[preset_id.to_s]
            raise 'Choose a material preset.' unless preset
            sw = preset[:stock_width] || preset['stock_width']
            sl = preset[:stock_length] || preset['stock_length']
            rotate = preset[:allow_rotate] || preset['allow_rotate']
            plan = Materials::StockSize.split_rectangle(w.to_f, l.to_f, sw.to_f, sl.to_f, truthy?(rotate))
            call_js('window.renderStockPreview',
                    pieces: plan, stats: Materials::StockSize.stats(plan), preset: preset_id.to_s)
          end

          # --- Connections
          cb.call('autoConnections')  { |detail| Connections::ConnectionEngine.auto_generate(detail.to_s); send_connections; send_scan }
          cb.call('connectSelected')  { |rule, detail| Connections::ConnectionEngine.connect_selected(rule.to_s, detail.to_s); send_connections }
          cb.call('getConnections')   { send_connections }

          # --- Update / check
          cb.call('trackBaseline')   { Update::UpdateManager.baseline!; send_update_status; send_checks }
          cb.call('updateChanged')   { Update::UpdateManager.update_changed; refresh_all }
          cb.call('updateSelected')  { Update::UpdateManager.update_selected; refresh_all }
          cb.call('getUpdateStatus') { send_update_status }
          cb.call('checkModel')      { send_checks }

          # --- Output
          cb.call('getBOM')               { send_bom }
          cb.call('exportBOM')            { Output::CSVExporter.export_bom }
          cb.call('exportCutList')        { Output::CSVExporter.export_cutlist }
          cb.call('exportProjectReport')  { Output::CSVExporter.export_report }
          cb.call('applyNumbering') do
            # Numbering rewrites marks and names on every generated object, so
            # it belongs in one undo step.
            result = Core::Transaction.run('Prefab Apply Numbering') { Output::Numbering.apply }
            send_bom
            send_project
            ::UI.messagebox("Numbering: #{result[:assigned]} assigned, #{result[:preserved]} preserved (revision #{result[:revision]}).")
          end

          # --- Project / production
          cb.call('getProject')          { send_project }
          cb.call('saveProjectPreset')   { |json| Project::PresetManager.save(JSON.parse(json.to_s)); send_project; send_column_types }
          cb.call('resetProjectPreset')  { Project::PresetManager.reset; send_project }
          cb.call('savePresetFile')      { Project::PresetManager.save_to_file }
          cb.call('loadPresetFile')      { Project::PresetManager.load_from_file; send_project }
          cb.call('getRules')            { send_rules }
          cb.call('productionCheck')     { send_production_checks }
          cb.call('finalizeProject')     { finalize_project }

          cb.call('zoomEntity') { |id| zoom_entity(id) }

          d
        end

        def truthy?(value)
          value == true || %w[true 1 yes on].include?(value.to_s.downcase)
        end

        def zoom_entity(id)
          model = Sketchup.active_model
          entity = model.find_entity_by_id(id.to_i)
          return false unless entity && entity.valid?
          model.selection.clear
          model.selection.add(entity)
          model.active_view.zoom(entity)
          true
        end

        # A short timer lets SketchUp finish committing the current operation
        # before the panel reads the model back.
        def schedule_refresh
          ::UI.start_timer(0.15, false) { refresh_all }
        end

        def refresh_all
          return false if @dialog.nil?
          # One model traversal feeds the BOM panels, and one model-check run
          # feeds the CHECK, PRODUCTION and PROJECT panels.
          Output::BOM.with_cache do
            checks = Validation::ModelChecker.report
            qa = Production::ProductionChecker.report(Sketchup.active_model, checks)

            send_scan
            send_column_types
            send_openings
            send_materials
            send_connections
            send_update_status
            send_tags
            send_rules
            call_js('window.renderChecks', checks)
            call_js('window.renderProductionChecks', qa)
            send_bom
            send_project(qa.length)
          end
          true
        end

        def finalize_project
          payload = Production::Finalizer.run
          call_js('window.renderFinalizeResult', payload)
          refresh_all
          payload
        end

        def send_scan;              call_js('window.renderScan', Source::Scanner.scan); end
        def send_column_types;      call_js('window.renderColumnTypes', Project::ColumnTypes.serializable); end
        def send_materials;         call_js('window.renderMaterials', Materials::MaterialLibrary.serializable); end
        def send_stock_report;      call_js('window.renderStockReport', Materials::MaterialChecker.report); end
        def send_openings;          call_js('window.renderOpenings', Structure::OpeningEngine.scan_types); end
        def send_connections;       call_js('window.renderConnections', Connections::ConnectionEngine.report); end
        def send_update_status;     call_js('window.renderUpdateStatus', Update::SourceTracker.report); end
        def send_checks;            call_js('window.renderChecks', Validation::ModelChecker.report); end
        def send_rules;             call_js('window.renderRules', Rules::RuleEngine.serializable); end
        def send_production_checks; call_js('window.renderProductionChecks', Production::ProductionChecker.report); end

        def send_tags
          model = Sketchup.active_model
          rows = Core::TagManager.all_tag_names.map do |name|
            layer = model.layers[name]
            profile = Framing::ProfileLibrary::PROFILES.values.find { |p| p[:tag] == name }
            {
              name: name,
              exists: !layer.nil?,
              visible: layer ? layer.visible? : false,
              color: profile ? format('#%02X%02X%02X', *profile[:color]) : nil,
              profile: profile ? Framing::ProfileLibrary::PROFILES.key(profile) : nil
            }
          end
          call_js('window.renderTags', rows)
        end

        def send_project(qa_issue_count = nil)
          Output::BOM.with_cache do
            call_js('window.renderProject',
                    preset: Project::PresetManager.current,
                    report: Output::Report.by_system,
                    marked_count: Output::Report.marked_items.length,
                    status: Output::Report.project_status(qa_issue_count))
          end
        end

        def send_bom
          Output::BOM.with_cache do
            call_js('window.renderBOM',
                    rows: Output::BOM.rows,
                    summary: Output::BOM.summary,
                    cut_rows: Output::CutList.grouped,
                    stock_plan: Output::CutList.stock_plan,
                    materials: Output::BOM.material_summary)
          end
        end
      end
    end
  end
end
