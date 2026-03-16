# frozen_string_literal: true

require_relative '../../../spec_helper'

unless Kernel.respond_to?(:require_dependency)
  def require_dependency(file)
    require file
  rescue LoadError
  end
end

# Stub QueryColumn
QueryColumn = Struct.new(:name) unless defined?(QueryColumn)

# Stub Query base class (only if not already defined)
unless defined?(Query)
  class ::Query
    attr_accessor :project

    def columns
      [QueryColumn.new(:id), QueryColumn.new(:subject), QueryColumn.new(:description)]
    end

    def available_block_columns
      [QueryColumn.new(:description), QueryColumn.new(:notes)]
    end

    def has_column?(column)
      columns.any? { |c| c.name == (column.is_a?(QueryColumn) ? column.name : column) }
    end

    def self.method_defined?(m)
      super
    end
  end
end

# Load the patch — this patches Query via alias_method at the class level
require File.expand_path('../../../../lib/redmine_view_issue_description/patches/query_patch.rb', __dir__)

RSpec.describe RedmineViewIssueDescription::Patches::QueryPatch::InstanceMethods do
  # The patch already applied alias_method on Query at load time,
  # so Query subclasses inherit the patched columns/available_block_columns/has_column?.
  # No need to re-alias here.
  let(:query) do
    q = Query.new
    q.project = project_obj
    q
  end

  let(:project_obj) { Object.new }

  before do
    @_saved_user = defined?(User) && User.respond_to?(:current) ? User.current : nil

    unless defined?(::Tracker)
      Object.const_set(:Tracker, Class.new do
        class << self
          attr_accessor :tracker_ids
        end

        def self.pluck(_col)
          Array(tracker_ids)
        end
      end)
    end

    Tracker.tracker_ids = [1, 2] if Tracker.respond_to?(:tracker_ids=)

    unless defined?(::Role)
      Object.const_set(:Role, Class.new do
        attr_reader :all_tracker_permissions, :tracker_permissions

        def initialize(all_tracker_permissions: [], tracker_permissions: {})
          @all_tracker_permissions = all_tracker_permissions
          @tracker_permissions     = tracker_permissions
        end

        def permissions_all_trackers?(permission)
          all_tracker_permissions.include?(permission)
        end

        def permissions_tracker_ids?(permission, tracker_id)
          Array(tracker_permissions[permission]).include?(tracker_id)
        end
      end)
    end

    unless defined?(::User)
      Object.const_set(:User, Class.new)
    end

    unless User.respond_to?(:current=)
      User.class_eval do
        class << self
          attr_accessor :current
        end
      end
    end
  end

  after do
    User.current = @_saved_user
  end

  def make_user(admin: false, permissions: {}, project_roles: {})
    user = User.allocate
    user.define_singleton_method(:admin?) { admin }
    user.define_singleton_method(:allowed_to?) do |permission, proj, **_opts|
      permissions[[permission, proj]] || false
    end
    user.define_singleton_method(:roles_for_project) do |proj|
      project_roles[proj] || []
    end
    user
  end

  # ── Admin always sees description ───────────────────────────────────────

  describe 'admin access' do
    before { User.current = make_user(admin: true) }

    it 'includes the description column for admin' do
      expect(query.columns.map(&:name)).to include(:description)
    end

    it 'includes description in block columns for admin' do
      expect(query.available_block_columns.map(&:name)).to include(:description)
    end

    it 'reports has_column? true for description' do
      expect(query.has_column?(:description)).to be(true)
    end
  end

  # ── User with view_issue_description for all trackers ───────────────────

  describe 'user with full permission' do
    before do
      role = Role.new(all_tracker_permissions: [:view_issue_description])
      User.current = make_user(
        permissions: { [:view_issue_description, project_obj] => true },
        project_roles: { project_obj => [role] }
      )
    end

    it 'includes the description column' do
      expect(query.columns.map(&:name)).to include(:description)
    end
  end

  # ── User with tracker-scoped permission ─────────────────────────────────

  describe 'user with tracker-scoped permission' do
    before do
      role = Role.new(tracker_permissions: { view_issue_description: [1] })
      User.current = make_user(
        permissions: { [:view_issue_description, project_obj] => true },
        project_roles: { project_obj => [role] }
      )
    end

    it 'includes the description column when at least one tracker is permitted' do
      expect(query.columns.map(&:name)).to include(:description)
    end
  end

  # ── User without view_issue_description ─────────────────────────────────

  describe 'user without permission' do
    before { User.current = make_user }

    it 'excludes the description column' do
      expect(query.columns.map(&:name)).not_to include(:description)
    end

    it 'excludes description from block columns' do
      expect(query.available_block_columns.map(&:name)).not_to include(:description)
    end

    it 'reports has_column? false for description' do
      expect(query.has_column?(:description)).to be(false)
    end

    it 'does not affect non-description columns' do
      expect(query.columns.map(&:name)).to include(:id, :subject)
    end
  end

  # ── Cross-project query (project is nil) ────────────────────────────────

  describe 'cross-project query (project nil)' do
    before do
      role = Role.new(all_tracker_permissions: [:view_issue_description])
      User.current = make_user(
        permissions: { [:view_issue_description, project_obj] => true },
        project_roles: { project_obj => [role] }
      )
      query.project = nil
    end

    it 'hides description for non-admin when project is nil' do
      expect(query.columns.map(&:name)).not_to include(:description)
    end

    it 'shows description for admin when project is nil' do
      User.current = make_user(admin: true)

      expect(query.columns.map(&:name)).to include(:description)
    end
  end

  # ── User with permission but no matching tracker ────────────────────────

  describe 'user with permission but no matching tracker' do
    before do
      role = Role.new(tracker_permissions: { view_issue_description: [999] })
      Tracker.tracker_ids = [1, 2]
      User.current = make_user(
        permissions: { [:view_issue_description, project_obj] => true },
        project_roles: { project_obj => [role] }
      )
    end

    it 'excludes description when no system tracker matches the role permission' do
      expect(query.columns.map(&:name)).not_to include(:description)
    end
  end
end
