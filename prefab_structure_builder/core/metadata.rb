module KTSHung
  module PrefabStructureBuilder
    module Core
      module Metadata
        DICT = 'KTSHung_Prefab'.freeze
        VERSION = '1.0.0'.freeze
        module_function
        def set(entity, key, value); entity.set_attribute(DICT, key.to_s, value); end
        def get(entity, key, default=nil); entity.get_attribute(DICT, key.to_s, default); end
        def stamp(entity, attrs)
          attrs.each { |k,v| set(entity, k, v) }
          set(entity, :version, VERSION)
          set(entity, :generated, true)
          entity
        end
      end
    end
  end
end
