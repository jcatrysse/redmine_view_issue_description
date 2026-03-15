# frozen_string_literal: true

module RedmineViewIssueDescription
  module Patches
    module ActivitiesControllerPatch
      module InstanceMethods
        def index_with_vid
          unless User.current.admin?
            allowed = if @project.present?
                        User.current.allowed_to?(:view_activities, @project)
                      else
                        User.current.allowed_to?(:view_activities_global, nil, global: true)
                      end

            unless allowed
              deny_access
              return
            end
          end

          index_without_vid
        end
      end
    end
  end
end

ActivitiesController.include(RedmineViewIssueDescription::Patches::ActivitiesControllerPatch::InstanceMethods)
ActivitiesController.class_eval do
  unless method_defined?(:index_without_vid)
    alias_method :index_without_vid, :index
    alias_method :index, :index_with_vid
  end
end
