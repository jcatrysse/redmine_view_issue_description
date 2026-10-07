// Function (q3, 2026-10-07): bulk edit and the context menu refuse assigning
// an issue the user may not open to themselves; as assignee they could open it.
import { e2e } from '../../.codex/e2e/lib.mjs';
import { P, api, issueId, showApi, pageFetch } from './_helpers.mjs';

const t = await e2e('bulk_assign');
await t.login('admin');
const id = await issueId(t, 'E2E second tracker issue');
const uid = async login => (await api(t, login, '/users/current.json')).json.user.id;
const hook = await uid('hookuser');
const manager = await uid('manager');
const assignee = async () => (await api(t, 'admin', `/issues/${id}.json`)).json.issue.assigned_to;

await t.login('hookuser');
await t.go(`/projects/${P}/issues`);
await t.page.click(`tr#issue-${id} td.checkbox input`);
await t.page.click(`tr#issue-${id} td.subject`, { button: 'right' });
await t.page.waitForSelector('#context-menu', { state: 'visible' }).catch(() => {});
await t.shot('hookuser-context-menu', 'hookuser (edit_issues, no view_issue_description) opens the context menu of an issue it may not open', { full: false });
const self = await pageFetch(t, 'POST', '/issues/bulk_update', { 'ids[]': id, 'issue[assigned_to_id]': hook });
const other = await pageFetch(t, 'POST', '/issues/bulk_update', { 'ids[]': id, 'issue[priority_id]': '' + (await api(t, 'admin', `/issues/${id}.json`)).json.issue.priority.id });
t.check('hookuser bulk', { requests: ['403 fetch', '406 fetch'] });
const show = await api(t, 'hookuser', `/issues/${id}.json`);
if (self !== 403) t.problems.push(`hookuser self-assignment: HTTP ${self}, expected 403`);
if (await assignee()) t.problems.push('hookuser: the issue got an assignee');
if (show.status !== 403) t.problems.push(`hookuser: issue API ${show.status} after the attempt, expected 403`);
await showApi(t, 'hookuser assigns the issue to itself through bulk_update (the context menu)',
  `POST /issues/bulk_update ids[]=${id} issue[assigned_to_id]=${hook}; then GET /issues/${id}.json`,
  `${self} / ${show.status}`, `self-assignment: ${self} (refused)\nanother bulk change (same priority): ${other} (not refused by the plugin)\nissue still refused afterwards: ${show.status}\nassignee now: ${JSON.stringify(await assignee())}`);
await t.shot('hookuser-self-assign-403', 'Self-assignment refused (403); the issue stays closed to hookuser');

await t.login('manager');
await t.go(`/projects/${P}/issues`);
const mgr = await pageFetch(t, 'POST', '/issues/bulk_update', { 'ids[]': id, 'issue[assigned_to_id]': manager });
t.check('manager bulk', { requests: ['406 fetch'] });
const after = await assignee();
if (!after || after.id !== manager) t.problems.push(`manager self-assignment did not apply (HTTP ${mgr})`);
await t.go(`/projects/${P}/issues`);
await t.shot('manager-self-assign', 'Manager (view_issue_description) assigns the issue to itself: allowed, as in core');
await pageFetch(t, 'POST', '/issues/bulk_update', { 'ids[]': id, 'issue[assigned_to_id]': 'none' });
t.check('manager reset', { requests: ['406 fetch'] });

await t.login('reporter');
await t.go(`/projects/${P}/issues`);
const rep = await pageFetch(t, 'POST', '/issues/bulk_update', { 'ids[]': id, 'issue[assigned_to_id]': await uid('reporter') });
t.check('reporter bulk', { requests: ['403 fetch'] });
if (rep !== 403) t.problems.push(`reporter bulk_update: HTTP ${rep}, expected 403 (no edit_issues)`);
await showApi(t, 'reporter (no edit_issues) tries the same', `POST /issues/bulk_update`, rep, '(refused by core: no edit_issues)');
await t.shot('reporter-403', 'Reporter has no edit_issues: core refuses bulk edit (403)');

await t.login('outsider');
await t.go('/projects/e2e-private/issues', { status: 403 });
await t.shot('outsider-private-403', 'A non-member cannot reach the issues of the private project at all');

await t.done();
