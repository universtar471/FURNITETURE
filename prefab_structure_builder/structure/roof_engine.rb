module KTSHung
  module PrefabStructureBuilder
    module Structure
      module RoofEngine
        module_function

        DEFAULTS = {
          'MONO' => { high: 1200.0, low: 300.0, ridge: 1200.0 },
          'GABLE' => { high: 1200.0, low: 300.0, ridge: 1200.0 },
          'HIP_FACES' => { high: 1200.0, low: 300.0, ridge: 1200.0 }
        }.freeze

        def generate_from_selected(roof_type='MONO', high=1200.0, low=300.0, ridge=1200.0,
                                   ridge_pos=50.0, direction='x+', front=600.0, back=600.0,
                                   left=600.0, right=600.0, spacing=1000.0,
                                   cover='CORRUGATED', soffit=true)
          model = Sketchup.active_model
          sources = model.selection.select { |e| Source::Scanner.source_type(e) == 'roof' }
          return ::UI.messagebox('Select ROOF placeholder group(s) first.') if sources.empty?

          cfg = {
            type: roof_type.to_s.upcase,
            high: high.to_f,
            low: low.to_f,
            ridge: ridge.to_f,
            ridge_pos: [[ridge_pos.to_f, 5.0].max, 95.0].min,
            direction: direction.to_s.downcase,
            overhang: {front: front.to_f, back: back.to_f, left: left.to_f, right: right.to_f},
            spacing: spacing.to_f > 0 ? spacing.to_f : 1000.0,
            cover: cover.to_s.upcase,
            soffit: !!soffit
          }

          model.start_operation('Generate Roof System', true)
          Core::TagManager.ensure_tags!(model)
          sources.each { |src| generate_one(model, src, cfg) }
          model.commit_operation
          true
        rescue => e
          model.abort_operation rescue nil
          ::UI.messagebox("Roof generation error: #{e.message}\n#{e.backtrace.first}")
          false
        end

        def source_name(e)
          Source::Scanner.source_name(e)
        end

        def generate_one(model, src, cfg)
          parent = model.entities.add_group
          parent.name = "GEN_ROOF_#{src.entityID}"
          parent.layer = Core::TagManager.tag(model, 'STRUCT_ROOF')
          Core::Metadata.stamp(parent,
            type:'roof', role:'roof_system', system:'roof', source_id:src.entityID,
            parent_id:source_name(src), roof_type:cfg[:type], direction:cfg[:direction],
            secondary_spacing:cfg[:spacing], cover:cfg[:cover]
          )

          if cfg[:type] == 'HIP_FACES'
            generate_from_faces(parent, src, cfg)
          elsif cfg[:type] == 'GABLE'
            generate_gable(parent, src.bounds, cfg)
          else
            generate_mono(parent, src.bounds, cfg)
          end
        end

        def expanded_rect(bb, cfg)
          oh = cfg[:overhang]
          # Front/back are -Y/+Y, left/right are -X/+X in the global plan.
          {
            xmin: bb.min.x - Core::Units.mm(oh[:left]),
            xmax: bb.max.x + Core::Units.mm(oh[:right]),
            ymin: bb.min.y - Core::Units.mm(oh[:front]),
            ymax: bb.max.y + Core::Units.mm(oh[:back]),
            base_z: bb.min.z
          }
        end

        def generate_mono(parent, bb, cfg)
          r = expanded_rect(bb, cfg)
          slope_axis, high_at_max = parse_direction(cfg[:direction])
          low_z = r[:base_z] + Core::Units.mm(cfg[:low])
          high_z = r[:base_z] + Core::Units.mm(cfg[:high])
          corners = rect_corners_with_z(r) do |x,y|
            t = slope_axis == :x ? fraction(x, r[:xmin], r[:xmax]) : fraction(y, r[:ymin], r[:ymax])
            t = 1.0 - t unless high_at_max
            low_z + (high_z - low_z) * t
          end

          add_perimeter(parent, corners)
          add_mono_main_frames(parent, bb, r, cfg, slope_axis, high_at_max, low_z, high_z)
          add_mono_secondary(parent, r, cfg, slope_axis, high_at_max, low_z, high_z)
          add_surface(parent, corners, cfg[:cover], 'ROOF_COVER')
          add_surface(parent, corners, 'NANO', 'ROOF_SOFFIT', -Core::Units.mm(25)) if cfg[:soffit]
          add_roof_wall_columns(parent, bb, cfg, slope_axis, high_at_max, low_z, high_z)
        end

        def generate_gable(parent, bb, cfg)
          r = expanded_rect(bb, cfg)
          ridge_axis = %w[x+ x-].include?(cfg[:direction]) ? :y : :x
          cross_axis = ridge_axis == :x ? :y : :x
          low_z = r[:base_z] + Core::Units.mm(cfg[:low])
          ridge_z = r[:base_z] + Core::Units.mm(cfg[:ridge])
          ridge_fraction = cfg[:ridge_pos] / 100.0
          cross_min = cross_axis == :x ? r[:xmin] : r[:ymin]
          cross_max = cross_axis == :x ? r[:xmax] : r[:ymax]
          ridge_c = cross_min + (cross_max - cross_min) * ridge_fraction

          zfun = lambda do |x,y|
            c = cross_axis == :x ? x : y
            if c <= ridge_c
              t = fraction(c, cross_min, ridge_c)
              low_z + (ridge_z - low_z) * t
            else
              t = fraction(c, ridge_c, cross_max)
              ridge_z + (low_z - ridge_z) * t
            end
          end

          corners = rect_corners_with_z(r, &zfun)
          add_perimeter(parent, corners)
          ridge_p1, ridge_p2 = if ridge_axis == :x
                                [[r[:xmin], ridge_c, ridge_z], [r[:xmax], ridge_c, ridge_z]]
                              else
                                [[ridge_c, r[:ymin], ridge_z], [ridge_c, r[:ymax], ridge_z]]
                              end
          add_between(parent, 'RIDGE_50x100', ridge_p1, ridge_p2, '50x100', 'ridge')

          add_gable_main_frames(parent, bb, r, cfg, ridge_axis, cross_axis, ridge_c, low_z, ridge_z)
          add_gable_secondary(parent, r, cfg, ridge_axis, cross_axis, ridge_c, low_z, ridge_z)

          # Split cover into two planes to keep proper gable geometry.
          if ridge_axis == :x
            left_plane = [[r[:xmin],r[:ymin],low_z],[r[:xmax],r[:ymin],low_z],ridge_p2,ridge_p1]
            right_plane = [ridge_p1,ridge_p2,[r[:xmax],r[:ymax],low_z],[r[:xmin],r[:ymax],low_z]]
          else
            left_plane = [[r[:xmin],r[:ymin],low_z],ridge_p1,ridge_p2,[r[:xmin],r[:ymax],low_z]]
            right_plane = [ridge_p1,[r[:xmax],r[:ymin],low_z],[r[:xmax],r[:ymax],low_z],ridge_p2]
          end
          add_surface(parent, left_plane, cfg[:cover], 'ROOF_COVER_A')
          add_surface(parent, right_plane, cfg[:cover], 'ROOF_COVER_B')
          if cfg[:soffit]
            add_surface(parent, left_plane, 'NANO', 'ROOF_SOFFIT_A', -Core::Units.mm(25))
            add_surface(parent, right_plane, 'NANO', 'ROOF_SOFFIT_B', -Core::Units.mm(25))
          end
          add_roof_wall_columns_gable(parent, bb, cfg, ridge_axis, cross_axis, ridge_c, low_z, ridge_z)
        end

        def generate_from_faces(parent, src, cfg)
          faces, tr = source_faces_and_transform(src)
          if faces.empty?
            # Raising here would roll back the whole operation for a multi-roof
            # selection, so this reports and leaves the other roofs intact.
            warn('[Prefab Structure Builder] ROOF From Faces: no faces inside the selected ROOF group.')
            return nil
          end

          edge_seen = {}
          faces.each do |face|
            pts = face.outer_loop.vertices.map { |v| v.position.transform(tr) }
            next if pts.length < 3
            add_surface(parent, pts.map{|p| [p.x,p.y,p.z]}, cfg[:cover], 'ROOF_COVER_FACE')
            add_surface(parent, pts.map { |p| [p.x, p.y, p.z] }, 'NANO', 'ROOF_SOFFIT_FACE', -Core::Units.mm(25)) if cfg[:soffit]
            face.outer_loop.edges.each do |edge|
              a = edge.start.position.transform(tr); b = edge.end.position.transform(tr)
              key = [[a.x,a.y,a.z],[b.x,b.y,b.z]].sort_by{|p| p.join(',')}.flatten.join('|')
              next if edge_seen[key]
              edge_seen[key] = true
              add_between(parent, 'ROOF_EDGE_50x100', a, b, '50x100', 'roof_edge')
            end
            add_face_secondary(parent, pts, cfg[:spacing])
          end
        end

        def source_faces_and_transform(src)
          if src.is_a?(Sketchup::Group)
            [src.entities.grep(Sketchup::Face), src.transformation]
          else
            [src.definition.entities.grep(Sketchup::Face), src.transformation]
          end
        end

        def add_perimeter(parent, corners)
          corners.each_with_index do |p,i|
            q = corners[(i+1) % corners.length]
            add_between(parent, "PERIMETER_#{i+1}", p, q, '50x100', 'perimeter_beam')
          end
        end

        def add_mono_main_frames(parent, source_bb, r, cfg, slope_axis, high_at_max, low_z, high_z)
          cols = structural_column_centers(source_bb)
          transverse_axis = slope_axis == :x ? :y : :x
          coords = cols.map{|p| transverse_axis == :x ? p.x : p.y}.uniq
          coords = [transverse_axis == :x ? source_bb.center.x : source_bb.center.y] if coords.empty?
          coords.each_with_index do |c,i|
            if slope_axis == :x
              p1=[r[:xmin],c, roof_z_mono(r[:xmin], r, slope_axis, high_at_max, low_z, high_z)]
              p2=[r[:xmax],c, roof_z_mono(r[:xmax], r, slope_axis, high_at_max, low_z, high_z)]
            else
              p1=[c,r[:ymin], roof_z_mono(r[:ymin], r, slope_axis, high_at_max, low_z, high_z)]
              p2=[c,r[:ymax], roof_z_mono(r[:ymax], r, slope_axis, high_at_max, low_z, high_z)]
            end
            add_between(parent,"MAIN_#{i+1}",p1,p2,'50x100','main_roof_frame')
          end
        end

        def add_mono_secondary(parent, r, cfg, slope_axis, high_at_max, low_z, high_z)
          span = slope_axis == :x ? (r[:xmax] - r[:xmin]) : (r[:ymax] - r[:ymin])
          count = [(Core::Units.to_mm(span) / spacing_of(cfg)).ceil, 1].max
          step = span / count.to_f
          (1...count).each do |i|
            if slope_axis == :x
              x = r[:xmin] + i*step; z = roof_z_mono(x,r,slope_axis,high_at_max,low_z,high_z)
              add_between(parent,"SECONDARY_#{i}",[x,r[:ymin],z],[x,r[:ymax],z],'30x60','secondary_roof_frame')
            else
              y = r[:ymin] + i*step; z = roof_z_mono(y,r,slope_axis,high_at_max,low_z,high_z)
              add_between(parent,"SECONDARY_#{i}",[r[:xmin],y,z],[r[:xmax],y,z],'30x60','secondary_roof_frame')
            end
          end
        end

        def add_gable_main_frames(parent, source_bb, r, cfg, ridge_axis, cross_axis, ridge_c, low_z, ridge_z)
          cols = structural_column_centers(source_bb)
          along_axis = ridge_axis
          coords = cols.map{|p| along_axis == :x ? p.x : p.y}.uniq
          coords = [along_axis == :x ? source_bb.center.x : source_bb.center.y] if coords.empty?
          coords.each_with_index do |c,i|
            if ridge_axis == :x
              add_between(parent,"MAIN_L_#{i+1}",[c,r[:ymin],low_z],[c,ridge_c,ridge_z],'50x100','main_roof_frame')
              add_between(parent,"MAIN_R_#{i+1}",[c,ridge_c,ridge_z],[c,r[:ymax],low_z],'50x100','main_roof_frame')
            else
              add_between(parent,"MAIN_L_#{i+1}",[r[:xmin],c,low_z],[ridge_c,c,ridge_z],'50x100','main_roof_frame')
              add_between(parent,"MAIN_R_#{i+1}",[ridge_c,c,ridge_z],[r[:xmax],c,low_z],'50x100','main_roof_frame')
            end
          end
        end

        def add_gable_secondary(parent, r, cfg, ridge_axis, cross_axis, ridge_c, low_z, ridge_z)
          cross_min = cross_axis == :x ? r[:xmin] : r[:ymin]
          cross_max = cross_axis == :x ? r[:xmax] : r[:ymax]
          [[cross_min,ridge_c,'A'],[ridge_c,cross_max,'B']].each do |a,b,label|
            span = b - a
            count = [(Core::Units.to_mm(span) / spacing_of(cfg)).ceil, 1].max
            step = span / count.to_f
            (1...count).each do |i|
              c=a+i*step
              t = label=='A' ? fraction(c,cross_min,ridge_c) : fraction(c,ridge_c,cross_max)
              z = label=='A' ? low_z+(ridge_z-low_z)*t : ridge_z+(low_z-ridge_z)*t
              if ridge_axis == :x
                add_between(parent,"SECONDARY_#{label}_#{i}",[r[:xmin],c,z],[r[:xmax],c,z],'30x60','secondary_roof_frame')
              else
                add_between(parent,"SECONDARY_#{label}_#{i}",[c,r[:ymin],z],[c,r[:ymax],z],'30x60','secondary_roof_frame')
              end
            end
          end
        end

        def spacing_of(cfg)
          s = cfg[:spacing].to_f
          s > 0 ? s : 1000.0
        end

        def add_face_secondary(parent, pts, max_spacing_mm)
          return if pts.length < 3
          # Work in XY. Contour lines (roughly horizontal on a roof plane) become 30x60 purlins.
          n = polygon_normal(pts)
          return if n.length.to_f < 1.0e-9 || n.z.abs < 1.0e-9
          slope = Geom::Vector3d.new(n.x, n.y, 0)
          return if slope.length < 1.0e-6
          slope.normalize!
          tangent = Geom::Vector3d.new(-slope.y, slope.x, 0)
          projections = pts.map{|p| p.x*slope.x + p.y*slope.y}
          minp,maxp=projections.minmax
          span=maxp-minp
          spacing = max_spacing_mm.to_f
          spacing = 1000.0 if spacing <= 0
          count = [(Core::Units.to_mm(span) / spacing).ceil, 1].max
          step = span / count.to_f
          (1...count).each do |i|
            d=minp+i*step
            ints=[]
            pts.each_with_index do |a,j|
              b=pts[(j+1)%pts.length]
              da=a.x*slope.x+a.y*slope.y-d
              db=b.x*slope.x+b.y*slope.y-d
              next if da.abs < 1e-9 && db.abs < 1e-9
              next if da*db > 0
              denom=da-db
              next if denom.abs < 1e-9
              t=da/denom
              next if t < -1e-6 || t > 1.0+1e-6
              ints << Geom::Point3d.new(a.x+(b.x-a.x)*t, a.y+(b.y-a.y)*t, a.z+(b.z-a.z)*t)
            end
            ints.uniq!{|p| [p.x.round(6),p.y.round(6),p.z.round(6)]}
            next if ints.length < 2
            pair=ints.combination(2).max_by{|a,b| a.distance(b)}
            add_between(parent,"FACE_SECONDARY_#{i}",pair[0],pair[1],'30x60','secondary_roof_frame') if pair
          end
        end

        def polygon_normal(pts)
          n=Geom::Vector3d.new(0,0,0)
          pts.each_with_index do |p,i|
            q=pts[(i+1)%pts.length]
            n.x += (p.y-q.y)*(p.z+q.z)
            n.y += (p.z-q.z)*(p.x+q.x)
            n.z += (p.x-q.x)*(p.y+q.y)
          end
          n
        end

        def add_roof_wall_columns(parent, bb, cfg, slope_axis, high_at_max, low_z, high_z)
          structural_column_centers(bb).each_with_index do |p,i|
            roofz = roof_z_mono(slope_axis==:x ? p.x : p.y, expanded_rect(bb,cfg), slope_axis, high_at_max, low_z, high_z)
            h = roofz - bb.max.z
            next if h.to_f <= Core::Units.mm(10)
            Framing::MemberFactory.add_profile_member(parent.entities,"ROOF_COLUMN_#{i+1}",[p.x,p.y,bb.max.z],h,:z,'100x100',
              {type:'member',role:'roof_column',system:'roof',parent_id:parent.entityID})
          end
        end

        def add_roof_wall_columns_gable(parent, bb, cfg, ridge_axis, cross_axis, ridge_c, low_z, ridge_z)
          r=expanded_rect(bb,cfg)
          cross_min=cross_axis==:x ? r[:xmin] : r[:ymin]
          cross_max=cross_axis==:x ? r[:xmax] : r[:ymax]
          structural_column_centers(bb).each_with_index do |p,i|
            c=cross_axis==:x ? p.x : p.y
            z = if c <= ridge_c
                  low_z+(ridge_z-low_z)*fraction(c,cross_min,ridge_c)
                else
                  ridge_z+(low_z-ridge_z)*fraction(c,ridge_c,cross_max)
                end
            h = z - bb.max.z
            next if h.to_f <= Core::Units.mm(10)
            Framing::MemberFactory.add_profile_member(parent.entities,"ROOF_COLUMN_#{i+1}",[p.x,p.y,bb.max.z],h,:z,'100x100',
              {type:'member',role:'roof_column',system:'roof',parent_id:parent.entityID})
          end
        end

        def structural_column_centers(bb)
          model=Sketchup.active_model
          pts=[]
          model.entities.each do |e|
            next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
            next unless Source::Scanner.source_type(e) == 'column'
            c = e.bounds.center
            tol = Core::Units.mm(5)
            if c.x >= bb.min.x - tol && c.x <= bb.max.x + tol && c.y >= bb.min.y - tol && c.y <= bb.max.y + tol
              pts << c
            end
          end
          pts
        end

        def add_between(parent, name, a, b, profile, role)
          p1 = a.is_a?(Geom::Point3d) ? a : Geom::Point3d.new(*a)
          p2 = b.is_a?(Geom::Point3d) ? b : Geom::Point3d.new(*b)
          return if p1.distance(p2).to_f < Core::Units.mm(1)
          Framing::MemberFactory.add_member_between(parent.entities,name,p1,p2,profile,
            {type:'member',role:role,system:'roof',parent_id:parent.entityID})
        end

        def add_surface(parent, points, material_key, name, z_offset=0)
          model=Sketchup.active_model
          g=parent.entities.add_group
          g.name=name
          pts=points.map do |p|
            q=p.is_a?(Geom::Point3d) ? p : Geom::Point3d.new(*p)
            Geom::Point3d.new(q.x,q.y,q.z+z_offset)
          end
          face=g.entities.add_face(pts)
          return g unless face
          tag_name = material_key == 'NANO' ? 'MAT_NANO' : 'MAT_ROOF'
          g.layer = Core::TagManager.tag(model, tag_name)
          mat_name="MAT_#{material_key}"
          mat=model.materials[mat_name] || model.materials.add(mat_name)
          mat.color = case material_key
                      when 'NANO' then Sketchup::Color.new(215,205,185)
                      when 'TILE' then Sketchup::Color.new(115,70,55)
                      else Sketchup::Color.new(125,135,145)
                      end
          face.material=mat; face.back_material=mat
          Core::Metadata.stamp(g,type:'sheet',role:name.downcase,system:'roof',material:material_key,parent_id:parent.entityID)
          g
        end

        def rect_corners_with_z(r)
          [[r[:xmin],r[:ymin]],[r[:xmax],r[:ymin]],[r[:xmax],r[:ymax]],[r[:xmin],r[:ymax]]].map do |x,y|
            [x,y,yield(x,y)]
          end
        end

        def parse_direction(direction)
          case direction
          when 'x-' then [:x,false]
          when 'y+' then [:y,true]
          when 'y-' then [:y,false]
          else [:x,true]
          end
        end

        def roof_z_mono(coord, r, slope_axis, high_at_max, low_z, high_z)
          minv=slope_axis==:x ? r[:xmin] : r[:ymin]
          maxv=slope_axis==:x ? r[:xmax] : r[:ymax]
          t=fraction(coord,minv,maxv)
          t=1.0-t unless high_at_max
          low_z+(high_z-low_z)*t
        end

        def fraction(v,a,b)
          return 0.0 if (b-a).abs < 1.0e-9
          [[(v-a)/(b-a),0.0].max,1.0].min
        end
      end
    end
  end
end
