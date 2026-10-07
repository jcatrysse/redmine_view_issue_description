# Plugin data for the end-to-end scenarios, run by start_server.sh after the
# generic seed (.codex/e2e/seed.rb). Idempotent.
#
#   watcher01..watcher30  role "E2E watched only" (view_issues with "own issues"
#                         visibility + view_watched_issues, no
#                         view_issue_description) in e2e-project: more than one
#                         page of watcher candidates; watcher01 watches
#                         "E2E unassigned issue".
#   scoped                role "E2E scoped description": view_issue_description
#                         for the first tracker only.
#   hookuser              role "E2E webhooks": view_issues + use_webhooks, no
#                         plugin permission; owns a webhook on e2e-project.
#   reader                role "E2E reader": view_issues, view_activities,
#                         add_issues, copy_issues, add_issue_notes, no
#                         view_issue_description; notified of every event
#                         (scoped as well), for the description leaks of q3.
# "E2E search issue": a description with words found nowhere else, changed once,
# so its history holds a description diff.
# A git repository "e2e" with a commit that refers to the assigned issue, for
# the include=changesets_new API.
password = ENV.fetch('RMP_USER_PASSWORD', ENV.fetch('RMP_ADMIN_PASSWORD', 'Redmine7Test!'))
User.current = User.find_by(login: 'admin')
project = Project.find('e2e-project')
trackers = project.trackers.sorted.to_a

def vid_user(login, firstname, password)
  user = User.find_by(login: login) ||
         User.new(login: login, firstname: firstname, lastname: 'E2E', mail: "#{login}@example.net")
  user.password = user.password_confirmation = password
  user.must_change_passwd = false
  user.status = User::STATUS_ACTIVE
  user.save!(validate: false)
  user
end

def vid_role(name, permissions, visibility: 'all')
  role = Role.find_by(name: name) || Role.new(name: name, assignable: true)
  role.permissions = permissions
  role.issues_visibility = visibility
  role.save!
  role
end

def vid_member(user, project, role)
  member = Member.find_by(user_id: user.id, project_id: project.id)
  if member
    member.role_ids = [role.id]
    member.save!
  else
    Member.create!(principal: user, project: project, roles: [role])
  end
end

watched_only = vid_role('E2E watched only', %i[view_issues add_issue_notes view_watched_issues], visibility: 'own')
scoped = vid_role('E2E scoped description', %i[view_issues view_issue_description])
scoped.permissions_all_trackers = scoped.permissions_all_trackers.merge('view_issue_description' => '0')
scoped.permissions_tracker_ids = scoped.permissions_tracker_ids.merge('view_issue_description' => [trackers.first.id.to_s])
scoped.save!
hooks = vid_role('E2E webhooks', %i[view_issues add_issues edit_issues use_webhooks])

watchers = (1..30).map do |n|
  user = vid_user(format('watcher%02d', n), format('Watcher %02d', n), password)
  vid_member(user, project, watched_only)
  user
end
vid_member(vid_user('scoped', 'Scoped', password), project, scoped)
hookuser = vid_user('hookuser', 'Hook', password)
vid_member(hookuser, project, hooks)
reader = vid_user('reader', 'Reader', password)
vid_member(reader, project, vid_role('E2E reader', %i[view_issues view_activities add_issues copy_issues add_issue_notes]))
[reader, User.find_by!(login: 'scoped')].each { |user| user.update!(mail_notification: 'all') }

unassigned = Issue.find_by!(project_id: project.id, subject: 'E2E unassigned issue')
Watcher.create!(watchable: unassigned, user: watchers.first) unless unassigned.watched_by?(watchers.first)

# Issues in the first and the second tracker, so the tracker-scoped grant shows one
# description and hides the other.
[[trackers.first, 'E2E first tracker issue'], [trackers.second || trackers.first, 'E2E second tracker issue']].each do |tracker, subject|
  next if Issue.where(project_id: project.id, subject: subject).exists?

  Issue.create!(project: project, tracker: tracker, subject: subject, author: User.current,
                priority: IssuePriority.default || IssuePriority.first, status: tracker.default_status,
                description: "Description of #{subject}")
end

unless Issue.where(project_id: project.id, subject: 'E2E search issue').exists?
  search_issue = Issue.create!(project: project, tracker: trackers.first, subject: 'E2E search issue',
                               author: User.current, priority: IssuePriority.default || IssuePriority.first,
                               status: trackers.first.default_status,
                               description: 'Vidsearch secret alpha, written before the change.')
  search_issue.reload.init_journal(User.current)
  search_issue.update!(description: 'Vidsearch secret omega, written after the change.')
end

Setting.webhooks_enabled = '1' if Setting.respond_to?(:webhooks_enabled=)
if defined?(Webhook)
  # Core refuses loopback targets, so the receiver of test/e2e/webhooks.mjs is
  # reached on the first non-loopback IPv4 address of this machine.
  host = ENV['RMP_HOOK_HOST'] || Socket.ip_address_list.detect { |a| a.ipv4? && !a.ipv4_loopback? }&.ip_address
  url = "http://#{host}:#{ENV.fetch('RMP_HOOK_PORT', '3999')}/hookuser"
  Webhook.find_by(user_id: hookuser.id) ||
    Webhook.create!(url: url, user: hookuser, projects: [project],
                    events: %w[issue.created issue.updated], active: true)
end

# Git repository with a commit that refers to the assigned issue.
assigned = Issue.find_by!(project_id: project.id, subject: 'E2E assigned issue')
repo_dir = Rails.root.join('tmp', 'e2e-git').to_s
unless File.directory?(File.join(repo_dir, '.git'))
  FileUtils.mkdir_p(repo_dir)
  Dir.chdir(repo_dir) do
    system('git', 'init', '-q', '-b', 'main', exception: true)
    File.write('README', "E2E\n")
    system('git', 'add', 'README', exception: true)
    system('git', '-c', 'user.name=Manager E2E', '-c', 'user.email=manager@example.net',
           'commit', '-q', '-m', "Refs ##{assigned.id}: e2e changeset", exception: true)
  end
end
Setting.enabled_scm = (Setting.enabled_scm | ['Git'])
repository = project.repositories.find_by(identifier: 'e2e') ||
             Repository::Git.new(project: project, identifier: 'e2e', is_default: true)
repository.url = repository.root_url = File.join(repo_dir, '.git') # Redmine reads it with --git-dir
repository.save!
repository.fetch_changesets

puts "Plugin seed: #{watchers.size} watcher users, scoped, hookuser; " \
     "webhooks #{defined?(Webhook) ? Webhook.count : 'n/a'}; changesets on ##{assigned.id}: #{assigned.reload.changesets.count}"

# With redmine_contacts_helpdesk installed: a helpdesk ticket with a contact on
# "E2E related issue", for test/e2e/helpdesk_api.mjs.
if defined?(HelpdeskTicket)
  project.enable_module!(:contacts)
  project.enable_module!(:contacts_helpdesk)
  ticket_issue = Issue.find_by!(project_id: project.id, subject: 'E2E related issue')
  unless HelpdeskTicket.where(issue_id: ticket_issue.id).exists?
    contact = Contact.create!(first_name: 'Jane', last_name: 'Customer', email: 'jane@example.net',
                              project: project, projects: [project])
    HelpdeskTicket.create!(issue: ticket_issue, contact: contact, from_address: 'jane@example.net',
                           ticket_date: Time.now, source: HelpdeskTicket::HELPDESK_EMAIL_SOURCE)
  end
  puts "Helpdesk ticket on ##{ticket_issue.id}"
end
