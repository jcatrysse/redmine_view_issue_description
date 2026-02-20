Redmine::Plugin.register :redmine_view_issue_description do
  name 'Redmine View Issue Description plugin'
  author 'Jan Catrysse'
  description 'Redmine plugin to add permissions to view issue description and the activity tabs'
  version '0.1.4'
  url 'https://github.com/redminetrustteam/redmine_view_issue_description'
  author_url 'https://github.com/redminetrustteam'

  requires_redmine version_or_higher: '4.0'

  project_module :issue_tracking do
    permission :view_issue_description, {}
    permission :view_watched_issues, {}
  end

  permission :view_activities, {:custom_activities => [:index]}
  permission :view_activities_global, {:custom_activities_global => [:index]}

  Redmine::MenuManager.map :application_menu do |menu|
    menu.delete :activity
  end

  Redmine::MenuManager.map :project_menu do |menu|
    menu.delete :activity
  end

  Redmine::MenuManager.map :application_menu do |menu|
    menu.push :activity, { :controller => 'activities', :action => 'index', :id => nil }, after: :projects, :if => Proc.new { User.current.admin? || User.current.allowed_to?(:view_activities_global, nil, :global => true) }
  end

  Redmine::MenuManager.map :project_menu do |menu|
    menu.push :activity, { :controller => 'activities', :action => 'index' }, after: :overview, :if => Proc.new {  |p| User.current.allowed_to?(:view_activities, p)  }
  end
end

require 'deface'

Rails.application.config.after_initialize do
  require_relative 'lib/redmine_view_issue_description/hooks'
  require_relative 'lib/redmine_view_issue_description/patches/issue_patch'
  require_relative 'lib/redmine_view_issue_description/patches/query_patch'
  require_relative 'lib/redmine_view_issue_description/patches/issues_controller_patch'
  require_relative 'lib/redmine_view_issue_description/patches/watchers_controller_patch'
  require_relative 'lib/redmine_view_issue_description/patches/activities_controller_patch'
  require_relative 'lib/redmine_view_issue_description/overrides/role_form_override'
  require_relative 'lib/redmine_view_issue_description/overrides/watchers_pagination_override'
end
