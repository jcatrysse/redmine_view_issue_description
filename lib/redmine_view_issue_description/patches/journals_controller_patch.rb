# frozen_string_literal: true

module RedmineViewIssueDescription
  module Patches
    # The history of an issue links to the diff of a description change, and
    # "Quote" on the issue quotes its description into a reply. Both give the
    # description of an issue the user may not open (decision q3, 2026-10-07),
    # so both are refused as the issue page is. The diff of another field and
    # quoting a note stay as core has them.
    module JournalsControllerPatch
      private

      # before_action on diff and new, after core's find_journal / find_issue and authorize.
      def vid_authorize_description
        issue, description =
          if action_name == 'diff'
            [@journal.issue, vid_description_detail?]
          else
            [@issue, params[:journal_id].blank?]
          end
        render_403 if description && issue && !issue.detail_access_granted?(User.current)
      end

      # Same detail as JournalsController#diff picks.
      def vid_description_detail?
        detail =
          if params[:detail_id].present?
            @journal.details.find_by_id(params[:detail_id])
          else
            @journal.details.detect { |d| d.property == 'attr' && d.prop_key == 'description' }
          end
        detail.present? && detail.property == 'attr' && detail.prop_key == 'description'
      end
    end
  end
end

unless JournalsController.ancestors.include?(RedmineViewIssueDescription::Patches::JournalsControllerPatch)
  JournalsController.include(RedmineViewIssueDescription::Patches::JournalsControllerPatch)
  JournalsController.before_action :vid_authorize_description, only: [:diff, :new]
end
