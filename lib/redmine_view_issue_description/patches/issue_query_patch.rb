# frozen_string_literal: true
require_dependency 'issue_query'

module RedmineViewIssueDescription
  module Patches
    # Issue lists (HTML block column, CSV, PDF, Atom, GET /issues.json and .xml)
    # show the description only for issues the current user may open; for the
    # others Issue#description reads nil. QueryPatch only hides the column as a
    # whole, which is not enough when the permission is tracker-scoped or the
    # list spans several projects.
    module IssueQueryPatch
      def issues(options = {})
        issues = super
        user = User.current
        return issues if user.admin? || issues.empty?

        # Load in one query each what the check reads, instead of once per issue.
        vid_preload(issues, [:tracker])
        unsure = issues.reject { |issue| issue.description_access_granted?(user) }
        vid_preload(unsure, [:assigned_to, :watcher_users]) if unsure.any?
        unsure.each do |issue|
          issue.vid_hide_description! unless issue.detail_access_granted?(user)
        end
        issues
      end

      private

      def vid_preload(records, associations)
        if ActiveRecord.version >= Gem::Version.new('7.0')
          ActiveRecord::Associations::Preloader.new(records: records, associations: associations).call
        else
          ActiveRecord::Associations::Preloader.new.preload(records, associations)
        end
      end
    end
  end
end

unless IssueQuery.ancestors.include?(RedmineViewIssueDescription::Patches::IssueQueryPatch)
  IssueQuery.prepend(RedmineViewIssueDescription::Patches::IssueQueryPatch)
end
