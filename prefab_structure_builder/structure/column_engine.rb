# encoding: UTF-8
module KTSHung
  module PrefabStructureBuilder
    module Structure
      module ColumnEngine
        module_function

        # Generates from the current selection. +type_name+ selects a saved
        # Column Type; passing a bare profile name still works for older callers.
        def generate_from_selected(profile_or_type = nil)
          model = Sketchup.active_model
          sources = model.selection.select do |e|
            (e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)) &&
              !Source::Scanner.generated?(e)
          end
          return ::UI.messagebox('Select COLUMN placeholder groups first.') if sources.empty?

          type = resolve_type(profile_or_type)
          return ::UI.messagebox("Unknown column profile/type: #{profile_or_type}") unless type

          model.start_operation('Generate Columns', true)
          Core::TagManager.ensure_tags!(model)
          made = 0
          sources.each { |src| made += 1 if generate_one(model, src, type) }
          model.commit_operation
          ::UI.messagebox('No columns were created. Check the selected placeholders.') if made.zero?
          made
        rescue => e
          model.abort_operation rescue nil
          ::UI.messagebox("Column generation error: #{e.message}\n#{e.backtrace.first}")
          0
        end

        # Accepts a Column Type hash, a saved type name, a profile name, or nil.
        def resolve_type(value)
          return Project::ColumnTypes.normalize(value) if value.is_a?(Hash)
          name = value.to_s.strip
          if name.empty?
            saved = Project::ColumnTypes.all.first
            return saved || Project::ColumnTypes.default_type
          end
          saved = Project::ColumnTypes[name]
          return saved if saved
          return nil unless Framing::ProfileLibrary[name]
          Project::ColumnTypes.normalize(Project::ColumnTypes.default_type.merge('profile' => name, 'name' => name))
        end

        # +type_or_profile+ keeps the old (model, src, profile_name, profile_hash)
        # call shape working for UpdateManager.
        def generate_one(model, src, type_or_profile, _legacy_profile = nil)
          type = resolve_type(type_or_profile)
          return false unless type
          profile_name = type['profile']
          profile = Framing::ProfileLibrary[profile_name]
          return false unless profile

          bb = src.bounds
          center = bb.center
          height = Project::ColumnTypes.resolved_height(type, bb)
          base_z = Project::ColumnTypes.resolved_base_z(type, bb)
          return false if height.to_f <= Core::Units.mm(1)

          g = model.entities.add_group
          g.name = "GEN_COLUMN_#{src.entityID}"
          # Drawn straight into the group rather than through add_profile_member:
          # a nested member group would be stamped as steel too and the BOM would
          # count the same column twice.
          unless Framing::MemberFactory.draw_profile(g.entities, profile, height)
            g.erase! if g.valid?
            return false
          end

          rotation = type['rotation_deg'].to_f
          g.transform!(Geom::Transformation.rotation(ORIGIN, Z_AXIS, rotation.degrees)) unless rotation.zero?
          g.transform!(Geom::Transformation.translation([center.x, center.y, base_z]))

          g.layer = Core::TagManager.tag(model, profile[:tag])
          mat = Framing::MemberFactory.material_for(model, profile_name)
          g.material = mat if mat
          Core::Metadata.stamp(g,
            type: 'column', role: 'primary_column', profile: profile_name,
            column_type: type['name'], material: type['material'],
            structural_role: type['structural_role'], rotation_deg: rotation,
            base_level: type['base_level'], top_level: type['top_level'],
            height_mm: Core::Units.to_mm(height), length_mm: Core::Units.to_mm(height),
            source_id: src.entityID, parent_id: Source::Scanner.source_name(src),
            system: 'structure')
          true
        end
      end
    end
  end
end
