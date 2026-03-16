# frozen_string_literal: true

module RedmineViewIssueDescription
  module Patches
    module IssuesControllerPatch
      module InstanceMethods
        def show_with_vid
          unless vid_description_access?
            render_403
            return
          end

          if api_request? && (include_changesets_new? || include_journal_messages?)
            # Set up variables needed by the custom API template and render directly.
            # This avoids a double-render that would occur if show_without_vid were called first.
            @project    = @issue.project
            @journals   = @issue.visible_journals_with_index
            @changesets = @issue.changesets.visible
            @relations  = @issue.relations.select { |r| r.other_issue(@issue)&.visible? }
            respond_to do |format|
              format.api { render 'issues/redmine_view_issue_description/show.api' }
            end
          else
            show_without_vid
          end
        end

        def edit_with_vid
          unless vid_description_access?
            render_403
            return
          end

          edit_without_vid
        end

        def update_with_vid
          unless vid_description_access?
            render_403
            return
          end

          update_without_vid
        end

        private

        # Returns true when the current user may access the issue description/detail page.
        # Paths to access:
        #   1. Global admin
        #   2. Assignee of the issue (intentional UX bypass — assignees must be able to work)
        #   3. Watcher with view_watched_issues permission (tracker-scoped)
        #   4. Explicit view_issue_description grant (tracker-scoped, respects issues_visibility)
        def vid_description_access?
          user = User.current
          user.admin? ||
            (!@issue.assigned_to.nil? && user.is_or_belongs_to?(@issue.assigned_to)) ||
            @issue.watcher_access_granted?(user) ||
            @issue.description_access_granted?(user)
        end

        def include_changesets_new?
          includes = params[:include]
          if includes.is_a?(Array)
            includes.map(&:to_s).include?('changesets_new')
          else
            includes.to_s.split(',').map(&:strip).include?('changesets_new')
          end
        end

        def include_journal_messages?
          includes = params[:include]
          if includes.is_a?(Array)
            includes.map(&:to_s).include?('journal_messages')
          else
            includes.to_s.split(',').map(&:strip).include?('journal_messages')
          end
        end
      end
    end
  end
end

IssuesController.include(RedmineViewIssueDescription::Patches::IssuesControllerPatch::InstanceMethods)
IssuesController.class_eval do
  unless method_defined?(:show_without_vid)
    alias_method :show_without_vid, :show
    alias_method :show, :show_with_vid
  end
  unless method_defined?(:edit_without_vid)
    alias_method :edit_without_vid, :edit
    alias_method :edit, :edit_with_vid
  end
  unless method_defined?(:update_without_vid)
    alias_method :update_without_vid, :update
    alias_method :update, :update_with_vid
  end
end
