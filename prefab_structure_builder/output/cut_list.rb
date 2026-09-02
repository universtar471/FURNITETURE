module KTSHung
  module PrefabStructureBuilder
    module Output
      module CutList
        module_function

        DEFAULT_STOCK_MM=6000.0
        DEFAULT_KERF_MM=3.0

        def member_rows
          BOM.generated_entities.filter_map do |e|
            next unless BOM.category(e)=='STEEL'
            len=BOM.length_mm(e)
            next if len <= 0
            {
              id:e.entityID, name:e.name.to_s, profile:Core::Metadata.get(e,'profile','UNKNOWN').to_s,
              role:Core::Metadata.get(e,'role','').to_s, system:Core::Metadata.get(e,'system','').to_s,
              length_mm:len.round(1)
            }
          end
        end

        def grouped
          h={}
          member_rows.each do |r|
            key=[r[:profile],r[:length_mm].round]
            g=(h[key] ||= {profile:r[:profile],length_mm:r[:length_mm].round,quantity:0,total_length_m:0.0,roles:{}})
            g[:quantity]+=1
            g[:total_length_m]+=r[:length_mm]/1000.0
            g[:roles][r[:role]]=(g[:roles][r[:role]]||0)+1
          end
          h.values.each{|g| g[:total_length_m]=g[:total_length_m].round(3); g[:roles]=g[:roles].map{|k,v|"#{k}:#{v}"}.join(', ')}
          h.values.sort_by{|g| [g[:profile],-g[:length_mm]]}
        end

        # First-fit decreasing stock-bar packing. Useful as a planning estimate, not a fabrication optimizer.
        def stock_plan(stock_mm=nil,kerf_mm=nil)
          cfg=Project::PresetManager.current
          stock_mm=(stock_mm || cfg[:steel_stock_mm] || DEFAULT_STOCK_MM).to_f
          kerf_mm=(kerf_mm || cfg[:steel_kerf_mm] || DEFAULT_KERF_MM).to_f
          by_profile=member_rows.group_by{|r|r[:profile]}
          by_profile.map do |profile,rows|
            cuts=rows.map{|r|r[:length_mm].to_f}.sort.reverse
            oversize=cuts.select{|c| c>stock_mm}
            packable=cuts.reject{|c| c>stock_mm}
            bars=[]
            packable.each do |cut|
              bar=bars.find{|b| b[:remaining] >= cut + (b[:cuts].empty? ? 0 : kerf_mm)}
              unless bar
                bar={cuts:[],remaining:stock_mm}; bars<<bar
              end
              kerf=bar[:cuts].empty? ? 0.0 : kerf_mm
              bar[:remaining]-=(cut+kerf); bar[:cuts]<<cut
            end
            used=packable.sum + [packable.length-bars.length,0].max*kerf_mm
            purchase=bars.length*stock_mm
            {
              profile:profile, stock_length_mm:stock_mm, kerf_mm:kerf_mm, bars:bars.length,
              cuts:cuts.length, oversize:oversize.length,
              used_m:(used/1000.0).round(3), purchase_m:(purchase/1000.0).round(3),
              waste_m:((purchase-used)/1000.0).round(3),
              waste_percent:(purchase>0 ? ((purchase-used)/purchase*100.0).round(1) : 0.0)
            }
          end.sort_by{|r|r[:profile]}
        end
      end
    end
  end
end
