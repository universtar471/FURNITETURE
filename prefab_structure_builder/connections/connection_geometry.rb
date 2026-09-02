module KTSHung
  module PrefabStructureBuilder
    module Connections
      module ConnectionGeometry
        module_function

        PLATE_COLOR = [105, 110, 118].freeze
        BOLT_COLOR  = [45, 45, 48].freeze
        WELD_COLOR  = [225, 135, 45].freeze

        def ensure_material(model, name, rgb)
          mat = model.materials[name] || model.materials.add(name)
          mat.color = Sketchup::Color.new(*rgb)
          mat
        end

        # Axis indicates plate normal. Dimensions are world-friendly conceptual geometry,
        # intentionally parametric so fabrication values can replace them later.
        def add_plate(parent_ents, name, center, width_mm=160.0, height_mm=220.0, thickness_mm=10.0, axis=:x, attrs={})
          model = Sketchup.active_model
          c = point(center)
          w = Core::Units.mm(width_mm)
          h = Core::Units.mm(height_mm)
          t = Core::Units.mm(thickness_mm)
          return nil if w <= 0 || h <= 0 || t <= 0
          g = parent_ents.add_group
          g.name = name

          case axis.to_sym
          when :y
            add_box_geometry(g.entities, -w/2, -t/2, -h/2, w, t, h)
          when :z
            add_box_geometry(g.entities, -w/2, -h/2, -t/2, w, h, t)
          else
            add_box_geometry(g.entities, -t/2, -w/2, -h/2, t, w, h)
          end

          g.transform!(Geom::Transformation.translation(c))
          g.layer = Core::TagManager.tag(model, 'CONN_PLATE')
          g.material = ensure_material(model, 'CONN_PLATE', PLATE_COLOR)
          Core::Metadata.stamp(g, attrs.merge(type:'connection_part', role:'plate', plate_width:width_mm.to_f, plate_height:height_mm.to_f, plate_thickness:thickness_mm.to_f, plate_axis:axis.to_s))
          g
        end

        def add_bolt_group(parent_ents, center, axis=:x, rows=4, cols=2, spacing_x_mm=55.0, spacing_z_mm=55.0, diameter_mm=16.0, length_mm=32.0, attrs={})
          c = point(center)
          model = Sketchup.active_model
          holder = parent_ents.add_group
          holder.name = 'BOLT_GROUP'
          holder.layer = Core::TagManager.tag(model, 'CONN_BOLT')
          holder.material = ensure_material(model, 'CONN_BOLT', BOLT_COLOR)
          rows = [rows.to_i, 1].max
          cols = [cols.to_i, 1].max
          sx = Core::Units.mm(spacing_x_mm)
          sz = Core::Units.mm(spacing_z_mm)
          r0 = (rows - 1) / 2.0
          c0 = (cols - 1) / 2.0
          rows.times do |ri|
            cols.times do |ci|
              a = (ci - c0) * sx
              b = (ri - r0) * sz
              offset = case axis.to_sym
                       when :y then Geom::Vector3d.new(a, 0, b)
                       when :z then Geom::Vector3d.new(a, b, 0)
                       else Geom::Vector3d.new(0, a, b)
                       end
              add_bolt(holder.entities, c + offset, axis, diameter_mm, length_mm)
            end
          end
          Core::Metadata.stamp(holder, attrs.merge(type:'connection_part', role:'bolt_group', bolt_rows:rows, bolt_cols:cols, bolt_diameter:diameter_mm.to_f))
          holder
        end

        def add_weld_marker(parent_ents, center, axis=:z, size_mm=55.0, attrs={})
          model = Sketchup.active_model
          c = point(center)
          s = Core::Units.mm(size_mm)
          return nil if s <= 0
          g = parent_ents.add_group
          g.name = 'WELD_DIRECT'
          # Small triangular prism serves as a visible conceptual weld marker.
          pts = [[0, 0, 0], [s, 0, 0], [0, s, 0]].map { |p| Geom::Point3d.new(*p) }
          f = g.entities.add_face(pts)
          unless f
            g.erase! if g.valid?
            return nil
          end
          Framing::MemberFactory.extrude(f, [s * 0.18, Core::Units.mm(2)].max)
          g.transform!(Geom::Transformation.translation([c.x - s / 2, c.y - s / 2, c.z]))
          g.layer = Core::TagManager.tag(model, 'CONN_WELD')
          g.material = ensure_material(model, 'CONN_WELD', WELD_COLOR)
          Core::Metadata.stamp(g, attrs.merge(type:'connection_part', role:'weld_marker', weld_type:'direct', weld_axis:axis.to_s))
          g
        end

        def add_box_geometry(ents, x, y, z, sx, sy, sz)
          pts = [[x, y, z], [x + sx, y, z], [x + sx, y + sy, z], [x, y + sy, z]].map { |p| Geom::Point3d.new(*p) }
          face = ents.add_face(pts)
          return nil unless face
          Framing::MemberFactory.extrude(face, sz)
          face
        end

        # Each bolt goes into its own group. Sharing one entities collection let
        # neighbouring bolt cylinders merge into each other's geometry.
        def add_bolt(ents, center, axis, diameter_mm, length_mm)
          c = point(center)
          radius = Core::Units.mm(diameter_mm) / 2.0
          length = Core::Units.mm(length_mm)
          return nil if radius <= 0 || length <= 0
          normal = case axis.to_sym
                   when :y then Y_AXIS
                   when :z then Z_AXIS
                   else X_AXIS
                   end
          g = ents.add_group
          g.name = 'BOLT'
          start = c.offset(normal.reverse, length / 2.0)
          edges = g.entities.add_circle(start, normal, radius, 12)
          face = edges ? g.entities.add_face(edges) : nil
          unless face
            g.erase! if g.valid?
            return nil
          end
          # The circle normal decides the extrusion sign, not the world Z axis.
          face.pushpull(face.normal.dot(normal) < 0 ? -length : length)
          g
        end

        def point(value)
          value.is_a?(Geom::Point3d) ? value : Geom::Point3d.new(*value)
        end
      end
    end
  end
end
