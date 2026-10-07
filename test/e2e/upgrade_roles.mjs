// Upgrade safety (finding 15): the roles keep view_issue_description as the
// role form stored it; the permissions report shows which roles may open
// issues. Only an administrator sees that report.
import { e2e } from '../../.codex/e2e/lib.mjs';
import { api, issueId, showApi } from './_helpers.mjs';

const t = await e2e('upgrade_roles');
await t.login('admin');
const id = await issueId(t, 'E2E unassigned issue');
await t.go('/roles/permissions');
await t.sudo();
const row = t.page.locator('tr', { has: t.page.locator('td', { hasText: /^\s*View issue description\s*$/i }) });
if (!(await row.count())) t.problems.push('admin: no "View issue description" row in the permissions report');
await row.first().scrollIntoViewIfNeeded().catch(() => {});
await t.shot('admin-permissions-report', 'Administration > Roles > Permissions report: which role has view_issue_description', { full: false });

const statuses = {};
for (const login of ['manager', 'scoped', 'reporter', 'reader', 'outsider']) {
  statuses[login] = (await api(t, login, `/issues/${id}.json`)).status;
}
const expected = { manager: 200, scoped: 403, reporter: 403, reader: 403, outsider: 403 };
for (const [login, status] of Object.entries(expected)) {
  if (statuses[login] !== status) t.problems.push(`${login}: GET /issues/${id}.json HTTP ${statuses[login]}, expected ${status}`);
}
await showApi(t, 'Who may open a second-tracker issue: the role decides, nothing is granted at the upgrade',
  `GET /issues/${id}.json (E2E unassigned issue, second tracker)`, 'see body', JSON.stringify(statuses, null, 2));
await t.shot('api-by-role', 'manager (all trackers) 200; scoped (first tracker only), reporter, reader (no view_issue_description) and outsider 403');

for (const login of ['manager', 'reporter', 'outsider']) {
  await t.login(login);
  await t.go('/roles/permissions', { status: 403 });
  await t.shot(`${login}-report-403`, `${login} is refused the permissions report (administrators only)`);
}

await t.done();
