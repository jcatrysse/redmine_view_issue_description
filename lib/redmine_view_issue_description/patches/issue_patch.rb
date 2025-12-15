require_dependency 'issue'
module RedmineViewIssueDescription
  module Patches
      module IssuePatch
        module InstanceMethods
        def tracker_permission_granted?(user, permission, project_roles = nil)
          return false unless user
          return false unless user.allowed_to?(permission, project)

          roles = project_roles || user.roles_for_project(project)

          return true if roles.any? { |role| role.permissions_all_trackers?(permission) }
          return false unless tracker

          roles.any? { |role| role.permissions_tracker_ids?(permission, tracker.id) }
        end

        def watcher_access_granted?(user, project_roles = nil)
          return false unless user && user.logged?
          return false unless tracker_permission_granted?(user, :view_watched_issues, project_roles)

          # Direct watcher user
          return true if respond_to?(:watched_by?) && watched_by?(user)

          # Group watchers: kijk naar watcher_principals (Users + Groups), niet naar watchers (Watcher records)
          if respond_to?(:watcher_principals) && user.respond_to?(:is_or_belongs_to?)
            return true if watcher_principals.any? { |principal| user.is_or_belongs_to?(principal) }
          elsif respond_to?(:watcher_groups) && user.respond_to?(:is_or_belongs_to?)
            return true if watcher_groups.any? { |group| user.is_or_belongs_to?(group) }
          end

          false
        end

        def addable_watcher_users_with_vid(user = User.current)
          base = addable_watcher_users_without_vid(user)
          return base unless project

          project_candidates = project.respond_to?(:users) ? project.users : []

          extra = project_candidates.select do |candidate|
            next false if base.include?(candidate)
            tracker_permission_granted?(candidate, :view_watched_issues)
          end

          (base + extra).uniq
        end

        def valid_watcher_with_vid?(principal)
          return valid_watcher_without_vid?(principal) unless principal.is_a?(User)

          if principal.logged? &&
             principal.respond_to?(:active?) && principal.active? &&
             tracker_permission_granted?(principal, :view_watched_issues)
            return true
          end

          valid_watcher_without_vid?(principal)
        end

        def visible_with_vid?(usr = nil)
          user = usr || User.current

          project_roles = user&.roles_for_project(self.project)

          return true if user&.admin?
          return true if user.is_or_belongs_to?(assigned_to)

          description_allowed = tracker_permission_granted?(user, :view_issue_description, project_roles)
          watcher_allowed = watcher_access_granted?(user, project_roles)
          base_visible = visible_without_vid?(user)

          return false unless description_allowed

          return true if watcher_allowed || base_visible

          false
        end

        end

        module ClassMethods
          def visible_condition_with_vid(user, options = {})
            base_condition = visible_condition_without_vid(user, options)

            return base_condition unless user&.logged?

            tracker_ids = Tracker.respond_to?(:all) ? Tracker.all.map(&:id) : []
            project_tracker_clauses = []

            memberships = user.respond_to?(:memberships) ? Array(user.memberships) : []
            memberships.each do |membership|
              project = membership.respond_to?(:project) ? membership.project : nil
              roles = membership.respond_to?(:roles) ? membership.roles : []

              next unless project
              next unless user.allowed_to?(:view_watched_issues, project)

              if roles.any? { |role| role.permissions_all_trackers?(:view_watched_issues) }
                project_tracker_clauses << "#{Issue.table_name}.project_id = #{project.id}"
                next
              end

              allowed_trackers = tracker_ids.select do |tracker_id|
                roles.any? { |role| role.permissions_tracker_ids?(:view_watched_issues, tracker_id) }
              end

              unless allowed_trackers.empty?
                project_tracker_clauses << "(#{Issue.table_name}.project_id = #{project.id} AND #{Issue.table_name}.tracker_id IN (#{allowed_trackers.join(',')}))"
              end
            end

            project_tracker_clauses.uniq!
            return base_condition if project_tracker_clauses.empty?

            watched_sql = <<~SQL
              EXISTS (
                SELECT 1 FROM watchers w
                WHERE w.watchable_type = 'Issue'
                  AND w.watchable_id = #{Issue.table_name}.id
                  AND w.user_id = #{user.id}
              )
            SQL

            watched_sql = watched_sql.gsub(/\s+/, ' ').strip

            "(#{base_condition}) OR ((#{watched_sql}) AND (#{project_tracker_clauses.join(' OR ')}))"
          end
        end
      end
    end
  end

Issue.include(RedmineViewIssueDescription::Patches::IssuePatch::InstanceMethods)
Issue.class_eval do
  alias_method :visible_without_vid?, :visible?
  alias_method :visible?, :visible_with_vid?

  if instance_methods.include?(:addable_watcher_users)
    alias_method :addable_watcher_users_without_vid, :addable_watcher_users
    alias_method :addable_watcher_users, :addable_watcher_users_with_vid
  end

  if instance_methods.include?(:valid_watcher?)
    alias_method :valid_watcher_without_vid?, :valid_watcher?
    alias_method :valid_watcher?, :valid_watcher_with_vid?
  end
end

Issue.singleton_class.include(RedmineViewIssueDescription::Patches::IssuePatch::ClassMethods)
Issue.singleton_class.class_eval do
  if method_defined?(:visible_condition)
    alias_method :visible_condition_without_vid, :visible_condition
    alias_method :visible_condition, :visible_condition_with_vid
  end
end
