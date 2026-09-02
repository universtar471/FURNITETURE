module KTSHung
  module PrefabStructureBuilder
    module Connections
      module ConnectionRegistry
        RULES = {
          'I_COLUMN_I_BOLTED' => {
            label: 'I beam → I column • plate + bolts',
            plate: {width: 160.0, height: 220.0, thickness: 10.0},
            bolts: {rows: 4, cols: 2, spacing_x: 55.0, spacing_z: 55.0, diameter: 16.0},
            detail: 'concept_fabrication_placeholder'
          },
          'I_SHS_WELD' => {
            label: 'I beam → SHS100 column • direct weld',
            weld: true,
            detail: 'concept'
          },
          'I_SECONDARY_PRIMARY_BOLTED' => {
            label: 'Secondary I → Primary I • bolted plate',
            plate: {width: 130.0, height: 170.0, thickness: 8.0},
            bolts: {rows: 3, cols: 2, spacing_x: 45.0, spacing_z: 50.0, diameter: 14.0},
            detail: 'concept_fabrication_placeholder'
          },
          'ROOF_SHS_WELD' => {
            label: 'Roof 50x100 → SHS100 column • direct weld',
            weld: true,
            detail: 'concept'
          },
          'UPPER_COLUMN_DECK_PLATE' => {
            label: 'Upper SHS100 column → I floor/deck • base plate + bolts',
            plate: {width: 180.0, height: 180.0, thickness: 12.0},
            bolts: {rows: 2, cols: 2, spacing_x: 110.0, spacing_z: 110.0, diameter: 16.0},
            detail: 'concept_fabrication_placeholder'
          }
        }.freeze

        module_function
        def [](id); RULES[id.to_s]; end
        def serializable
          RULES.map{|id,cfg| {id:id,label:cfg[:label],detail:cfg[:detail]} }
        end
      end
    end
  end
end
