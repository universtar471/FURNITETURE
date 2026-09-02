module KTSHung
  module PrefabStructureBuilder
    module Core
      module Transaction
        module_function
        def run(name, disable_ui=true)
          model=Sketchup.active_model
          model.start_operation(name, disable_ui)
          result=yield(model)
          model.commit_operation
          result
        rescue => e
          model.abort_operation rescue nil
          raise e
        end
      end
    end
  end
end
