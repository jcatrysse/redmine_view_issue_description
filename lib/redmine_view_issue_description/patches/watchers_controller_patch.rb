require_dependency 'watchers_controller'
require 'redmine/pagination'

module RedmineViewIssueDescription
  module Patches
    # Adds pagination and server-side filtering to the watcher candidate list
    # so large projects (1000+ members) don't load every principal at once.
    module WatchersControllerPatch
      def self.included(base)
        base.class_eval do
          helper_method :watcher_pagination_link_params

          private

          alias_method :users_for_new_watcher_without_vid, :users_for_new_watcher
          alias_method :users_for_new_watcher, :users_for_new_watcher_with_vid
        end
      end

      private

      def users_for_new_watcher_with_vid
        scope = watcher_candidates_scope
        return [] unless scope

        scope = apply_watcher_search(scope)
        total_count = watcher_total_count(scope)
        scope = apply_watcher_sort(scope)
        scope = apply_watcher_pagination(scope)

        @watcher_paginator = build_watcher_paginator(total_count)
        @watcher_total_count = total_count

        users = scope.respond_to?(:to_a) ? scope.to_a : Array(scope)
        users -= Array(@watchables&.first&.visible_watcher_users) if single_watchable?

        Array(@watchables).each do |watchable|
          users.select! { |user| watchable.valid_watcher?(user) }
        end

        users
      end

      def watcher_candidates_scope
        if watcher_query.empty?
          return @project.principals.assignable_watchers if @project
          return principal_scope_for_multiple_projects if @projects && !@projects.empty? && @projects.size > 1
        end

        Principal.assignable_watchers
      end

      def principal_scope_for_multiple_projects
        Principal
          .joins(:members)
          .where(:members => { :project_id => @projects })
          .assignable_watchers
          .distinct
      end

      def apply_watcher_search(scope)
        return scope if watcher_query.empty?

        if scope.respond_to?(:like)
          scope.like(watcher_query)
        else
          Array(scope).select do |principal|
            name = principal.respond_to?(:name) ? principal.name.to_s : principal.to_s
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

      def apply_watcher_pagination(scope)
        return Array(scope)[watcher_offset, watcher_page_size] || [] unless scope.respond_to?(:offset) && scope.respond_to?(:limit)

        scope.offset(watcher_offset).limit(watcher_page_size)
      end

      def watcher_total_count(scope)
        return Array(scope).size unless scope.respond_to?(:count)

        scope.count
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

        base.delete_if { |_, v| v.blank? }
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
