# frozen_string_literal: true
require_dependency 'issue'

module RedmineViewIssueDescription
  module Patches
    # Search (/search, /search.json) neither shows nor matches the description
    # of an issue the user may not open (decision q3, 2026-10-07). The issue
    # stays findable through its subject, notes, custom fields and attachments,
    # as in the issue list, where its description is empty as well.
    module IssueSearchPatch
      DESCRIPTION_COLUMN = "#{Issue.table_name}.description"

      # Runs core's search twice when the description can matter: once as
      # core does, once without the description column. An issue found only
      # through its description is kept when the user may open it.
      def search_result_ranks_and_ids(tokens, user = User.current, projects = nil, options = {})
        ranks_and_ids = super
        return ranks_and_ids if ranks_and_ids.empty? || user.admin? ||
                                options[:titles_only] || options[:attachments] == 'only'

        # The second pass can only drop issues the user may not open; skip it when
        # every project of the results shows the user every description.
        return ranks_and_ids if vid_all_descriptions_open?(ranks_and_ids.map(&:last), user)

        without = vid_without_description { super }
        found_without = without.to_set(&:last)
        only_through_description = ranks_and_ids.map(&:last).reject { |id| found_without.include?(id) }
        return ranks_and_ids if only_through_description.empty?

        openable = vid_openable_ids(Issue.where(id: only_through_description).to_a, user).to_set
        ranks_and_ids.select { |_, id| found_without.include?(id) || openable.include?(id) }
      end

      # The results shown (title and description of each issue) are loaded here.
      def search_results_from_ids(ids)
        issues = super
        user = User.current
        return issues if user.admin? || issues.empty?

        openable = vid_openable_ids(issues, user)
        issues.each { |issue| issue.vid_hide_description! unless openable.include?(issue.id) }
        issues
      end

      def searchable_options
        options = super
        return options unless Thread.current[:vid_search_without_description]

        options.merge(columns: options[:columns] - [DESCRIPTION_COLUMN])
      end

      private

      # True when, in every project of the given issues, one role of the user
      # grants view_issue_description for all trackers with "all issues"
      # visibility: then the user may open each of them (Issue#detail_access_granted?)
      # and nothing found through a description has to be dropped. Conservative:
      # false sends the search through the second pass as before.
      def vid_all_descriptions_open?(ids, user)
        return false if user.respond_to?(:authorized_by_oauth?) && user.authorized_by_oauth?

        project_ids = Issue.where(id: ids).distinct.pluck(:project_id)
        ActiveRecord::Associations::Preloader.new(
          records: [user], associations: { memberships: [:roles, { project: :enabled_modules }] }
        ).call
        memberships = user.memberships.index_by(&:project_id)

        Project.where(id: project_ids).preload(:enabled_modules).all? do |project|
          next false unless project.allows_to?(:view_issue_description)

          membership = memberships[project.id]
          roles = membership ? membership.roles.to_a : user.roles_for_project(project)
          roles.any? do |role|
            (project.is_public? || role.member?) && role.allowed_to?(:view_issue_description) &&
              role.issues_visibility.to_s == 'all' && role.permissions_all_trackers?(:view_issue_description)
          end
        end
      end

      def vid_without_description
        previous = Thread.current[:vid_search_without_description]
        Thread.current[:vid_search_without_description] = true
        yield
      ensure
        Thread.current[:vid_search_without_description] = previous
      end
    end
  end
end

unless Issue.singleton_class.ancestors.include?(RedmineViewIssueDescription::Patches::IssueSearchPatch)
  Issue.singleton_class.prepend(RedmineViewIssueDescription::Patches::IssueSearchPatch)
end
