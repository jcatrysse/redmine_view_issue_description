# frozen_string_literal: true
require_dependency 'roles_helper'

module RedmineViewIssueDescription
  module Overrides
    module RoleFormOverride
      Deface::Override.new(
        virtual_path: 'roles/_form',
        name: 'view_issue_description_tracker_permission',
        replace: "erb[silent]:contains('permissions = [:view_issues, :add_issues, :edit_issues, :add_issue_notes, :delete_issues] & setable_permissions.collect(&:name)')",
        text: "<% permissions = [:view_issue_description, :view_watched_issues, :view_issues, :add_issues, :edit_issues, :add_issue_notes, :delete_issues] & setable_permissions.collect(&:name) %>"
      )
    end
  end
end
