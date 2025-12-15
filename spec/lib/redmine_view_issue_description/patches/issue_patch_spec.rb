require_relative '../../../spec_helper'

unless defined?(RedmineViewIssueDescription)
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

      def allowed_to?(permission, project)
        permissions[[permission, project]] || false
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
      attr_reader :all_tracker_permissions, :tracker_permissions

      def initialize(all_tracker_permissions: [], tracker_permissions: {})
        @all_tracker_permissions = all_tracker_permissions
        @tracker_permissions = tracker_permissions
      end

      def permissions_all_trackers?(permission)
        all_tracker_permissions.include?(permission)
      end

      def permissions_tracker_ids?(permission, tracker_id)
        Array(tracker_permissions[permission]).include?(tracker_id)
      end
    end

    class ::Issue
      attr_accessor :project, :tracker, :assigned_to, :watchers_list, :base_visible, :addable_candidates

      def initialize(project:, tracker:, assigned_to: nil, watchers: [], base_visible: true, addable_candidates: [])
        @project = project
        @tracker = tracker
        @assigned_to = assigned_to
        @watchers_list = watchers
        @base_visible = base_visible
        @addable_candidates = addable_candidates
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

      expect(issue.visible?(user)).to be(false)
    end

    it 'allows watcher visibility when the permission is set for the tracker only' do
      role = Role.new(tracker_permissions: { view_watched_issues: [tracker.id] })
      user = User.new(
        permissions: { [:view_watched_issues, project] => true },
        project_roles: { project => [role] }
      )
      issue = Issue.new(project: project, tracker: tracker, watchers: [user], base_visible: false)

      expect(issue.visible?(user)).to be(false)
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

    it 'requires view_issue_description permission even for watchers' do
      role = Role.new(tracker_permissions: { view_watched_issues: [tracker.id] })
      user = User.new(
        permissions: { [:view_watched_issues, project] => true },
        project_roles: { project => [role] }
      )
      issue = Issue.new(project: project, tracker: tracker, watchers: [user], base_visible: false)

      expect(issue.visible?(user)).to be(false)
    end

    it 'denies viewing the description without the view_issue_description permission' do
      user = User.new(project_roles: { project => [Role.new] }, permissions: { [:view_issues, project] => true })
      issue = Issue.new(project: project, tracker: tracker)

      expect(issue.visible?(user)).to be(false)
    end

    it 'falls back to default visibility when not a watcher' do
      user = User.new
      issue = Issue.new(project: project, tracker: tracker, base_visible: false)

      expect(issue.visible?(user)).to be(false)
    end

    it 'allows access for users assigned to the issue' do
      assignee = User.new
      issue = Issue.new(project: project, tracker: tracker, assigned_to: assignee)

      expect(issue.visible?(assignee)).to be(true)
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

  describe '#addable_watcher_users_with_vid' do
    let(:project_users) { [] }
    let(:project) { double('Project', users: project_users) }

    it 'returns base candidates when there are no additional users with permission' do
      base_user = User.new
      issue = Issue.new(project: project, tracker: tracker, addable_candidates: [base_user])

      expect(issue.addable_watcher_users(User.new)).to contain_exactly(base_user)
    end

    it 'adds project members that have the watcher permission for all trackers' do
      candidate = User.new(project_roles: { project => [all_tracker_watch_role] }, permissions: { [:view_watched_issues, project] => true })
      base_user = User.new
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
      allowed_role = Role.new(tracker_permissions: { view_watched_issues: [tracker.id] })
      disallowed_role = Role.new(tracker_permissions: { view_watched_issues: [other_tracker.id] })

      allowed_candidate = User.new(project_roles: { project => [allowed_role] }, permissions: { [:view_watched_issues, project] => true })
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
  end
end
