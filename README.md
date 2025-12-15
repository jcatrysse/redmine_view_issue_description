# Redmine plugin: View Issue Description

This plugin adds the possibility to limit the **visibility** of **issue descriptions**, based on _role permissions_ and _selected trackers_.
The main goal is to limit the visibility for external users (e.g., customers), without hiding an essential issue overview and issue related information.

Long story short, without the new `view_issue_description` permission, a user cannot enter an issue or view its description.
An exception is made for `issues` where the user is the `assigned user`.
With the additional `view_watched_issues` permission, you can extend visibility to users or groups that are watchers on specific issues.

Some extra features have been added, to improve the general usability.

## Features
1. Project module `issue_tracking` has extended permissions:
    * `view_issue_description`
    * `view_watched_issues` for watcher-based visibility
1. Project module `project` has extended permission:
    * `view_activities`
    * `view_activities_global`
1. Filters `start_date` and `end_date` have been extended with a `not equal to` operator.
1. API calls on `issues` have been extended with:
    * `repository` information if set `include=changesets_new`
    * `helpdesk_ticket` information if the `RedmineUP` helpdesk plugin is installed.
    * Set `include=journal_messages,journals` for helpdesk journals.

The tracker-level checkboxes for `view_issue_description` and `view_watched_issues` are injected into the role form via a Deface override so upgrades to Redmine core do not require copying the entire partial.

## Installation

1. Move the files into `$REDMINE/plugins/redmine_view_issue_description`
2. Install plugin dependencies from the plugin directory (Deface is required to extend the role form without copying the core partial):

```
bundle install
```

3. Restart REDMINE.

## Usage

1. Set the permissions for `view_issue_description`, `view_watched_issues`, `view_activities`, `view_activities_global` as needed for each role.
2. To allow watcher-only access to issues, create a role that includes `view_watched_issues`, add the user (or their group) to the project with that role, and mark them as a watcher on the relevant issues.
   * You can scope `view_watched_issues` and `view_issue_description` to specific trackers via the role form checkboxes.
   * Users with the `view_watched_issues` permission (including tracker-scoped) are available in the watchers selection list even if they lack other view permissions.
3. API: https://site.url/issues/<issue_id_here>.json
4. API: https://site.url/issues/<issue_id_here>.json?include=journal_messages,journals
5. API: https://site.url/issues/<issue_id_here>.json?include=changesets_new

## Testing

The plugin includes an RSpec test suite for the visibility logic. Run the full suite with:

```
RAILS_ENV=test bundle exec rspec plugins/redmine_view_issue_description/spec
```

## Compatibility

1. Tested on Redmine 5.1
