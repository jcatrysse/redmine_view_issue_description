# frozen_string_literal: true

require_relative '../test_helper'

# Every request computes the watched-issues clauses itself: the per-request memo
# (WatchedClauseCache) must not carry over from one request to the next. In
# functional tests (no Rails executor around each request) it did, so a page
# counted after a member change cost more queries than the same page before it
# (found by redmine_agile's board query-count tests).
class RequestQueryCountTest < Redmine::ControllerTest
  tests IssuesController
  include RedmineViewIssueDescription::TestHelper

  fixtures :projects, :users, :email_addresses, :members, :member_roles, :roles,
           :trackers, :projects_trackers, :enabled_modules, :issue_statuses,
           :issues, :enumerations, :watchers, :queries

  def count_queries
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name] == 'SCHEMA' || payload[:cached] }
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') { yield }
    count
  end

  def list
    get :index, params: { project_id: 'ecookbook', set_filter: 1, status_id: '*' }
    assert_response :success
  end

  test 'the issue list costs the same before and after a member change elsewhere' do
    vid_grant(Role.find_by_name('Developer'), :view_watched_issues)
    @request.session[:user_id] = 3 # dlopper, Developer in ecookbook
    list # warm up
    before = count_queries { list }

    # another user joins another project: nothing the list of user 3 depends on
    Member.create!(principal: User.generate!, project: Project.find('onlinestore'), roles: [Role.find(1)])
    after = count_queries { list }

    assert_equal before, after, "issue list: #{before} queries before, #{after} after the member change"
  end
end
