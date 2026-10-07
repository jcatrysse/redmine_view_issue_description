# frozen_string_literal: true

require_relative '../test_helper'

# Round 3 of Jan's decisions (2026-10-07): the activity stream (HTML and Atom)
# no longer shows the notes of an issue the user may not open; the update
# event itself stays, as the new-issue event stays without its description.
class ActivityNotesTest < Redmine::IntegrationTest
  include RedmineViewIssueDescription::TestHelper

  fixtures :projects, :users, :email_addresses, :members, :member_roles, :roles,
           :trackers, :projects_trackers, :enabled_modules, :issue_statuses,
           :issues, :enumerations, :watchers, :journals, :journal_details

  setup do
    @dlopper = User.find_by_login('dlopper') # Developer in ecookbook, no view_issue_description
    @role = Role.find_by_name('Developer')
    vid_grant(@role, :view_activities)
    @hidden = Issue.generate!(project_id: 1, tracker_id: 1, author_id: 1, subject: 'Vidnotes hidden')
    @assigned = Issue.generate!(project_id: 1, tracker_id: 1, author_id: 1, subject: 'Vidnotes assigned',
                                assigned_to: @dlopper)
    Journal.create!(journalized: @hidden, user: User.find(1), notes: 'Vidnotes secret note')
    Journal.create!(journalized: @assigned, user: User.find(1), notes: 'Vidnotes assigned note')
    log_user('dlopper', 'foo')
  end

  test 'project activity: the update stays, its note does not' do
    get '/projects/ecookbook/activity', params: { show_issues: '1' }
    assert_response :success

    assert_select 'dt.issue-note a', text: /Vidnotes hidden/
    assert_not_includes response.body, 'Vidnotes secret note'
    assert_select 'dd span.description', text: /Vidnotes assigned note/
  end

  test 'Atom: no note of an issue the user may not open' do
    get '/projects/ecookbook/activity.atom', params: { show_issues: '1' }
    assert_response :success

    assert_not_includes response.body, 'Vidnotes secret note'
    assert_includes response.body, 'Vidnotes assigned note'
  end

  test 'view_issue_description gives the note' do
    vid_grant(@role, :view_issue_description)
    get '/projects/ecookbook/activity', params: { show_issues: '1' }

    assert_select 'dd span.description', text: /Vidnotes secret note/
  end

  test 'the hidden note is never written back' do
    get '/projects/ecookbook/activity', params: { show_issues: '1' }
    assert_equal 'Vidnotes secret note', @hidden.journals.last.reload.notes
  end
end
