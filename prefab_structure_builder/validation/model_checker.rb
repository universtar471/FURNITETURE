module KTSHung
  module PrefabStructureBuilder
    module Validation
      module ModelChecker
        module_function

        def report(model=Sketchup.active_model)
          issues=[]
          check_stock(issues)
          check_sources(issues,model)
          check_generated_orphans(issues,model)
          check_duplicate_roots(issues,model)
          check_member_lengths(issues,model)
          check_connections(issues,model)
          check_openings(issues,model)
          Output::Numbering.duplicate_marks.each do |mark,ents|
            ents.each{|e| issues << issue('error','DUPLICATE_MARK',e.entityID,e.name,"Duplicate mark #{mark}.",'Refresh numbering.')}
          end
          issues.each_with_index{|r,i| r[:issue_id]="CHK-#{(i+1).to_s.rjust(3,'0')}"}
          issues
        end

        def check_stock(issues)
          Materials::MaterialChecker.report.each do |r|
            next unless r[:status].to_s=='ERROR'
            issues << issue('error','STOCK_SIZE',r[:id],r[:name],"Sheet #{r[:actual]} exceeds stock #{r[:stock]}.",'Split/re-layout this sheet.')
          end
        end

        def check_sources(issues,model)
          Update::SourceTracker.report(model).each do |r|
            if r[:changed]
              issues << issue('warning','SOURCE_CHANGED',r[:id],r[:name],'Source geometry/name/tag changed since last baseline/update.','Run Update Changed.')
            end
          end
        end

        def check_generated_orphans(issues,model)
          source_ids=Update::SourceTracker.recognized_sources(model).map(&:entityID)
          model.entities.grep(Sketchup::Group).each do |g|
            sid=Core::Metadata.get(g,'source_id',nil)
            next unless sid && Core::Metadata.get(g,'generated',false)
            next if source_ids.include?(sid.to_i)
            issues << issue('warning','ORPHAN_GENERATED',g.entityID,g.name,'Generated object no longer has a source placeholder.','Delete it or restore the source group.')
          end
        end

        def check_duplicate_roots(issues,model)
          h=Hash.new{|x,k|x[k]=[]}
          model.entities.grep(Sketchup::Group).each do |g|
            sid=Core::Metadata.get(g,'source_id',nil)
            next unless sid && Core::Metadata.get(g,'generated',false)
            h[[sid.to_i,Core::Metadata.get(g,'system','')]] << g
          end
          h.each do |(_key),arr|
            next unless arr.length>1
            arr.each{|g| issues << issue('warning','DUPLICATE_GENERATED',g.entityID,g.name,"#{arr.length} generated roots share the same source/system.",'Update source to rebuild one clean system.')}
          end
        end

        def check_member_lengths(issues,model)
          walk(model.entities) do |e|
            next unless Core::Metadata.get(e,'type','')=='member'
            len=Core::Metadata.get(e,'length_mm',nil)
            if len && len.to_f <= 1.0
              issues << issue('error','ZERO_MEMBER',e.entityID,e.name,'Structural member has near-zero length.','Delete/regenerate this system.')
            end
            profile=Core::Metadata.get(e,'profile','')
            unless Framing::ProfileLibrary[profile]
              issues << issue('error','UNKNOWN_PROFILE',e.entityID,e.name,"Unknown steel profile #{profile}.",'Assign a supported profile.')
            end
          end
        end

        def check_connections(issues,model)
          records=Connections::ConnectionEngine.collect_structural_records
          connected={}
          Connections::ConnectionEngine.report.each do |r|
            connected[r[:member_a].to_i]=true; connected[r[:member_b].to_i]=true
          end
          records.each do |r|
            next unless %w[primary_beam secondary_beam].include?(r[:role].to_s)
            next if connected[r[:id].to_i]
            issues << issue('info','UNCONNECTED_BEAM',r[:id],r[:name],'Beam has no generated Connection node yet.','Run Auto Connections or connect it manually.')
          end
        end

        def check_openings(issues,model)
          Structure::OpeningEngine.scan_types.each do |row|
            c=row[:config]||{}
            if c['width'].to_f<=0 || c['height'].to_f<=0
              issues << issue('error','OPENING_SIZE',row[:entity_ids].first,row[:name],'Opening clear width/height is missing or zero.','Fill the Door/Window table.')
            end
          end
        end

        def issue(severity,code,id,name,message,fix)
          {severity:severity,code:code,id:id,name:name,message:message,fix:fix}
        end

        MAX_DEPTH = 12

        # Depth-limited and definition-guarded: a component definition holding an
        # instance of itself would otherwise recurse until the stack blows.
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
