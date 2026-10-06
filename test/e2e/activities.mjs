// Function: view_activities (project Activity tab) and view_activities_global
// (/activity): menu items and the pages themselves.
import { e2e } from '../../.codex/e2e/lib.mjs';
import { P } from './_helpers.mjs';

const t = await e2e('activities');

await t.login('manager');
await t.go(`/projects/${P}`);
if (!(await t.page.locator('#main-menu a.activity').count())) t.problems.push('manager: no Activity tab');
await t.go(`/projects/${P}/activity`);
await t.shot('manager-project', 'Manager (view_activities) has the Activity tab and opens it');
await t.go('/activity');
await t.shot('manager-global', 'Manager (view_activities_global) opens the global activity');

await t.login('reporter');
await t.go(`/projects/${P}`);
if (await t.page.locator('#main-menu a.activity').count()) t.problems.push('reporter: Activity tab shown without view_activities');
await t.shot('reporter-no-tab', 'Reporter (no view_activities): no Activity tab in the project menu');
await t.go(`/projects/${P}/activity`, { status: 403 });
await t.shot('reporter-project-403', 'Reporter is refused the project activity (403)');
await t.go('/activity', { status: 403 });
await t.shot('reporter-global-403', 'Reporter is refused the global activity (403)');

await t.anonymous();
await t.go('/activity');
if (!t.page.url().includes('/login')) t.problems.push(`anonymous /activity: ended on ${t.page.url()}, expected the login page`);
await t.shot('anonymous-login', 'Anonymous is sent to the login page for /activity');

await t.done();
