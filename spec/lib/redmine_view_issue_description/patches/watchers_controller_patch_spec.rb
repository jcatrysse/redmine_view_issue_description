require_relative '../../../spec_helper'

unless Kernel.respond_to?(:require_dependency)
  def require_dependency(file)
    require file
  rescue LoadError
  end
end

class ::WatchersController
  def users_for_new_watcher
    []
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
      attr_reader :principals

      def initialize(users)
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
  end
end
