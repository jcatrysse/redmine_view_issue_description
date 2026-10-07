# frozen_string_literal: true
require_dependency 'mailer'

module RedmineViewIssueDescription
  module Patches
    # Issue notification mails (new issue, issue update) carry the description,
    # the notes and the attachment names.
    # A recipient who may not open the issue still gets the mail, without the
    # description (decision q3, 2026-10-07), the notes and the attachment names
    # (round 3). The mail is rendered inside the action, so they are hidden for
    # this one recipient only and shown again afterwards.
    module MailerPatch
      def issue_add(user, issue)
        vid_restricted_for(user, issue) { super }
      end

      def issue_edit(user, journal)
        vid_restricted_for(user, journal.journalized, journal) { super }
      end

      private

      # For a recipient who may not open the issue: no description (q3), no notes
      # and no attachment names (round 3) while this one mail is rendered.
      def vid_restricted_for(user, issue, journal = nil)
        return yield unless issue.is_a?(Issue) && !issue.detail_access_granted?(user)

        before = [issue.vid_description_hidden?, issue.vid_attachments_hidden?, journal&.vid_notes_hidden?]
        begin
          issue.vid_hide_description!
          issue.vid_hide_attachments!
          journal&.vid_hide_notes!
          yield
        ensure
          issue.vid_hide_description!(before[0])
          issue.vid_hide_attachments!(before[1])
          journal&.vid_hide_notes!(before[2])
        end
      end
    end
  end
end

unless Mailer.ancestors.include?(RedmineViewIssueDescription::Patches::MailerPatch)
  Mailer.prepend(RedmineViewIssueDescription::Patches::MailerPatch)
end
