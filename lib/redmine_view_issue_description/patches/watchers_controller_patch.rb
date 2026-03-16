# frozen_string_literal: true
require_dependency 'watchers_controller'
require 'redmine/pagination'

module RedmineViewIssueDescription
  module Patches
    # Adds pagination and search filtering to the watcher candidate list.
    # NOTE: the full candidate scope is materialised in memory so Ruby-level
    # valid_watcher? checks can run before pagination.  Memory is O(N) where
    # N = project members.  For very large projects (1000+ members) this is a
    # known trade-off — the check cannot be pushed to SQL.
    module WatchersControllerPatch
      def self.included(base)
        base.class_eval do
          helper_method :watcher_pagination_link_params

          before_action :check_self_watch_permission, only: [:create, :watch]

          private

          alias_method :users_for_new_watcher_without_vid, :users_for_new_watcher
          alias_method :users_for_new_watcher, :users_for_new_watcher_with_vid
        end
      end

      private

      # Blocks self-watching unless the user can already access the issue detail
      # through a non-watcher path (admin, assignee, or view_issue_description).
      # This prevents privilege escalation where a user with only view_watched_issues
      # could self-watch to gain description access they are not entitled to.
      # Covers both the `create` action (@watchable, singular) and the `watch` action
      # (@watchables, plural — used by the context menu and bulk watch).
      # Watchers added by a manager (with add_issue_watchers permission on behalf of
      # another user) are not affected because target_user != User.current in that case.
      def check_self_watch_permission
        issues = resolve_watchable_issues

        # M6 fix: if @watchables/@watchable weren't populated yet (timing difference across
        # Redmine versions), fall back to params-based resolution as a safety net.
        if issues.empty? && params[:object_type].to_s == 'Issue'
          issues = resolve_issues_from_params
        end

        return if issues.empty?

        # For the `create` action a manager may add someone else as watcher.
        # Avoid ActiveSupport .present? / Array.wrap so this runs in unit tests.
        requested_ids = if params[:user_id].to_s != ''
                          [params[:user_id].to_i]
                        elsif (watcher_params = params[:watcher])
                          ids = watcher_params[:user_ids] || watcher_params[:user_id]
                          Array(ids).map(&:to_i).compact
                        else
                          [User.current.id]
                        end
        return unless requested_ids.include?(User.current.id)

        # Block self-watch unless the user can already access the issue detail
        # through a non-watcher path.  Without this gate a user who holds only
        # view_watched_issues (but not view_issue_description) could add
        # themselves as watcher and thereby gain description access — a circular
        # privilege escalation.
        blocked_issue = issues.find do |issue|
          user = User.current
          next false if user.admin?
          next false if issue.assigned_to && user.is_or_belongs_to?(issue.assigned_to)
          next false if issue.description_access_granted?(user)
          true
        end
        render_403 if blocked_issue
      end

      # Returns Issue watchables regardless of whether the controller has already
      # resolved @watchables/@watchable.  The `create` action uses a before_action
      # (find_watchable) so @watchable is set in time.  The `watch` action sets
      # @watchables inside the action body — meaning our before_action runs first
      # with @watchables still nil in some Redmine versions.  We parse params directly
      # in that case so the permission check always has the Issues it needs.
      def resolve_watchable_issues
        items = if @watchables.respond_to?(:empty?) && !@watchables.empty?
                  Array(@watchables)
                elsif !@watchable.nil?
                  [@watchable]
                else
                  resolve_issues_from_params
                end

        items.select { |w| w.is_a?(Issue) }
      end

      # Safely resolves Issue records from params[:object_type] + params[:object_ids]
      # (or params[:object_id]) without allowing arbitrary class instantiation.
      # Uses only pure Ruby so this runs cleanly in non-ActiveSupport unit tests.
      def resolve_issues_from_params
        return [] unless params[:object_type].to_s == 'Issue'

        ids = Array(params[:object_ids]).map(&:to_i).select(&:positive?)
        ids << params[:object_id].to_i if ids.empty? && params[:object_id].to_s != ''
        ids.select!(&:positive?)
        ids.uniq!

        ids.empty? ? [] : Issue.where(id: ids).to_a
      rescue StandardError
        []
      end

      def users_for_new_watcher_with_vid
        scope = watcher_candidates_scope
        return [] unless scope

        scope = apply_watcher_search(scope)
        scope = apply_watcher_sort(scope)

        # Materialize the full scope so Ruby-level valid_watcher? checks can run
        # before pagination.  This is O(N) in memory but ensures accurate totals.
        candidates = scope.respond_to?(:to_a) ? scope.to_a : Array(scope)

        # Exclude users already watching (for single watchable only)
        candidates -= Array(@watchables&.first&.visible_watcher_users) if single_watchable?

        # Exclude candidates that fail tracker-permission / access checks
        Array(@watchables).each do |watchable|
          candidates.select! { |user| watchable.valid_watcher?(user) }
        end

        @watcher_total_count = candidates.size
        @watcher_paginator   = build_watcher_paginator(@watcher_total_count)

        candidates[watcher_offset, watcher_page_size] || []
      end

      def watcher_candidates_scope
        # Always scope to the project when available, even when a search query is present.
        projects = Array(@projects)
        if @project
          @project.principals.assignable_watchers
        elsif projects.size > 1
          principal_scope_for_multiple_projects
        elsif projects.size == 1
          projects.first.principals.assignable_watchers
        else
          # No project context — falls back to the global assignable scope.
          # This path is only reached for non-project watchables (rare in practice).
          Principal.assignable_watchers
        end
      end

      def principal_scope_for_multiple_projects
        Principal
          .joins(:members)
          .where(:members => { :project_id => @projects.map(&:id) })
          .assignable_watchers
          .distinct
      end

      def apply_watcher_search(scope)
        return scope if watcher_query.empty?

        if scope.respond_to?(:like)
          scope.like(watcher_query)
        else
          Array(scope).select do |principal|
            name  = principal.respond_to?(:name)  ? principal.name.to_s  : principal.to_s
            login = principal.respond_to?(:login) ? principal.login.to_s : ''
            name.downcase.include?(watcher_query.downcase) || login.downcase.include?(watcher_query.downcase)
          end
        end
      end

      def apply_watcher_sort(scope)
        if scope.respond_to?(:sorted)
          scope.sorted
        else
          Array(scope).sort_by { |principal| (principal.respond_to?(:name) ? principal.name.to_s : principal.to_s).downcase }
        end
      end

      def build_watcher_paginator(total_count)
        Redmine::Pagination::Paginator.new(total_count, watcher_page_size, watcher_page_number)
      end

      def watcher_page_size
        raw = params[:per_page].to_i
        size = raw.positive? ? raw : 25
        [size, 100].min
      end

      def watcher_offset
        (watcher_page_number - 1) * watcher_page_size
      end

      def watcher_page_number
        [params[:page].to_i, 1].max
      end

      def watcher_query
        params[:q].to_s.strip
      end

      def watcher_pagination_link_params(overrides = {})
        base = {
          controller: 'watchers',
          action: 'autocomplete_for_user',
          object_type: params[:object_type],
          object_id: params[:object_id],
          project_id: params[:project_id],
          per_page: params[:per_page],
          q: watcher_query,
          format: nil
        }.merge(overrides)

        base.delete_if { |_, v| v.nil? || v.to_s.empty? }
      end

      def single_watchable?
        @watchables && @watchables.size == 1
      end
    end
  end
end

unless WatchersController.included_modules.include?(RedmineViewIssueDescription::Patches::WatchersControllerPatch)
  WatchersController.send(:include, RedmineViewIssueDescription::Patches::WatchersControllerPatch)
end
