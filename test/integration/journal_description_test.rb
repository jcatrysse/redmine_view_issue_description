# frozen_string_literal: true

require_relative '../test_helper'

# Two more ways to the description of an issue the user may not open
# (decision q3 of 2026-10-07): the diff of a description change in the
# history (/journals/:id/diff) and quoting the issue in a reply
# (POST /issues/:id/quoted, which quotes the description). Both are refused,
# as the issue page is; other diffs and quoting a note stay as core has them.
class JournalDescriptionTest < Redmine::IntegrationTest
  include RedmineViewIssueDescription::TestHelper

  fixtures :projects, :users, :email_addresses, :members, :member_roles, :roles,
           :trackers, :projects_trackers, :enabled_modules, :issue_statuses,
           :issues, :enumerations, :watchers, :journals, :journal_details

  setup do
    @project = Project.find('ecookbook')
    @dlopper = User.find_by_login('dlopper') # Developer in ecookbook, no view_issue_description
    @role = Role.find_by_name('Developer')
    @issue = Issue.generate!(project: @project, tracker: Tracker.find(1), author: User.find(1),
                             description: 'Vidjournal old description')
    @issue.init_journal(User.find(1), 'Vidjournal note')
    @issue.update!(description: 'Vidjournal new description')
    @journal = @issue.journals.last
    @detail = @journal.details.detect { |d| d.prop_key == 'description' }
    log_user('dlopper', 'foo')
  end

  test 'the description diff is refused to a user who may not open the issue' do
    get "/journals/#{@journal.id}/diff"
    assert_response :forbidden
    assert_not_includes response.body, 'Vidjournal'

    get "/journals/#{@journal.id}/diff", params: { detail_id: @detail.id }
    assert_response :forbidden
  end

  test 'the assignee gets the description diff' do
    @issue.update_column(:assigned_to_id, @dlopper.id)

    get "/journals/#{@journal.id}/diff", params: { detail_id: @detail.id }
    assert_response :success
    assert_select 'span.diff_in', text: 'new'
  end

  test 'view_issue_description gives the description diff' do
    vid_grant(@role, :view_issue_description)

    get "/journals/#{@journal.id}/diff"
    assert_response :success
    assert_select 'span.diff_out', text: 'old'
  end

  test 'quoting the issue (its description) is refused to a user who may not open it' do
    post "/issues/#{@issue.id}/quoted", xhr: true
    assert_response :forbidden
    assert_not_includes response.body, 'Vidjournal'
  end

  test 'quoting a note stays as core has it' do
    post "/issues/#{@issue.id}/quoted", params: { journal_id: @journal.id }, xhr: true
    assert_response :success
    assert_includes response.body, 'Vidjournal note'
  end

  test 'quoting the issue works with view_issue_description' do
    vid_grant(@role, :view_issue_description)

    post "/issues/#{@issue.id}/quoted", xhr: true
    assert_response :success
    assert_includes response.body, 'Vidjournal new description'
  end
end
