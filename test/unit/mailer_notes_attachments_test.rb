# frozen_string_literal: true

require_relative '../test_helper'

# Round 3 of Jan's decisions (2026-10-07): a recipient who may not open the
# issue no longer reads its notes or the names of its attachments in the issue
# mails either; the mail is still sent, as with the description (q3).
class MailerNotesAttachmentsTest < ActiveSupport::TestCase
  include RedmineViewIssueDescription::TestHelper

  fixtures :projects, :users, :email_addresses, :user_preferences, :members, :member_roles,
           :roles, :trackers, :projects_trackers, :enabled_modules, :issue_statuses,
           :issues, :enumerations, :watchers, :journals, :journal_details

  setup do
    # See mailer_description_test.rb: the e2e configuration.yml may set :file.
    @delivery_method = ActionMailer::Base.delivery_method
    ActionMailer::Base.delivery_method = :test
    set_tmp_attachments_directory
    @dlopper = User.find_by_login('dlopper') # Developer in ecookbook, no view_issue_description
    @issue = Issue.generate!(project: Project.find('ecookbook'), tracker: Tracker.find(1),
                             author: User.find(1), description: 'Vidmail description')
    @attachment = Attachment.create!(container: @issue, author: User.find(1),
                                     file: mock_file_with_options(original_filename: 'vidsecret-file.txt'))
    @journal = Journal.create!(journalized: @issue, user: User.find(1), notes: 'Vidsecret note text')
    JournalDetail.create!(journal: @journal, property: 'attachment', prop_key: @attachment.id.to_s,
                          value: 'vidsecret-file.txt')
    @journal.reload
  end

  teardown do
    ActionMailer::Base.delivery_method = @delivery_method
  end

  def mail_text(mail)
    mail.parts.map { |part| part.body.decoded }.join("\n")
  end

  test 'issue_edit: no notes and no attachment names for a recipient who may not open the issue' do
    text = mail_text(Mailer.issue_edit(@dlopper, @journal).deliver_now)

    assert_includes text, "##{@issue.id}"
    assert_not_includes text, 'Vidsecret note'
    assert_not_includes text, 'vidsecret-file'
  end

  test 'issue_add: no attachment names for a recipient who may not open the issue' do
    text = mail_text(Mailer.issue_add(@dlopper, @issue).deliver_now)

    assert_not_includes text, 'vidsecret-file'
  end

  test 'the assignee gets notes and attachment names' do
    @issue.update_column(:assigned_to_id, @dlopper.id)
    text = mail_text(Mailer.issue_edit(@dlopper, @journal.reload).deliver_now)

    assert_includes text, 'Vidsecret note text'
    assert_includes text, 'vidsecret-file.txt'
  end

  test 'notes and attachments are back for the next recipient and never written' do
    Mailer.issue_edit(@dlopper, @journal).deliver_now
    text = mail_text(Mailer.issue_edit(User.find(1), @journal).deliver_now)

    assert_includes text, 'Vidsecret note text'
    assert_includes text, 'vidsecret-file.txt'
    assert_equal 'Vidsecret note text', @journal.reload.notes
    assert_equal 1, @issue.reload.attachments.count
  end
end
