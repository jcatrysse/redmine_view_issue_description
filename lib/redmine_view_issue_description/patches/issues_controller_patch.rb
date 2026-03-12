module RedmineViewIssueDescription
  module Patches
    module IssuesControllerPatch
      module InstanceMethods
        def show_with_vid
          user = User.current
          unless user.admin? ||
                 user.is_or_belongs_to?(@issue.assigned_to) ||
                 @issue.watcher_access_granted?(user) ||
                 @issue.description_access_granted?(user)
            render_403
            return
          end

          show_without_vid
          if api_request? && (include_changesets_new? || (Redmine::Plugin.installed?('redmine_contacts_helpdesk') && @issue.respond_to?(:helpdesk_ticket) && @issue.helpdesk_ticket))
            Rails.logger.error("Rendering custom API: redmine_view_issue_description => issues/redmine_view_issue_description/show.api")
            respond_to do |format|
              format.api { render 'issues/redmine_view_issue_description/show.api' }
            end
          end
        end

        private
        def include_changesets_new?
          params[:include] == 'changesets_new'
        end
      end
    end
  end
end

IssuesController.include(RedmineViewIssueDescription::Patches::IssuesControllerPatch::InstanceMethods)
IssuesController.class_eval do
  alias_method :show_without_vid, :show
  alias_method :show, :show_with_vid
end
