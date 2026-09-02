module KTSHung
  module PrefabStructureBuilder
    module Update
      module UpdateManager
        module_function

        # Writes a signature attribute onto every source, so it needs its own
        # undo step; without one each attribute write lands in the undo stack
        # separately (or not at all).
        def baseline!
          count=0
          Core::Transaction.run('Prefab Save Source Baseline') do |model|
            count=SourceTracker.recognized_sources(model).length
            SourceTracker.baseline!(model)
          end
          ::UI.messagebox("Prefab: source baseline saved for #{count} source object(s).")
          true
        rescue => e
          ::UI.messagebox("Baseline error: #{e.message}")
          false
        end

        def update_changed
          model=Sketchup.active_model
          sources=SourceTracker.changed_sources(model)
          return ::UI.messagebox('No changed source objects detected.') if sources.empty?
          model.start_operation('Prefab Update Changed Sources',true)
          Core::TagManager.ensure_tags!(model)
          updated=0
          sources.each do |src|
            begin
              update_one(model,src)
              SourceTracker.mark_clean!(src)
              updated += 1
            rescue => e
              puts("Prefab update source #{src.entityID}: #{e.message}")
            end
          end
          cleanup_stale_connections(model)
          model.commit_operation
          ::UI.messagebox("Prefab V1.0: updated #{updated}/#{sources.length} changed source object(s).")
          updated
        rescue => e
          model.abort_operation rescue nil
          ::UI.messagebox("Update error: #{e.message}\n#{e.backtrace.first}")
          0
        end

        def update_selected
          model=Sketchup.active_model
          recognized=SourceTracker.recognized_sources(model)
          sources=model.selection.to_a.select{|e| recognized.include?(e)}
          return ::UI.messagebox('Select one or more semantic source groups first.') if sources.empty?
          model.start_operation('Prefab Update Selected Sources',true)
          Core::TagManager.ensure_tags!(model)
          sources.each{|src| update_one(model,src); SourceTracker.mark_clean!(src)}
          cleanup_stale_connections(model)
          model.commit_operation
          sources.length
        rescue => e
          model.abort_operation rescue nil
          ::UI.messagebox("Update selected error: #{e.message}")
          0
        end

        def update_one(model,src)
          type=Source::Scanner.source_type(src)
          previous=generated_roots_for_source(model,src.entityID)
          config=harvest_config(previous,type)
          previous.each{|g| g.erase! if g.valid?}

          case type
          when 'column'
            # A model saved with a profile that later left the library would have
            # handed generate_one a nil profile hash.
            Structure::ColumnEngine.generate_one(model, src, config[:column_type] || config[:profile])
          when 'wall'
            wall_type=config[:wall_type]
            rules=Structure::WallEngine::DEFAULTS[wall_type] || Structure::WallEngine::DEFAULTS['AZ100']
            cfg=rules.dup
            cfg['spacing']=config[:spacing] if config[:spacing].to_f>0
            Structure::WallEngine.generate_one(model,src,wall_type,cfg)
          when 'door','window'
            row=Structure::OpeningEngine.scan_types.find{|r| r[:entity_ids].include?(src.entityID)}
            Structure::OpeningEngine.generate_one(model,src,type,row ? row[:name] : SourceTracker.source_name(src),row ? row[:config] : default_opening(type))
          when 'floor','balcony'
            ft=config[:floor_type]
            base=Structure::FloorEngine::FLOOR_TYPES[ft] || Structure::FloorEngine::FLOOR_TYPES[type=='balcony' ? 'BALCONY_WPC' : 'GROUND_STEEL_CEMBOARD']
            cfg=base.dup
            cfg[:primary]=config[:primary] if config[:primary]
            cfg[:secondary]=config[:secondary] if config[:secondary]
            cfg[:spacing]=config[:spacing] if config[:spacing].to_f>0
            cfg[:direction]=config[:direction] || 'auto'
            Structure::FloorEngine.generate_one(model,src,ft,cfg)
          when 'roof'
            cfg=default_roof.merge(config[:roof_cfg] || {})
            Structure::RoofEngine.generate_one(model,src,cfg)
          when 'void'
            # VOID is source-only in V0.7. It participates in validation but creates no geometry.
          end
        end

        def generated_roots_for_source(model,source_id)
          model.entities.grep(Sketchup::Group).select do |g|
            g.valid? &&
              Core::Metadata.get(g,'source_id',nil).to_i == source_id.to_i &&
              Core::Metadata.get(g,'generated',false)
          end
        end

        def harvest_config(groups,type)
          g=groups.first
          case type
          when 'column'
            profile=g ? Core::Metadata.get(g,'profile',nil) : nil
            profile=Rules::RuleEngine.valid_profile(profile,Rules::RuleEngine.column_profile)
            type_name=g ? Core::Metadata.get(g,'column_type',nil) : nil
            {profile: profile,
             column_type: (type_name && Project::ColumnTypes[type_name] ? type_name : nil)}
          when 'wall'
            begin
              wr=Rules::RuleEngine.wall(g ? Core::Metadata.get(g,'wall_type',nil) : nil)
              {wall_type:wr[:id],spacing:wr[:spacing_mm]}
            end
          when 'floor','balcony'
            {floor_type:g ? Core::Metadata.get(g,'floor_type',(type=='balcony' ? 'BALCONY_WPC':'GROUND_STEEL_CEMBOARD')) : (type=='balcony' ? 'BALCONY_WPC':'GROUND_STEEL_CEMBOARD'),
             primary:g ? Core::Metadata.get(g,'primary',nil):nil,
             secondary:g ? Core::Metadata.get(g,'secondary',nil):nil,
             spacing:(g ? Core::Metadata.get(g,'spacing',nil).to_f : nil),
             direction:'auto'}
          when 'roof'
            {roof_cfg: g ? {
              type:Core::Metadata.get(g,'roof_type','MONO'), direction:Core::Metadata.get(g,'direction','x+'),
              spacing:Core::Metadata.get(g,'secondary_spacing',1000).to_f, cover:Core::Metadata.get(g,'cover','CORRUGATED')
            } : {}}
          else
            {}
          end
        end


        def cleanup_stale_connections(model)
          container=Connections::ConnectionEngine.find_connection_container(model)
          return unless container
          container.entities.grep(Sketchup::Group).each do |g|
            a=Core::Metadata.get(g,'member_a',nil); b=Core::Metadata.get(g,'member_b',nil)
            next unless a || b
            alive_a = a.nil? || !model.find_entity_by_id(a.to_i).nil?
            alive_b = b.nil? || !model.find_entity_by_id(b.to_i).nil?
            g.erase! unless alive_a && alive_b
          end
        end

        def default_opening(type)
          Rules::RuleEngine.opening(type,'exterior').transform_keys(&:to_s)
        end

        def default_roof
          rr=Rules::RuleEngine.roof
          {type:'MONO',high:1200.0,low:300.0,ridge:1200.0,ridge_pos:50.0,direction:'x+',
           overhang:{front:rr[:overhang_mm],back:rr[:overhang_mm],left:rr[:overhang_mm],right:rr[:overhang_mm]},
           spacing:rr[:secondary_spacing_mm],cover:rr[:cover],soffit:rr[:soffit]}
        end
      end
    end
  end
end
