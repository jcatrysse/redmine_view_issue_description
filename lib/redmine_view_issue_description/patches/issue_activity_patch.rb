# frozen_string_literal: true
require_dependency 'issue'

module RedmineViewIssueDescription
  module Patches
    # The activity stream (project and global, HTML and Atom) shows each new
    # issue with its description. For an issue the user may not open the
    # event stays and its description is left out (decision q3, 2026-10-07),
    # as in the issue lists.
    module IssueActivityPatch
      def find_events(event_type, user, from, to, options)
        events = super
        return events if user.admin? || events.empty?

        openable = vid_openable_ids(events, user)
        events.each { |issue| issue.vid_hide_description! unless openable.include?(issue.id) }
        events
      end
    end
  end
end

unless Issue.singleton_class.ancestors.include?(RedmineViewIssueDescription::Patches::IssueActivityPatch)
  Issue.singleton_class.prepend(RedmineViewIssueDescription::Patches::IssueActivityPatch)
end
