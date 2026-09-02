# encoding: UTF-8
require 'json'

module KTSHung
  module PrefabStructureBuilder
    module Project
      # Named, reusable column definitions stored in the model, plus the storey
      # levels they can be anchored to. This is what the COLUMN panel edits.
      module ColumnTypes
        DICT = 'KTSHung_Prefab_Project'.freeze
        TYPES_KEY = 'column_types_json'.freeze
        LEVELS_KEY = 'levels_json'.freeze

        HEIGHT_MODES = %w[level fixed source].freeze
        ROLES = ['Primary Column', 'Secondary Column', 'Post', 'Brace'].freeze
        MATERIALS = %w[Steel Aluminium Timber Concrete].freeze

        module_function

        def default_levels
          height = Project::PresetManager.current[:floor_height_mm].to_f
          height = 3000.0 if height <= 0
          [
            { 'name' => 'Level 1', 'elevation_mm' => 0.0 },
            { 'name' => 'Level 2', 'elevation_mm' => height }
          ]
        end

        def levels
          raw = Sketchup.active_model.get_attribute(DICT, LEVELS_KEY, nil)
          return default_levels if raw.nil? || raw.to_s.empty?
          parsed = JSON.parse(raw)
          return default_levels unless parsed.is_a?(Array) && !parsed.empty?
          parsed.map do |l|
            { 'name' => l['name'].to_s, 'elevation_mm' => l['elevation_mm'].to_f }
          end.sort_by { |l| l['elevation_mm'] }
        rescue StandardError
          default_levels
        end

        def save_levels(list)
          clean = Array(list).map do |l|
            name = (l['name'] || l[:name]).to_s.strip
            next nil if name.empty?
            { 'name' => name, 'elevation_mm' => (l['elevation_mm'] || l[:elevation_mm]).to_f }
          end.compact
          clean = default_levels if clean.empty?
          Sketchup.active_model.set_attribute(DICT, LEVELS_KEY, JSON.generate(clean))
          clean
        end

        def level_elevation(name)
          found = levels.find { |l| l['name'] == name.to_s }
          found ? found['elevation_mm'] : 0.0
        end

        def default_type(name = 'COLUMN 1')
          profile = Rules::RuleEngine.column_profile
          lv = levels
          {
            'name' => name,
            'profile' => profile,
            'material' => 'Steel',
            'height_mode' => 'level',
            'height_mm' => Project::PresetManager.current[:floor_height_mm].to_f,
            'rotation_deg' => 0.0,
            'base_level' => lv.first['name'],
            'top_level' => (lv[1] || lv.first)['name'],
            'structural_role' => ROLES.first,
            'description' => "Main column type #{profile}"
          }
        end

        def all
          raw = Sketchup.active_model.get_attribute(DICT, TYPES_KEY, nil)
          return [default_type] if raw.nil? || raw.to_s.empty?
          parsed = JSON.parse(raw)
          return [default_type] unless parsed.is_a?(Array) && !parsed.empty?
          parsed.map { |t| normalize(t) }
        rescue StandardError
          [default_type]
        end

        def [](name)
          all.find { |t| t['name'].to_s.casecmp(name.to_s).zero? }
        end

        # Fills in missing keys and rejects values the rest of the plugin cannot use.
        def normalize(raw)
          t = default_type
          (raw || {}).each { |k, v| t[k.to_s] = v }
          t['name'] = t['name'].to_s.strip
          t['name'] = 'COLUMN' if t['name'].empty?
          t['profile'] = Rules::RuleEngine.valid_profile(t['profile'], Rules::RuleEngine.column_profile)
          t['material'] = 'Steel' unless MATERIALS.include?(t['material'].to_s)
          t['height_mode'] = 'level' unless HEIGHT_MODES.include?(t['height_mode'].to_s)
          t['height_mm'] = t['height_mm'].to_f
          t['rotation_deg'] = t['rotation_deg'].to_f % 360.0
          t['structural_role'] = ROLES.first unless ROLES.include?(t['structural_role'].to_s)
          t['description'] = t['description'].to_s
          t
        end

        def save_all(list)
          clean = Array(list).map { |t| normalize(t) }
          clean = [default_type] if clean.empty?
          # Names address a type, so they have to stay unique.
          seen = {}
          clean.each do |t|
            base = t['name']
            n = 2
            while seen[t['name'].downcase]
              t['name'] = "#{base} (#{n})"
              n += 1
            end
            seen[t['name'].downcase] = true
          end
          Sketchup.active_model.set_attribute(DICT, TYPES_KEY, JSON.generate(clean))
          clean
        end

        # Resolved height in internal inches for one column type, given the
        # bounding box of its source placeholder.
        def resolved_height(type, source_bounds = nil)
          t = normalize(type)
          case t['height_mode']
          when 'fixed'
            Core::Units.mm(t['height_mm'])
          when 'source'
            h = source_bounds ? source_bounds.depth : 0
            h.to_f > Core::Units.mm(1) ? h : Core::Units.mm(t['height_mm'])
          else
            delta = level_elevation(t['top_level']) - level_elevation(t['base_level'])
            delta = t['height_mm'].to_f if delta <= 0
            delta = 3000.0 if delta <= 0
            Core::Units.mm(delta)
          end
        end

        # Base elevation in internal inches. Level mode anchors to the storey,
        # every other mode sits on the placeholder.
        def resolved_base_z(type, source_bounds = nil)
          t = normalize(type)
          return Core::Units.mm(level_elevation(t['base_level'])) if t['height_mode'] == 'level'
          source_bounds ? source_bounds.min.z : 0
        end

        def serializable
          {
            types: all,
            levels: levels,
            profiles: Framing::ProfileLibrary.names,
            roles: ROLES,
            materials: MATERIALS,
            height_modes: HEIGHT_MODES,
            profile_colors: Framing::ProfileLibrary::PROFILES.map { |k, v|
              { 'profile' => k, 'tag' => v[:tag], 'color' => format('#%02X%02X%02X', *v[:color]) }
            }
          }
        end
      end
    end
  end
end
