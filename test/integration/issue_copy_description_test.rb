# frozen_string_literal: true

require_relative '../test_helper'

# "Copy" on an issue opens the new issue form filled with the description of
# the source (/projects/:id/issues/:copy_from/copy). For a source the user may
# not open that is the description again (decision q3 of 2026-10-07), so the
# copy is refused, as the issue page is.
class IssueCopyDescriptionTest < Redmine::IntegrationTest
  include RedmineViewIssueDescription::TestHelper

  fixtures :projects, :users, :email_addresses, :members, :member_roles, :roles,
           :trackers, :projects_trackers, :enabled_modules, :issue_statuses,
           :issues, :enumerations, :watchers, :journals, :journal_details,
           :workflows, :custom_fields, :custom_values, :custom_fields_projects, :custom_fields_trackers

  setup do
    @project = Project.find('ecookbook')
    @dlopper = User.find_by_login('dlopper') # Developer: add_issues, copy_issues, no view_issue_description
    @role = Role.find_by_name('Developer')
    @source = Issue.generate!(project: @project, tracker: Tracker.find(1), author: User.find(1),
                              subject: 'Vidcopy source', description: 'Vidcopy secret description')
    log_user('dlopper', 'foo')
  end

  test 'the copy form is refused for a source the user may not open' do
    get "/projects/ecookbook/issues/#{@source.id}/copy"
    assert_response :forbidden
    assert_not_includes response.body, 'Vidcopy secret'
  end

  test 'creating a copy of such a source is refused' do
    assert_no_difference 'Issue.count' do
      post '/projects/ecookbook/issues', params: {
        copy_from: @source.id,
        issue: { tracker_id: 1, subject: 'Vidcopy copy', status_id: 1, priority_id: 5 }
      }
    end
    assert_response :forbidden
  end

  test 'the assignee may copy' do
    @source.update_column(:assigned_to_id, @dlopper.id)

    get "/projects/ecookbook/issues/#{@source.id}/copy"
    assert_response :success
    assert_select 'textarea#issue_description', text: /Vidcopy secret description/
  end

  test 'view_issue_description allows the copy' do
    vid_grant(@role, :view_issue_description)

    get "/projects/ecookbook/issues/#{@source.id}/copy"
    assert_response :success
    assert_select 'textarea#issue_description', text: /Vidcopy secret description/
  end

  test 'a new issue without a source stays as core has it' do
    get '/projects/ecookbook/issues/new'
    assert_response :success
  end
end
