# upgrade_roles

Run 2026-10-08T05:44:04.875Z against http://127.0.0.1:3001.

| screenshot | user | URL | shows |
|---|---|---|---|
| ![](upgrade_roles-admin-permissions-report.png) | admin | `/roles/permissions` | Administration > Roles > Permissions report: which role has view_issue_description |
| ![](upgrade_roles-api-by-role.png) | admin | `/roles/permissions` | manager (all trackers) 200; scoped (first tracker only), reporter, reader (no view_issue_description) and outsider 403 |
| ![](upgrade_roles-manager-report-403.png) | manager | `/roles/permissions` | manager is refused the permissions report (administrators only) |
| ![](upgrade_roles-reporter-report-403.png) | reporter | `/roles/permissions` | reporter is refused the permissions report (administrators only) |
| ![](upgrade_roles-outsider-report-403.png) | outsider | `/roles/permissions` | outsider is refused the permissions report (administrators only) |
