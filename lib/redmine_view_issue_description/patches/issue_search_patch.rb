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

        without = vid_without_description { super }
        found_without = without.map(&:last)
        only_through_description = ranks_and_ids.map(&:last) - found_without
        return ranks_and_ids if only_through_description.empty?

        openable = vid_openable_ids(Issue.where(id: only_through_description).to_a, user)
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
