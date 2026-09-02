module KTSHung
  module PrefabStructureBuilder
    module Core
      module ProjectStore
        DICT = 'KTSHung_Prefab_Project'.freeze
        module_function
        def get(key, default=nil)
          Sketchup.active_model.get_attribute(DICT, key.to_s, default)
        end
        def set(key, value)
          Sketchup.active_model.set_attribute(DICT, key.to_s, value)
        end
        def opening_types
          raw = get('opening_types', '{}')
          JSON.parse(raw)
        rescue
          {}
        end
        def save_opening_types(hash)
          set('opening_types', JSON.generate(hash))
        end
      end
    end
  end
end
