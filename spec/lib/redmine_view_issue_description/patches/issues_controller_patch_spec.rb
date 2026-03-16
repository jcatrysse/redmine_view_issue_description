# frozen_string_literal: true

require_relative '../../../spec_helper'

# Minimal stubs so the patch file can be loaded outside a Redmine runtime.
unless Kernel.respond_to?(:require_dependency)
  def require_dependency(file)
    require file
  rescue LoadError
  end
end

# Define stubs only if they haven't been defined yet by another spec file.
unless defined?(IssuesController)
  class ::IssuesController
    def show; end
    def edit; end
    def update; end

    def self.method_defined?(m)
      super
    end
  end
end

# Load the patch (this will define the module we reference in describe)
require File.expand_path('../../../../lib/redmine_view_issue_description/patches/issues_controller_patch.rb', __dir__)

RSpec.describe RedmineViewIssueDescription::Patches::IssuesControllerPatch::InstanceMethods do
  # Include instance methods in a testable class
  let(:controller_class) do
    Class.new do
      include RedmineViewIssueDescription::Patches::IssuesControllerPatch::InstanceMethods

      attr_accessor :params
      attr_reader :rendered_403

      def initialize
        @params = {}
        @rendered_403 = false
      end

      def render_403
        @rendered_403 = true
      end

      def api_request?
        false
      end

      def show_without_vid; end
      def edit_without_vid; end
      def update_without_vid; end
    end
  end

  let(:controller) { controller_class.new }

  before do
    @_saved_user = defined?(User) && User.respond_to?(:current) ? User.current : nil

    # Define minimal User if not already defined
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

    user = User.allocate
    # Define admin?/is_or_belongs_to? as singleton methods to avoid polluting the class
    def user.admin?; false; end
    def user.is_or_belongs_to?(principal); principal.equal?(self); end
    User.current = user
  end

  after do
    User.current = @_saved_user
  end

  def make_issue(assigned_to: nil)
    issue = if defined?(::Issue) && Issue.respond_to?(:new)
              Issue.allocate
            else
              Object.new
            end
    issue.define_singleton_method(:assigned_to) { assigned_to }
    issue.define_singleton_method(:watcher_access_granted?) { |_u| false }
    issue.define_singleton_method(:description_access_granted?) { |_u| false }
    issue.define_singleton_method(:project) { Object.new }
    issue
  end

  # ── vid_description_access? ──────────────────────────────────────────────

  describe '#vid_description_access? (via show_with_vid)' do
    it 'grants access to admin' do
      admin = User.allocate
      def admin.admin?; true; end
      def admin.is_or_belongs_to?(_); false; end
      User.current = admin
      controller.instance_variable_set(:@issue, make_issue)

      controller.show_with_vid

      expect(controller.rendered_403).to be(false)
    end

    it 'grants access to the assignee' do
      assignee = User.current
      controller.instance_variable_set(:@issue, make_issue(assigned_to: assignee))

      controller.show_with_vid

      expect(controller.rendered_403).to be(false)
    end

    it 'grants access to a user in the assignee group' do
      group = Object.new
      user = User.allocate
      def user.admin?; false; end
      user.define_singleton_method(:is_or_belongs_to?) { |p| p.equal?(group) }
      User.current = user
      controller.instance_variable_set(:@issue, make_issue(assigned_to: group))

      controller.show_with_vid

      expect(controller.rendered_403).to be(false)
    end

    it 'grants access when watcher_access_granted? returns true' do
      issue = make_issue
      issue.define_singleton_method(:watcher_access_granted?) { |_u| true }
      controller.instance_variable_set(:@issue, issue)

      controller.show_with_vid

      expect(controller.rendered_403).to be(false)
    end

    it 'grants access when description_access_granted? returns true' do
      issue = make_issue
      issue.define_singleton_method(:description_access_granted?) { |_u| true }
      controller.instance_variable_set(:@issue, issue)

      controller.show_with_vid

      expect(controller.rendered_403).to be(false)
    end

    it 'renders 403 when no access path is satisfied' do
      controller.instance_variable_set(:@issue, make_issue)

      controller.show_with_vid

      expect(controller.rendered_403).to be(true)
    end

    it 'renders 403 when assigned_to is nil and no other access' do
      controller.instance_variable_set(:@issue, make_issue(assigned_to: nil))

      controller.show_with_vid

      expect(controller.rendered_403).to be(true)
    end
  end

  # ── edit_with_vid ────────────────────────────────────────────────────────

  describe '#edit_with_vid' do
    it 'renders 403 when user lacks description access' do
      controller.instance_variable_set(:@issue, make_issue)

      controller.edit_with_vid

      expect(controller.rendered_403).to be(true)
    end

    it 'delegates to edit_without_vid when access is granted' do
      admin = User.allocate
      def admin.admin?; true; end
      User.current = admin
      controller.instance_variable_set(:@issue, make_issue)

      expect(controller).to receive(:edit_without_vid)

      controller.edit_with_vid
    end
  end

  # ── update_with_vid ──────────────────────────────────────────────────────

  describe '#update_with_vid' do
    it 'renders 403 when user lacks description access' do
      controller.instance_variable_set(:@issue, make_issue)

      controller.update_with_vid

      expect(controller.rendered_403).to be(true)
    end

    it 'delegates to update_without_vid when access is granted' do
      admin = User.allocate
      def admin.admin?; true; end
      User.current = admin
      controller.instance_variable_set(:@issue, make_issue)

      expect(controller).to receive(:update_without_vid)

      controller.update_with_vid
    end
  end

  # ── include_changesets_new? ──────────────────────────────────────────────

  describe '#include_changesets_new?' do
    it 'detects changesets_new in comma-separated include param' do
      controller.params = { include: 'journals,changesets_new' }

      expect(controller.send(:include_changesets_new?)).to be(true)
    end

    it 'detects changesets_new in array include param' do
      controller.params = { include: ['journals', 'changesets_new'] }

      expect(controller.send(:include_changesets_new?)).to be(true)
    end

    it 'returns false when changesets_new is not requested' do
      controller.params = { include: 'journals,changesets' }

      expect(controller.send(:include_changesets_new?)).to be(false)
    end

    it 'returns false when include is nil' do
      controller.params = {}

      expect(controller.send(:include_changesets_new?)).to be(false)
    end
  end

  # ── include_journal_messages? ────────────────────────────────────────────

  describe '#include_journal_messages?' do
    it 'detects journal_messages in comma-separated include param' do
      controller.params = { include: 'journals,journal_messages' }

      expect(controller.send(:include_journal_messages?)).to be(true)
    end

    it 'detects journal_messages in array include param' do
      controller.params = { include: ['journals', 'journal_messages'] }

      expect(controller.send(:include_journal_messages?)).to be(true)
    end

    it 'returns false when journal_messages is not requested' do
      controller.params = { include: 'journals' }

      expect(controller.send(:include_journal_messages?)).to be(false)
    end
  end
end
