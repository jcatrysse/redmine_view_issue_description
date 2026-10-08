# frozen_string_literal: true
require_dependency 'query'
require_relative '../prepend_chain'

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
        # For single-project queries: checks the project permission + tracker access.
        # For cross-project queries: the column is shown when the user has
        # view_issue_description in ALL projects they belong to — this prevents
        # leaking the column for projects where the user lacks the permission.
        # Individual issue descriptions are still filtered at render time.
        def description_column_visible?
          user = User.current
          return true if user.admin?

          if self.project
            description_column_visible_for_project?(user, self.project)
          else
            description_column_visible_cross_project?(user)
          end
        end

        def description_column_visible_for_project?(user, project)
          return false unless user.allowed_to?(:view_issue_description, project)

          project_roles = user.roles_for_project(project)
          tracker_ids = vid_cached_tracker_ids

          project_roles.any? do |role|
            role.permissions_all_trackers?(:view_issue_description) ||
              tracker_ids.any? { |tid| role.permissions_tracker_ids?(:view_issue_description, tid) }
          end
        end

        def description_column_visible_cross_project?(user)
          memberships = user.respond_to?(:memberships) ? Array(user.memberships) : []
          return false if memberships.empty?

          memberships.all? do |membership|
            project = membership.respond_to?(:project) ? membership.project : nil
            next true unless project

            user.allowed_to?(:view_issue_description, project)
          end
        end

        # Cache per Query instance to avoid repeated SELECT on tracker IDs within a request.
        def vid_cached_tracker_ids
          @vid_tracker_ids ||= (Tracker.respond_to?(:pluck) ? Tracker.pluck(:id) : Tracker.all.map(&:id))
        end
      end
    end
  end
end

Query.include(RedmineViewIssueDescription::Patches::QueryPatch::InstanceMethods)
# prepend, not alias_method (Jan, 2026-10-07): see PrependChain.
RedmineViewIssueDescription::PrependChain.wrap(Query, :QueryColumns, :columns,
                                               with: :columns_with_ifv, without: :columns_without_ifv)
RedmineViewIssueDescription::PrependChain.wrap(Query, :QueryAvailableBlockColumns, :available_block_columns,
                                               with: :available_block_columns_with_ifv,
                                               without: :available_block_columns_without_ifv)
RedmineViewIssueDescription::PrependChain.wrap(Query, :QueryHasColumn, :has_column?,
                                               with: :has_column_with_ifv?, without: :has_column_without_ifv?)
