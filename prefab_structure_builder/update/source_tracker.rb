module KTSHung
  module PrefabStructureBuilder
    module Update
      module SourceTracker
        module_function
        TRACK_KEY='source_signature'.freeze

        def recognized_sources(model=Sketchup.active_model)
          Source::Scanner.recognized_entities(model,true).map{|r|r[:entity]}.uniq
        end

        def source_name(e); Source::Scanner.source_name(e); end

        def signature(e)
          bb=e.bounds
          values=[source_name(e),e.layer&.name.to_s,(e.respond_to?(:persistent_id) ? e.persistent_id : e.entityID)]
          values += [bb.min.x,bb.min.y,bb.min.z,bb.max.x,bb.max.y,bb.max.z].map{|v|(v.to_f*1_000_000).round}
          values += e.transformation.to_a.map{|v|(v.to_f*1_000_000).round} if e.respond_to?(:transformation)
          values.join('|')
        end

        def baseline!(model=Sketchup.active_model)
          recognized_sources(model).each{|e| Core::Metadata.set(e,TRACK_KEY,signature(e))}
          Core::ProjectStore.set('baseline_version',Core::Metadata::VERSION)
          Core::ProjectStore.set('baseline_at',Time.now.to_i)
          true
        end

        def changed?(e)
          old=Core::Metadata.get(e,TRACK_KEY,nil)
          old.nil? || old.to_s != signature(e)
        end

        def changed_sources(model=Sketchup.active_model); recognized_sources(model).select{|e|changed?(e)}; end

        def mark_clean!(e)
          Core::Metadata.set(e,TRACK_KEY,signature(e))
          Core::Metadata.set(e,'source_tracked_at',Time.now.to_i)
          e
        end

        def report(model=Sketchup.active_model)
          recursive=Source::Scanner.recognized_entities(model,true)
          recursive.map do |r|
            e=r[:entity]; type,num=Source::Scanner.classify(source_name(e),e.layer&.name)
            {id:e.entityID,name:(num ? "#{type.upcase} #{num}" : type.to_s.upcase),type:type,
             changed:changed?(e),tracked:!Core::Metadata.get(e,TRACK_KEY,nil).nil?,
             depth:r[:depth],nested:r[:depth].to_i>0,path:r[:path]}
          end.sort_by{|r|[r[:changed] ? 0:1,r[:type].to_s,r[:name].to_s,r[:depth].to_i]}
        end
      end
    end
  end
end
