# frozen_string_literal: true
require_dependency 'issue'

module RedmineViewIssueDescription
  module Patches
    module IssuePatch
      module InstanceMethods
        def tracker_permission_granted?(user, permission, project_roles = nil)
          return false unless user
          return true if user.admin?
          return false unless user.allowed_to?(permission, project)

          roles = project_roles || user.roles_for_project(project)

          return true if roles.any? { |role| role.permissions_all_trackers?(permission) }
          return false unless tracker

          roles.any? { |role| role.permissions_tracker_ids?(permission, tracker.id) }
        end

        def role_allows_issue_visibility?(role, user)
          visibility = role.respond_to?(:issues_visibility) ? role.issues_visibility.to_s : 'all'

          case visibility
          when 'all', ''
            true
          when 'default'
            !respond_to?(:is_private?) || !is_private?
          when 'own'
            respond_to?(:author) && user.is_or_belongs_to?(author)
          else
            false
          end
        end

        def description_access_granted?(user, project_roles = nil)
          return false unless user
          return true if user.admin?
          return false unless user.allowed_to?(:view_issue_description, project)

          roles = project_roles || user.roles_for_project(project)

          # Each role must independently satisfy BOTH tracker access AND issue visibility.
          # This prevents cross-role escalation (tracker from role A + visibility from role B).
          roles.any? do |role|
            tracker_accessible = role.permissions_all_trackers?(:view_issue_description) ||
                                  (tracker && role.permissions_tracker_ids?(:view_issue_description, tracker.id))
            next false unless tracker_accessible

            role_allows_issue_visibility?(role, user)
          end
        end

        def watcher_access_granted?(user, project_roles = nil)
          return false unless user && user.logged?
          return false unless tracker_permission_granted?(user, :view_watched_issues, project_roles)

          # Direct watcher check
          return true if respond_to?(:watched_by?) && watched_by?(user)

          # Group watcher check via watcher_principals (Users + Groups)
          if respond_to?(:watcher_principals) && user.respond_to?(:is_or_belongs_to?)
            return true if watcher_principals.any? { |principal| user.is_or_belongs_to?(principal) }
          end

          false
        end

        def addable_watcher_users_with_vid(user = User.current)
          base = addable_watcher_users_without_vid(user)
          return base unless project

          # Preload roles per project member to avoid N+1 queries in tracker_permission_granted?
          preloaded_roles = if project.respond_to?(:members)
            scope = project.members
            if scope.respond_to?(:includes)
              scope.includes(:roles).each_with_object({}) { |m, h| h[m.user_id] = m.roles }
            else
              {}
            end
          else
            {}
          end

          # Filter out base candidates that lack view_watched_issues —
          # core addable_watcher_users may include users the role form would
          # otherwise allow to self-watch without the permission.
          # Use non-destructive select to avoid mutating the array returned by core.
          base = base.select do |candidate|
            next true unless candidate.is_a?(User)

            roles = candidate.respond_to?(:id) ? preloaded_roles[candidate.id] : nil
            tracker_permission_granted?(candidate, :view_watched_issues, roles)
          end

          project_candidates = project.respond_to?(:users) ? project.users : []
          return base if project_candidates.empty?

          extra = project_candidates.select do |candidate|
            next false if base.include?(candidate)

            roles = candidate.respond_to?(:id) ? preloaded_roles[candidate.id] : nil
            tracker_permission_granted?(candidate, :view_watched_issues, roles)
          end

          (base + extra).uniq
        end

        def valid_watcher_with_vid?(principal)
          return valid_watcher_without_vid?(principal) unless principal.is_a?(User)

          return false unless principal.logged? && principal.respond_to?(:active?) && principal.active?

          # view_watched_issues is the only gate to become a watcher.
          # Falling through to core would allow any visible user to self-watch,
          # bypassing this permission model (e.g. via the issue edit form).
          tracker_permission_granted?(principal, :view_watched_issues)
        end

        def visible_with_vid?(usr = nil)
          user = usr || User.current
          return true if user&.admin?

          project_roles = user&.roles_for_project(self.project)
          return true if watcher_access_granted?(user, project_roles)

          visible_without_vid?(user)
        end
      end

      module ClassMethods
        def visible_condition_with_vid(user, options = {})
          base_condition = visible_condition_without_vid(user, options)

          return base_condition unless user&.logged?

          # Avoid stale process-level cache: tracker IDs are queried fresh each call.
          # The query is cheap (typically < 20 rows) and Redmine has query caching.
          tracker_ids = Tracker.respond_to?(:pluck) ? Tracker.pluck(:id) : Tracker.all.map(&:id)
          watched_clauses = []

          memberships = user.respond_to?(:memberships) ? Array(user.memberships) : []
          memberships.each do |membership|
            project = membership.respond_to?(:project) ? membership.project : nil
            roles   = membership.respond_to?(:roles)   ? membership.roles   : []

            next unless project

            # view_watched_issues: only lets the user see issues they are actually watching
            if user.allowed_to?(:view_watched_issues, project)
              project_id = project.id.to_i
              if roles.any? { |role| role.permissions_all_trackers?(:view_watched_issues) }
                watched_clauses << "#{Issue.table_name}.project_id = #{project_id}"
              else
                allowed = tracker_ids.select do |tid|
                  roles.any? { |role| role.permissions_tracker_ids?(:view_watched_issues, tid) }
                end
                unless allowed.empty?
                  watched_clauses << "(#{Issue.table_name}.project_id = #{project_id} AND #{Issue.table_name}.tracker_id IN (#{allowed.join(',')}))"
                end
              end
            end
          end

          watched_clauses.uniq!
          return base_condition if watched_clauses.empty?

          user_id = user.id.to_i

          # Include both direct user watches and watches via group membership
          watched_sql = <<~SQL.gsub(/\s+/, ' ').strip
            EXISTS (
              SELECT 1 FROM watchers w
              WHERE w.watchable_type = 'Issue'
                AND w.watchable_id = #{Issue.table_name}.id
                AND (
                  w.user_id = #{user_id}
                  OR EXISTS (
                    SELECT 1 FROM groups_users gu
                    WHERE gu.group_id = w.user_id
                      AND gu.user_id = #{user_id}
                  )
                )
            )
          SQL

          watched_part = "((#{watched_sql}) AND (#{watched_clauses.join(' OR ')}))"

          "(#{base_condition}) OR (#{watched_part})"
        end
      end
    end
  end
end

Issue.include(RedmineViewIssueDescription::Patches::IssuePatch::InstanceMethods)
Issue.class_eval do
  unless instance_methods.include?(:visible_without_vid?)
    alias_method :visible_without_vid?, :visible?
    alias_method :visible?, :visible_with_vid?
  end

  if instance_methods.include?(:addable_watcher_users) && !instance_methods.include?(:addable_watcher_users_without_vid)
    alias_method :addable_watcher_users_without_vid, :addable_watcher_users
    alias_method :addable_watcher_users, :addable_watcher_users_with_vid
  end

  if instance_methods.include?(:valid_watcher?) && !instance_methods.include?(:valid_watcher_without_vid?)
    alias_method :valid_watcher_without_vid?, :valid_watcher?
    alias_method :valid_watcher?, :valid_watcher_with_vid?
  end
end

Issue.singleton_class.include(RedmineViewIssueDescription::Patches::IssuePatch::ClassMethods)
Issue.singleton_class.class_eval do
  if method_defined?(:visible_condition) && !method_defined?(:visible_condition_without_vid)
    alias_method :visible_condition_without_vid, :visible_condition
    alias_method :visible_condition, :visible_condition_with_vid
  end
end
