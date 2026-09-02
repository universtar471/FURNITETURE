# encoding: UTF-8
module KTSHung
  module PrefabStructureBuilder
    module Output
      # Writes CSV without requiring the stdlib 'csv' library. csv became a
      # bundled gem in newer Rubies and is not guaranteed to be loadable from
      # inside SketchUp, so the (small) quoting rules live here instead.
      module CSVExporter
        # Excel on Windows only detects UTF-8 in a CSV when a BOM is present.
        BOM = "\xEF\xBB\xBF".dup.force_encoding(Encoding::UTF_8).freeze

        module_function

        def escape(value)
          s = value.nil? ? '' : value.to_s
          return s unless s =~ /[",\r\n]/
          %("#{s.gsub('"', '""')}")
        end

        def line(row)
          Array(row).map { |v| escape(v) }.join(',') + "\r\n"
        end

        def write(path, rows)
          File.open(path, 'w:UTF-8') do |f|
            f.write(BOM)
            rows.each { |row| f.write(line(row)) }
          end
          path
        end

        def choose_path(default_name)
          model = Sketchup.active_model
          base = model.path.to_s.empty? ? Dir.home : File.dirname(model.path)
          ::UI.savepanel('Export Prefab CSV', base, default_name)
        end

        def export_bom
          path = choose_path('prefab_bom.csv')
          return nil unless path
          rows = [%w[Category Item System Role Quantity TotalLength_m TotalArea_m2]]
          BOM.rows.each do |r|
            rows << [r[:category], r[:item], r[:system], r[:role], r[:quantity], r[:total_length_m], r[:total_area_m2]]
          end
          write(path, rows)
          ::UI.messagebox("BOM exported:\n#{path}")
          path
        rescue => e
          ::UI.messagebox("BOM export error: #{e.message}")
          nil
        end

        def export_cutlist
          path = choose_path('prefab_cut_list.csv')
          return nil unless path
          rows = [%w[Profile Length_mm Quantity TotalLength_m Roles]]
          CutList.grouped.each do |r|
            rows << [r[:profile], r[:length_mm], r[:quantity], r[:total_length_m], r[:roles]]
          end
          rows << []
          rows << %w[Profile StockLength_mm Bars Cuts Oversize Used_m Purchase_m Waste_m Waste_percent]
          CutList.stock_plan.each do |r|
            rows << [r[:profile], r[:stock_length_mm], r[:bars], r[:cuts], r[:oversize],
                     r[:used_m], r[:purchase_m], r[:waste_m], r[:waste_percent]]
          end
          write(path, rows)
          ::UI.messagebox("Cut List exported:\n#{path}")
          path
        rescue => e
          ::UI.messagebox("Cut List export error: #{e.message}")
          nil
        end

        def export_report
          path = choose_path('prefab_project_report.csv')
          return nil unless path
          rows = [['PROJECT']]
          Project::PresetManager.current.each { |k, v| rows << [k, v] }
          rows << []
          rows << ['PROJECT STATUS']
          Report.project_status.each { |k, v| rows << [k, v] }
          rows << []
          rows << ['SUMMARY']
          BOM.summary.each { |k, v| rows << [k, v] }
          rows << []
          rows << ['BY SYSTEM']
          rows << %w[System Quantity SteelLength_m SheetArea_m2 Categories]
          Report.by_system.each do |r|
            rows << [r[:system], r[:quantity], r[:steel_length_m], r[:sheet_area_m2], r[:categories]]
          end
          rows << []
          rows << ['MARKED ITEMS']
          rows << %w[Mark Type System Role Profile Length_mm SourceId]
          Report.marked_items.each do |r|
            rows << [r[:mark], r[:type], r[:system], r[:role], r[:profile], r[:length_mm], r[:source_id]]
          end
          write(path, rows)
          ::UI.messagebox("Project report exported:\n#{path}")
          path
        rescue => e
          ::UI.messagebox("Report export error: #{e.message}")
          nil
        end
      end
    end
  end
end
