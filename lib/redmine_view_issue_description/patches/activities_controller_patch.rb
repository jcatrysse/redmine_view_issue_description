# frozen_string_literal: true
require_relative '../prepend_chain'

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
# prepend, not alias_method (Jan, 2026-10-07): see PrependChain.
RedmineViewIssueDescription::PrependChain.wrap(ActivitiesController, :ActivitiesIndex, :index,
                                               with: :index_with_vid, without: :index_without_vid)
