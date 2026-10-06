// Function: view_watched_issues. A watcher sees the issues it watches in the list
// even with "own issues" visibility (Issue.visible_condition), but may not watch
// an issue itself to gain access (self-watch block).
import { e2e } from '../../.codex/e2e/lib.mjs';
import { P, issueId, pageFetch } from './_helpers.mjs';

const t = await e2e('watched_issues');
await t.login('admin');
const unassigned = await issueId(t, 'E2E unassigned issue');
const related = await issueId(t, 'E2E related issue');

await t.login('watcher01');
await t.go(`/projects/${P}/issues?set_filter=1&status_id=*`);
const rows = await t.page.locator('table.issues tr.issue').count();
if (rows !== 1 || !(await t.page.locator(`tr#issue-${unassigned}`).count())) t.problems.push(`watcher01 list: ${rows} rows, expected only #${unassigned}`);
await t.shot('list', 'watcher01 ("own issues" visibility) lists exactly the issue it watches');

await t.go(`/issues/${related}`, { status: 403 });
const watch = await pageFetch(t, 'POST', `/watchers/watch?object_type=issue&object_id=${related}`);
t.check('self-watch', { requests: ['403 fetch'] });
if (watch !== 403) t.problems.push(`self-watch without detail access: HTTP ${watch}, expected 403`);
await t.go(`/issues/${related}`, { status: 403 });
await t.shot('self-watch-refused', `Watching #${related} itself is refused (403), so the issue stays closed to watcher01`);

await t.login('reporter');
await t.go(`/projects/${P}/issues`);
const rwatch = await pageFetch(t, 'POST', `/watchers/watch?object_type=issue&object_id=${related}`);
t.check('reporter self-watch', { requests: ['403 fetch'] });
if (rwatch !== 403) t.problems.push(`reporter self-watch: HTTP ${rwatch}, expected 403`);

// Manager (view_issue_description) may watch and unwatch.
await t.login('manager');
await t.go(`/issues/${related}`);
await t.page.locator('#content .contextual a:has-text("Watch")').first().click();
await t.page.waitForSelector('#content .contextual a:has-text("Unwatch")', { timeout: 10000 })
  .catch(() => t.problems.push('manager: Watch did not switch to Unwatch'));
t.check('manager watch');
await t.shot('manager-watch', 'Manager can watch an issue (the link turns into Unwatch)');
await t.page.locator('#content .contextual a:has-text("Unwatch")').first().click();
await t.page.waitForSelector('#content .contextual a:has-text("Watch"):not(:has-text("Unwatch"))', { timeout: 10000 }).catch(() => {});

await t.done();
