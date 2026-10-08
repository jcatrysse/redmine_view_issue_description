# core

Run 2026-10-08T05:27:36.964Z against http://127.0.0.1:3001.

| screenshot | user | URL | shows |
|---|---|---|---|
| ![](core-new-issue-form.png) | manager | `/projects/e2e-project/issues/new` | New issue form as a member with every permission |
| ![](core-issue-created.png) | manager | `/issues/13` | The issue is created and shown |
| ![](core-note-added.png) | manager | `/issues/13` | The note is saved and shown in the history |
| ![](core-context-menu.png) | manager | `/projects/e2e-project/issues` | The context menu on the issue list |
| ![](core-issue-as-reporter.png) | reporter | `/issues/1` | A member without the plugin's permissions gets HTTP 403 on the issue, as the plugin intends |
| ![](core-private-refused.png) | outsider | `/projects/e2e-private` | A private project is refused to a non-member |
