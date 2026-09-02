module KTSHung
  module PrefabStructureBuilder
    module Structure
      module FloorEngine
        module_function

        FLOOR_TYPES = {
          'GROUND_STEEL_CEMBOARD' => {
            label: 'Ground - Steel + Cemboard',
            primary: '100x100', secondary: '40x80', spacing: 500.0,
            finish: 'CEMBOARD', sheet_w: 1220.0, sheet_l: 2440.0, sheet_t: 16.0
          },
          'UPPER_DECK' => {
            label: 'Upper - Deck',
            primary: 'I200', secondary: 'I150', spacing: 1000.0,
            finish: 'DECK'
          },
          'UPPER_I_CEMBOARD' => {
            label: 'Upper - I + Cemboard',
            primary: 'I200', secondary: 'I150', spacing: 600.0,
            finish: 'CEMBOARD', sheet_w: 1220.0, sheet_l: 2440.0, sheet_t: 16.0
          },
          'BALCONY_WPC' => {
            label: 'Balcony - Steel + WPC',
            primary: '100x100', secondary: '40x80', spacing: 500.0,
            finish: 'WPC'
          }
        }.freeze

        def generate_from_selected(floor_type='GROUND_STEEL_CEMBOARD', primary=nil, secondary=nil, spacing=nil, direction='auto')
          model = Sketchup.active_model
          sources = model.selection.select do |e|
            %w[floor balcony].include?(Source::Scanner.source_type(e))
          end
          return ::UI.messagebox('Select FLOOR or BALCONY placeholder groups first.') if sources.empty?

          base = FLOOR_TYPES[floor_type] || FLOOR_TYPES['GROUND_STEEL_CEMBOARD']
          cfg = base.dup
          cfg[:primary] = primary.to_s unless primary.to_s.empty?
          cfg[:secondary] = secondary.to_s unless secondary.to_s.empty?
          cfg[:spacing] = spacing.to_f if spacing.to_f > 0
          cfg[:direction] = direction.to_s

          unless Framing::ProfileLibrary[cfg[:primary]] && Framing::ProfileLibrary[cfg[:secondary]]
            return ::UI.messagebox('Unknown primary/secondary steel profile.')
          end

          model.start_operation('Generate Floor System', true)
          Core::TagManager.ensure_tags!(model)
          sources.each { |src| generate_one(model, src, floor_type, cfg) }
          model.commit_operation
          true
        rescue => e
          model.abort_operation rescue nil
          ::UI.messagebox("Floor generation error: #{e.message}\n#{e.backtrace.first}")
          false
        end

        def source_name(e)
          Source::Scanner.source_name(e)
        end

        def generate_one(model, src, floor_type, cfg)
          bb = src.bounds
          xlen = bb.width
          ylen = bb.height
          z = bb.min.z
          return false if xlen.to_f <= Core::Units.mm(1) || ylen.to_f <= Core::Units.mm(1)

          parent = model.entities.add_group
          parent.name = "GEN_FLOOR_#{src.entityID}"
          parent.layer = Core::TagManager.tag(model, 'STRUCT_FLOOR')
          Core::Metadata.stamp(parent,
            type: 'floor', role: 'floor_system', floor_type: floor_type,
            source_id: src.entityID, parent_id: source_name(src), system: 'floor',
            primary: cfg[:primary], secondary: cfg[:secondary], spacing: cfg[:spacing]
          )

          secondary_axis = choose_secondary_axis(xlen, ylen, cfg[:direction])

          add_primary_perimeter(parent, bb, z, cfg[:primary])
          add_secondary_grid(parent, bb, z, cfg[:secondary], cfg[:spacing], secondary_axis)
          add_finish(parent, bb, z, cfg, floor_type)
          true
        end

        def choose_secondary_axis(xlen, ylen, direction)
          case direction.to_s.downcase
          when 'x' then :x
          when 'y' then :y
          else
            xlen <= ylen ? :x : :y
          end
        end

        def add_primary_perimeter(parent, bb, z, profile)
          # V0.3: perimeter primary frame. Column-to-column beam graph comes in connection/update phase.
          Framing::MemberFactory.add_profile_member(parent.entities, 'PRIMARY_X1', [bb.min.x, bb.min.y, z], bb.width, :x, profile,
            {type:'member', role:'primary_beam', system:'floor', parent_id:parent.entityID})
          Framing::MemberFactory.add_profile_member(parent.entities, 'PRIMARY_X2', [bb.min.x, bb.max.y, z], bb.width, :x, profile,
            {type:'member', role:'primary_beam', system:'floor', parent_id:parent.entityID})
          Framing::MemberFactory.add_profile_member(parent.entities, 'PRIMARY_Y1', [bb.min.x, bb.min.y, z], bb.height, :y, profile,
            {type:'member', role:'primary_beam', system:'floor', parent_id:parent.entityID})
          Framing::MemberFactory.add_profile_member(parent.entities, 'PRIMARY_Y2', [bb.max.x, bb.min.y, z], bb.height, :y, profile,
            {type:'member', role:'primary_beam', system:'floor', parent_id:parent.entityID})
        end

        def add_secondary_grid(parent, bb, z, profile, max_spacing_mm, axis)
          span = axis == :x ? bb.height : bb.width
          spacing = max_spacing_mm.to_f
          spacing = 500.0 if spacing <= 0
          count = [(Core::Units.to_mm(span) / spacing).ceil, 1].max
          step = span / count.to_f
          (1...count).each do |i|
            if axis == :x
              origin = [bb.min.x, bb.min.y + i * step, z]
              length = bb.width
            else
              origin = [bb.min.x + i * step, bb.min.y, z]
              length = bb.height
            end
            Framing::MemberFactory.add_profile_member(parent.entities, "SECONDARY_#{i}", origin, length, axis, profile,
              {type:'member', role:'secondary_beam', system:'floor', parent_id:parent.entityID, max_spacing:max_spacing_mm})
          end
        end

        def add_finish(parent, bb, z, cfg, floor_type)
          case cfg[:finish]
          when 'CEMBOARD'
            layout_sheets(parent, bb, z, cfg)
          when 'DECK'
            add_deck_surface(parent, bb, z, floor_type)
          when 'WPC'
            add_wpc_surface(parent, bb, z, floor_type)
          end
        end

        def layout_sheets(parent, bb, z, cfg)
          preset = choose_cemboard_preset(cfg)
          Materials::SheetLayout.create_rect_layout(
            parent.entities, [bb.min.x, bb.min.y, z],
            Core::Units.to_mm(bb.height), Core::Units.to_mm(bb.width), preset,
            role: 'floor_finish', system: 'floor', parent_id: parent.entityID
          )
        end

        def choose_cemboard_preset(cfg)
          w=cfg[:sheet_w].to_f; l=cfg[:sheet_l].to_f; t=cfg[:sheet_t].to_f
          match=Materials::MaterialLibrary.all.find do |_id,p|
            fam=(p[:family]||p['family']).to_s
            pw=(p[:stock_width]||p['stock_width']).to_f
            pl=(p[:stock_length]||p['stock_length']).to_f
            pt=(p[:thickness]||p['thickness']).to_f
            fam=='CEMBOARD' && (pw-w).abs<0.1 && (pl-l).abs<0.1 && (pt-t).abs<0.1
          end
          match ? match.first : 'CEMBOARD_1220_2440_16'
        end

        def add_deck_surface(parent, bb, z, _floor_type)
          add_flat_surface(parent, bb, z, 'STEEL_DECK', 'MAT_ROOF', 'MAT_DECK',
                           Sketchup::Color.new(150, 160, 170),
                           type: 'sheet', role: 'deck_surface', material: 'STEEL_DECK')
        end

        def add_wpc_surface(parent, bb, z, _floor_type)
          add_flat_surface(parent, bb, z, 'WPC_FINISH', 'MAT_WPC', 'MAT_WPC',
                           Sketchup::Color.new(140, 95, 60),
                           type: 'finish', role: 'balcony_finish', material: 'WPC')
        end

        def add_flat_surface(parent, bb, z, name, tag_name, mat_name, color, attrs)
          model = Sketchup.active_model
          mat = model.materials[mat_name]
          unless mat
            mat = model.materials.add(mat_name)
            mat.color = color
          end
          g = parent.entities.add_group
          g.name = name
          pts = [[bb.min.x, bb.min.y, z], [bb.max.x, bb.min.y, z],
                 [bb.max.x, bb.max.y, z], [bb.min.x, bb.max.y, z]].map { |a| Geom::Point3d.new(*a) }
          face = g.entities.add_face(pts)
          unless face
            g.erase! if g.valid?
            return nil
          end
          face.material = mat
          face.back_material = mat
          g.layer = Core::TagManager.tag(model, tag_name)
          Core::Metadata.stamp(g, attrs.merge(
            system: 'floor', parent_id: parent.entityID,
            actual_width: Core::Units.to_mm(bb.height),
            actual_length: Core::Units.to_mm(bb.width)))
          g
        end
      end
    end
  end
end
