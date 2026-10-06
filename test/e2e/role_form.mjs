// Function: the role form shows view_issue_description and view_watched_issues
// per tracker (Deface override of roles/_form), and saves a tracker-scoped grant.
import { e2e } from '../../.codex/e2e/lib.mjs';

const t = await e2e('role_form');
await t.login('admin');
await t.go('/roles');
const link = t.page.locator('#content table a', { hasText: 'E2E scoped description' }).first();
const href = await link.getAttribute('href');
await t.go(href);
await t.sudo();
const table = t.page.locator('#role-permissions-trackers table');
for (const header of ['View issue description', 'View watched issues']) {
  if (!(await table.locator('th', { hasText: header }).count())) t.problems.push(`role form: no "${header}" column`);
}
const all = t.page.locator('input[name="role[permissions_all_trackers][view_issue_description]"][type=checkbox]');
const scoped = t.page.locator('input[name="role[permissions_tracker_ids][view_issue_description][]"]');
if (await all.isChecked()) t.problems.push('scoped role: "all trackers" is checked for view_issue_description');
if ((await scoped.evaluateAll(els => els.filter(e => e.checked).length)) !== 1) t.problems.push('scoped role: not exactly one tracker checked');
await table.scrollIntoViewIfNeeded();
await t.shot('tracker-columns', 'The tracker table has the plugin columns; the scoped role has view_issue_description for the first tracker only');

// Save a change: also allow the second tracker, then put it back.
await scoped.nth(1).check();
await t.page.click('#roles-form input[type=submit], form.edit_role input[type=submit]');
await t.settle();
t.check('save role');
await t.go(href);
const after = await scoped.evaluateAll(els => els.filter(e => e.checked).length);
if (after !== 2) t.problems.push(`after saving: ${after} trackers checked, expected 2`);
await t.page.locator('#role-permissions-trackers').scrollIntoViewIfNeeded();
await t.shot('saved', 'After saving, view_issue_description is granted for two trackers');
await scoped.nth(1).uncheck();
await t.page.click('#roles-form input[type=submit], form.edit_role input[type=submit]');
await t.settle();

// Without view_issues the tracker table (and the plugin columns) is hidden, as in core.
await t.go('/roles/new');
await t.page.uncheck('#role_permissions_view_issues');
if (await t.page.locator('#role-permissions-trackers').isVisible()) t.problems.push('new role without view_issues: tracker table still visible');
await t.shot('no-view-issues', 'A role without view_issues hides the tracker table, plugin columns included');

await t.done();
