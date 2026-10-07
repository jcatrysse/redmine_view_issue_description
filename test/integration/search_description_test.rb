# frozen_string_literal: true

require_relative '../test_helper'

# Search (/search and /search.json) neither shows nor matches the description
# of an issue the user may not open (decision q3 of 2026-10-07). The issue
# itself stays findable through its subject, as in the issue list.
class SearchDescriptionTest < Redmine::IntegrationTest
  include RedmineViewIssueDescription::TestHelper

  fixtures :projects, :users, :email_addresses, :members, :member_roles, :roles,
           :trackers, :projects_trackers, :enabled_modules, :issue_statuses,
           :issues, :enumerations, :watchers, :journals, :journal_details

  setup do
    Setting.rest_api_enabled = '1'
    @project = Project.find('ecookbook')
    @dlopper = User.find_by_login('dlopper') # Developer in ecookbook, no view_issue_description
    @role = Role.find_by_name('Developer')
    @hidden = Issue.generate!(project: @project, tracker: Tracker.find(1), author: User.find(1),
                              subject: 'Vidsubject hidden', description: 'Vidsecret word in the description')
    @assigned = Issue.generate!(project: @project, tracker: Tracker.find(1), author: User.find(1),
                                assigned_to: @dlopper, subject: 'Vidsubject assigned',
                                description: 'Vidsecret assigned description')
  end

  def search_json(q, user = 'dlopper', password = 'foo')
    get '/search.json', params: { q: q, issues: '1', limit: 100 },
                        headers: credentials(user, password)
    assert_response :success
    response.parsed_body['results'].select { |r| r['type'].start_with?('issue') }
  end

  test 'a word of the description does not find an issue the user may not open' do
    ids = search_json('Vidsecret').map { |r| r['id'] }

    assert_not_includes ids, @hidden.id
    assert_includes ids, @assigned.id
  end

  test 'all words: subject and description together do not find it either' do
    get '/search.json', params: { q: 'Vidsubject Vidsecret', all_words: '1', issues: '1' },
                        headers: credentials('dlopper', 'foo')
    ids = response.parsed_body['results'].map { |r| r['id'] }

    assert_not_includes ids, @hidden.id
    assert_includes ids, @assigned.id
  end

  test 'found through the subject, without the description' do
    results = search_json('Vidsubject')
    hidden = results.detect { |r| r['id'] == @hidden.id }
    assigned = results.detect { |r| r['id'] == @assigned.id }

    assert hidden, 'the issue stays findable by its subject'
    assert_equal '', hidden['description'].to_s
    assert_equal 'Vidsecret assigned description', assigned['description']
  end

  test 'the HTML result has no description for an issue the user may not open' do
    log_user('dlopper', 'foo')
    get '/search', params: { q: 'Vidsubject', issues: '1' }
    assert_response :success

    assert_select 'dt.issue a', text: /Vidsubject hidden/
    assert_select 'dd span.description', text: /Vidsecret word/, count: 0
    assert_select 'dd span.description', text: /Vidsecret assigned/
  end

  test 'view_issue_description gives match and description' do
    vid_grant(@role, :view_issue_description)

    hidden = search_json('Vidsecret').detect { |r| r['id'] == @hidden.id }
    assert hidden
    assert_equal 'Vidsecret word in the description', hidden['description']
  end

  test 'a tracker-scoped grant only opens the tracker it names' do
    vid_grant(@role, :view_issue_description)
    @role.permissions_all_trackers = @role.permissions_all_trackers.merge('view_issue_description' => '0')
    @role.permissions_tracker_ids = @role.permissions_tracker_ids.merge('view_issue_description' => ['2'])
    @role.save!
    other = Issue.generate!(project: @project, tracker: Tracker.find(2), author: User.find(1),
                            description: 'Vidsecret on tracker 2')

    ids = search_json('Vidsecret').map { |r| r['id'] }
    assert_includes ids, other.id
    assert_not_includes ids, @hidden.id
  end

  test 'admin finds and sees every description' do
    hidden = search_json('Vidsecret', 'admin', 'admin').detect { |r| r['id'] == @hidden.id }
    assert hidden
    assert_equal 'Vidsecret word in the description', hidden['description']
  end

  test 'the hidden description is never written back' do
    search_json('Vidsubject')
    assert_equal 'Vidsecret word in the description', @hidden.reload.description
  end
end
