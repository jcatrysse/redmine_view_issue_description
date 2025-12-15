# CHANGELOG

### 0.1.3
* Added `view_watched_issues` permission to allow watcher-based visibility when granted on a role.
* Updated issue visibility logic and added RSpec coverage for watcher, assignment, and permission flows.
* Documented watcher usage, testing instructions, and bumped plugin metadata version.

### 0.1.2
* Correction for more consistent access based on user permissions.
* Removed filter on `root_issue`, has been moved to the `redmine_parent_child_filters` plugin
* Resolved potential issue: `SystemStackError (stack level too deep)`  
  Converted methods to use `alias_method`
* Update `locales`
