// Function: the issue page (show, edit, update, API show) opens only for admin,
// view_issue_description, the assignee, and a watcher with view_watched_issues.
import { e2e } from '../../.codex/e2e/lib.mjs';
import { P, api, issueId, showApi, pageFetch } from './_helpers.mjs';

const t = await e2e('issue_access');
await t.login('admin');
const unassigned = await issueId(t, 'E2E unassigned issue');
const assigned = await issueId(t, 'E2E assigned issue');
const subtask = await issueId(t, 'E2E subtask');
const priv = await issueId(t, 'E2E private issue');

await t.login('manager');
await t.go(`/issues/${unassigned}`);
if (!(await t.page.locator('.description .wiki').count())) t.problems.push('manager: no description on the issue page');
await t.shot('manager-show', 'Manager (view_issue_description) opens the issue and sees the description');
await t.go(`/issues/${unassigned}/edit`);
await t.shot('manager-edit', 'Manager can open the edit form');

await t.login('reporter');
await t.go(`/projects/${P}/issues`);
if (!(await t.page.locator(`tr#issue-${unassigned}`).count())) t.problems.push('reporter: the issue is not in the list');
await t.shot('reporter-list', 'Reporter (no plugin permission) still sees the issue in the list');
await t.go(`/issues/${unassigned}`, { status: 403 });
await t.shot('reporter-show-403', 'Reporter is refused the issue page (403)');
await t.go(`/issues/${unassigned}/edit`, { status: 403 });
await t.shot('reporter-edit-403', 'Reporter is refused the edit form (403)');
await t.go(`/projects/${P}/issues`);
const updateStatus = await pageFetch(t, 'PATCH', `/issues/${unassigned}`, { 'issue[notes]': 'should not be saved' });
t.check('reporter update', { requests: ['403 fetch'] });
if (updateStatus !== 403) t.problems.push(`reporter update: HTTP ${updateStatus}, expected 403`);
const show = await api(t, 'reporter', `/issues/${unassigned}.json`);
if (show.status !== 403) t.problems.push(`reporter API show: HTTP ${show.status}, expected 403`);
await showApi(t, 'Reporter: API show and update of an issue without detail access', `GET /issues/${unassigned}.json; PATCH /issues/${unassigned}`,
  `${show.status} / ${updateStatus}`, show.text || '(empty body)');
await t.shot('reporter-api-403', 'API show and an update from the page are refused (403) as well');
await t.go(`/issues/${subtask}`);
if (!(await t.page.locator('.description .wiki').count())) t.problems.push('reporter: assignee does not see the description');
await t.shot('reporter-assignee', 'Reporter opens the subtask it is assigned to (assignee path)');

await t.login('watcher01');
await t.go(`/issues/${unassigned}`);
await t.shot('watcher-show', 'watcher01 (view_watched_issues, no view_issue_description) opens the issue it watches');
await t.go(`/issues/${assigned}`, { status: 403 });
await t.shot('watcher-other-403', 'watcher01 is refused an issue it does not watch');

await t.login('outsider');
await t.go(`/issues/${priv}`, { status: 403 });
await t.shot('outsider-private', 'A non-member is refused an issue of the private project');

await t.done();
