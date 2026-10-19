# frozen_string_literal: true

module RedmineViewIssueDescription
  # Per-request memo of the watched-issues part of Issue.visible_condition
  # (issue lists, gantt, my page, search and activity each build that condition,
  # often several times per page). ActiveSupport::CurrentAttributes is reset by
  # Rails around every request and job. Any change to what the condition reads
  # (memberships, roles and their permissions, enabled modules, trackers,
  # projects) clears it at once, so a request that changes them never reads a
  # stale condition.
  class WatchedClauseCache < ActiveSupport::CurrentAttributes
    attribute :clauses

    def self.fetch(key)
      self.clauses ||= {}
      return clauses[key] if clauses.key?(key)

      clauses[key] = yield
    end

    def self.clear
      self.clauses = nil
    end
  end
end

[Member, MemberRole, Role, EnabledModule, Tracker, Project].each do |model|
  model.after_save { RedmineViewIssueDescription::WatchedClauseCache.clear }
  model.after_destroy { RedmineViewIssueDescription::WatchedClauseCache.clear }
end

# Each controller request starts with an empty memo. Rails resets
# CurrentAttributes around every request through its executor, but functional
# tests (ActionController::TestCase) run requests without it, so the memo of one
# request reached the next and query counts depended on what came before. The
# notification fires for every controller, also those loaded before this file.
unless defined?(RedmineViewIssueDescription::WATCHED_CLAUSE_CACHE_RESET)
  RedmineViewIssueDescription::WATCHED_CLAUSE_CACHE_RESET =
    ActiveSupport::Notifications.subscribe('start_processing.action_controller') do
      RedmineViewIssueDescription::WatchedClauseCache.clear
    end
end
