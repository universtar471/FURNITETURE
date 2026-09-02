# encoding: UTF-8
module KTSHung
  module PrefabStructureBuilder
    module Core
      module TagManager
        FUNCTION_TAGS = %w[
          00_SOURCE STRUCT_COLUMN STRUCT_WALL STRUCT_FLOOR STRUCT_ROOF OPENING
          MAT_PANEL MAT_NANO MAT_CEMBOARD MAT_WPC MAT_ROOF
          CONNECTION CONN_PLATE CONN_BOLT CONN_WELD
        ].freeze

        module_function

        def profile_tags
          Framing::ProfileLibrary::PROFILES.values.map { |p| p[:tag] }
        end

        def all_tag_names
          (FUNCTION_TAGS + profile_tags).uniq
        end

        # Creates any missing Tag and repaints profile Tags to their library colour.
        # Deliberately transaction-free: callers already own an open operation, and
        # a nested start_operation/commit_operation pair silently closes it,
        # splitting one user action into several undo steps.
        def ensure_tags!(model = Sketchup.active_model)
          layers = model.layers
          all_tag_names.each do |name|
            layer = layers[name] || layers.add(name)
            profile = Framing::ProfileLibrary::PROFILES.values.find { |p| p[:tag] == name }
            next unless profile
            begin
              layer.color = Sketchup::Color.new(*profile[:color])
            rescue StandardError
              # Layer#color= is unavailable in some SketchUp builds; colour is cosmetic.
            end
          end
          true
        end

        # Standalone entry point (menu item / toolbar button) with its own undo step.
        def setup!(model = Sketchup.active_model)
          model.start_operation('Setup Prefab Tags', true)
          ensure_tags!(model)
          model.commit_operation
          true
        rescue => e
          model.abort_operation rescue nil
          ::UI.messagebox("Setup Tags error: #{e.message}")
          false
        end

        def tag(model, name)
          model.layers[name] || model.layers.add(name)
        end
      end
    end
  end
end
