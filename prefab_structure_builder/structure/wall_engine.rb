# encoding: UTF-8
module KTSHung
  module PrefabStructureBuilder
    module Structure
      module WallEngine
        DEFAULTS = {
          'AZ100'    => { 'frame' => '25x25', 'spacing' => 500.0, 'direction' => 'vertical',   'panel_width' => 400.0 },
          'NANO'     => { 'frame' => '25x25', 'spacing' => 500.0, 'direction' => 'horizontal', 'panel_width' => 400.0 },
          'PANEL100' => { 'frame' => nil,     'spacing' => 0.0,   'direction' => 'none',       'panel_width' => 1000.0 }
        }.freeze

        STUD = 25.0  # mm, nominal stud section
        MIN_THICKNESS = 100.0 # mm

        module_function

        def generate_from_selected(wall_type = 'AZ100', spacing = 500.0)
          model = Sketchup.active_model
          sources = model.selection.select { |e| Source::Scanner.source_type(e) == 'wall' }
          return ::UI.messagebox('Select WALL placeholder groups first.') if sources.empty?

          wall_type = 'AZ100' unless DEFAULTS.key?(wall_type.to_s)
          cfg = DEFAULTS[wall_type.to_s].dup
          cfg['spacing'] = spacing.to_f if spacing.to_f > 0

          model.start_operation('Generate Walls', true)
          Core::TagManager.ensure_tags!(model)
          sources.each { |src| generate_one(model, src, wall_type.to_s, cfg) }
          model.commit_operation
          true
        rescue => e
          model.abort_operation rescue nil
          ::UI.messagebox("Wall generation error: #{e.message}\n#{e.backtrace.first}")
          false
        end

        def source_name(e)
          Source::Scanner.source_name(e)
        end

        def generate_one(model, src, wall_type, cfg)
          bb = src.bounds
          xlen = bb.width
          ylen = bb.height
          zlen = bb.depth
          return false if zlen.to_f <= Core::Units.mm(1)

          axis = xlen >= ylen ? :x : :y
          length = axis == :x ? xlen : ylen
          thickness = [(axis == :x ? ylen : xlen).to_f, Core::Units.mm(MIN_THICKNESS)].max
          return false if length.to_f <= Core::Units.mm(1)

          parent = model.entities.add_group
          parent.name = "GEN_WALL_#{src.entityID}"
          parent.layer = Core::TagManager.tag(model, 'STRUCT_WALL')
          Core::Metadata.stamp(parent,
            type: 'wall', role: 'wall_system', wall_type: wall_type,
            source_id: src.entityID, parent_id: source_name(src), system: 'wall',
            spacing: cfg['spacing'], panel_width: cfg['panel_width'])

          add_framing(parent, bb, axis, length, thickness, zlen, cfg, src) if cfg['frame']
          create_panel_skin(parent, bb, axis, wall_type, cfg, src)
          true
        end

        def add_framing(parent, bb, axis, length, thickness, zlen, cfg, src)
          stud = Core::Units.mm(STUD)
          half = stud / 2.0
          web = [thickness, stud].max
          spacing = cfg['spacing'].to_f
          spacing = 500.0 if spacing <= 0
          min = bb.min
          attrs = { type: 'member', role: nil, source_id: src.entityID, system: 'wall', parent_id: parent.entityID }

          if cfg['direction'] == 'vertical'
            count = [(Core::Units.to_mm(length) / spacing).ceil, 1].max
            step = length / count.to_f
            (0..count).each do |i|
              pos = i * step
              a = attrs.merge(role: 'wall_stud')
              if axis == :x
                Framing::MemberFactory.add_box(parent.entities, "STUD_#{i}",
                                               [min.x + pos - half, min.y, min.z], stud, web, zlen, '25x25', a)
              else
                Framing::MemberFactory.add_box(parent.entities, "STUD_#{i}",
                                               [min.x, min.y + pos - half, min.z], web, stud, zlen, '25x25', a)
              end
            end
          else
            count = [(Core::Units.to_mm(zlen) / spacing).ceil, 1].max
            step = zlen / count.to_f
            (0..count).each do |i|
              z = min.z + i * step - half
              a = attrs.merge(role: 'wall_rail')
              if axis == :x
                Framing::MemberFactory.add_box(parent.entities, "RAIL_#{i}",
                                               [min.x, min.y, z], length, web, stud, '25x25', a)
              else
                Framing::MemberFactory.add_box(parent.entities, "RAIL_#{i}",
                                               [min.x, min.y, z], web, length, stud, '25x25', a)
              end
            end
          end
        end

        def create_panel_skin(parent, bb, axis, wall_type, cfg, src)
          model = Sketchup.active_model
          mat_name = wall_type == 'NANO' ? 'MAT_NANO' : 'MAT_PANEL'
          mat = model.materials[mat_name]
          unless mat
            mat = model.materials.add(mat_name)
            mat.color = Sketchup::Color.new(220, 220, 220)
          end
          length = axis == :x ? bb.width : bb.height
          pw = Core::Units.mm(cfg['panel_width'].to_f)
          return if pw <= 0 || length.to_f <= 0
          n = [(length / pw).ceil, 1].max
          step = length / n.to_f

          n.times do |i|
            g = parent.entities.add_group
            g.name = "#{wall_type}_PANEL_#{i + 1}"
            pts = if axis == :x
                    [[bb.min.x + i * step, bb.min.y, bb.min.z],
                     [bb.min.x + (i + 1) * step, bb.min.y, bb.min.z],
                     [bb.min.x + (i + 1) * step, bb.min.y, bb.max.z],
                     [bb.min.x + i * step, bb.min.y, bb.max.z]]
                  else
                    [[bb.min.x, bb.min.y + i * step, bb.min.z],
                     [bb.min.x, bb.min.y + (i + 1) * step, bb.min.z],
                     [bb.min.x, bb.min.y + (i + 1) * step, bb.max.z],
                     [bb.min.x, bb.min.y + i * step, bb.max.z]]
                  end
            face = g.entities.add_face(pts.map { |a| Geom::Point3d.new(*a) })
            unless face
              g.erase! if g.valid?
              next
            end
            face.material = mat
            face.back_material = mat
            g.layer = Core::TagManager.tag(model, mat_name)
            Core::Metadata.stamp(g,
              type: 'panel', role: 'wall_finish', material: wall_type,
              actual_width: Core::Units.to_mm(step), actual_length: Core::Units.to_mm(bb.depth),
              source_id: src.entityID, parent_id: parent.entityID, system: 'wall')
          end
        end
      end
    end
  end
end
