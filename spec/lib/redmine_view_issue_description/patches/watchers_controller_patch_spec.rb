require_relative '../../../spec_helper'

unless Kernel.respond_to?(:require_dependency)
  def require_dependency(file)
    require file
  rescue LoadError
  end
end

class ::WatchersController
  def self.helper_method(*); end
  def self.before_action(*); end

  def users_for_new_watcher
    []
  end
end

redmine_root = File.expand_path('../../../../../../', __dir__)
redmine_lib = File.join(redmine_root, 'lib')
$LOAD_PATH.unshift(redmine_lib) if Dir.exist?(redmine_lib) && !$LOAD_PATH.include?(redmine_lib)

unless defined?(ActionController::Base)
  module ActionController
    class Base; end
  end
end

if defined?(Redmine) && Redmine.respond_to?(:autoload?) && Redmine.autoload?(:I18n)
  Redmine.send(:remove_const, :I18n)
end

unless defined?(Redmine::I18n)
  module Redmine
    module I18n
    end
  end
end

# Prevent LoadError when the patch does `require 'redmine/pagination'` outside Redmine
$LOADED_FEATURES << 'redmine/pagination' unless $LOADED_FEATURES.include?('redmine/pagination')

unless defined?(Redmine::Pagination)
  module Redmine
    module Pagination
      class Paginator
        attr_reader :per_page, :item_count, :page

        def initialize(count, per_page, page)
          @item_count = count.to_i
          @per_page   = per_page.to_i
          @page       = [page.to_i, 1].max
        end

        def page_count
          return 1 if @per_page.zero?
          ((@item_count - 1) / @per_page) + 1
        end

        def previous_page
          @page > 1 ? @page - 1 : nil
        end

        def next_page
          @page < page_count ? @page + 1 : nil
        end
      end
    end
  end
end

require File.expand_path('../../../../lib/redmine_view_issue_description/patches/watchers_controller_patch.rb', __dir__)

RSpec.describe RedmineViewIssueDescription::Patches::WatchersControllerPatch do
  before(:all) do
    class ::User
      attr_reader :name, :login

      def initialize(name:, login: nil)
        @name = name
        @login = login || name
      end
    end

    class ::FakeScope
      attr_reader :users

      def initialize(users)
        @users = users
      end

      def assignable_watchers
        self
      end

      def sorted
        FakeScope.new(users.sort_by(&:name))
      end

      def like(query)
        return self if query.to_s.strip.empty?

        FakeScope.new(users.select do |user|
          user.name.downcase.include?(query.downcase) || user.login.downcase.include?(query.downcase)
        end)
      end

      def limit(value)
        FakeScope.new(users.first(value))
      end

      def offset(value)
        FakeScope.new(users.drop(value))
      end

      def distinct
        self
      end

      def joins(*)
        self
      end

      def where(*)
        self
      end

      def to_a
        users
      end
    end

    class ::Principal
      class << self
        attr_accessor :assignable_scope
      end

      def self.assignable_watchers
        assignable_scope || FakeScope.new([])
      end

      def self.joins(*)
        assignable_watchers
      end

      def self.where(*)
        assignable_watchers
      end
    end

    class ::Project
      attr_reader :principals, :id

      @@_vid_next_id = 0

      def initialize(users)
        @@_vid_next_id += 1
        @id = @@_vid_next_id
        @principals = FakeScope.new(users)
      end
    end

    class ::Watchable
      attr_reader :visible_watcher_users, :allowed_users

      def initialize(visible_watcher_users: [], allowed_users: [])
        @visible_watcher_users = visible_watcher_users
        @allowed_users = allowed_users
      end

      def valid_watcher?(user)
        allowed_users.empty? || allowed_users.include?(user)
      end
    end

    class ::WatchersController
      attr_accessor :params, :projects
      attr_reader :project, :watchables

      def initialize
        @params = {}
        @projects = []
        @watchables = []
      end

      def project=(project)
        @project = project
      end

      def watchables=(watchables)
        @watchables = watchables
      end
    end
  end

  def build_users(count)
    Array.new(count) { |index| User.new(name: format('User %03d', index), login: "user#{index}") }
  end

  # ── check_self_watch_permission ──────────────────────────────────────────────

  describe '#check_self_watch_permission' do
    before(:all) do
      ::WatchersController.class_eval do
        def render_403
          @_vid_403_called = true
        end

        def vid_403_called?
          @_vid_403_called == true
        end
      end

      # Add User.current class accessor and id instance method if absent.
      unless ::User.respond_to?(:current=)
        ::User.class_eval do
          class << self
            attr_accessor :current
          end
        end
      end

      unless ::User.method_defined?(:id)
        ::User.class_eval do
          def id
            @name.hash.abs
          end
        end
      end

      unless ::User.method_defined?(:admin?)
        ::User.class_eval do
          def admin?
            @admin == true
          end

          def is_or_belongs_to?(principal)
            principal.equal?(self)
          end
        end
      end

      # Add Issue.where lookup used by resolve_issues_from_params.
      # Uses a class-level instance variable registry so each example can register
      # fake issues by id without triggering Ruby 3.x toplevel @@ warnings.
      unless defined?(::Issue)
        class ::Issue; end
      end
      unless ::Issue.respond_to?(:where)
        ::Issue.instance_variable_set(:@_ctrl_spec_store, {})

        ::Issue.define_singleton_method(:register_for_ctrl_spec) do |id, issue|
          @_ctrl_spec_store[id] = issue
        end

        ::Issue.define_singleton_method(:clear_ctrl_spec_registry) do
          @_ctrl_spec_store.clear
        end

        ::Issue.define_singleton_method(:where) do |conditions = {}|
          ids = Array(conditions[:id])
          store = @_ctrl_spec_store
          found = ids.map { |i| store[i] }.compact
          Struct.new(:items) { def to_a; items; end }.new(found)
        end
      end
    end

    after { ::Issue.clear_ctrl_spec_registry if ::Issue.respond_to?(:clear_ctrl_spec_registry) }

    let(:current_user) { User.new(name: 'Current User') }

    before { allow(User).to receive(:current).and_return(current_user) }

    # ── Stubbing resolve_watchable_issues lets us test check_self_watch_permission
    # in isolation, independent of how Issues are resolved from params. ──────

    it 'renders 403 when user lacks description access on the Issue' do
      blocking_issue = double('Issue', assigned_to: nil)
      allow(blocking_issue).to receive(:description_access_granted?)
        .with(current_user).and_return(false)

      ctrl = WatchersController.new
      allow(ctrl).to receive(:resolve_watchable_issues).and_return([blocking_issue])

      ctrl.send(:check_self_watch_permission)

      expect(ctrl.vid_403_called?).to be(true)
    end

    it 'does not render 403 when the user has description access on the Issue' do
      allowing_issue = double('Issue', assigned_to: nil)
      allow(allowing_issue).to receive(:description_access_granted?)
        .with(current_user).and_return(true)

      ctrl = WatchersController.new
      allow(ctrl).to receive(:resolve_watchable_issues).and_return([allowing_issue])

      ctrl.send(:check_self_watch_permission)

      expect(ctrl.vid_403_called?).not_to be(true)
    end

    it 'does not render 403 when the user is the assignee' do
      issue = double('Issue', assigned_to: current_user)
      # description_access_granted? not needed — assignee short-circuits

      ctrl = WatchersController.new
      allow(ctrl).to receive(:resolve_watchable_issues).and_return([issue])

      ctrl.send(:check_self_watch_permission)

      expect(ctrl.vid_403_called?).not_to be(true)
    end

    it 'does not render 403 when the user is admin (M2 regression)' do
      admin_user = User.new(name: 'Admin User')
      admin_user.instance_variable_set(:@admin, true)
      allow(User).to receive(:current).and_return(admin_user)

      blocking_issue = double('Issue', assigned_to: nil)
      allow(blocking_issue).to receive(:description_access_granted?)
        .with(admin_user).and_return(false)

      ctrl = WatchersController.new
      allow(ctrl).to receive(:resolve_watchable_issues).and_return([blocking_issue])

      ctrl.send(:check_self_watch_permission)

      expect(ctrl.vid_403_called?).not_to be(true)
    end

    # M1 regression: a user who holds view_watched_issues but lacks
    # view_issue_description must NOT be able to self-watch.
    it 'renders 403 when user has view_watched_issues but no description access (M1 regression)' do
      escalation_issue = double('Issue', assigned_to: nil)
      allow(escalation_issue).to receive(:description_access_granted?)
        .with(current_user).and_return(false)

      ctrl = WatchersController.new
      allow(ctrl).to receive(:resolve_watchable_issues).and_return([escalation_issue])

      ctrl.send(:check_self_watch_permission)

      expect(ctrl.vid_403_called?).to be(true)
    end

    it 'does not render 403 when a manager adds a different user (current user not in requested ids)' do
      blocking_issue = double('Issue', assigned_to: nil)
      allow(blocking_issue).to receive(:description_access_granted?).and_return(false)

      ctrl = WatchersController.new
      ctrl.params[:user_id] = '9999'  # some other user — not current_user.id
      allow(ctrl).to receive(:resolve_watchable_issues).and_return([blocking_issue])

      ctrl.send(:check_self_watch_permission)

      expect(ctrl.vid_403_called?).not_to be(true)
    end

    it 'does not render 403 when there are no watchable Issues to check' do
      ctrl = WatchersController.new
      allow(ctrl).to receive(:resolve_watchable_issues).and_return([])

      ctrl.send(:check_self_watch_permission)

      expect(ctrl.vid_403_called?).not_to be(true)
    end

    # ── regression: watch action sets @watchables in the action body, not via
    # a before_action.  resolve_watchable_issues must fall through to params. ──

    it 'resolves the blocking Issue from params when @watchables is not yet set (watch action path)' do
      issue = double('Issue', assigned_to: nil)
      allow(issue).to receive(:is_a?).with(Issue).and_return(true)
      allow(issue).to receive(:description_access_granted?)
        .with(current_user).and_return(false)
      Issue.register_for_ctrl_spec(801, issue)

      ctrl = WatchersController.new  # @watchables = [] (empty, not yet populated)
      ctrl.params = { object_type: 'Issue', object_ids: [801] }

      ctrl.send(:check_self_watch_permission)

      expect(ctrl.vid_403_called?).to be(true)
    end

    it 'allows the watch when Issue is resolved from params and user has description access' do
      issue = double('Issue', assigned_to: nil)
      allow(issue).to receive(:is_a?).with(Issue).and_return(true)
      allow(issue).to receive(:description_access_granted?)
        .with(current_user).and_return(true)
      Issue.register_for_ctrl_spec(802, issue)

      ctrl = WatchersController.new
      ctrl.params = { object_type: 'Issue', object_ids: [802] }

      ctrl.send(:check_self_watch_permission)

      expect(ctrl.vid_403_called?).not_to be(true)
    end
  end

  # ── resolve_issues_from_params ────────────────────────────────────────────

  describe '#resolve_issues_from_params (via resolve_watchable_issues)' do
    it 'returns empty when object_type is not Issue' do
      ctrl = WatchersController.new
      ctrl.params = { object_type: 'WikiPage', object_ids: [1] }

      result = ctrl.send(:resolve_watchable_issues)

      expect(result).to be_empty
    end

    it 'returns empty when no object IDs are provided' do
      ctrl = WatchersController.new
      ctrl.params = { object_type: 'Issue' }

      result = ctrl.send(:resolve_watchable_issues)

      expect(result).to be_empty
    end

    it 'supports the singular object_id param variant' do
      issue = double('Issue')
      allow(issue).to receive(:is_a?).with(Issue).and_return(true)
      Issue.register_for_ctrl_spec(803, issue)

      ctrl = WatchersController.new
      ctrl.params = { object_type: 'Issue', object_id: '803' }

      result = ctrl.send(:resolve_watchable_issues)

      expect(result).to include(issue)
    end
  end

  describe '#users_for_new_watcher_with_vid' do
    it 'paginates the candidate list when no query is provided' do
      controller = WatchersController.new
      users = build_users(30)
      controller.project = Project.new(users)
      controller.watchables = [Watchable.new]

      result = controller.send(:users_for_new_watcher)

      expect(result.size).to eq(25)
      expect(result.map(&:name)).to eq(users.sort_by(&:name).first(25).map(&:name))
    end

    it 'returns subsequent pages when requested' do
      controller = WatchersController.new
      users = build_users(30)
      controller.project = Project.new(users)
      controller.watchables = [Watchable.new]
      controller.params[:page] = 2
      controller.params[:per_page] = 10

      result = controller.send(:users_for_new_watcher)

      expect(result.map(&:name)).to eq(users.sort_by(&:name)[10, 10].map(&:name))
    end

    it 'filters by query before paginating' do
      controller = WatchersController.new
      users = build_users(50)
      controller.project = Project.new(users)
      controller.watchables = [Watchable.new]
      controller.params[:q] = 'User 01'
      controller.params[:per_page] = 5

      result = controller.send(:users_for_new_watcher)

      expect(result.all? { |user| user.name.include?('User 01') }).to be(true)
      expect(result.size).to be <= 5
    end

    it 'excludes already visible watchers for single watchables' do
      controller = WatchersController.new
      allowed_users = build_users(5)
      blocked_user = User.new(name: 'Blocked User', login: 'blocked')
      watchable = Watchable.new(visible_watcher_users: [blocked_user], allowed_users: allowed_users)
      controller.project = Project.new(allowed_users + [blocked_user])
      controller.watchables = [watchable]

      result = controller.send(:users_for_new_watcher)

      expect(result).not_to include(blocked_user)
      expect(result).to match_array(allowed_users)
    end

    it 'caps the page size to 100 to avoid oversized queries' do
      controller = WatchersController.new
      users = build_users(150)
      controller.project = Project.new(users)
      controller.watchables = [Watchable.new]
      controller.params[:per_page] = 200

      result = controller.send(:users_for_new_watcher)

      expect(result.size).to eq(100)
    end

    it 'defaults to the first page when the page number is invalid' do
      controller = WatchersController.new
      users = build_users(30)
      controller.project = Project.new(users)
      controller.watchables = [Watchable.new]
      controller.params[:page] = 0
      controller.params[:per_page] = 10

      result = controller.send(:users_for_new_watcher)

      expect(result.map(&:name)).to eq(users.sort_by(&:name).first(10).map(&:name))
    end

    it 'reports correct total count after valid_watcher? filtering (prevents broken pagination)' do
      controller = WatchersController.new
      allowed_users = build_users(10)
      restricted_user = User.new(name: 'Zzz Restricted', login: 'restricted')
      # Only 10 of 11 users pass valid_watcher? (allowed_users list is explicit)
      watchable = Watchable.new(allowed_users: allowed_users)
      controller.project = Project.new(allowed_users + [restricted_user])
      controller.watchables = [watchable]
      controller.params[:per_page] = 5

      result = controller.send(:users_for_new_watcher)

      expect(result.size).to eq(5)
      expect(controller.instance_variable_get(:@watcher_total_count)).to eq(10)
    end

    it 'scopes to single project when @projects has one entry and @project is nil' do
      controller = WatchersController.new
      users = build_users(5)
      project = Project.new(users)
      # @project is nil, but @projects has one entry
      controller.projects = [project]
      controller.watchables = [Watchable.new]

      result = controller.send(:users_for_new_watcher)

      expect(result.map(&:name)).to eq(users.sort_by(&:name).map(&:name))
    end

    it 'preserves object_ids in pagination link params for bulk-watcher flows' do
      controller = WatchersController.new
      controller.params = {
        object_type: 'Issue',
        object_ids: ['10', '20', '30'],
        project_id: '1',
        per_page: '10',
        q: 'john'
      }

      result = controller.send(:watcher_pagination_link_params, page: 2)

      expect(result[:'object_ids[]']).to eq(['10', '20', '30'])
      expect(result[:object_type]).to eq('Issue')
      expect(result[:page]).to eq(2)
    end

    it 'omits object_ids from pagination link params when not present' do
      controller = WatchersController.new
      controller.params = {
        object_type: 'Issue',
        object_id: '10',
        project_id: '1'
      }

      result = controller.send(:watcher_pagination_link_params, page: 2)

      expect(result).not_to have_key(:'object_ids[]')
      expect(result[:object_id]).to eq('10')
    end

    it 'uses the principal scope when searching across multiple projects' do
      controller = WatchersController.new
      users = build_users(12)
      Principal.assignable_scope = FakeScope.new(users)
      controller.projects = [Project.new(users), Project.new(users)]
      controller.watchables = []

      result = controller.send(:users_for_new_watcher)

      expect(result.map(&:name)).to eq(users.sort_by(&:name).first(25).map(&:name))
    ensure
      Principal.assignable_scope = nil
    end
  end
end
