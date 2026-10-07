# CHANGELOG

### 0.3.0
* Redmine 7 support (7.0-stable-GEOxyz, Rails 8.1).
* Search (`/search`, `/search.json`) no longer shows the description of an
  issue the user may not open, and no longer finds such an issue through a word
  of its description; it stays findable by its subject, notes, custom fields
  and attachments.
* Redmine 7 webhooks: an issue event is only delivered to hooks whose owner may
  open the issue (admin, `view_issue_description`, assignee, watcher with
  `view_watched_issues`). The webhook payload carries the description and the
  journal, which the issue page refuses to the other users.
* Issue lists no longer show the description of issues the user may not open:
  HTML description column, CSV, PDF, Atom and `GET /issues.json` / `.xml`
  (the description reads `null` there). Before, the column was only hidden as a
  whole per project, so a tracker-scoped grant or the API index still exposed
  every description.
* The issue page (show, edit, update) is refused in a `before_action`. A refused
  update no longer runs the `after_action`s of other plugins (helpdesk answered
  500 instead of 403).
* Helpdesk 4.3: the `helpdesk_ticket` API section reads the contact through
  `HelpdeskTicket#contact` (renamed from `#customer`); the section disappeared
  with helpdesk 4.3.x.
* Add watchers modal: users checked on one page of candidates stay checked on
  another page.
* Rails tests against a real database (`test/`) and browser scenarios
  (`test/e2e/`) next to the RSpec specs.

### 0.2.2
* Fixed cross-project leak in `Issue.visible_condition`: the watcher clause is
  OR'ed outside the condition returned by core, which is where the caller's
  project restriction lives, so project scoped callers also received watched
  issues from every other project the user is a member of. Most visible on the
  project activity tab (`/projects/<identifier>/activity`), which scopes through
  `visible_condition`'s options instead of through a query statement; issue lists
  were unaffected because `IssueQuery` applies its project filter separately.
* The watcher clause now honours `options[:project]` and, when set,
  `options[:with_subprojects]` (requested project plus its descendants).
  Cross-project and global callers, as well as the `Journal` and `TimeEntry`
  paths, keep their previous SQL unchanged.
* Added regression specs for project scoped, subproject scoped and unscoped
  callers.

### 0.2.1
* Fix SystemStackError: convert IssuesController patch to prepend

### 0.2.0
* Complete refactoring of the plugin.

### 0.1.5
* Fixed issue with `view_issues` permission not showing relations correctly.

### 0.1.4
* Fixed mixed-role authorization leak where `view_issue_description` could be
  combined across roles to expose descriptions outside the role's
  `issues_visibility` scope.
* Restored watcher-based visibility exception so `view_watched_issues` can make
  watched issues visible independent of base issues visibility constraints.
* Added regression and edge-case specs for mixed-role, watcher exception,
  own-only, and private/default visibility behavior.

### 0.1.3
* Added `view_watched_issues` permission to allow watcher-based visibility when
  granted on a role.
* Updated issue visibility logic and added RSpec coverage for watcher,
  assignment, and permission flows.
* Documented watcher usage, testing instructions, and bumped plugin metadata version.

### 0.1.2
* Correction for more consistent access based on user permissions.
* Removed filter on `root_issue`, has been moved to the `redmine_parent_child_filters` plugin.
* Resolved potential issue: `SystemStackError (stack level too deep)`.
  Converted methods to use `alias_method`.
* Update `locales`.
