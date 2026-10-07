# frozen_string_literal: true
require_dependency 'mailer'

module RedmineViewIssueDescription
  module Patches
    # Issue notification mails (new issue, issue update) carry the description.
    # A recipient who may not open the issue still gets the mail, without the
    # description (decision q3, 2026-10-07), as in the issue lists. The mail is
    # rendered inside the action, so the description is hidden for this one
    # recipient only and shown again afterwards.
    module MailerPatch
      def issue_add(user, issue)
        vid_without_description_for(user, issue) { super }
      end

      def issue_edit(user, journal)
        vid_without_description_for(user, journal.journalized) { super }
      end

      private

      def vid_without_description_for(user, issue)
        return yield unless issue.is_a?(Issue) && !issue.detail_access_granted?(user)

        hidden_before = issue.vid_description_hidden?
        begin
          issue.vid_hide_description!
          yield
        ensure
          issue.vid_hide_description!(hidden_before)
        end
      end
    end
  end
end

unless Mailer.ancestors.include?(RedmineViewIssueDescription::Patches::MailerPatch)
  Mailer.prepend(RedmineViewIssueDescription::Patches::MailerPatch)
end
