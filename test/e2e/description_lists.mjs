// Function: the description in issue lists. The description column is offered
// only with view_issue_description (QueryPatch), and inside a list a
// description is shown only for issues the user may open (IssueQueryPatch):
// HTML block column, CSV, Atom and GET /issues.json and .xml.
import { e2e } from '../../.codex/e2e/lib.mjs';
import { P, api, issueId, showApi } from './_helpers.mjs';

const t = await e2e('description_lists');
await t.login('admin');
const first = await issueId(t, 'E2E first tracker issue');
const second = await issueId(t, 'E2E second tracker issue');
const subtask = await issueId(t, 'E2E subtask');
const listUrl = `/projects/${P}/issues?set_filter=1&status_id=*&c[]=tracker&c[]=subject&c[]=description&sort=id`;

await t.login('manager');
await t.go(listUrl);
if (!(await t.page.locator(`tr#issue-${second} + tr td.description`).count())) t.problems.push('manager: no description row');
await t.shot('manager', 'Manager: the description column shows every description');

await t.login('scoped');
await t.go(listUrl);
const firstDesc = await t.page.locator(`tr#issue-${first} + tr.issue td.description, tr#issue-${first} + tr td.description`).innerText().catch(() => '');
const secondDesc = await t.page.locator(`tr#issue-${second} + tr td.description`).innerText().catch(() => '');
if (!firstDesc.includes('Description of E2E first tracker issue')) t.problems.push(`scoped: first tracker description missing (${firstDesc})`);
if (secondDesc.includes('Description of E2E second tracker issue')) t.problems.push('scoped: the second tracker description is shown');
await t.shot('scoped', 'scoped (view_issue_description for Bug only): the Bug description is shown, the Feature one is empty');

const csv = await t.page.request.get(`${t.BASE}/projects/${P}/issues.csv?set_filter=1&status_id=*&c[]=subject&c[]=description&encoding=UTF-8`);
const csvText = await csv.text();
if (!csvText.includes('Description of E2E first tracker issue')) t.problems.push('scoped CSV: Bug description missing');
if (csvText.includes('Description of E2E second tracker issue')) t.problems.push('scoped CSV: Feature description leaked');
await showApi(t, 'scoped: CSV export with the description column', `GET /projects/${P}/issues.csv?c[]=subject&c[]=description`, csv.status(), csvText);
await t.shot('scoped-csv', 'CSV export: the Feature issue has an empty description');

const atom = await t.page.request.get(`${t.BASE}/projects/${P}/issues.atom?set_filter=1&status_id=*`);
const atomText = await atom.text();
if (atomText.includes('Description of E2E second tracker issue')) t.problems.push('scoped Atom: Feature description leaked');
if (!atomText.includes('Description of E2E first tracker issue')) t.problems.push('scoped Atom: Bug description missing');

await t.login('reporter');
await t.go(listUrl);
if (await t.page.locator('td.description').count()) t.problems.push('reporter: a description cell is shown');
await t.shot('reporter', 'Reporter (no view_issue_description): no description column even when asked for in the URL');

const json = await api(t, 'reporter', `/projects/${P}/issues.json?status_id=*&limit=100`);
const byId = Object.fromEntries((json.json?.issues || []).map(i => [i.id, i]));
if (byId[second]?.description) t.problems.push('reporter JSON: description of an issue it cannot open');
if (!byId[subtask]?.description) t.problems.push('reporter JSON: no description for the issue it is assigned to');
const xml = await api(t, 'reporter', `/projects/${P}/issues.xml?status_id=*&limit=100`);
if (xml.text.includes('Description of E2E second tracker issue')) t.problems.push('reporter XML: description leaked');
const excerpt = (json.json?.issues || []).map(i => ({ id: i.id, subject: i.subject, assigned_to: i.assigned_to?.name, description: i.description }));
await showApi(t, 'Reporter: GET /issues.json (id, subject, assigned_to, description)', `GET /projects/${P}/issues.json?status_id=*`,
  json.status, JSON.stringify(excerpt, null, 1));
await t.shot('reporter-api-index', 'API index: description null except for the subtask the reporter is assigned to');

const manager = await api(t, 'manager', `/projects/${P}/issues.json?status_id=*&limit=100`);
if (!manager.json.issues.find(i => i.id === second)?.description) t.problems.push('manager JSON: description missing');

await t.done();
