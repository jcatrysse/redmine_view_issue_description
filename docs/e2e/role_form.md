# role_form

Run 2026-10-07T20:16:05.081Z against http://127.0.0.1:3001.

| screenshot | user | URL | shows |
|---|---|---|---|
| ![](role_form-tracker-columns.png) | admin | `/roles/8/edit` | The tracker table has the plugin columns; the scoped role has view_issue_description for the first tracker only |
| ![](role_form-saved.png) | admin | `/roles/8/edit` | After saving, view_issue_description is granted for two trackers |
| ![](role_form-no-view-issues.png) | admin | `/roles/new` | A role without view_issues hides the tracker table, plugin columns included |
