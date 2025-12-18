module RedmineViewIssueDescription
    class Hooks < Redmine::Hook::ViewListener
      def view_layouts_base_html_head(context = {})
        stylesheet_link_tag('redmine_view_issue_description.css', plugin: 'redmine_view_issue_description')
      end
    end
end
