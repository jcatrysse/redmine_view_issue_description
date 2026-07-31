# CHANGELOG

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
