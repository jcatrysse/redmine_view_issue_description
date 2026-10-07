# mail_description

Run 2026-10-07T21:50:09.624Z against http://127.0.0.1:3001.

| screenshot | user | URL | shows |
|---|---|---|---|
| ![](mail_description-manager-created.png) | manager | `/issues/12` | Manager creates an issue (first tracker) with a description |
| ![](mail_description-reader-mail-new.png) | manager | `/issues/12` | reader still gets the mail of the new issue, without the description |
| ![](mail_description-scoped-mail-new.png) | manager | `/issues/12` | scoped (may open the issue) gets the mail with the description |
| ![](mail_description-manager-updated.png) | manager | `/issues/12` | Manager adds a note and an attachment to the issue |
| ![](mail_description-reader-mail-update.png) | manager | `/issues/12` | The update mail still reaches reader, without note, attachment name or description |
| ![](mail_description-scoped-mail-update.png) | manager | `/issues/12` | scoped (may open the issue) gets the note and the attachment name |
