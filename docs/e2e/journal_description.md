# journal_description

Run 2026-10-07T20:14:36.787Z against http://127.0.0.1:3001.

| screenshot | user | URL | shows |
|---|---|---|---|
| ![](journal_description-admin-diff.png) | admin | `/journals/3/diff` | Admin sees the description diff |
| ![](journal_description-manager-history.png) | manager | `/issues/9` | Manager (view_issue_description): the history links to the description diff |
| ![](journal_description-manager-diff.png) | manager | `/journals/3/diff` | Manager sees the old and the new description |
| ![](journal_description-manager-copy.png) | manager | `/projects/e2e-project/issues/9/copy` | Manager copies the issue: the form carries the description |
| ![](journal_description-reporter-diff-403.png) | reporter | `/journals/3/diff` | Reporter (view_issues, no view_issue_description) is refused the description diff |
| ![](journal_description-reporter-quote-403.png) | reporter | `/projects/e2e-project/issues` | Quoting the issue description is refused (403) |
| ![](journal_description-reader-copy-403.png) | reader | `/projects/e2e-project/issues/9/copy` | reader (add_issues + copy_issues, no view_issue_description) is refused the copy form |
| ![](journal_description-reader-new.png) | reader | `/projects/e2e-project/issues/new` | A new issue without a source stays open to reader |
| ![](journal_description-reader-diff-403.png) | reader | `/journals/3/diff` | reader is refused the description diff as well |
| ![](journal_description-outsider-diff-403.png) | outsider | `/journals/3/diff` | A non-member of the public project is refused the description diff (core alone would show it) |
| ![](journal_description-outsider-private-copy.png) | outsider | `/projects/e2e-private/issues/6/copy` | A non-member is refused copying an issue of the private project |
