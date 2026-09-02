module KTSHung
  module PrefabStructureBuilder
    module Output
      module Report
        module_function

        def project_status(qa_issue_count=nil)
          {
            plugin_version:Core::Metadata::VERSION,
            revision:Project::PresetManager.current[:project_revision].to_s,
            finalized_at:Core::ProjectStore.get('finalized_at',nil),
            finalized_version:Core::ProjectStore.get('finalized_version',nil),
            baseline_at:Core::ProjectStore.get('baseline_at',nil),
            source_count:Update::SourceTracker.recognized_sources.length,
            generated_count:BOM.generated_entities.length,
            qa_issues:(qa_issue_count || Production::ProductionChecker.report.length)
          }
        end

        def by_system
          h={}
          BOM.rows.each do |r|
            key=r[:system].to_s.empty? ? 'UNASSIGNED' : r[:system].to_s
            g=(h[key] ||= {system:key,quantity:0,steel_length_m:0.0,sheet_area_m2:0.0,categories:Hash.new(0)})
            g[:quantity]+=r[:quantity].to_i
            g[:steel_length_m]+=r[:total_length_m].to_f
            g[:sheet_area_m2]+=r[:total_area_m2].to_f
            g[:categories][r[:category]]+=r[:quantity].to_i
          end
          h.values.each do |g|
            g[:steel_length_m]=g[:steel_length_m].round(3)
            g[:sheet_area_m2]=g[:sheet_area_m2].round(3)
            g[:categories]=g[:categories].map{|k,v|"#{k}:#{v}"}.join(', ')
          end.sort_by{|g|g[:system]}
        end

        def marked_items
          BOM.generated_entities.map do |e|
            {
              mark:Core::Metadata.get(e,'mark','').to_s,
              type:Core::Metadata.get(e,'type','').to_s,
              system:Core::Metadata.get(e,'system','').to_s,
              role:Core::Metadata.get(e,'role','').to_s,
              profile:Core::Metadata.get(e,'profile','').to_s,
              length_mm:BOM.length_mm(e).round(1),
              source_id:Core::Metadata.get(e,'source_id','').to_s
            }
          end.reject{|r|r[:mark].empty?}.sort_by{|r|r[:mark]}
        end
      end
    end
  end
end
