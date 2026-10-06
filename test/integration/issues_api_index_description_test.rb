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

  test 'the per-issue check costs no query per issue' do
    count_queries = lambda do |login, password|
      queries = 0
      counter = ->(*, payload) { queries += 1 unless payload[:name] == 'SCHEMA' || payload[:cached] }
      ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') do
        get '/projects/ecookbook/issues.json', params: { status_id: '*', limit: 100 },
                                               headers: credentials(login, password)
      end
      assert_response :success
      queries
    end
    # view_watched_issues makes the check look at assignee and watchers too
    vid_grant(@role, :view_watched_issues)
    count_queries.call('dlopper', 'foo') # warm up
    user_before = count_queries.call('dlopper', 'foo')
    admin_before = count_queries.call('admin', 'admin') # admin skips the check: core's own cost
    20.times do |n|
      issue = Issue.generate!(project: @project, tracker: Tracker.find(n.even? ? 1 : 2), author: User.find(1),
                              assigned_to: (n % 3).zero? ? User.find(2) : nil)
      Watcher.create!(watchable: issue, user: User.find(3)) if (n % 4).zero?
    end
    user_growth = count_queries.call('dlopper', 'foo') - user_before
    admin_growth = count_queries.call('admin', 'admin') - admin_before

    # a few constant preload queries (watchers, their users) are fine, one per issue is not
    assert_operator user_growth - admin_growth, :<=, 5,
                    "20 more issues: #{user_growth} more queries for dlopper, #{admin_growth} for admin"
  end
end
