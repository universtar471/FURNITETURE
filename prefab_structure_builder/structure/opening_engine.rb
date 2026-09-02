# encoding: UTF-8
module KTSHung
  module PrefabStructureBuilder
    module Structure
      module OpeningEngine
        module_function

        def scan_types
          rows = Source::Scanner.scan.select { |r| %w[door window].include?(r[:type]) }
          saved = Core::ProjectStore.opening_types
          rows.map do |r|
            d = saved[r[:name]] || {}
            defaults = if r[:type] == 'door'
                         { 'width' => 900, 'height' => 2200, 'sill' => 0 }
                       else
                         { 'width' => 1200, 'height' => 1400, 'sill' => 900 }
                       end
            loc = d['location'] || 'exterior'
            frame = d['frame'] || (loc == 'exterior' ? '40x80' : '50x100')
            frame = Rules::RuleEngine.valid_profile(frame, loc == 'exterior' ? '40x80' : '50x100')
            r.merge(config: defaults.merge(d).merge('location' => loc, 'frame' => frame))
          end
        end

        def save_types(json)
          data = JSON.parse(json.to_s)
          raise 'Opening table must be a JSON object.' unless data.is_a?(Hash)
          Core::ProjectStore.save_opening_types(data)
          true
        rescue => e
          ::UI.messagebox("Opening data error: #{e.message}")
          false
        end

        def generate_all
          model = Sketchup.active_model
          types = scan_types
          return ::UI.messagebox('No DOOR/WINDOW source groups found.') if types.empty?

          model.start_operation('Generate Openings', true)
          Core::TagManager.ensure_tags!(model)
          made = 0
          types.each do |row|
            row[:entity_ids].each do |id|
              src = model.find_entity_by_id(id)
              next unless src && src.valid?
              made += 1 if generate_one(model, src, row[:type], row[:name], row[:config])
            end
          end
          model.commit_operation
          ::UI.messagebox('No opening frames could be built. Check the type table dimensions.') if made.zero?
          true
        rescue => e
          model.abort_operation rescue nil
          ::UI.messagebox("Opening generation error: #{e.message}\n#{e.backtrace.first}")
          false
        end

        # Frame section: +along+ is the width consumed alongside the opening,
        # +depth+ is how far the frame reaches through the wall.
        def frame_section(profile)
          p = Framing::ProfileLibrary[profile] || Framing::ProfileLibrary['40x80']
          # RHS profiles carry :w/:h, I profiles carry :b/:h. The original code
          # did [p[:h] || 80, 80].to_f, and Array has no #to_f.
          along = (p[:w] || p[:b] || 40).to_f
          depth = [(p[:h] || 80).to_f, 80.0].max
          [Core::Units.mm(along), Core::Units.mm(depth)]
        end

        def generate_one(model, src, type, type_name, cfg)
          bb = src.bounds
          c = bb.center
          wall = find_host_wall(model, c)
          wbb = wall ? wall.bounds : bb
          axis = wbb.width >= wbb.height ? :x : :y

          clear_w = Core::Units.mm(cfg['width'].to_f)
          clear_h = Core::Units.mm(cfg['height'].to_f)
          sill    = Core::Units.mm(cfg['sill'].to_f)
          return false if clear_w <= 0 || clear_h <= 0

          profile = cfg['frame'].to_s
          profile = '40x80' unless Framing::ProfileLibrary[profile]
          along, depth = frame_section(profile)

          z0 = wbb.min.z
          z1 = wbb.max.z
          opening_bottom = type == 'door' ? z0 : z0 + sill
          opening_top = opening_bottom + clear_h

          parent = model.entities.add_group
          parent.name = "GEN_#{type_name.to_s.gsub(/\s+/, '_')}_#{src.entityID}"
          parent.layer = Core::TagManager.tag(model, 'OPENING')
          Core::Metadata.stamp(parent,
            type: type, role: 'opening_frame', source_id: src.entityID, parent_id: type_name.to_s,
            system: 'opening', clear_width: cfg['width'], clear_height: cfg['height'],
            sill: cfg['sill'], location: cfg['location'], frame_profile: profile)

          member_attrs = { system: 'opening', source_id: src.entityID, parent_id: parent.entityID }
          height = z1 - z0

          if axis == :x
            y = wbb.min.y
            left_x  = c.x - clear_w / 2 - along
            right_x = c.x + clear_w / 2
            Framing::MemberFactory.add_box(parent.entities, 'LEFT_JAMB', [left_x, y, z0], along, depth, height, profile,
                                           member_attrs.merge(type: 'member', role: 'opening_jamb'))
            Framing::MemberFactory.add_box(parent.entities, 'RIGHT_JAMB', [right_x, y, z0], along, depth, height, profile,
                                           member_attrs.merge(type: 'member', role: 'opening_jamb'))
            Framing::MemberFactory.add_box(parent.entities, 'HEADER', [c.x - clear_w / 2, y, opening_top], clear_w, depth, along, profile,
                                           member_attrs.merge(type: 'member', role: 'opening_header'))
            if type == 'window'
              Framing::MemberFactory.add_box(parent.entities, 'SILL', [c.x - clear_w / 2, y, opening_bottom - along], clear_w, depth, along, profile,
                                             member_attrs.merge(type: 'member', role: 'opening_sill'))
            end
          else
            x = wbb.min.x
            left_y  = c.y - clear_w / 2 - along
            right_y = c.y + clear_w / 2
            Framing::MemberFactory.add_box(parent.entities, 'LEFT_JAMB', [x, left_y, z0], depth, along, height, profile,
                                           member_attrs.merge(type: 'member', role: 'opening_jamb'))
            Framing::MemberFactory.add_box(parent.entities, 'RIGHT_JAMB', [x, right_y, z0], depth, along, height, profile,
                                           member_attrs.merge(type: 'member', role: 'opening_jamb'))
            Framing::MemberFactory.add_box(parent.entities, 'HEADER', [x, c.y - clear_w / 2, opening_top], depth, clear_w, along, profile,
                                           member_attrs.merge(type: 'member', role: 'opening_header'))
            if type == 'window'
              Framing::MemberFactory.add_box(parent.entities, 'SILL', [x, c.y - clear_w / 2, opening_bottom - along], depth, clear_w, along, profile,
                                             member_attrs.merge(type: 'member', role: 'opening_sill'))
            end
          end
          true
        end

        def find_host_wall(model, point)
          walls = Source::Scanner.recognized_entities(model, true)
                                 .select { |r| r[:type] == 'wall' }
                                 .map { |r| r[:entity] }
          return nil if walls.empty?
          walls.min_by do |w|
            bb = w.bounds
            dx = [bb.min.x - point.x, 0, point.x - bb.max.x].max
            dy = [bb.min.y - point.y, 0, point.y - bb.max.y].max
            dz = [bb.min.z - point.z, 0, point.z - bb.max.z].max
            Math.sqrt(dx.to_f**2 + dy.to_f**2 + dz.to_f**2)
          end
        end
      end
    end
  end
end
