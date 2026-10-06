# frozen_string_literal: true

require_relative '../test_helper'

# include=helpdesk_ticket on GET /issues/:id.json and .xml, with
# redmine_contacts_helpdesk installed (skipped otherwise). Helpdesk 4.3
# renamed HelpdeskTicket#customer to #contact.
class IssuesApiHelpdeskTest < Redmine::IntegrationTest
  include RedmineViewIssueDescription::TestHelper

  fixtures :projects, :users, :email_addresses, :members, :member_roles, :roles,
           :trackers, :projects_trackers, :enabled_modules, :issue_statuses,
           :issues, :enumerations

  setup do
    skip 'redmine_contacts_helpdesk is not installed' unless defined?(HelpdeskTicket)

    Setting.rest_api_enabled = '1'
    @project = Project.find('ecookbook')
    @project.enable_module!(:contacts)
    @project.enable_module!(:contacts_helpdesk)
    @role = Role.find_by_name('Developer') # dlopper
    @issue = Issue.generate!(project: @project, tracker: Tracker.find(1), author: User.find(1),
                             description: 'Mail body')
    contact = Contact.create!(first_name: 'Jane', last_name: 'Customer', email: 'jane@example.net',
                              project: @project, projects: [@project])
    HelpdeskTicket.create!(issue: @issue, contact: contact, from_address: 'jane@example.net',
                           ticket_date: Time.now, source: HelpdeskTicket::HELPDESK_EMAIL_SOURCE)
  end

  test 'JSON: helpdesk_ticket with its contact' do
    get "/issues/#{@issue.id}.json", params: { include: 'helpdesk_ticket' }, headers: credentials('admin')
    assert_response :success
    ticket = response.parsed_body['issue']['helpdesk_ticket']
    assert ticket, 'no helpdesk_ticket section'
    assert_equal 'Jane Customer', ticket['contact']['name']
    assert_equal 'Mail body', ticket['content']
  end

  test 'XML: helpdesk_ticket with its contact' do
    get "/issues/#{@issue.id}.xml", params: { include: 'helpdesk_ticket' }, headers: credentials('admin')
    assert_response :success
    contact = Nokogiri::XML(response.body).at_xpath('/issue/helpdesk_ticket/contact')
    assert contact, 'no helpdesk_ticket/contact'
    assert_equal 'Jane Customer', contact['name']
  end

  test 'journal_messages also brings the ticket' do
    get "/issues/#{@issue.id}.json", params: { include: 'journal_messages' }, headers: credentials('admin')
    assert_response :success
    assert_equal [], response.parsed_body['issue']['helpdesk_ticket']['journal_messages']
  end

  test 'no helpdesk_ticket without view_helpdesk_tickets' do
    vid_grant(@role, :view_issue_description)
    get "/issues/#{@issue.id}.json", params: { include: 'helpdesk_ticket' }, headers: credentials('dlopper', 'foo')
    assert_response :success
    assert_not response.parsed_body['issue'].key?('helpdesk_ticket')
  end

  test 'helpdesk_ticket with view_helpdesk_tickets and view_issue_description' do
    vid_grant(@role, :view_issue_description, :view_helpdesk_tickets)
    get "/issues/#{@issue.id}.json", params: { include: 'helpdesk_ticket' }, headers: credentials('dlopper', 'foo')
    assert_response :success
    assert_equal 'Jane Customer', response.parsed_body['issue']['helpdesk_ticket']['contact']['name']
  end
end
