// Function (q3, 2026-10-07): the activity stream (project, global, Atom) shows
// a new issue without its description to a user who may not open the issue.
import { e2e } from '../../.codex/e2e/lib.mjs';
import { P, issueId, showApi } from './_helpers.mjs';

const t = await e2e('activity_description');
await t.login('admin');
const id = await issueId(t, 'E2E search issue');
const event = () => t.page.locator(`dt.issue a[href$="/issues/${id}"]`).count();
const description = () => t.page.locator('dd span.description', { hasText: 'Vidsearch secret' }).count();
const from = new Date().toISOString().slice(0, 10);

await t.go(`/activity?show_issues=1&from=${from}`);
if (!(await event()) || !(await description())) t.problems.push('admin: event or description missing');
await t.shot('admin-global', 'Admin: the new issue in the global activity, with its description');

await t.login('manager');
await t.go(`/projects/${P}/activity?show_issues=1&from=${from}`);
if (!(await event()) || !(await description())) t.problems.push('manager: event or description missing');
await t.shot('manager-project', 'Manager (view_issue_description): event with description');

await t.login('reader');
await t.go(`/projects/${P}/activity?show_issues=1&from=${from}`);
if (!(await event())) t.problems.push('reader: the event is gone');
if (await description()) t.problems.push('reader: description shown');
await t.shot('reader-project', 'reader (view_activities, no view_issue_description): the event stays, without the description');
const atom = await t.page.request.get(`${t.BASE}/projects/${P}/activity.atom?show_issues=1`);
const body = await atom.text();
if (atom.status() !== 200 || !body.includes('E2E search issue') || body.includes('Vidsearch secret')) t.problems.push('reader: Atom feed wrong');
await showApi(t, 'reader: project activity Atom feed', `GET /projects/${P}/activity.atom?show_issues=1`, atom.status(),
  body.split('<entry>').filter(e => e.includes('E2E search issue')).join('\n<entry>') || body.slice(0, 1500));
await t.shot('reader-atom', 'Atom feed: the entry of the issue has no description');

await t.login('reporter');
await t.go(`/projects/${P}/activity`, { status: 403 });
await t.shot('reporter-403', 'Reporter has no view_activities: the activity tab stays refused (403), as before');

await t.login('outsider');
await t.go('/projects/e2e-private/activity', { status: 403 });
await t.shot('outsider-private-403', 'A non-member is refused the activity of the private project');

await t.done();
