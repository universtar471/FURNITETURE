module KTSHung
  module PrefabStructureBuilder
    module Materials
      module SheetLayout
        module_function

        def create_rect_layout(parent_ents, origin, required_w_mm, required_l_mm, preset_id, opts={})
          preset=MaterialLibrary[preset_id]
          raise "Unknown material preset #{preset_id}" unless preset
          sw=value(preset,:stock_width); sl=value(preset,:stock_length); t=value(preset,:thickness)
          allow=truth(value(preset,:allow_rotate))
          plan=StockSize.split_rectangle(required_w_mm,required_l_mm,sw,sl,allow)
          model=Sketchup.active_model
          tag_name=tag_for(value(preset,:family)); tag=Core::TagManager.tag(model,tag_name)
          mat_name="MAT_#{value(preset,:family)}"
          mat=model.materials[mat_name]
          unless mat
            mat=model.materials.add(mat_name)
            mat.color=material_color(value(preset,:family))
          end
          x0=origin[0]; y0=origin[1]; z0=origin[2]
          # Plan x is along required length; plan y is along required width.
          plan.each_with_index do |p,i|
            g=parent_ents.add_group; g.name="#{value(preset,:family)}_#{i+1}"
            lx=Core::Units.mm(p[:length_mm]); ly=Core::Units.mm(p[:width_mm]); th=Core::Units.mm(t)
            face=g.entities.add_face([0,0,0],[lx,0,0],[lx,ly,0],[0,ly,0])
            unless face
              g.erase! if g.valid?
              next
            end
            Framing::MemberFactory.extrude(face, th) if th > 0
            g.transform!(Geom::Transformation.translation([x0+Core::Units.mm(p[:x_mm]),y0+Core::Units.mm(p[:y_mm]),z0]))
            g.layer=tag; g.material=mat
            Core::Metadata.stamp(g,
              type:'sheet', role:(opts[:role]||'finish_sheet'), system:(opts[:system]||'material'),
              material:value(preset,:family), material_preset:preset_id,
              stock_width:sw, stock_length:sl, thickness:t,
              actual_width:p[:width_mm], actual_length:p[:length_mm],
              status:p[:status], rotated:p[:rotated], parent_id:opts[:parent_id]
            )
          end
          {plan:plan,stats:StockSize.stats(plan)}
        end

        def value(hash,key)
          hash[key] || hash[key.to_s]
        end
        def truth(v); v == true || v.to_s=='true'; end
        def tag_for(family)
          case family.to_s.upcase
          when 'NANO' then 'MAT_NANO'
          when 'AZ100' then 'MAT_PANEL'
          when 'CEMBOARD' then 'MAT_CEMBOARD'
          when 'WPC' then 'MAT_WPC'
          else 'MAT_PANEL'
          end
        end
        def material_color(family)
          case family.to_s.upcase
          when 'NANO' then Sketchup::Color.new(225,220,205)
          when 'AZ100' then Sketchup::Color.new(205,205,195)
          when 'CEMBOARD' then Sketchup::Color.new(185,185,170)
          when 'WPC' then Sketchup::Color.new(140,95,60)
          else Sketchup::Color.new(200,200,200)
          end
        end
      end
    end
  end
end
