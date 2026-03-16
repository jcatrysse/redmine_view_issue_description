Redmine::Plugin.register :redmine_view_issue_description do
  name 'Redmine View Issue Description plugin'
  author 'Jan Catrysse'
  description 'Redmine plugin to add permissions to view issue description and the activity tabs'
  version '0.2.0'
  url 'https://github.com/redminetrustteam/redmine_view_issue_description'
  author_url 'https://github.com/redminetrustteam'

  requires_redmine version_or_higher: '4.0'

  project_module :issue_tracking do
    permission :view_issue_description, {}
    permission :view_watched_issues, {}
    permission :view_activities, {}
  end

  permission :view_activities_global, {}

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

  # Validate Deface selector targets still exist in the Redmine source.
  # If Redmine restructures its views, the overrides silently produce no match
  # and the tracker-permission checkboxes disappear from the role form.
  form_path = File.join(Rails.root, 'app', 'views', 'roles', '_form.html.erb')
  if File.exist?(form_path)
    content = File.read(form_path)
    unless content.include?('permissions = [:view_issues,')
      Rails.logger.warn(
        '[redmine_view_issue_description] Deface selector may not match: ' \
        'expected "permissions = [:view_issues," in roles/_form.html.erb. ' \
        'Tracker permission checkboxes may not appear on the role form.'
      )
    end
  end
end
