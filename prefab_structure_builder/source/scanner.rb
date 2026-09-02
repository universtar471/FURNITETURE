# encoding: UTF-8
module KTSHung
  module PrefabStructureBuilder
    module Source
      # Recognises semantic placeholder Groups/Components ("COLUMN 1", "WALL 2", ...)
      # by name first, then by Tag. Generated prefab output is skipped: its Tags
      # (STRUCT_WALL, STRUCT_ROOF, ...) contain the same keywords the Tag fallback
      # looks for, so without that filter the plugin re-detects its own output as
      # new source placeholders and double-counts everything downstream.
      module Scanner
        PATTERNS = {
          'column'  => /^COLUMN(?:[ _-]*(\d+))?/i,
          'wall'    => /^WALL(?:[ _-]*(\d+))?/i,
          'floor'   => /^FLOOR(?:[ _-]*(\d+))?/i,
          'roof'    => /^ROOF(?:[ _-]*(\d+))?/i,
          'door'    => /^DOOR(?:[ _-]*(\d+))?/i,
          'window'  => /^(?:WINDOW|WINDOOW|WIND+O+W)(?:[ _-]*(\d+))?/i,
          'balcony' => /^BALCONY(?:[ _-]*(\d+))?/i,
          'void'    => /^(?:VOID|OPENING)(?:[ _-]*(\d+))?/i
        }.freeze

        # Names the plugin gives its own containers.
        GENERATED_NAME = /\A(?:GEN_|PREFAB_CONNECTIONS\z)/.freeze

        MAX_DEPTH = 12

        module_function

        def scan(model = Sketchup.active_model, recursive = true)
          rows = recognized_entities(model, recursive).map do |r|
            e = r[:entity]
            num = r[:number]
            {
              type: r[:type],
              normalized_name: num ? "#{r[:type].upcase} #{num}" : r[:type].upcase,
              source: r[:source], entity_id: e.entityID, raw_name: r[:name],
              depth: r[:depth], path: r[:path]
            }
          end

          rows.group_by { |r| [r[:type], r[:normalized_name]] }.map do |(type, name), arr|
            {
              type: type, name: name, quantity: arr.size, source: arr.first[:source],
              entity_ids: arr.map { |x| x[:entity_id] },
              depths: arr.map { |x| x[:depth] },
              nested: arr.any? { |x| x[:depth] > 0 },
              paths: arr.map { |x| x[:path] },
              status: 'ready'
            }
          end.sort_by { |r| [r[:type], r[:name]] }
        end

        # Returns [{entity:, type:, number:, name:, source:, depth:, path:}, ...]
        def recognized_entities(model = Sketchup.active_model, recursive = true)
          found = []
          walk_entities(model.entities, found, 0, 'MODEL', recursive, {})
          found
        end

        def walk_entities(ents, found, depth, path, recursive, visited_defs)
          return if depth > MAX_DEPTH
          ents.each do |e|
            next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
            next if generated?(e)

            name = source_name(e)
            type, number = classify(name, tag_name(e))
            source = e.is_a?(Sketchup::Group) ? 'Group' : 'Component'
            current = "#{path}/#{name.empty? ? source : name}"
            if type
              found << { entity: e, type: type, number: number, name: name,
                         source: source, depth: depth, path: current }
            end
            next unless recursive

            if e.is_a?(Sketchup::Group)
              walk_entities(e.entities, found, depth + 1, current, true, visited_defs)
            else
              # Guard against a component definition that (directly or through a
              # chain) contains an instance of itself, which would recurse forever.
              key = e.definition.entityID
              next if visited_defs[key]
              visited_defs[key] = true
              walk_entities(e.definition.entities, found, depth + 1, current, true, visited_defs)
              visited_defs.delete(key)
            end
          end
        end

        # True for anything this plugin created.
        def generated?(e)
          return true if Core::Metadata.get(e, 'generated', false)
          e.name.to_s =~ GENERATED_NAME ? true : false
        end

        def tag_name(e)
          layer = e.layer
          layer ? layer.name.to_s : ''
        rescue StandardError
          ''
        end

        def source_name(e)
          n = e.name.to_s.strip
          return n unless n.empty?
          # Group#definition and ComponentInstance#definition can be nil for an
          # entity that has just been erased, so this cannot assume a receiver.
          defn = e.respond_to?(:definition) ? e.definition : nil
          defn ? defn.name.to_s.strip : ''
        rescue StandardError
          ''
        end

        # Returns [type, number] or [nil, nil].
        def classify(name, tag = nil)
          PATTERNS.each do |type, re|
            m = name.to_s.strip.match(re)
            return [type, m[1]] if m
          end
          t = tag.to_s.upcase
          return [nil, nil] if t.empty?
          # Tag fallback. Prefab output Tags are excluded by the generated? filter
          # above, so only user placeholder Tags reach this point.
          return ['column',  nil] if t.include?('COLUMN')
          return ['wall',    nil] if t.include?('WALL')
          return ['floor',   nil] if t.include?('FLOOR')
          return ['roof',    nil] if t.include?('ROOF')
          return ['door',    nil] if t.include?('DOOR')
          return ['window',  nil] if t.include?('WINDOW') || t.include?('WINDOOW')
          return ['balcony', nil] if t.include?('BALCONY')
          return ['void',    nil] if t.include?('VOID') || t.include?('OPENING')
          [nil, nil]
        end

        # Convenience used by the generators when filtering a selection.
        def source_type(e)
          return nil if generated?(e)
          classify(source_name(e), tag_name(e)).first
        end
      end
    end
  end
end
