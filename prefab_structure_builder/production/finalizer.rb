module KTSHung
  module PrefabStructureBuilder
    module Production
      module Finalizer
        module_function
        def run
          result=nil
          Core::Transaction.run('Prefab Finalize Project') do |model|
            # ensure_tags! rather than setup!: setup! opens its own operation,
            # which would close this one and split Finalize across undo steps.
            Core::TagManager.ensure_tags!(model)
            numbering=Output::Numbering.apply
            Update::SourceTracker.baseline!
            Core::ProjectStore.set('finalized_at',Time.now.to_i)
            Core::ProjectStore.set('finalized_version',Core::Metadata::VERSION)
            Core::ProjectStore.set('project_revision',Project::PresetManager.current[:project_revision].to_s)
            result={numbering:numbering,issues:ProductionChecker.report}
          end
          result
        rescue => e
          ::UI.messagebox("Finalize Project error: #{e.message}")
          {numbering:{assigned:0,preserved:0},issues:[{severity:'error',code:'FINALIZE_ERROR',message:e.message}]}
        end
      end
    end
  end
end
