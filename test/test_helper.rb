# frozen_string_literal: true

# Rails tests against a real database (Redmine fixtures), next to the plain
# RSpec specs in spec/. Run from the Redmine root:
#   bundle exec rake redmine:plugins:test NAME=redmine_view_issue_description
require File.expand_path('../../../test/test_helper', __dir__)

module RedmineViewIssueDescription
  module TestHelper
    # Grants a plugin permission to a role, for all trackers.
    def vid_grant(role, *permissions)
      permissions.each { |permission| role.add_permission!(permission) }
      role.reload
    end
  end
end
