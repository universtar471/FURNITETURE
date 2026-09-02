module KTSHung
  module PrefabStructureBuilder
    module Output
      module BOM
        module_function

        # Container types are excluded: they are stamped as generated too, and
        # counting them alongside their contents would double the BOM.
        CONTAINER_TYPES = %w[wall floor roof system connection].freeze
        MAX_DEPTH = 12

        # One refresh of the panel asks for the generated entity list up to eight
        # times (BOM rows, summary, material summary, cut list, stock plan,
        # numbering, report, status) and each call walks the whole model. The
        # dialog wraps a refresh in with_cache so they share one traversal.
        # Scoping the cache to that block keeps it from ever going stale: the
        # model is not mutated while the block is open.
        def with_cache
          @cache_depth = (@cache_depth || 0) + 1
          yield
        ensure
          @cache_depth -= 1
          @cache = nil if @cache_depth.zero?
        end

        def generated_entities(model = Sketchup.active_model)
          return @cache if @cache
          out = []
          walk(model.entities, out, 0, {})
          @cache = out if (@cache_depth || 0) > 0
          out
        end

        def walk(ents, out, depth, visited_defs)
          return if depth > MAX_DEPTH
          ents.each do |e|
            # Edges and faces cannot carry generated metadata, and skipping them
            # avoids a get_attribute call per primitive on large models.
            next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
            type = Core::Metadata.get(e, 'type', '').to_s
            out << e if Core::Metadata.get(e, 'generated', false) && !CONTAINER_TYPES.include?(type)
            if e.is_a?(Sketchup::Group)
              walk(e.entities, out, depth + 1, visited_defs)
            else
              key = e.definition.entityID
              next if visited_defs[key]
              visited_defs[key] = true
              walk(e.definition.entities, out, depth + 1, visited_defs)
              visited_defs.delete(key)
            end
          end
        end

        def length_mm(e)
          v=Core::Metadata.get(e,'length_mm',nil)
          return v.to_f if v && v.to_f > 0
          return 0.0 unless e.respond_to?(:bounds)
          b = e.bounds
          [b.width, b.height, b.depth].map { |d| Core::Units.to_mm(d) }.max
        end

        def area_m2(e)
          aw=Core::Metadata.get(e,'actual_width',nil)
          al=Core::Metadata.get(e,'actual_length',nil)
          return aw.to_f*al.to_f/1_000_000.0 if aw && al
          return 0.0 unless e.respond_to?(:bounds)
          b = e.bounds
          dims = [b.width, b.height, b.depth].map { |d| Core::Units.to_mm(d) }.sort.reverse
          dims[0] * dims[1] / 1_000_000.0
        end

        def category(e)
          type=Core::Metadata.get(e,'type','').to_s
          role=Core::Metadata.get(e,'role','').to_s
          return 'STEEL' if %w[member column].include?(type) || !Core::Metadata.get(e,'profile','').to_s.empty?
          return 'SHEET' if %w[sheet panel finish].include?(type)
          return 'CONNECTION' if type=='connection_part' || role =~ /(plate|bolt|weld)/
          'OTHER'
        end

        def item_name(e)
          c=category(e)
          case c
          when 'STEEL'
            Core::Metadata.get(e,'profile','UNKNOWN').to_s
          when 'SHEET'
            Core::Metadata.get(e,'material_preset',Core::Metadata.get(e,'material','UNKNOWN')).to_s
          when 'CONNECTION'
            Core::Metadata.get(e,'role','CONNECTION_PART').to_s
          else
            Core::Metadata.get(e,'role',e.name.to_s).to_s
          end
        end

        def rows
          groups={}
          generated_entities.each do |e|
            c=category(e); item=item_name(e)
            key=[c,item,Core::Metadata.get(e,'system','').to_s,Core::Metadata.get(e,'role','').to_s]
            g=(groups[key] ||= {category:c,item:item,system:key[2],role:key[3],quantity:0,total_length_m:0.0,total_area_m2:0.0,marks:[]})
            g[:quantity]+=1
            mk=Core::Metadata.get(e,'mark','').to_s; g[:marks] << mk unless mk.empty?
            g[:total_length_m]+=length_mm(e)/1000.0 if c=='STEEL'
            g[:total_area_m2]+=area_m2(e) if c=='SHEET'
          end
          groups.values.each do |g|
            g[:total_length_m]=g[:total_length_m].round(3)
            g[:total_area_m2]=g[:total_area_m2].round(3)
            g[:marks]=g[:marks].uniq.sort.join(', ')
          end.sort_by{|g| [g[:category],g[:item],g[:system],g[:role]]}
        end

        def summary
          rs=rows
          {
            items: rs.sum{|r| r[:quantity]},
            steel_length_m: rs.select{|r|r[:category]=='STEEL'}.sum{|r|r[:total_length_m]}.round(3),
            sheet_area_m2: rs.select{|r|r[:category]=='SHEET'}.sum{|r|r[:total_area_m2]}.round(3),
            connection_parts: rs.select{|r|r[:category]=='CONNECTION'}.sum{|r|r[:quantity]}
          }
        end

        def material_summary
          groups={}
          generated_entities.each do |e|
            next unless category(e)=='SHEET'
            material=Core::Metadata.get(e,'material','UNKNOWN').to_s
            preset=Core::Metadata.get(e,'material_preset','').to_s
            sw=Core::Metadata.get(e,'stock_width',0).to_f
            sl=Core::Metadata.get(e,'stock_length',0).to_f
            key=[material,preset,sw,sl]
            g=(groups[key] ||= {material:material,preset:preset,stock_width:sw,stock_length:sl,pieces:0,full:0,cut:0,actual_area_m2:0.0})
            g[:pieces]+=1
            st=Core::Metadata.get(e,'status','').to_s.upcase
            g[:full]+=1 if st=='FULL'; g[:cut]+=1 if st=='CUT'
            g[:actual_area_m2]+=area_m2(e)
          end
          groups.values.each do |g|
            stock_area=(g[:stock_width]*g[:stock_length]/1_000_000.0)
            g[:actual_area_m2]=g[:actual_area_m2].round(3)
            g[:min_stock_by_area]=stock_area>0 ? (g[:actual_area_m2]/stock_area).ceil : 0
          end.sort_by{|g| [g[:material],g[:preset]]}
        end
      end
    end
  end
end
