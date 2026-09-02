module KTSHung
  module PrefabStructureBuilder
    module Framing
      module ProfileLibrary
        PROFILES = {
          '100x100' => {kind:'rhs', w:100, h:100, color:[145,145,145], tag:'STEEL_100x100'},
          '25x25'   => {kind:'rhs', w:25,  h:25,  color:[245,205,35],  tag:'STEEL_25x25'},
          '50x50'   => {kind:'rhs', w:50,  h:50,  color:[210,55,55],   tag:'STEEL_50x50'},
          '40x80'   => {kind:'rhs', w:40,  h:80,  color:[150,80,190],  tag:'STEEL_40x80'},
          '30x60'   => {kind:'rhs', w:30,  h:60,  color:[55,165,75],   tag:'STEEL_30x60'},
          '50x100'  => {kind:'rhs', w:50,  h:100, color:[70,165,220],  tag:'STEEL_50x100'},
          'I150'    => {kind:'i',   h:150, b:75, tw:5, tf:7, color:[135,85,45], tag:'STEEL_I150'},
          'I200'    => {kind:'i',   h:200, b:100,tw:5.5,tf:8, color:[35,70,130], tag:'STEEL_I200'}
        }.freeze
        module_function
        def [](name); PROFILES[name]; end
        def names; PROFILES.keys; end
      end
    end
  end
end
