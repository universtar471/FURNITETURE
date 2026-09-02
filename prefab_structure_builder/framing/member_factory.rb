# encoding: UTF-8
module KTSHung
  module PrefabStructureBuilder
    module Framing
      # Builds steel members as groups. Every profile is drawn in local XY,
      # centred on the local origin, and extruded along local +Z. Placement is
      # then a single transformation, which keeps orientation logic in one place.
      module MemberFactory
        MIN_LENGTH = 1.0e-6

        module_function

        def material_for(model, profile_name)
          p = ProfileLibrary[profile_name]
          return nil unless p
          mat = model.materials[p[:tag]]
          unless mat
            mat = model.materials.add(p[:tag])
            mat.color = Sketchup::Color.new(*p[:color])
          end
          mat
        end

        # Axis-aligned box helper for stud/rail/jamb framing where a full
        # profile section adds no value.
        def add_box(parent_ents, name, origin, sx, sy, sz, profile_name, attrs = {})
          return nil if sx.to_f.abs < MIN_LENGTH || sy.to_f.abs < MIN_LENGTH || sz.to_f.abs < MIN_LENGTH
          g = parent_ents.add_group
          g.name = name
          pts = [[0, 0, 0], [sx, 0, 0], [sx, sy, 0], [0, sy, 0]].map { |a| Geom::Point3d.new(*a) }
          face = g.entities.add_face(pts)
          unless face
            g.erase! if g.valid?
            return nil
          end
          extrude(face, sz)
          g.transform!(Geom::Transformation.translation(origin))
          style_member(g, profile_name, attrs.merge(length_mm: Core::Units.to_mm([sx, sy, sz].max_by { |v| v.to_f.abs })))
          g
        end

        # Extrudes a profile along one global axis (:x, :y or :z).
        def add_profile_member(parent_ents, name, origin, length, axis, profile_name, attrs = {})
          p = ProfileLibrary[profile_name]
          raise "Unknown profile #{profile_name}" unless p
          return nil if length.to_f.abs < MIN_LENGTH

          g = parent_ents.add_group
          g.name = name
          unless draw_profile(g.entities, p, length)
            g.erase! if g.valid?
            return nil
          end
          g.transform!(axis_transformation(axis))
          g.transform!(Geom::Transformation.translation(origin))
          style_member(g, profile_name, attrs.merge(axis: axis.to_s, length_mm: Core::Units.to_mm(length)))
          g
        end

        # Maps local (profile XY, extrusion +Z) onto a global axis so that the
        # section height (local +Y) always ends up vertical for horizontal members.
        # A plain rotation about Y for the :x case leaves an I-section lying on
        # its side, so the axes are named explicitly instead.
        def axis_transformation(axis)
          case axis.to_sym
          when :x
            # member runs along +X, section height along +Z
            Geom::Transformation.axes(ORIGIN, Y_AXIS, Z_AXIS, X_AXIS)
          when :y
            # member runs along +Y, section height along +Z
            Geom::Transformation.axes(ORIGIN, X_AXIS.reverse, Z_AXIS, Y_AXIS)
          else
            Geom::Transformation.new
          end
        end

        # Creates a profile between any two 3D points. Local +Z follows the member
        # axis; local +Y is kept as close to global vertical as the direction allows.
        def add_member_between(parent_ents, name, point1, point2, profile_name, attrs = {})
          p = ProfileLibrary[profile_name]
          raise "Unknown profile #{profile_name}" unless p
          p1 = to_point(point1)
          p2 = to_point(point2)
          axis = p2 - p1
          length = axis.length
          return nil if length.to_f < MIN_LENGTH

          zaxis = axis.clone
          zaxis.normalize!
          xaxis = Z_AXIS.cross(zaxis)
          if xaxis.length.to_f < MIN_LENGTH
            xaxis = X_AXIS.clone
          else
            xaxis.normalize!
          end
          yaxis = zaxis.cross(xaxis)
          yaxis.normalize!

          g = parent_ents.add_group
          g.name = name
          unless draw_profile(g.entities, p, length)
            g.erase! if g.valid?
            return nil
          end
          g.transform!(Geom::Transformation.axes(p1, xaxis, yaxis, zaxis))
          style_member(g, profile_name,
                       attrs.merge(length_mm: Core::Units.to_mm(length),
                                   vector: [axis.x.to_f, axis.y.to_f, axis.z.to_f]))
          g
        end

        # Returns the created face, or nil when SketchUp refused the outline.
        def draw_profile(ents, p, length)
          pts = profile_points(p).map { |x, y| Geom::Point3d.new(x, y, 0) }
          face = ents.add_face(pts)
          return nil unless face
          extrude(face, length)
          face
        end

        # Section outline in internal inches, counter-clockwise, centred on origin.
        def profile_points(p)
          if p[:kind] == 'rhs'
            w = Core::Units.mm(p[:w])
            h = Core::Units.mm(p[:h])
            [[-w / 2, -h / 2], [w / 2, -h / 2], [w / 2, h / 2], [-w / 2, h / 2]]
          else
            b  = Core::Units.mm(p[:b])
            h  = Core::Units.mm(p[:h])
            tw = Core::Units.mm(p[:tw])
            tf = Core::Units.mm(p[:tf])
            x = b / 2.0
            y = h / 2.0
            wx = tw / 2.0
            [[-x, -y], [x, -y], [x, -y + tf], [wx, -y + tf], [wx, y - tf], [x, y - tf],
             [x, y], [-x, y], [-x, y - tf], [-wx, y - tf], [-wx, -y + tf], [-x, -y + tf]]
          end
        end

        # add_face may hand back a face whose normal points the other way, which
        # would extrude the member backwards from its insertion point.
        def extrude(face, distance)
          d = distance.to_f
          d = -d if face.normal.z < 0 && d != 0
          face.pushpull(d)
          face
        end

        def style_member(g, profile_name, attrs = {})
          model = Sketchup.active_model
          p = ProfileLibrary[profile_name]
          if p
            tag = model.layers[p[:tag]]
            g.layer = tag if tag
            mat = material_for(model, profile_name)
            g.material = mat if mat
          end
          Core::Metadata.stamp(g, attrs.merge(profile: profile_name.to_s))
        end

        def to_point(value)
          value.is_a?(Geom::Point3d) ? value : Geom::Point3d.new(*value)
        end
      end
    end
  end
end
