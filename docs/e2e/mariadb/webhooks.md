# webhooks

Run 2026-10-06T20:16:17.529Z against http://127.0.0.1:3000.

| screenshot | user | URL | shows |
|---|---|---|---|
| ![](webhooks-hookuser-hooks.png) | hookuser | `/webhooks` | hookuser (use_webhooks, no view_issue_description) owns an active issue hook on the project |
| ![](webhooks-manager-new.png) | manager | `/webhooks/2/edit` | Manager sets up an active issue.updated hook for the E2E project |
| ![](webhooks-manager-hooks.png) | manager | `/webhooks` | The manager hook is listed |
| ![](webhooks-deliveries.png) | manager | `http://127.0.0.1:3999/` | Receiver: the note reached only the manager hook; after assigning hookuser, its hook got the update too |
