# frozen_string_literal: true

require_relative '../test_helper'

# The assignee may always open an issue. Without this check a member with
# edit_issues could assign an issue they may not open to themselves through
# the context menu or bulk edit (POST /issues/bulk_update), the one edit path
# the plugin did not refuse, and then read its description (decision q3 of
# 2026-10-07). Only that self-assignment is refused; other bulk changes and
# assigning someone else stay as core has them.
class IssueBulkAssignTest < Redmine::IntegrationTest
  include RedmineViewIssueDescription::TestHelper

  fixtures :projects, :users, :email_addresses, :members, :member_roles, :roles,
           :trackers, :projects_trackers, :enabled_modules, :issue_statuses,
           :issues, :enumerations, :watchers, :journals, :journal_details, :workflows,
           :groups_users

  setup do
    @project = Project.find('ecookbook')
    @dlopper = User.find_by_login('dlopper') # Developer: edit_issues, no view_issue_description
    @role = Role.find_by_name('Developer')
    @issue = Issue.generate!(project: @project, tracker: Tracker.find(1), author: User.find(1),
                             description: 'Vidbulk secret description')
    log_user('dlopper', 'foo')
  end

  test 'assigning an issue the user may not open to themselves is refused' do
    post '/issues/bulk_update', params: { ids: [@issue.id], issue: { assigned_to_id: @dlopper.id } }
    assert_response :forbidden
    assert_nil @issue.reload.assigned_to_id

    get "/issues/#{@issue.id}"
    assert_response :forbidden
  end

  test 'a group the user belongs to counts as themselves' do
    group = Group.find(10)
    group.users << @dlopper unless group.users.include?(@dlopper)
    Member.create!(principal: group, project: @project, roles: [Role.find_by_name('Developer')])
    with_settings issue_group_assignment: '1' do
      post '/issues/bulk_update', params: { ids: [@issue.id], issue: { assigned_to_id: group.id } }
    end
    assert_response :forbidden
    assert_nil @issue.reload.assigned_to_id
  end

  test 'copying with self-assignment is refused too' do
    assert_no_difference 'Issue.count' do
      post '/issues/bulk_update', params: { ids: [@issue.id], copy: '1', issue: { project_id: @project.id, assigned_to_id: @dlopper.id } }
    end
    assert_response :forbidden
  end

  test 'assigning someone else stays as core has it' do
    jsmith = User.find_by_login('jsmith')
    post '/issues/bulk_update', params: { ids: [@issue.id], issue: { assigned_to_id: jsmith.id } }
    assert_response :redirect
    assert_equal jsmith.id, @issue.reload.assigned_to_id
  end

  test 'other bulk changes stay as core has them' do
    post '/issues/bulk_update', params: { ids: [@issue.id], issue: { priority_id: 6 } }
    assert_response :redirect
    assert_equal 6, @issue.reload.priority_id
  end

  test 'with view_issue_description the user may assign themselves' do
    vid_grant(@role, :view_issue_description)

    post '/issues/bulk_update', params: { ids: [@issue.id], issue: { assigned_to_id: @dlopper.id } }
    assert_response :redirect
    assert_equal @dlopper.id, @issue.reload.assigned_to_id
  end
end
