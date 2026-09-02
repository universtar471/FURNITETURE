module KTSHung
  module PrefabStructureBuilder
    module Rules
      module RuleEngine
        module_function

        WALL = {
          'AZ100'=>{frame:'25x25',spacing_mm:500.0,direction:'vertical',panel_width_mm:400.0},
          'NANO'=>{frame:'25x25',spacing_mm:500.0,direction:'horizontal',panel_width_mm:400.0},
          'PANEL100'=>{frame:nil,spacing_mm:0.0,direction:'none',panel_width_mm:1000.0}
        }.freeze

        FLOOR = {
          'GROUND_STEEL_CEMBOARD'=>{primary:'100x100',secondary:'40x80',spacing_mm:500.0,direction:'auto'},
          'UPPER_DECK'=>{primary:'I200',secondary:'I150',spacing_mm:1000.0,direction:'auto'},
          'UPPER_I_CEMBOARD'=>{primary:'I200',secondary:'I150',spacing_mm:600.0,direction:'auto'},
          'BALCONY_WPC'=>{primary:'100x100',secondary:'40x80',spacing_mm:500.0,direction:'auto'}
        }.freeze

        ROOF = {
          column:'100x100', primary:'50x100', secondary:'30x60',
          secondary_spacing_mm:1000.0, overhang_mm:600.0, cover:'CORRUGATED', soffit:true
        }.freeze

        def preset
          Project::PresetManager.current
        end

        def column_profile
          valid_profile(preset[:default_column], '100x100')
        end

        def wall(wall_type=nil)
          id=(wall_type.to_s.empty? ? preset[:default_wall_system] : wall_type).to_s.upcase
          base=(WALL[id] || WALL['AZ100']).dup
          {id:id}.merge(base)
        end

        def floor(floor_type)
          base=(FLOOR[floor_type.to_s] || FLOOR['GROUND_STEEL_CEMBOARD']).dup
          # project presets override only semantically matching defaults
          if floor_type.to_s=='GROUND_STEEL_CEMBOARD'
            base[:primary]=valid_profile(preset[:default_floor_primary], base[:primary])
            base[:secondary]=valid_profile(preset[:default_floor_secondary], base[:secondary])
          end
          base
        end

        def roof
          r=ROOF.dup
          r[:primary]=valid_profile(preset[:default_roof_primary],r[:primary])
          r[:secondary]=valid_profile(preset[:default_roof_secondary],r[:secondary])
          r
        end

        def opening(type,location='exterior')
          frame = location.to_s=='interior' ? preset[:default_opening_int] : preset[:default_opening_ext]
          frame=valid_profile(frame, location.to_s=='interior' ? '50x100' : '40x80')
          if type.to_s=='door'
            {width:900.0,height:2200.0,sill:0.0,location:location.to_s,frame:frame}
          else
            {width:1200.0,height:1400.0,sill:900.0,location:location.to_s,frame:frame}
          end
        end

        def steel_stock
          {
            length_mm:[preset[:steel_stock_mm].to_f,1.0].max,
            kerf_mm:[preset[:steel_kerf_mm].to_f,0.0].max
          }
        end

        def valid_profile(name,fallback)
          Framing::ProfileLibrary[name.to_s] ? name.to_s : fallback
        end

        def serializable
          {
            preset:preset,
            column:{profile:column_profile},
            walls:WALL,
            floors:FLOOR,
            roof:roof,
            steel_stock:steel_stock
          }
        end
      end
    end
  end
end
