# frozen_string_literal: true

require_relative '../test_helper'

# GET /issues.json and .xml list issues the user can see; the description is
# only given for issues the user may open (view_issue_description, assignee,
# watcher with view_watched_issues), as on the issue page and its API show.
class IssuesApiIndexDescriptionTest < Redmine::IntegrationTest
  include RedmineViewIssueDescription::TestHelper

  fixtures :projects, :users, :email_addresses, :members, :member_roles, :roles,
           :trackers, :projects_trackers, :enabled_modules, :issue_statuses,
           :issues, :enumerations, :watchers, :journals, :journal_details

  setup do
    Setting.rest_api_enabled = '1'
    @project = Project.find('ecookbook')
    @dlopper = User.find_by_login('dlopper') # Developer in ecookbook
    @role = Role.find_by_name('Developer')
    @hidden = Issue.generate!(project: @project, tracker: Tracker.find(1), author: User.find(1),
                              description: 'Secret description')
    @assigned = Issue.generate!(project: @project, tracker: Tracker.find(1), author: User.find(1),
                                assigned_to: @dlopper, description: 'Assigned description')
  end

  def json_issue(id)
    get '/projects/ecookbook/issues.json', params: { status_id: '*', limit: 100 },
                                           headers: credentials('dlopper', 'foo')
    assert_response :success
    issue = response.parsed_body['issues'].detect { |i| i['id'] == id }
    assert issue, "issue #{id} is not in the list"
    issue
  end

  test 'JSON: no description for an issue the user may not open' do
    assert_nil json_issue(@hidden.id)['description']
  end

  test 'JSON: the assignee gets the description' do
    assert_equal 'Assigned description', json_issue(@assigned.id)['description']
  end

  test 'JSON: view_issue_description gives the description' do
    vid_grant(@role, :view_issue_description)

    assert_equal 'Secret description', json_issue(@hidden.id)['description']
  end

  test 'XML: no description for an issue the user may not open' do
    get '/projects/ecookbook/issues.xml', params: { status_id: '*', limit: 100 },
                                          headers: credentials('dlopper', 'foo')
    assert_response :success
    doc = Nokogiri::XML(response.body)
    assert_equal '', doc.at_xpath("//issue[id=#{@hidden.id}]/description").text
    assert_equal 'Assigned description', doc.at_xpath("//issue[id=#{@assigned.id}]/description").text
  end

  test 'the issue API show stays refused without detail access' do
    get "/issues/#{@hidden.id}.json", headers: credentials('dlopper', 'foo')
    assert_response :forbidden
  end

  test 'admin gets every description' do
    get '/projects/ecookbook/issues.json', params: { status_id: '*', limit: 100 },
                                           headers: credentials('admin')
    issue = response.parsed_body['issues'].detect { |i| i['id'] == @hidden.id }
    assert_equal 'Secret description', issue['description']
  end

  test 'the hidden description is never written back' do
    json_issue(@hidden.id)
    assert_equal 'Secret description', @hidden.reload.description
  end

  test 'CSV export with the description column leaves the hidden description out' do
    vid_grant(@role, :view_issue_description)
    # tracker-scoped grant: the description is allowed for tracker 2 only
    @role.permissions_all_trackers = @role.permissions_all_trackers.merge('view_issue_description' => '0')
    @role.permissions_tracker_ids = @role.permissions_tracker_ids.merge('view_issue_description' => ['2'])
    @role.save!
    log_user('dlopper', 'foo')

    get '/projects/ecookbook/issues.csv', params: { set_filter: 1, status_id: '*', c: %w[subject description] }
    assert_response :success
    assert_not_includes response.body, 'Secret description'
    assert_includes response.body, 'Assigned description'
  end
end
