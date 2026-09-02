module KTSHung
  module PrefabStructureBuilder
    module Connections
      module ConnectionEngine
        module_function

        TOUCH_TOLERANCE_MM = 35.0
        MAX_DEPTH = 12

        def self.touch_tolerance
          Core::Units.mm(TOUCH_TOLERANCE_MM)
        end

        def auto_generate(detail_mode='concept')
          model = Sketchup.active_model
          records = collect_structural_records
          pairs = candidate_pairs(records)
          return ::UI.messagebox('No compatible member intersections were found.') if pairs.empty?

          model.start_operation('Generate Prefab Connections', true)
          Core::TagManager.ensure_tags!(model)
          container = connection_container(model)
          existing = existing_keys(container)
          made = 0
          pairs.each do |a,b|
            rule = classify_pair(a,b)
            next unless rule
            key = connection_key(a,b,rule)
            next if existing[key]
            point = connection_point(a[:bbox], b[:bbox])
            create_connection(container.entities, rule, point, a, b, detail_mode)
            existing[key] = true
            made += 1
          end
          model.commit_operation
          ::UI.messagebox("Connection Engine: created #{made} connection(s).") if made > 0
          made
        rescue => e
          model.abort_operation rescue nil
          ::UI.messagebox("Connection generation error: #{e.message}\n#{e.backtrace.first}")
          0
        end

        # Explicit mode is useful when geometry is conceptual or the auto classifier cannot
        # infer an upper-floor-column condition from the rough model.
        def connect_selected(rule_id, detail_mode='concept')
          model = Sketchup.active_model
          selected = model.selection.to_a.select{|e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)}
          return ::UI.messagebox('Select exactly two generated structural groups.') unless selected.length == 2
          records = selected.map{|e| record_for_entity(e)}
          return ::UI.messagebox('Both selections must be generated Prefab structural objects.') if records.any?(&:nil?)
          rule = ConnectionRegistry[rule_id]
          return ::UI.messagebox('Choose a valid connection type.') unless rule
          model.start_operation('Create Selected Connection', true)
          Core::TagManager.ensure_tags!(model)
          container = connection_container(model)
          rid = rule_id.to_s
          point = connection_point(records[0][:bbox], records[1][:bbox])
          create_connection(container.entities, rid, point, records[0], records[1], detail_mode)
          model.commit_operation
          true
        rescue => e
          model.abort_operation rescue nil
          ::UI.messagebox("Selected connection error: #{e.message}")
          false
        end

        def report
          container = find_connection_container(Sketchup.active_model)
          return [] unless container
          container.entities.grep(Sketchup::Group).map do |g|
            {
              id: g.entityID,
              name: g.name,
              rule: Core::Metadata.get(g,'connection_type',''),
              member_a: Core::Metadata.get(g,'member_a',''),
              member_b: Core::Metadata.get(g,'member_b',''),
              detail: Core::Metadata.get(g,'detail_mode','concept')
            }
          end
        end

        def collect_structural_records
          records = []
          walk_entities(Sketchup.active_model.entities, Geom::Transformation.new, records, 0, {})
          records
        end

        def walk_entities(entities, parent_tr, records, depth = 0, visited_defs = {})
          return if depth > MAX_DEPTH
          entities.each do |e|
            next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
            # Connection nodes are not structural members and must not become
            # candidates for further connections.
            next if Core::Metadata.get(e, 'system', nil).to_s == 'connection'

            type = Core::Metadata.get(e, 'type', nil)
            profile = Core::Metadata.get(e, 'profile', nil)
            records << make_record(e, parent_tr) if type && profile && %w[column member].include?(type.to_s)

            tr = parent_tr * e.transformation
            if e.is_a?(Sketchup::Group)
              walk_entities(e.entities, tr, records, depth + 1, visited_defs)
            else
              # A definition that contains an instance of itself would recurse forever.
              key = e.definition.entityID
              next if visited_defs[key]
              visited_defs[key] = true
              walk_entities(e.definition.entities, tr, records, depth + 1, visited_defs)
              visited_defs.delete(key)
            end
          end
        end

        def record_for_entity(e)
          return nil unless Core::Metadata.get(e,'type',nil)
          make_record(e, Geom::Transformation.new)
        end

        def make_record(e, parent_tr)
          {
            entity: e,
            id: e.entityID,
            name: e.name.to_s,
            type: Core::Metadata.get(e,'type',''),
            role: Core::Metadata.get(e,'role',''),
            profile: Core::Metadata.get(e,'profile',''),
            system: Core::Metadata.get(e,'system',''),
            parent_id: Core::Metadata.get(e,'parent_id',''),
            bbox: transform_bbox(e.bounds, parent_tr)
          }
        end

        def transform_bbox(bb, tr)
          out = Geom::BoundingBox.new
          8.times { |i| out.add(bb.corner(i).transform(tr)) }
          out
        end

        def candidate_pairs(records)
          out=[]
          records.each_with_index do |a,i|
            ((i+1)...records.length).each do |j|
              b=records[j]
              next unless bbox_near?(a[:bbox], b[:bbox], touch_tolerance)
              next unless classify_pair(a,b)
              out << [a,b]
            end
          end
          out
        end

        def bbox_near?(a,b,tol)
          !(a.max.x + tol < b.min.x || b.max.x + tol < a.min.x ||
            a.max.y + tol < b.min.y || b.max.y + tol < a.min.y ||
            a.max.z + tol < b.min.z || b.max.z + tol < a.min.z)
        end

        def classify_pair(a,b)
          # secondary I into primary I
          if i_profile?(a) && i_profile?(b) && roles?(a,b,'secondary_beam','primary_beam')
            return 'I_SECONDARY_PRIMARY_BOLTED'
          end

          # Any structural I beam meeting a generated I column.
          if i_profile?(a) && i_profile?(b) && ((column?(a) && beam?(b)) || (column?(b) && beam?(a)))
            return 'I_COLUMN_I_BOLTED'
          end

          # I beam to SHS100 main column: direct weld.
          if ((i_profile?(a) && shs100_column?(b)) || (i_profile?(b) && shs100_column?(a)))
            return 'I_SHS_WELD'
          end

          # Roof frame 50x100 to SHS100 roof/main column: direct weld.
          if ((roof_50x100?(a) && shs100_column?(b)) || (roof_50x100?(b) && shs100_column?(a)))
            return 'ROOF_SHS_WELD'
          end
          nil
        end

        def i_profile?(r); %w[I150 I200].include?(r[:profile].to_s); end
        def column?(r); r[:type].to_s=='column' || r[:role].to_s.include?('column'); end
        def beam?(r); r[:role].to_s.include?('beam') || r[:role].to_s.include?('frame'); end
        def shs100_column?(r); r[:profile].to_s=='100x100' && column?(r); end
        def roof_50x100?(r); r[:profile].to_s=='50x100' && r[:system].to_s=='roof'; end
        def roles?(a,b,r1,r2); [a[:role].to_s,b[:role].to_s].sort == [r1,r2].sort; end

        def create_connection(parent_ents, rule_id, point, a, b, detail_mode)
          cfg = ConnectionRegistry[rule_id]
          raise "Unknown connection rule #{rule_id}" unless cfg
          g = parent_ents.add_group
          g.name = "CONN_#{rule_id}_#{a[:id]}_#{b[:id]}"
          g.layer = Core::TagManager.tag(Sketchup.active_model, 'CONNECTION')
          key = connection_key(a,b,rule_id)
          attrs = {
            type:'connection', role:'connection_node', system:'connection', connection_type:rule_id,
            member_a:a[:id], member_b:b[:id], member_a_profile:a[:profile], member_b_profile:b[:profile],
            member_a_role:a[:role], member_b_role:b[:role], connection_key:key, detail_mode:detail_mode.to_s
          }

          axis = connection_axis(a,b)
          if cfg[:plate]
            p=cfg[:plate]
            plate_axis = rule_id == 'UPPER_COLUMN_DECK_PLATE' ? :z : axis
            ConnectionGeometry.add_plate(g.entities,'PLATE',point,p[:width],p[:height],p[:thickness],plate_axis,attrs)
          end
          if cfg[:bolts] && detail_mode.to_s != 'concept'
            bt=cfg[:bolts]
            bolt_axis = rule_id == 'UPPER_COLUMN_DECK_PLATE' ? :z : axis
            ConnectionGeometry.add_bolt_group(g.entities,point,bolt_axis,bt[:rows],bt[:cols],bt[:spacing_x],bt[:spacing_z],bt[:diameter],32.0,attrs)
          end
          ConnectionGeometry.add_weld_marker(g.entities,point,axis,45.0,attrs) if cfg[:weld]
          Core::Metadata.stamp(g,attrs)
          g
        end

        def connection_axis(a,b)
          # Choose plate/bolt axis based on the thinner overlap dimension. This is robust
          # enough for conceptual X/Y framing and can be replaced by exact web normals later.
          ov = overlap_dimensions(a[:bbox],b[:bbox])
          dims = {x:ov[0].abs,y:ov[1].abs,z:ov[2].abs}
          dims.min_by{|_,v| v}.first
        end

        def overlap_dimensions(a,b)
          [ [a.max.x,b.max.x].min-[a.min.x,b.min.x].max,
            [a.max.y,b.max.y].min-[a.min.y,b.min.y].max,
            [a.max.z,b.max.z].min-[a.min.z,b.min.z].max ]
        end

        def connection_point(a,b)
          xmin=[a.min.x,b.min.x].max; xmax=[a.max.x,b.max.x].min
          ymin=[a.min.y,b.min.y].max; ymax=[a.max.y,b.max.y].min
          zmin=[a.min.z,b.min.z].max; zmax=[a.max.z,b.max.z].min
          x = xmin <= xmax ? (xmin+xmax)/2.0 : (a.center.x+b.center.x)/2.0
          y = ymin <= ymax ? (ymin+ymax)/2.0 : (a.center.y+b.center.y)/2.0
          z = zmin <= zmax ? (zmin+zmax)/2.0 : (a.center.z+b.center.z)/2.0
          Geom::Point3d.new(x,y,z)
        end

        def connection_key(a,b,rule)
          ids=[a[:id].to_i,b[:id].to_i].sort
          "#{rule}:#{ids[0]}:#{ids[1]}"
        end

        def connection_container(model)
          find_connection_container(model) || begin
            g=model.entities.add_group
            g.name='PREFAB_CONNECTIONS'
            g.layer = Core::TagManager.tag(model, 'CONNECTION')
            Core::Metadata.stamp(g,type:'system',role:'connection_container',system:'connection')
            g
          end
        end

        def find_connection_container(model)
          model.entities.grep(Sketchup::Group).find{|g| g.name=='PREFAB_CONNECTIONS'}
        end

        def existing_keys(container)
          h={}
          container.entities.grep(Sketchup::Group).each do |g|
            k=Core::Metadata.get(g,'connection_key',nil)
            h[k]=true if k
          end
          h
        end
      end
    end
  end
end
