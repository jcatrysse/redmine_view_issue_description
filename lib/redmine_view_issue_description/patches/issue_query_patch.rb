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
        return issues if user.admin?

        issues.each do |issue|
          issue.vid_hide_description! unless issue.detail_access_granted?(user)
        end
      end
    end
  end
end

unless IssueQuery.ancestors.include?(RedmineViewIssueDescription::Patches::IssueQueryPatch)
  IssueQuery.prepend(RedmineViewIssueDescription::Patches::IssueQueryPatch)
end
