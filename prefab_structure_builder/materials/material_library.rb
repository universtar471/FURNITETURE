module KTSHung
  module PrefabStructureBuilder
    module Materials
      module MaterialLibrary
        module_function

        # Presets reflect the working standards defined for this project.
        # Every value can be overridden per project through ProjectStore.
        PRESETS = {
          'NANO_400_2900_9' => {
            family:'NANO', label:'Nano 400×2900×9', stock_width:400.0,
            stock_length:2900.0, thickness:9.0, effective_width:400.0,
            allow_rotate:false, support_profile:'25x25', support_role:'nano_joint'
          },
          'NANO_600_3000_9' => {
            family:'NANO', label:'Nano 600×3000×9', stock_width:600.0,
            stock_length:3000.0, thickness:9.0, effective_width:600.0,
            allow_rotate:false, support_profile:'25x25', support_role:'nano_joint'
          },
          'AZ100_400_2900_16' => {
            family:'AZ100', label:'AZ100 400×2900×16', stock_width:400.0,
            stock_length:2900.0, thickness:16.0, effective_width:400.0,
            allow_rotate:false, support_profile:'25x25', support_role:'panel_joint'
          },
          'AZ100_383_3800_16' => {
            family:'AZ100', label:'AZ100 eff.383×3800×16', stock_width:400.0,
            stock_length:3800.0, thickness:16.0, effective_width:383.0,
            allow_rotate:false, support_profile:'25x25', support_role:'panel_joint'
          },
          'CEMBOARD_1000_2000_14' => {
            family:'CEMBOARD', label:'Cemboard 1000×2000×14', stock_width:1000.0,
            stock_length:2000.0, thickness:14.0, effective_width:1000.0,
            allow_rotate:true, support_profile:'40x80', support_role:'sheet_joint'
          },
          'CEMBOARD_1220_2440_16' => {
            family:'CEMBOARD', label:'Cemboard 1220×2440×16', stock_width:1220.0,
            stock_length:2440.0, thickness:16.0, effective_width:1220.0,
            allow_rotate:true, support_profile:'40x80', support_role:'sheet_joint'
          },
          'CEMBOARD_1220_2440_20' => {
            family:'CEMBOARD', label:'Cemboard 1220×2440×20', stock_width:1220.0,
            stock_length:2440.0, thickness:20.0, effective_width:1220.0,
            allow_rotate:true, support_profile:'40x80', support_role:'sheet_joint'
          }
        }.freeze

        # Custom presets round-trip through JSON, so they come back with String
        # keys while the built-ins use Symbols. Everything is normalised to
        # Symbols here so consumers can rely on preset[:stock_width].
        def all
          raw = Core::ProjectStore.get('material_presets', '{}')
          custom = begin
            JSON.parse(raw)
          rescue StandardError
            {}
          end
          normalized = {}
          (custom || {}).each do |id, hash|
            next unless hash.is_a?(Hash)
            normalized[id.to_s] = hash.each_with_object({}) { |(k, v), o| o[k.to_sym] = v }
          end
          PRESETS.merge(normalized)
        end

        def [](id)
          all[id.to_s]
        end

        def save_custom(id, hash)
          id = id.to_s.strip.upcase.gsub(/[^A-Z0-9_]+/, '_')
          raise 'Material ID is empty.' if id.empty?
          raw = Core::ProjectStore.get('material_presets', '{}')
          custom = JSON.parse(raw) rescue {}
          clean = {}
          hash.each { |k,v| clean[k.to_s] = v }
          custom[id] = clean
          Core::ProjectStore.set('material_presets', JSON.generate(custom))
          id
        end

        def serializable
          all.map do |id, p|
            q = {}
            p.each { |k, v| q[k.to_s] = v }
            q['id'] = id
            q['label'] ||= id
            q
          end
        end
      end
    end
  end
end
