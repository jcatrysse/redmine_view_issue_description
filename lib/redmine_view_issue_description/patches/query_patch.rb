# frozen_string_literal: true
require_dependency 'query'

module RedmineViewIssueDescription
  module Patches
    module QueryPatch
      module InstanceMethods
        def columns_with_ifv
          columns_without_ifv.reject { |col| col.name == :description && !description_column_visible? }
        end

        def available_block_columns_with_ifv
          available_block_columns_without_ifv.reject { |col| col.name == :description && !description_column_visible? }
        end

        def has_column_with_ifv?(column)
          column_name = column.is_a?(QueryColumn) ? column.name : column
          return false if column_name == :description && !description_column_visible?

          has_column_without_ifv?(column)
        end

        private

        # Returns true when the current user may see the description column.
        # A user qualifies if at least one of their project roles grants
        # view_issue_description for all trackers OR for any specific tracker.
        # This is consistent with description_access_granted? on the Issue model.
        def description_column_visible?
          user = User.current
          return true if user.admin?
          return false unless self.project
          return false unless user.allowed_to?(:view_issue_description, self.project)

          project_roles = user.roles_for_project(self.project)
          # Cache per Query instance to avoid repeated SELECT on tracker IDs within a request.
          tracker_ids = @vid_tracker_ids ||= (Tracker.respond_to?(:pluck) ? Tracker.pluck(:id) : Tracker.all.map(&:id))

          project_roles.any? do |role|
            role.permissions_all_trackers?(:view_issue_description) ||
              tracker_ids.any? { |tid| role.permissions_tracker_ids?(:view_issue_description, tid) }
          end
        end
      end
    end
  end
end

Query.include(RedmineViewIssueDescription::Patches::QueryPatch::InstanceMethods)
Query.class_eval do
  unless method_defined?(:columns_without_ifv)
    alias_method :columns_without_ifv, :columns
    alias_method :columns, :columns_with_ifv
  end

  unless method_defined?(:available_block_columns_without_ifv)
    alias_method :available_block_columns_without_ifv, :available_block_columns
    alias_method :available_block_columns, :available_block_columns_with_ifv
  end

  unless method_defined?(:has_column_without_ifv?)
    alias_method :has_column_without_ifv?, :has_column?
    alias_method :has_column?, :has_column_with_ifv?
  end
end
