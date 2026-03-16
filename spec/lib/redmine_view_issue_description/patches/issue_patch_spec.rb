require_relative '../../../spec_helper'

unless defined?(RedmineViewIssueDescription::Patches::IssuePatch)
  module RedmineViewIssueDescription
    module Patches
      module IssuePatch
        module InstanceMethods; end
      end
    end
  end
end

unless Kernel.respond_to?(:require_dependency)
  def require_dependency(file)
    require file
  rescue LoadError
  end
end

RSpec.describe RedmineViewIssueDescription::Patches::IssuePatch::InstanceMethods do
  before(:all) do
    class ::User
      class << self
        attr_accessor :current, :active_users

        def active
          active_users || []
        end
      end

      attr_reader :name, :admin, :logged, :permissions, :project_roles, :groups

      def initialize(name: 'user', admin: false, logged: true, permissions: {}, project_roles: {}, groups: [])
        @name = name
        @admin = admin
        @logged = logged
        @permissions = permissions
        @project_roles = project_roles
        @groups = groups
      end

      def admin?
        admin
      end

      def logged?
        logged
      end

      def allowed_to?(permission, project, global: false, **_opts)
        if global
          permissions.any? { |(perm, _proj), granted| perm == permission && granted }
        else
          permissions[[permission, project]] || false
        end
      end

      def active?
        true
      end

      def roles_for_project(project)
        project_roles[project] || []
      end

      def is_or_belongs_to?(principal)
        principal.equal?(self) || groups.include?(principal)
      end
    end

    class ::Role
      attr_reader :all_tracker_permissions, :tracker_permissions, :issues_visibility

      def initialize(all_tracker_permissions: [], tracker_permissions: {}, issues_visibility: 'all')
        @all_tracker_permissions = all_tracker_permissions
        @tracker_permissions = tracker_permissions
        @issues_visibility = issues_visibility
      end

      def permissions_all_trackers?(permission)
        all_tracker_permissions.include?(permission)
      end

      def permissions_tracker_ids?(permission, tracker_id)
        Array(tracker_permissions[permission]).include?(tracker_id)
      end
    end

    class ::Issue
      attr_accessor :project, :tracker, :assigned_to, :author, :private_flag, :watchers_list, :base_visible, :addable_candidates

      def initialize(project:, tracker:, assigned_to: nil, author: nil, private_flag: false, watchers: [], base_visible: true, addable_candidates: [])
        @project = project
        @tracker = tracker
        @assigned_to = assigned_to
        @author = author
        @private_flag = private_flag
        @watchers_list = watchers
        @base_visible = base_visible
        @addable_candidates = addable_candidates
      end

      def is_private?
        private_flag
      end

      def watcher_principals
        watchers_list
      end

      def visible?(user = nil)
        base_visible
      end

      def watched_by?(user)
        watchers_list.include?(user)
      end

      def addable_watcher_users(user = nil)
        addable_candidates
      end

      def valid_watcher?(principal)
        false
      end
    end

    load File.expand_path('../../../../../lib/redmine_view_issue_description/patches/issue_patch.rb', __FILE__)
  end

  let(:project) { double('Project') }
  let(:tracker) { double('Tracker', id: 1) }
  let(:other_tracker) { double('Tracker', id: 2) }
  let(:all_tracker_watch_role) { Role.new(all_tracker_permissions: [:view_watched_issues]) }

  describe '#tracker_permission_granted?' do
    it 'grants access to admin even without role permissions (M2 regression)' do
      admin = User.new(admin: true, project_roles: {})
      issue = Issue.new(project: project, tracker: tracker)

      expect(issue.tracker_permission_granted?(admin, :view_watched_issues)).to be(true)
    end

    it 'denies access to non-admin without the permission' do
      user = User.new(project_roles: { project => [Role.new] }, permissions: {})
      issue = Issue.new(project: project, tracker: tracker)

      expect(issue.tracker_permission_granted?(user, :view_watched_issues)).to be(false)
    end
  end

  describe '#watcher_access_granted?' do
    it 'denies access when no user is provided' do
      issue = Issue.new(project: project, tracker: tracker)

      expect(issue.watcher_access_granted?(nil)).to be(false)
    end

    it 'grants access to a logged-in watcher with the permission' do
      user = User.new(
        project_roles: { project => [all_tracker_watch_role] },
        permissions: { [:view_watched_issues, project] => true }
      )
      issue = Issue.new(project: project, tracker: tracker, watchers: [user])

      expect(issue.watcher_access_granted?(user)).to be(true)
    end

    it 'grants access via watcher groups when permitted' do
      group = double('Group')
      user = User.new(
        groups: [group],
        project_roles: { project => [all_tracker_watch_role] },
        permissions: { [:view_watched_issues, project] => true }
      )
      issue = Issue.new(project: project, tracker: tracker, watchers: [group])

      expect(issue.watcher_access_granted?(user)).to be(true)
    end

    it 'denies access when permission is missing even if watching' do
      user = User.new
      issue = Issue.new(project: project, tracker: tracker, watchers: [user])

      expect(issue.watcher_access_granted?(user)).to be(false)
    end

    it 'grants access when watcher permission is limited to the issue tracker' do
      role = Role.new(tracker_permissions: { view_watched_issues: [tracker.id] })
      user = User.new(
        permissions: { [:view_watched_issues, project] => true },
        project_roles: { project => [role] }
      )
      issue = Issue.new(project: project, tracker: tracker, watchers: [user])

      expect(issue.watcher_access_granted?(user)).to be(true)
    end

    it 'denies access when watcher permission tracker does not match' do
      role = Role.new(tracker_permissions: { view_watched_issues: [other_tracker.id] })
      user = User.new(
        permissions: { [:view_watched_issues, project] => true },
        project_roles: { project => [role] }
      )
      issue = Issue.new(project: project, tracker: tracker, watchers: [user])

      expect(issue.watcher_access_granted?(user)).to be(false)
    end
  end

  describe '#visible_with_vid?' do
    it 'allows admins to see issues' do
      admin = User.new(admin: true)
      issue = Issue.new(project: project, tracker: tracker)

      expect(issue.visible?(admin)).to be(true)
    end

    it 'allows watchers with permission even when base visibility fails' do
      user = User.new(
        project_roles: { project => [all_tracker_watch_role] },
        permissions: { [:view_watched_issues, project] => true }
      )
      issue = Issue.new(project: project, tracker: tracker, watchers: [user], base_visible: false)

      expect(issue.visible?(user)).to be(true)
    end

    it 'allows watcher visibility when the permission is set for the tracker only' do
      role = Role.new(tracker_permissions: { view_watched_issues: [tracker.id] })
      user = User.new(
        permissions: { [:view_watched_issues, project] => true },
        project_roles: { project => [role] }
      )
      issue = Issue.new(project: project, tracker: tracker, watchers: [user], base_visible: false)

      expect(issue.visible?(user)).to be(true)
    end

    it 'allows watcher visibility when both view permissions are granted' do
      role = Role.new(tracker_permissions: { view_watched_issues: [tracker.id], view_issue_description: [tracker.id] })
      user = User.new(
        permissions: {
          [:view_watched_issues, project] => true,
          [:view_issue_description, project] => true
        },
        project_roles: { project => [role] }
      )
      issue = Issue.new(project: project, tracker: tracker, watchers: [user], base_visible: false)

      expect(issue.visible?(user)).to be(true)
    end

    it 'denies watcher visibility when the tracker is not permitted' do
      role = Role.new(tracker_permissions: { view_watched_issues: [other_tracker.id] })
      user = User.new(
        permissions: { [:view_watched_issues, project] => true },
        project_roles: { project => [role] }
      )
      issue = Issue.new(project: project, tracker: tracker, watchers: [user], base_visible: false)

      expect(issue.visible?(user)).to be(false)
    end

    it 'allows watcher visibility without view_issue_description permission' do
      role = Role.new(tracker_permissions: { view_watched_issues: [tracker.id] })
      user = User.new(
        permissions: { [:view_watched_issues, project] => true },
        project_roles: { project => [role] }
      )
      issue = Issue.new(project: project, tracker: tracker, watchers: [user], base_visible: false)

      expect(issue.visible?(user)).to be(true)
    end

    it 'allows watcher visibility independent of own-only issues visibility constraints' do
      own_description_role = Role.new(
        tracker_permissions: { view_issue_description: [tracker.id] },
        issues_visibility: 'own'
      )
      watcher_role = Role.new(
        tracker_permissions: { view_watched_issues: [tracker.id] },
        issues_visibility: 'all'
      )
      user = User.new(
        permissions: {
          [:view_issue_description, project] => true,
          [:view_watched_issues, project] => true
        },
        project_roles: { project => [own_description_role, watcher_role] }
      )
      issue = Issue.new(project: project, tracker: tracker, author: User.new, private_flag: true, watchers: [user], base_visible: false)

      expect(issue.visible?(user)).to be(true)
    end

    it 'allows seeing the issue with only view_issues permission (description gate moved to controller)' do
      user = User.new(project_roles: { project => [Role.new] }, permissions: { [:view_issues, project] => true })
      issue = Issue.new(project: project, tracker: tracker, base_visible: true)

      expect(issue.visible?(user)).to be(true)
    end

    it 'hides the issue when base visibility also denies access' do
      user = User.new(project_roles: { project => [Role.new] }, permissions: {})
      issue = Issue.new(project: project, tracker: tracker, base_visible: false)

      expect(issue.visible?(user)).to be(false)
    end

    it 'falls back to default visibility when not a watcher' do
      user = User.new
      issue = Issue.new(project: project, tracker: tracker, base_visible: false)

      expect(issue.visible?(user)).to be(false)
    end

    it 'delegates assignee visibility to Redmine core (base visible)' do
      assignee = User.new
      issue = Issue.new(project: project, tracker: tracker, assigned_to: assignee)

      # Plugin does not override assignee visibility at model level; core visible? (base_visible=true) grants it.
      expect(issue.visible?(assignee)).to be(true)
    end

    it 'does not crash and returns false when called with a nil user' do
      issue = Issue.new(project: project, tracker: tracker, base_visible: false)

      expect { issue.visible?(nil) }.not_to raise_error
      expect(issue.visible?(nil)).to be(false)
    end

    it 'does not crash when assigned_to is nil' do
      user = User.new
      issue = Issue.new(project: project, tracker: tracker, assigned_to: nil, base_visible: false)

      expect { issue.visible?(user) }.not_to raise_error
    end

    it 'respects role permissions for viewing descriptions' do
      role = Role.new(all_tracker_permissions: [:view_issue_description])
      user = User.new(
        project_roles: { project => [role] },
        permissions: { [:view_issue_description, project] => true }
      )
      issue = Issue.new(project: project, tracker: tracker)

      expect(issue.visible?(user)).to be(true)
    end

    it 'checks tracker-specific permissions when allowed on project' do
      role = Role.new(tracker_permissions: { view_issue_description: [tracker.id] })
      user = User.new(
        project_roles: { project => [role] },
        permissions: { [:view_issue_description, project] => true }
      )
      issue = Issue.new(project: project, tracker: tracker)

      expect(issue.visible?(user)).to be(true)
    end
  end

  describe '#description_access_granted?' do
    # Regression test for M9: cross-role escalation must not grant access.
    it 'does not leak description access from all-issues role when description role is own-only' do
      own_description_role = Role.new(
        tracker_permissions: { view_issue_description: [tracker.id] },
        issues_visibility: 'own'
      )
      all_issues_role = Role.new(issues_visibility: 'all')
      user = User.new(
        project_roles: { project => [own_description_role, all_issues_role] },
        permissions: { [:view_issue_description, project] => true }
      )
      issue = Issue.new(project: project, tracker: tracker, author: User.new)

      expect(issue.description_access_granted?(user)).to be(false)
    end

    it 'grants description access for own issue with own-only description role' do
      own_description_role = Role.new(
        tracker_permissions: { view_issue_description: [tracker.id] },
        issues_visibility: 'own'
      )
      user = User.new(
        project_roles: { project => [own_description_role] },
        permissions: { [:view_issue_description, project] => true }
      )
      issue = Issue.new(project: project, tracker: tracker, author: user)

      expect(issue.description_access_granted?(user)).to be(true)
    end

    it 'denies description access for private issues with default-visibility role' do
      default_description_role = Role.new(
        tracker_permissions: { view_issue_description: [tracker.id] },
        issues_visibility: 'default'
      )
      user = User.new(
        project_roles: { project => [default_description_role] },
        permissions: { [:view_issue_description, project] => true }
      )
      issue = Issue.new(project: project, tracker: tracker, private_flag: true)

      expect(issue.description_access_granted?(user)).to be(false)
    end

    it 'denies description access for any unrecognised issues_visibility value' do
      unknown_role = Role.new(
        tracker_permissions: { view_issue_description: [tracker.id] },
        issues_visibility: 'assigned'
      )
      assignee = User.new(
        project_roles: { project => [unknown_role] },
        permissions: { [:view_issue_description, project] => true }
      )
      issue = Issue.new(project: project, tracker: tracker, assigned_to: assignee)

      expect(issue.description_access_granted?(assignee)).to be(false)
    end
  end

  describe '#addable_watcher_users_with_vid' do
    let(:project_users) { [] }
    let(:project) { double('Project', users: project_users, members: []) }

    it 'returns base candidates that have the watcher permission' do
      base_user = User.new(
        project_roles: { project => [all_tracker_watch_role] },
        permissions: { [:view_watched_issues, project] => true }
      )
      issue = Issue.new(project: project, tracker: tracker, addable_candidates: [base_user])

      expect(issue.addable_watcher_users(User.new)).to contain_exactly(base_user)
    end

    it 'filters base candidates that lack view_watched_issues' do
      unpermitted_user = User.new(project_roles: { project => [Role.new] }, permissions: {})
      issue = Issue.new(project: project, tracker: tracker, addable_candidates: [unpermitted_user])

      expect(issue.addable_watcher_users(User.new)).to be_empty
    end

    it 'adds project members that have the watcher permission for all trackers' do
      candidate = User.new(project_roles: { project => [all_tracker_watch_role] }, permissions: { [:view_watched_issues, project] => true })
      base_user = User.new(project_roles: { project => [all_tracker_watch_role] }, permissions: { [:view_watched_issues, project] => true })
      project_users << candidate
      issue = Issue.new(project: project, tracker: tracker, addable_candidates: [base_user])

      expect(issue.addable_watcher_users(User.new(project_roles: { project => [all_tracker_watch_role] }))).to contain_exactly(base_user, candidate)
    end

    it 'returns candidates with the watcher permission even when the current user has no project roles' do
      candidate_role = Role.new(all_tracker_permissions: [:view_watched_issues])
      candidate = User.new(project_roles: { project => [candidate_role] }, permissions: { [:view_watched_issues, project] => true })
      project_users << candidate

      issue = Issue.new(project: project, tracker: tracker, addable_candidates: [])

      expect(issue.addable_watcher_users(User.new)).to contain_exactly(candidate)
    end

    it 'includes candidates only when their tracker permission matches the issue tracker' do
      allowed_role    = Role.new(tracker_permissions: { view_watched_issues: [tracker.id] })
      disallowed_role = Role.new(tracker_permissions: { view_watched_issues: [other_tracker.id] })

      allowed_candidate    = User.new(project_roles: { project => [allowed_role] },    permissions: { [:view_watched_issues, project] => true })
      disallowed_candidate = User.new(project_roles: { project => [disallowed_role] }, permissions: { [:view_watched_issues, project] => true })
      project_users.concat([allowed_candidate, disallowed_candidate])

      issue = Issue.new(project: project, tracker: tracker, addable_candidates: [])

      addables = issue.addable_watcher_users(User.new(project_roles: { project => [allowed_role] }))
      expect(addables).to contain_exactly(allowed_candidate)
    end
  end

  describe '#valid_watcher_with_vid?' do
    it 'allows a user with view_watched_issues permission to be a watcher' do
      user = User.new(
        project_roles: { project => [all_tracker_watch_role] },
        permissions: { [:view_watched_issues, project] => true }
      )
      issue = Issue.new(project: project, tracker: tracker)

      expect(issue.valid_watcher?(user)).to be(true)
    end

    it 'denies watcher when tracker permission does not match' do
      role = Role.new(tracker_permissions: { view_watched_issues: [other_tracker.id] })
      user = User.new(
        project_roles: { project => [role] },
        permissions: { [:view_watched_issues, project] => true }
      )
      issue = Issue.new(project: project, tracker: tracker)

      expect(issue.valid_watcher?(user)).to be(false)
    end

    it 'denies watcher when user lacks view_watched_issues (no core fallthrough)' do
      user = User.new(project_roles: { project => [Role.new] }, permissions: {})
      issue = Issue.new(project: project, tracker: tracker)

      # view_watched_issues is the only gate; core is not consulted for User principals.
      expect(issue.valid_watcher?(user)).to be(false)
    end

    it 'allows admin as valid watcher even without view_watched_issues (M2 regression)' do
      admin = User.new(admin: true, project_roles: {})
      issue = Issue.new(project: project, tracker: tracker)

      expect(issue.valid_watcher?(admin)).to be(true)
    end
  end
end
