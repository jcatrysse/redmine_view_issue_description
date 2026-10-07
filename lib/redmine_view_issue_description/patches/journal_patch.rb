# frozen_string_literal: true
require_dependency 'journal'

module RedmineViewIssueDescription
  module Patches
    # Round 3 of Jan's decisions (2026-10-07): whoever may not open an issue no
    # longer reads its notes or the names of its attachments in the issue mails
    # and the activity stream. Like Issue#vid_hide_description!, this marks one
    # loaded record; the attributes are untouched and never written back.
    module JournalPatch
      def vid_hide_notes!(hidden = true)
        @vid_notes_hidden = hidden
      end

      def vid_notes_hidden?
        @vid_notes_hidden == true
      end

      def notes
        @vid_notes_hidden ? nil : super
      end

      # Attachment details ("File x added") name the attachment.
      def visible_details(user = User.current)
        details = super
        @vid_notes_hidden ? details.reject { |detail| detail.property == 'attachment' } : details
      end
    end

    # The activity stream shows each issue update with its notes. For an issue
    # the user may not open the event stays and its notes are left out.
    module JournalActivityPatch
      def find_events(event_type, user, from, to, options)
        events = super
        return events if user.admin? || events.empty?

        issues = events.map(&:issue).compact.uniq # preloaded by the activity scope
        openable = Issue.vid_openable_ids(issues, user)
        events.each { |journal| journal.vid_hide_notes! unless openable.include?(journal.journalized_id) }
        events
      end
    end
  end
end

unless Journal.singleton_class.ancestors.include?(RedmineViewIssueDescription::Patches::JournalActivityPatch)
  Journal.singleton_class.prepend(RedmineViewIssueDescription::Patches::JournalActivityPatch)
end

unless Journal.ancestors.include?(RedmineViewIssueDescription::Patches::JournalPatch)
  Journal.prepend(RedmineViewIssueDescription::Patches::JournalPatch)
end
