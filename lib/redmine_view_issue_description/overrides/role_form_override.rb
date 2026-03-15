# frozen_string_literal: true
require_dependency 'roles_helper'

module RedmineViewIssueDescription
  module Overrides
    module RoleFormOverride
      # insert_after is used instead of replace so the override is additive:
      # even if Redmine changes the base permissions list the selector still
      # matches and our permissions are prepended to whatever Redmine defined.
      #
      # FRAGILITY NOTE: The selector targets the `permissions = [:view_issues,`
      # string literal in app/views/roles/_form.html.erb.  If Redmine renames
      # that local variable or restructures that line the Deface selector will
      # silently produce no match — the tracker-permission checkboxes simply
      # disappear from the role form without raising an error.  When upgrading
      # Redmine, verify the role form still shows the tracker-permission rows
      # for view_issue_description / view_watched_issues.
      # Search for `permissions = [` in the Redmine _form partial to confirm
      # the selector is still valid.
      Deface::Override.new(
        virtual_path: 'roles/_form',
        name: 'view_issue_description_tracker_permission',
        insert_after: "erb[silent]:contains('permissions = [:view_issues,')",
        text: "<% permissions = ([:view_issue_description, :view_watched_issues] | permissions) & setable_permissions.collect(&:name) %>"
      )
    end
  end
end
