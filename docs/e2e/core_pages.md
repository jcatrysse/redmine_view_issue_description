# core_pages

Run 2026-10-07T20:08:28.800Z against http://127.0.0.1:3001.

| screenshot | user | URL | shows |
|---|---|---|---|
| ![](core_pages-admin-plugins.png) | admin | `/admin/plugins` | Administration > Plugins: the plugins installed for this run (HTTP 200) |
| ![](core_pages-admin-project-settings.png) | admin | `/projects/e2e-project/settings` | admin: Project > Settings answers 200 |
| ![](core_pages-admin-issue-list.png) | admin | `/projects/e2e-project/issues` | admin: the issue list answers 200 |
| ![](core_pages-admin-issue-page.png) | admin | `/issues/2` | admin: an issue page answers 200 |
| ![](core_pages-manager-project-settings.png) | manager | `/projects/e2e-project/settings` | manager: Project > Settings answers 200 |
| ![](core_pages-manager-issue-list.png) | manager | `/projects/e2e-project/issues` | manager: the issue list answers 200 |
| ![](core_pages-manager-issue-page.png) | manager | `/issues/2` | manager: an issue page answers 200 |
| ![](core_pages-reporter-issue-list.png) | reporter | `/projects/e2e-project/issues` | reporter: the issue list answers 200 (settings 403: no manage_project) |
| ![](core_pages-reporter-issue-page-403.png) | reporter | `/issues/2` | reporter: the issue page stays refused by this plugin (403), not a 500 |
| ![](core_pages-outsider-private-403.png) | outsider | `/issues/6` | outsider: an issue of the private project is refused (403) |
