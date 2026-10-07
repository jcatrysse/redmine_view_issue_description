# frozen_string_literal: true

require_relative '../test_helper'

# Issue notification mails (new issue, issue update) leave the description out
# for a recipient who may not open the issue (decision q3 of 2026-10-07). The
# mail itself is still sent, as before.
class MailerDescriptionTest < ActiveSupport::TestCase
  include RedmineViewIssueDescription::TestHelper
  include ActiveJob::TestHelper

  fixtures :projects, :users, :email_addresses, :user_preferences, :members, :member_roles,
           :roles, :trackers, :projects_trackers, :enabled_modules, :issue_statuses,
           :issues, :enumerations, :watchers, :journals, :journal_details

  setup do
    ActionMailer::Base.deliveries.clear
    Setting.plain_text_mail = '0'
    @project = Project.find('ecookbook')
    @dlopper = User.find_by_login('dlopper') # Developer in ecookbook, no view_issue_description
    @role = Role.find_by_name('Developer')
    @issue = Issue.generate!(project: @project, tracker: Tracker.find(1), author: User.find(1),
                             subject: 'Vidmail issue', description: 'Vidmail secret description')
  end

  def mail_text(mail)
    mail.parts.map { |part| part.body.decoded }.join("\n")
  end

  test 'issue_add: no description for a recipient who may not open the issue' do
    mail = Mailer.issue_add(@dlopper, @issue).deliver_now

    assert_includes mail.subject, 'Vidmail issue'
    assert_not_includes mail_text(mail), 'Vidmail secret'
  end

  test 'issue_edit: no description for a recipient who may not open the issue' do
    journal = @issue.init_journal(User.find(1), 'Vidmail note')
    @issue.update!(subject: 'Vidmail issue changed')

    mail = Mailer.issue_edit(@dlopper, journal).deliver_now

    assert_includes mail_text(mail), 'Vidmail note'
    assert_not_includes mail_text(mail), 'Vidmail secret'
  end

  test 'the assignee gets the description' do
    @issue.update!(assigned_to: @dlopper)

    assert_includes mail_text(Mailer.issue_add(@dlopper, @issue).deliver_now), 'Vidmail secret description'
  end

  test 'view_issue_description gives the description' do
    vid_grant(@role, :view_issue_description)

    assert_includes mail_text(Mailer.issue_add(@dlopper.reload, @issue).deliver_now), 'Vidmail secret description'
  end

  test 'one issue mailed to two recipients: each gets what he may see' do
    jsmith = User.find_by_login('jsmith')
    vid_grant(Role.find_by_name('Manager'), :view_issue_description)

    hidden = Mailer.issue_add(@dlopper, @issue).deliver_now
    shown = Mailer.issue_add(jsmith, @issue).deliver_now

    assert_not_includes mail_text(hidden), 'Vidmail secret'
    assert_includes mail_text(shown), 'Vidmail secret description'
    assert_equal 'Vidmail secret description', @issue.description
  end

  test 'deliver_issue_add still mails a recipient who may not open the issue' do
    @dlopper.pref.update!(no_self_notified: false)
    @dlopper.update!(mail_notification: 'all')
    with_settings notified_events: %w(issue_added) do
      perform_enqueued_jobs { Mailer.deliver_issue_add(@issue) }
    end
    mail = ActionMailer::Base.deliveries.detect { |m| m.to.include?(@dlopper.mail) }

    assert mail, 'dlopper is still notified'
    assert_not_includes mail_text(mail), 'Vidmail secret'
  end
end
