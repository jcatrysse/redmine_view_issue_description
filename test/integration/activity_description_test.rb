# frozen_string_literal: true

require_relative '../test_helper'

# The activity stream (HTML and Atom, project and global) does not show the
# description of an issue the user may not open (decision q3 of 2026-10-07).
# The event itself stays, as the issue stays in the issue list.
class ActivityDescriptionTest < Redmine::IntegrationTest
  include RedmineViewIssueDescription::TestHelper

  fixtures :projects, :users, :email_addresses, :members, :member_roles, :roles,
           :trackers, :projects_trackers, :enabled_modules, :issue_statuses,
           :issues, :enumerations, :watchers, :journals, :journal_details

  setup do
    @project = Project.find('ecookbook')
    @dlopper = User.find_by_login('dlopper') # Developer in ecookbook, no view_issue_description
    @role = Role.find_by_name('Developer')
    vid_grant(@role, :view_activities)
    @hidden = Issue.generate!(project: @project, tracker: Tracker.find(1), author: User.find(1),
                              subject: 'Vidactivity hidden', description: 'Vidactivity secret description')
    @assigned = Issue.generate!(project: @project, tracker: Tracker.find(1), author: User.find(1),
                                assigned_to: @dlopper, subject: 'Vidactivity assigned',
                                description: 'Vidactivity assigned description')
    log_user('dlopper', 'foo')
  end

  test 'project activity: the event stays, its description does not' do
    get '/projects/ecookbook/activity', params: { show_issues: '1' }
    assert_response :success

    assert_select 'dt.issue a', text: /Vidactivity hidden/
    assert_select 'dd span.description', text: /Vidactivity secret/, count: 0
    assert_select 'dd span.description', text: /Vidactivity assigned description/
  end

  test 'project activity Atom: no description for an issue the user may not open' do
    get '/projects/ecookbook/activity.atom', params: { show_issues: '1' }
    assert_response :success

    assert_includes response.body, 'Vidactivity hidden'
    assert_not_includes response.body, 'Vidactivity secret'
    assert_includes response.body, 'Vidactivity assigned description'
  end

  test 'global activity: no description for an issue the user may not open' do
    vid_grant(@role, :view_activities_global)
    get '/activity', params: { show_issues: '1' }
    assert_response :success

    assert_select 'dt.issue a', text: /Vidactivity hidden/
    assert_not_includes response.body, 'Vidactivity secret'
  end

  test 'view_issue_description gives the description' do
    vid_grant(@role, :view_issue_description)
    get '/projects/ecookbook/activity', params: { show_issues: '1' }

    assert_select 'dd span.description', text: /Vidactivity secret description/
  end

  test 'the hidden description is never written back' do
    get '/projects/ecookbook/activity', params: { show_issues: '1' }
    assert_equal 'Vidactivity secret description', @hidden.reload.description
  end
end
