require_relative '../spec_helper'

RSpec.describe 'Issue.visible_condition patch' do
  before do
    Object.send(:remove_const, :Issue) if Object.const_defined?(:Issue)
    Object.send(:remove_const, :User) if Object.const_defined?(:User)
    Object.send(:remove_const, :Project) if Object.const_defined?(:Project)

    stub_const('User', Class.new do
      attr_reader :id, :memberships

      def initialize(id:, logged: true, memberships: [])
        @id = id
        @logged = logged
        @memberships = memberships
      end

      def logged?
        @logged
      end

      def allowed_to?(permission, project)
        memberships.any? { |membership| membership.project == project && membership.allows?(permission) }
      end

      def roles_for_project(project)
        memberships.find { |membership| membership.project == project }&.roles || []
      end

      def is_or_belongs_to?(_principal)
        false
      end
    end)

    stub_const('Project', Class.new do
      class << self
        attr_accessor :project_ids, :last_condition
      end

      def self.allowed_to_condition(user, permission)
        { user: user, permission: permission }
      end

      def self.where(condition)
        self.last_condition = condition
        self
      end

      def self.pluck(_column)
        project_ids || []
      end
    end)

    stub_const('Tracker', Class.new do
      class << self
        attr_accessor :tracker_ids
      end

      attr_reader :id

      def initialize(id:)
        @id = id
      end

      def self.all
        Array(tracker_ids).map { |id| new(id: id) }
      end
    end)

    stub_const('MemberRole', Class.new do
      attr_reader :role

      def initialize(role)
        @role = role
      end
    end)

    stub_const('Member', Class.new do
      attr_reader :project, :roles, :allowed_permissions

      def initialize(project:, roles:, allowed_permissions: [:view_watched_issues])
        @project = project
        @roles = roles
        @allowed_permissions = allowed_permissions
      end

      def allows?(permission)
        allowed_permissions.include?(permission)
      end
    end)

    stub_const('Role', Class.new do
      attr_reader :tracker_permissions, :all_tracker_permissions

      def initialize(tracker_permissions: {}, all_tracker_permissions: [])
        @tracker_permissions = tracker_permissions
        @all_tracker_permissions = all_tracker_permissions
      end

      def permissions_all_trackers?(permission)
        all_tracker_permissions.include?(permission)
      end

      def permissions_tracker_ids?(permission, tracker_id)
        Array(tracker_permissions[permission]).include?(tracker_id)
      end
    end)

    stub_const('Issue', Class.new do
      def self.table_name
        'issues'
      end

      def self.visible_condition(_user, _options = {})
        'base_condition'
      end

      def visible?(_user = nil)
        true
      end
    end)

    Kernel.module_eval do
      def require_dependency(*); end
    end

    load File.expand_path('../../lib/redmine_view_issue_description/patches/issue_patch.rb', __dir__)
  end

  it 'keeps the original condition for anonymous users' do
    anonymous = User.new(id: 5, logged: false)

    expect(Issue.visible_condition(anonymous)).to eq('base_condition')
  end

  it 'returns the base condition when the user has no permitted projects' do
    Project.project_ids = []
    user = User.new(id: 7)

    expect(Issue.visible_condition(user)).to eq('base_condition')
  end

  it 'extends the condition with watched issues for permitted projects' do
    tracker = Tracker.new(id: 2)
    Tracker.tracker_ids = [tracker.id]
    project = double('Project', id: 3)
    role = Role.new(all_tracker_permissions: [:view_watched_issues])
    membership = Member.new(project: project, roles: [role])
    Project.project_ids = [project.id]
    user = User.new(id: 11, memberships: [membership])

    condition = Issue.visible_condition(user)

    expect(condition).to include('base_condition')
    expect(condition).to include('watchers w')
    expect(condition).to include('w.user_id = 11')
    expect(condition).to include('issues.project_id = 3')
  end

  it 'limits watched issues to permitted trackers' do
    project = double('Project', id: 7)
    tracker = Tracker.new(id: 9)
    Tracker.tracker_ids = [tracker.id]
    role = Role.new(tracker_permissions: { view_watched_issues: [tracker.id] })
    membership = Member.new(project: project, roles: [role])
    Project.project_ids = [project.id]
    user = User.new(id: 15, memberships: [membership])

    condition = Issue.visible_condition(user)

    expect(condition).to include('issues.tracker_id IN (9)')
    expect(condition).to include('issues.project_id = 7')
  end

  it 'omits watched condition when no trackers are permitted' do
    project = double('Project', id: 8)
    Tracker.tracker_ids = [5]
    role = Role.new(tracker_permissions: { view_watched_issues: [] })
    membership = Member.new(project: project, roles: [role])
    Project.project_ids = [project.id]
    user = User.new(id: 21, memberships: [membership])

    expect(Issue.visible_condition(user)).to eq('base_condition')
  end
end
