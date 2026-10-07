// Function (q3, 2026-10-07): the description diff in the history, quoting the
// issue (its description) and copying the issue (form filled with the
// description) are refused (403) to a user who may not open the issue.
import { e2e } from '../../.codex/e2e/lib.mjs';
import { P, api, issueId, showApi, pageFetch } from './_helpers.mjs';

const t = await e2e('journal_description');
await t.login('admin');
const id = await issueId(t, 'E2E search issue');
const priv = await issueId(t, 'E2E private issue');
const { json } = await api(t, 'admin', `/issues/${id}.json?include=journals`);
const journal = json.issue.journals.find(j => j.details.some(d => d.name === 'description'));
if (!journal) throw new Error('no description change in the history of the search issue');
const diff = `/journals/${journal.id}/diff`;

await t.go(diff);
if (!(await t.page.locator('.diff_in, .diff_out').count())) t.problems.push('admin: no diff');
await t.shot('admin-diff', 'Admin sees the description diff');

await t.login('manager');
await t.go(`/issues/${id}`);
await t.shot('manager-history', 'Manager (view_issue_description): the history links to the description diff');
await t.go(diff);
if (!(await t.page.locator('.diff_in, .diff_out').count())) t.problems.push('manager: no diff');
await t.shot('manager-diff', 'Manager sees the old and the new description');
await t.go(`/projects/${P}/issues/${id}/copy`);
if (!(await t.page.inputValue('#issue_description')).includes('Vidsearch secret')) t.problems.push('manager: copy form without the description');
await t.shot('manager-copy', 'Manager copies the issue: the form carries the description');

await t.login('reporter');
await t.go(diff, { status: 403 });
await t.shot('reporter-diff-403', 'Reporter (view_issues, no view_issue_description) is refused the description diff');
await t.go(`/projects/${P}/issues`);
const quote = await pageFetch(t, 'POST', `/issues/${id}/quoted`);
t.check('reporter quote', { requests: ['403 fetch'] });
if (quote !== 403) t.problems.push(`reporter quote: HTTP ${quote}, expected 403`);
await showApi(t, 'Reporter quotes the issue (its description)', `POST /issues/${id}/quoted`, quote, '(refused, no description)');
await t.shot('reporter-quote-403', 'Quoting the issue description is refused (403)');

await t.login('reader');
await t.go(`/projects/${P}/issues/${id}/copy`, { status: 403 });
await t.shot('reader-copy-403', 'reader (add_issues + copy_issues, no view_issue_description) is refused the copy form');
await t.go(`/projects/${P}/issues/new`);
await t.shot('reader-new', 'A new issue without a source stays open to reader');
await t.go(diff, { status: 403 });
await t.shot('reader-diff-403', 'reader is refused the description diff as well');

await t.login('outsider');
await t.go(diff, { status: 403 });
await t.shot('outsider-diff-403', 'A non-member of the public project is refused the description diff (core alone would show it)');
await t.go(`/projects/e2e-private/issues/${priv}/copy`, { status: 403 });
await t.shot('outsider-private-copy', 'A non-member is refused copying an issue of the private project');

await t.done();
