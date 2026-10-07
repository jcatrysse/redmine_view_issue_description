// General decision of 2026-10-07: with the other GEOxyz plugins installed,
// Project > Settings, the issue list and an issue page answer 200 (no
// alias_method/prepend recursion). Run on the server with RMP_EXTRA_PLUGINS
// as well as on the one with this plugin alone.
import { e2e } from '../../.codex/e2e/lib.mjs';
import { P, issueId } from './_helpers.mjs';

const t = await e2e('core_pages');
await t.login('admin');
const id = await issueId(t, 'E2E unassigned issue');
const priv = await issueId(t, 'E2E private issue');
const plugins = await t.page.request.get(`${t.BASE}/admin/plugins`);
await t.go('/admin/plugins');
await t.sudo();
await t.shot('admin-plugins', `Administration > Plugins: the plugins installed for this run (HTTP ${plugins.status()})`, { full: false });

for (const login of ['admin', 'manager']) {
  if (login !== 'admin') await t.login(login);
  await t.go(`/projects/${P}/settings`);
  await t.shot(`${login}-project-settings`, `${login}: Project > Settings answers 200`, { full: false });
  await t.go(`/projects/${P}/issues`);
  await t.shot(`${login}-issue-list`, `${login}: the issue list answers 200`, { full: false });
  await t.go(`/issues/${id}`);
  await t.shot(`${login}-issue-page`, `${login}: an issue page answers 200`, { full: false });
}

await t.login('reporter');
await t.go(`/projects/${P}/settings`, { status: 403 });
await t.go(`/projects/${P}/issues`);
await t.shot('reporter-issue-list', 'reporter: the issue list answers 200 (settings 403: no manage_project)', { full: false });
await t.go(`/issues/${id}`, { status: 403 });
await t.shot('reporter-issue-page-403', 'reporter: the issue page stays refused by this plugin (403), not a 500', { full: false });

await t.login('outsider');
await t.go(`/issues/${priv}`, { status: 403 });
await t.shot('outsider-private-403', 'outsider: an issue of the private project is refused (403)', { full: false });

await t.done();
