# frozen_string_literal: true

require_relative '../test_helper'

# Redmine 7 webhooks send the issue API payload (description, journal) to the
# hook owner; this plugin only lets users with detail access open an issue.
class WebhookIssueDetailTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include RedmineViewIssueDescription::TestHelper

  fixtures :projects, :users, :email_addresses, :members, :member_roles, :roles,
           :trackers, :projects_trackers, :enabled_modules, :issue_statuses,
           :issues, :enumerations, :watchers

  setup do
    skip 'Redmine without webhooks' unless defined?(Webhook)

    @project = Project.find('ecookbook')
    @dlopper = User.find_by_login('dlopper')
    @role = Role.find_by_name('Developer')
    @role.add_permission!(:use_webhooks)
    @issue = Issue.generate!(project: @project, tracker: Tracker.find(1), author: User.find(1))
    @hook = Webhook.create!(url: 'https://example.com/hook', user: @dlopper, projects: [@project],
                            events: %w[issue.created issue.updated], active: true)
  end

  test 'no issue hook for an owner who may see the issue but not open it' do
    assert @issue.visible?(@dlopper)
    assert_not @issue.detail_access_granted?(@dlopper)

    assert_equal [], Webhook.hooks_for('issue.created', @issue)
  end

  test 'issue hook for an owner with view_issue_description' do
    vid_grant(@role, :view_issue_description)

    assert_equal [@hook], Webhook.hooks_for('issue.created', @issue)
  end

  test 'issue hook for an owner who is the assignee' do
    @issue.update!(assigned_to: @dlopper)

    assert_equal [@hook], Webhook.hooks_for('issue.updated', @issue)
  end

  test 'issue hook for a watching owner with view_watched_issues' do
    vid_grant(@role, :view_watched_issues)
    Watcher.create!(watchable: @issue, user: @dlopper)

    assert_equal [@hook], Webhook.hooks_for('issue.updated', @issue.reload)
  end

  test 'saving an issue enqueues no webhook job for an owner without detail access' do
    with_settings webhooks_enabled: '1' do
      ActiveJob::Base.queue_adapter = :test
      assert_no_enqueued_jobs(only: WebhookJob) do
        Issue.generate!(project: @project, tracker: Tracker.find(1), author: User.find(1))
      end

      vid_grant(@role, :view_issue_description)
      assert_enqueued_jobs(1, only: WebhookJob) do
        Issue.generate!(project: @project, tracker: Tracker.find(1), author: User.find(1))
      end
    end
  end
end
