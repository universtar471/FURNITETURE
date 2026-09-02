require 'json'
module KTSHung
  module PrefabStructureBuilder
    module Project
      module PresetManager
        module_function

        DICT='KTSHung_Prefab_Project'.freeze
        KEY='preset_json'.freeze

        DEFAULT = {
          project_name: 'Prefab Project',
          floor_height_mm: 3000,
          default_column: '100x100',
          default_wall_system: 'AZ100',
          default_opening_ext: '40x80',
          default_opening_int: '50x100',
          default_floor_primary: 'I150',
          default_floor_secondary: '40x80',
          default_roof_primary: '50x100',
          default_roof_secondary: '30x60',
          steel_stock_mm: 6000,
          steel_kerf_mm: 3,
          code_prefix: 'PFB',
          project_revision: 'A',
          preserve_existing_marks: true,
          recursive_source_scan: true,
          auto_baseline_after_generate: false
        }.freeze

        def current
          model=Sketchup.active_model
          raw=model.get_attribute(DICT,KEY,nil)
          return DEFAULT.dup unless raw && !raw.to_s.empty?
          data=JSON.parse(raw, symbolize_names:true)
          DEFAULT.merge(data)
        rescue
          DEFAULT.dup
        end

        def save(data)
          cfg=DEFAULT.merge(symbolize_keys(data || {}))
          Sketchup.active_model.set_attribute(DICT,KEY,JSON.generate(cfg))
          cfg
        end

        def reset
          Sketchup.active_model.delete_attribute(DICT,KEY)
          DEFAULT.dup
        rescue
          DEFAULT.dup
        end

        def symbolize_keys(h)
          h.each_with_object({}){|(k,v),o| o[k.to_sym]=v}
        end

        def save_to_file
          path=::UI.savepanel('Save Prefab Project Preset', Dir.home, 'prefab_project_preset.json')
          return unless path
          File.write(path, JSON.pretty_generate(current))
          path
        end

        def load_from_file
          path=::UI.openpanel('Load Prefab Project Preset', Dir.home, 'JSON|*.json||')
          return unless path
          data=JSON.parse(File.read(path), symbolize_names:true)
          save(data)
        rescue => e
          ::UI.messagebox("Preset load error: #{e.message}")
          nil
        end
      end
    end
  end
end
