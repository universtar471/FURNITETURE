module KTSHung
  module PrefabStructureBuilder
    module Output
      module Numbering
        module_function
        def generated; BOM.generated_entities; end

        def code_group(e)
          type=Core::Metadata.get(e,'type','').to_s
          role=Core::Metadata.get(e,'role','').to_s
          profile=Core::Metadata.get(e,'profile','').to_s
          system=Core::Metadata.get(e,'system','').to_s
          if %w[column member].include?(type)
            base=type=='column' ? 'COL' : (role =~ /primary/i ? 'BM-P' : role =~ /secondary/i ? 'BM-S' : 'STL')
            [base,profile,system]
          elsif %w[sheet panel finish].include?(type)
            mat=Core::Metadata.get(e,'material_preset',Core::Metadata.get(e,'material','MAT')).to_s
            ['SHT',mat,system]
          elsif type=='connection_part' || role =~ /(plate|bolt|weld)/i
            ['CONN',role,system]
          else
            ['OBJ',role,system]
          end
        end

        # Assumes the caller owns an open model operation: it is invoked both
        # standalone from the panel and from inside Finalizer's transaction, and
        # opening one here would close the outer one.
        def apply(preserve=nil)
          BOM.with_cache { apply_marks(preserve) }
        end

        def apply_marks(preserve=nil)
          cfg=Project::PresetManager.current
          prefix=cfg[:code_prefix].to_s.strip; prefix='PFB' if prefix.empty?
          revision=cfg[:project_revision].to_s.strip; revision='A' if revision.empty?
          preserve=cfg[:preserve_existing_marks] if preserve.nil?
          counters=Hash.new(0)
          count=0; preserved=0

          # Reserve existing sequence values first, preventing duplicate new marks.
          generated.each do |e|
            mk=Core::Metadata.get(e,'mark','').to_s
            next if mk.empty?
            key=code_group(e)
            if mk =~ /-(\d+)(?:-R[^-]+)?$/
              counters[key]=[counters[key],$1.to_i].max
            end
          end

          generated.sort_by{|e|[code_group(e).join('|'),e.entityID]}.each do |e|
            existing=Core::Metadata.get(e,'mark','').to_s
            if preserve && !existing.empty?
              Core::Metadata.set(e,'revision',revision)
              preserved+=1
              next
            end
            key=code_group(e); counters[key]+=1
            base="#{prefix}-#{key[0]}-#{counters[key].to_s.rjust(3,'0')}"
            code="#{base}-R#{revision}"
            Core::Metadata.set(e,'mark',code)
            Core::Metadata.set(e,'mark_base',base)
            Core::Metadata.set(e,'mark_group',key.join('|'))
            Core::Metadata.set(e,'revision',revision)
            e.name=code if e.respond_to?(:name=)
            count+=1
          end
          {assigned:count,preserved:preserved,revision:revision}
        end

        def duplicate_marks
          h=Hash.new{|x,k|x[k]=[]}
          generated.each do |e|
            mk=Core::Metadata.get(e,'mark','').to_s
            h[mk] << e unless mk.empty?
          end
          h.select{|_k,v|v.length>1}
        end
      end
    end
  end
end
