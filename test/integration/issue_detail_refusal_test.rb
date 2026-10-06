# frozen_string_literal: true

require_relative '../test_helper'

# show, edit and update are refused before the action runs, so no
# after_action of core or another plugin works on a half-built request.
class IssueDetailRefusalTest < Redmine::IntegrationTest
  include RedmineViewIssueDescription::TestHelper

  fixtures :projects, :users, :email_addresses, :members, :member_roles, :roles,
           :trackers, :projects_trackers, :enabled_modules, :issue_statuses,
           :issues, :enumerations, :workflows

  # Stands in for an after_action like redmine_contacts_helpdesk's
  # flash_helpdesk, which reads @issue.current_journal after an update.
  IssuesController.class_eval do
    after_action(only: [:show, :edit, :update]) do
      Thread.current[:vid_after_action_ran] = true if Thread.current[:vid_probe]
    end
  end

  setup do
    @role = Role.find_by_name('Developer') # dlopper in ecookbook
    @role.add_permission!(:edit_issues)
    @issue = Issue.generate!(project: Project.find('ecookbook'), tracker: Tracker.find(1), author: User.find(1))
    Thread.current[:vid_probe] = true
    Thread.current[:vid_after_action_ran] = false
  end

  teardown do
    Thread.current[:vid_probe] = nil
  end

  test 'a refused update writes nothing and runs no after_action' do
    log_user('dlopper', 'foo')
    assert_no_difference 'Journal.count' do
      patch "/issues/#{@issue.id}", params: { issue: { notes: 'refused' } }
    end
    assert_response :forbidden
    assert_not Thread.current[:vid_after_action_ran]
  end

  test 'a refused show and edit run no after_action' do
    log_user('dlopper', 'foo')
    get "/issues/#{@issue.id}"
    assert_response :forbidden
    get "/issues/#{@issue.id}/edit"
    assert_response :forbidden
    assert_not Thread.current[:vid_after_action_ran]
  end

  test 'an allowed update still runs the action and its after_actions' do
    vid_grant(@role, :view_issue_description)
    log_user('dlopper', 'foo')
    assert_difference 'Journal.count', 1 do
      patch "/issues/#{@issue.id}", params: { issue: { notes: 'allowed' } }
    end
    assert_redirected_to "/issues/#{@issue.id}"
    assert Thread.current[:vid_after_action_ran]
  end
end
