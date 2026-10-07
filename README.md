# Redmine plugin: View Issue Description

This plugin adds the possibility to limit the **visibility** of **issue descriptions**, based on _role permissions_ and _selected trackers_.
The main goal is to limit the visibility for external users (e.g., customers), without hiding an essential issue overview and issue related information.

Without the `view_issue_description` permission, a user cannot open an issue or view its description.
With the additional `view_watched_issues` permission, you can extend visibility to users or groups that are watchers on specific issues.

Some extra features have been added to improve the general usability.

## Features

1. Project module `issue_tracking` has extended permissions:
    * `view_issue_description`: required to open an issue and view its description, journals, and attachments.
    * `view_watched_issues`: watcher-based visibility — watched issues are visible and accessible even without `view_issue_description`.
    * `view_activities`: controls access to the project activity tab.
1. Global permission:
    * `view_activities_global`: controls access to the application-wide activity overview.
1. Issue lists (description column, CSV, PDF, Atom, `GET /issues.json` and `.xml`) only show the description of issues the user may open; for the others it is empty (`null` in the API).
1. Redmine 7 webhooks: issue events are only sent to webhooks whose owner may open the issue.
1. The description does not reach a user who may not open the issue in other places either: search neither shows nor matches it, the activity stream and the issue notification mails leave it out (the mail is still sent), and the description diff in the history, quoting the issue and copying it answer 403.
1. API calls on `issues` have been extended with:
    * `repository` information when using `include=changesets_new`
    * `helpdesk_ticket` information if the `RedmineUP` helpdesk plugin is installed.
    * Set `include=journal_messages,journals` for helpdesk journal data.

The tracker-level checkboxes for `view_issue_description` and `view_watched_issues` are injected into the role form via a Deface override so upgrades to Redmine core do not require copying the entire partial.

> **Note on assignee access**: users assigned to an issue always have access to the issue detail page, regardless of their role's `view_issue_description` setting. This is intentional — assignees must be able to see the issue they are working on.

> **Install note**: on a Redmine where this plugin is installed for the first time, members whose roles lack `view_issue_description` can no longer open issues (403 on the issue page, its edit form and the API show), except as assignee or as watcher with `view_watched_issues`. Grant `view_issue_description` to the roles that must open issues. Upgrading from an earlier version of this plugin changes no role; the plugin has no migrations.

> **Upgrade note**: after installing the plugin, existing roles will no longer have access to the project activity tab until `view_activities` is explicitly granted. Assign this permission to all roles that previously had unrestricted activity access.

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

Rails tests against a real database (Redmine fixtures; webhook tests need Redmine 7, helpdesk tests need redmine_contacts_helpdesk):

```
RAILS_ENV=test bundle exec rake redmine:plugins:test NAME=redmine_view_issue_description
```

Browser scenarios for every function are in `test/e2e/` (see `.codex/e2e.sh`).

## Compatibility

Tested on Redmine 7.0 (7.0-stable-GEOxyz) with PostgreSQL 16. Redmine 5.1 and MariaDB are no longer tested.
