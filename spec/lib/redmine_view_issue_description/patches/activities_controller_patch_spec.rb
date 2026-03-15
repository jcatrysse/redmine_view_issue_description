# frozen_string_literal: true

require_relative '../../../spec_helper'

unless Kernel.respond_to?(:require_dependency)
  def require_dependency(file)
    require file
  rescue LoadError
  end
end

# Minimal ActiveSupport polyfill — the patch uses @project.present?
unless Object.method_defined?(:present?)
  class ::Object
    def present?
      respond_to?(:empty?) ? !empty? : !nil?
    end
  end

  class ::NilClass
    def present?; false; end
  end

  class ::FalseClass
    def present?; false; end
  end
end

unless defined?(ActivitiesController)
  class ::ActivitiesController
    def index; end

    def self.method_defined?(m)
      super
    end
  end
end

# Load the patch
require File.expand_path('../../../../lib/redmine_view_issue_description/patches/activities_controller_patch.rb', __dir__)

RSpec.describe RedmineViewIssueDescription::Patches::ActivitiesControllerPatch::InstanceMethods do
  let(:controller_class) do
    Class.new do
      include RedmineViewIssueDescription::Patches::ActivitiesControllerPatch::InstanceMethods

      attr_accessor :project
      attr_reader :denied, :index_called

      def initialize
        @denied       = false
        @index_called = false
      end

      def deny_access
        @denied = true
      end

      def index_without_vid
        @index_called = true
      end
    end
  end

  let(:controller) { controller_class.new }
  let(:project_obj) { Object.new }

  before do
    @_saved_user = defined?(User) && User.respond_to?(:current) ? User.current : nil

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

  def make_user(admin: false, permissions: {})
    user = User.allocate
    user.define_singleton_method(:admin?) { admin }
    user.define_singleton_method(:allowed_to?) do |permission, proj, global: false, **_opts|
      if global
        permissions[[permission, :global]] || false
      else
        permissions[[permission, proj]] || false
      end
    end
    user
  end

  # ── Project-scoped activity ──────────────────────────────────────────────

  describe '#index_with_vid (project-scoped)' do
    before { controller.project = project_obj }

    it 'allows admin access without permission check' do
      User.current = make_user(admin: true)

      controller.index_with_vid

      expect(controller.denied).to be(false)
      expect(controller.index_called).to be(true)
    end

    it 'allows access when user has view_activities permission' do
      User.current = make_user(permissions: { [:view_activities, project_obj] => true })

      controller.index_with_vid

      expect(controller.denied).to be(false)
      expect(controller.index_called).to be(true)
    end

    it 'denies access when user lacks view_activities permission' do
      User.current = make_user

      controller.index_with_vid

      expect(controller.denied).to be(true)
      expect(controller.index_called).to be(false)
    end
  end

  # ── Global activity ─────────────────────────────────────────────────────

  describe '#index_with_vid (global)' do
    before { controller.project = nil }

    it 'allows admin access for global activity' do
      User.current = make_user(admin: true)

      controller.index_with_vid

      expect(controller.denied).to be(false)
      expect(controller.index_called).to be(true)
    end

    it 'allows access when user has view_activities_global permission' do
      User.current = make_user(permissions: { [:view_activities_global, :global] => true })

      controller.index_with_vid

      expect(controller.denied).to be(false)
      expect(controller.index_called).to be(true)
    end

    it 'denies access when user lacks view_activities_global permission' do
      User.current = make_user

      controller.index_with_vid

      expect(controller.denied).to be(true)
      expect(controller.index_called).to be(false)
    end
  end
end
