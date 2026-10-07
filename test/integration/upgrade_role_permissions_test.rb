# frozen_string_literal: true

require_relative '../test_helper'

# Production safety at the Redmine 7 upgrade. GEOxyz production already runs
# this plugin (0.2.2 on main), which refuses the issue page without
# view_issue_description in the same way. Its roles keep the permission
# exactly as the role form stored it (roles.permissions plus the per-tracker
# columns), so access does not change at the upgrade, and the plugin ships no
# migration that grants the permission: granting it to every role with
# view_issues would open the description to the roles that are denied it on
# purpose. See docs/REDMINE7-MIGRATION.md, "After the upgrade".
class UpgradeRolePermissionsTest < Redmine::IntegrationTest
  fixtures :projects, :users, :email_addresses, :members, :member_roles, :roles,
           :trackers, :projects_trackers, :enabled_modules, :issue_statuses,
           :issues, :enumerations, :watchers, :journals, :journal_details, :workflows

  setup do
    Setting.rest_api_enabled = '1'
    @role = Role.find_by_name('Developer') # dlopper's role in ecookbook
    @bug = Issue.generate!(project_id: 1, tracker_id: 1, author_id: 1, description: 'Vidupgrade bug')
    @feature = Issue.generate!(project_id: 1, tracker_id: 2, author_id: 1, description: 'Vidupgrade feature')
  end

  # The role form of 0.2.2 and of this version post the same fields.
  def save_role_as_the_role_form(all_trackers:, tracker_ids: [])
    log_user('admin', 'admin')
    permissions = @role.permissions.map(&:to_s) | %w(view_issues view_issue_description)
    patch "/roles/#{@role.id}", params: {
      role: {
        permissions: permissions,
        permissions_all_trackers: { 'view_issues' => '1', 'view_issue_description' => all_trackers ? '1' : '0' },
        permissions_tracker_ids: { 'view_issue_description' => tracker_ids.map(&:to_s) }
      }
    }
    assert_redirected_to '/roles'
    reset!
  end

  def statuses_as_dlopper(issue)
    headers = credentials('dlopper', 'foo')
    get "/issues/#{issue.id}.json", headers: headers
    show = response.status
    put "/issues/#{issue.id}.json", params: { issue: { notes: 'Vidupgrade note' } }, headers: headers
    [show, response.status]
  end

  test 'the plugin ships no migration, so the upgrade leaves the roles as they are' do
    plugin = Redmine::Plugin.find(:redmine_view_issue_description)
    assert_empty Dir[File.join(plugin.directory, 'db', 'migrate', '*')]
  end

  test 'a role saved with view_issue_description for all trackers keeps show, update and the API' do
    save_role_as_the_role_form(all_trackers: true)

    assert @role.reload.has_permission?(:view_issue_description)
    assert_equal [200, 204], statuses_as_dlopper(@bug)
    assert_equal [200, 204], statuses_as_dlopper(@feature)
  end

  test 'a tracker-scoped grant keeps exactly its trackers' do
    save_role_as_the_role_form(all_trackers: false, tracker_ids: [1])

    assert_equal [200, 204], statuses_as_dlopper(@bug)
    assert_equal [403, 403], statuses_as_dlopper(@feature)
  end

  test 'a role with view_issues only is refused, as with 0.2.2' do
    assert_not @role.has_permission?(:view_issue_description)

    assert_equal [403, 403], statuses_as_dlopper(@bug)
  end
end
