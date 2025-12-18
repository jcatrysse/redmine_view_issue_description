# frozen_string_literal: true

module RedmineViewIssueDescription
  module Overrides
    module WatchersPaginationOverride
      Deface::Override.new(
        virtual_path: 'watchers/_new',
        name: 'watchers_paginated_candidates_in_modal',
        replace: "erb[loud]:contains(\"principals_check_box_tags('watcher[user_ids][]', users)\")",
        text: "<%= render partial: 'redmine_view_issue_description/watchers/paginated_principals', locals: { users: users } %>"
      )

      Deface::Override.new(
        virtual_path: 'watchers/autocomplete_for_user',
        name: 'watchers_paginated_candidates_in_autocomplete',
        replace: "erb[loud]:contains(\"principals_check_box_tags 'watcher[user_ids][]', @users\")",
        text: "<%= render partial: 'redmine_view_issue_description/watchers/paginated_principals', locals: { users: @users } %>"
      )
    end
  end
end
