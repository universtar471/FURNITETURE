module KTSHung
  module PrefabStructureBuilder
    module Production
      module ProductionChecker
        module_function

        # +base_issues+ lets a caller that has already run the model checker
        # reuse the result. A panel refresh would otherwise run it three times
        # (checks, QA, project status), each a full model traversal.
        def report(model=Sketchup.active_model, base_issues=nil)
          issues=(base_issues || Validation::ModelChecker.report(model)).map(&:dup)
          check_duplicate_marks(issues)
          check_versions(issues,model)
          check_project_preset(issues)
          check_source_names(issues,model)
          check_nested_sources(issues,model)
          issues.each_with_index{|r,i|r[:issue_id]="QA-#{(i+1).to_s.rjust(3,'0')}"}
          issues
        end

        def check_duplicate_marks(issues)
          Output::Numbering.duplicate_marks.each do |mark,ents|
            ents.each{|e|issues << issue('error','DUPLICATE_MARK',e.entityID,e.name,"Duplicate fabrication mark #{mark}.",'Re-run numbering or clear one duplicated mark.')}
          end
        end

        def check_versions(issues,model)
          walk(model.entities) do |e|
            next unless Core::Metadata.get(e,'generated',false)
            ver=Core::Metadata.get(e,'version','').to_s
            next if ver==Core::Metadata::VERSION
            issues << issue('info','LEGACY_GENERATED',e.entityID,e.name,"Generated with plugin #{ver.empty? ? 'legacy/unknown' : ver}, current is #{Core::Metadata::VERSION}.",'Update/regenerate this system before final fabrication output.')
          end
        end

        def check_project_preset(issues)
          c=Project::PresetManager.current
          issues << issue('error','PROJECT_STOCK',nil,'Project Preset','Steel stock length must be greater than zero.','Set a valid steel stock length.') if c[:steel_stock_mm].to_f<=0
          issues << issue('error','PROJECT_FLOOR_HEIGHT',nil,'Project Preset','Default floor height must be greater than zero.','Set a valid floor height.') if c[:floor_height_mm].to_f<=0
          %i[default_column default_floor_primary default_floor_secondary default_roof_primary default_roof_secondary].each do |k|
            val=c[k].to_s
            next if val.empty? || Framing::ProfileLibrary[val]
            issues << issue('warning','PRESET_PROFILE',nil,'Project Preset',"#{k}=#{val} is not in the profile library.",'Choose a supported steel profile.')
          end
        end

        def check_source_names(issues,model)
          Source::Scanner.recognized_entities(model,true).each do |r|
            e=r[:entity]; name=Source::Scanner.source_name(e)
            if name.strip.empty?
              issues << issue('warning','SOURCE_NAME',e.entityID,'Unnamed Source','Semantic source is recognized only by Tag and has no stable semantic name.','Name it COLUMN/WALL/FLOOR/ROOF/DOOR/WINDOW + type number.')
            end
          end
        end

        def check_nested_sources(issues,model)
          nested=Source::Scanner.recognized_entities(model,true).select{|r|r[:depth].to_i>0}
          nested.each do |r|
            e=r[:entity]
            generated=Update::UpdateManager.generated_roots_for_source(model,e.entityID)
            next if generated.any?
            issues << issue('info','NESTED_SOURCE',e.entityID,Source::Scanner.source_name(e),'Nested semantic source detected. Scan/tracking supports it, but V1.0 generation should be run while its editing context is active if world placement is ambiguous.','Open the parent group/component, select this source, then Generate.')
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
