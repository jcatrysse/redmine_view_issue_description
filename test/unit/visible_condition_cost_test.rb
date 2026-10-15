# frozen_string_literal: true

require_relative '../test_helper'

# Issue.visible_condition is called several times per page (issue list, gantt,
# my page, search, activity). The plugin's watched-issues part must not cost
# queries per membership of the user, and repeats within a request are free.
class VisibleConditionCostTest < ActiveSupport::TestCase
  include RedmineViewIssueDescription::TestHelper

  fixtures :projects, :users, :email_addresses, :members, :member_roles, :roles,
           :trackers, :projects_trackers, :enabled_modules, :issue_statuses,
           :issues, :enumerations, :watchers

  setup do
    @role = Role.generate!(permissions: %i[view_issues view_watched_issues])
    @user = User.generate!
  end

  def add_memberships(count)
    count.times do |n|
      project = Project.generate!(enabled_module_names: %w[issue_tracking])
      project.trackers = Tracker.all.to_a
      Member.create!(principal: @user, project: project, roles: [@role])
    end
  end

  def queries_for(user)
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name] == 'SCHEMA' || payload[:cached] }
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') { yield user }
    count
  end

  def fresh_user
    RedmineViewIssueDescription::WatchedClauseCache.clear if defined?(RedmineViewIssueDescription::WatchedClauseCache)
    User.find(@user.id)
  end

  test 'the cost does not grow with the number of memberships' do
    add_memberships(5)
    with_5 = queries_for(fresh_user) { |u| Issue.visible_condition(u) }
    add_memberships(5)
    with_10 = queries_for(fresh_user) { |u| Issue.visible_condition(u) }

    assert_equal with_5, with_10, "5 memberships: #{with_5} queries, 10 memberships: #{with_10}"
  end

  test 'a second call in the same request adds no query to core own' do
    add_memberships(3)
    user = fresh_user
    Issue.visible_condition(user)
    core_only = queries_for(user) { |u| Issue.visible_condition_without_vid(u) }
    assert_equal core_only, queries_for(user) { |u| Issue.visible_condition(u) }
  end

  test 'the condition still follows a role change in the same request' do
    project = Project.generate!(enabled_module_names: %w[issue_tracking])
    project.trackers = Tracker.all.to_a
    plain = Role.generate!(permissions: %i[view_issues])
    Member.create!(principal: @user, project: project, roles: [plain])
    user = fresh_user
    assert_not_includes Issue.visible_condition(user), "project_id = #{project.id}"

    plain.add_permission!(:view_watched_issues)
    assert_includes Issue.visible_condition(User.find(@user.id)), "project_id = #{project.id}"
  end

  test 'the condition is the same with and without the cache' do
    add_memberships(3)
    first = Issue.visible_condition(fresh_user)
    cached = Issue.visible_condition(User.find(@user.id))
    assert_equal first, cached
    assert_includes first, 'watchers'
  end
end
