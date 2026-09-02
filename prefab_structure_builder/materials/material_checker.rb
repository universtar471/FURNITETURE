module KTSHung
  module PrefabStructureBuilder
    module Materials
      module MaterialChecker
        module_function
        def report
          rows=[]
          walk(Sketchup.active_model.entities) do |e|
            next unless %w[sheet panel finish].include?(Core::Metadata.get(e, 'type').to_s)
            preset_id = Core::Metadata.get(e, 'material_preset')
            sw = Core::Metadata.get(e, 'stock_width', 0).to_f
            sl = Core::Metadata.get(e, 'stock_length', 0).to_f
            # Surfaces such as deck/WPC/wall skins are not stock-controlled.
            # Without a recorded stock size there is nothing to check against,
            # and treating "no stock" as 0x0 would flag every one of them.
            next if sw <= 0 || sl <= 0
            aw = Core::Metadata.get(e, 'actual_width', 0).to_f
            al = Core::Metadata.get(e, 'actual_length', 0).to_f
            allow=preset_id && MaterialLibrary[preset_id] ? MaterialLibrary[preset_id][:allow_rotate] : false
            bad=StockSize.violation?(aw,al,sw,sl,allow)
            rows << {id:e.entityID,name:e.name,material:Core::Metadata.get(e,'material'),preset:preset_id,
                     actual:"#{aw.round(1)}×#{al.round(1)}",stock:"#{sw.round(1)}×#{sl.round(1)}",
                     status:bad ? 'ERROR' : Core::Metadata.get(e,'status','OK')}
          end
          rows
        end
        MAX_DEPTH = 12

        def walk(ents, depth = 0, visited_defs = {}, &block)
          return if depth > MAX_DEPTH
          ents.each do |e|
            next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
            yield e
            if e.is_a?(Sketchup::Group)
              walk(e.entities, depth + 1, visited_defs, &block)
            else
              key = e.definition.entityID
              next if visited_defs[key]
              visited_defs[key] = true
              walk(e.definition.entities, depth + 1, visited_defs, &block)
              visited_defs.delete(key)
            end
          end
        end
      end
    end
  end
end
