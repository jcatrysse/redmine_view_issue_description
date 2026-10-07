// Function (q3, 2026-10-07): search (/search, /search.json) neither shows nor
// matches the description of an issue the user may not open; the issue stays
// findable by its subject.
import { e2e } from '../../.codex/e2e/lib.mjs';
import { P, api, issueId, showApi } from './_helpers.mjs';

const t = await e2e('search');
await t.login('admin');
const id = await issueId(t, 'E2E search issue');
const priv = await issueId(t, 'E2E private issue');
const found = () => t.page.locator(`dt a[href$="/issues/${id}"]`).count();
const descriptionShown = () => t.page.locator('dd span.description', { hasText: 'Vidsearch secret' }).count();

await t.go(`/search?q=Vidsearch&issues=1`);
if (!(await found()) || !(await descriptionShown())) t.problems.push('admin: description word does not find the issue with its description');
await t.shot('admin-description-word', 'Admin finds the issue by a word of its description, description shown');

await t.login('manager');
await t.go(`/projects/${P}/search?q=Vidsearch&issues=1`);
if (!(await found()) || !(await descriptionShown())) t.problems.push('manager: description word does not find the issue with its description');
await t.shot('manager-description-word', 'Manager (view_issue_description) finds it by its description and sees it');

await t.login('reporter');
await t.go(`/projects/${P}/search?q=Vidsearch&issues=1`);
if (await found()) t.problems.push('reporter: found through the description');
await t.shot('reporter-description-word', 'Reporter (no view_issue_description): a word of the description finds nothing');
await t.go(`/projects/${P}/search?q=${encodeURIComponent('E2E search issue')}&issues=1`);
if (!(await found())) t.problems.push('reporter: not found by its subject');
if (await descriptionShown()) t.problems.push('reporter: description shown in the result');
await t.shot('reporter-subject', 'Reporter still finds the issue by its subject, without the description');
const json = await api(t, 'reporter', `/search.json?q=Vidsearch&issues=1`);
const bySubject = await api(t, 'reporter', `/search.json?q=${encodeURIComponent('E2E search issue')}&issues=1`);
const hit = bySubject.json && bySubject.json.results.find(r => r.id === id);
if (json.status !== 200 || json.json.results.some(r => r.id === id)) t.problems.push('reporter API: found through the description');
if (!hit || hit.description) t.problems.push(`reporter API: by subject ${hit ? 'with description' : 'not found'}`);
await showApi(t, 'Reporter: search API by a description word and by the subject',
  `GET /search.json?q=Vidsearch ; GET /search.json?q=E2E search issue`, `${json.status} / ${bySubject.status}`,
  JSON.stringify({ by_description_word: json.json, by_subject: bySubject.json }, null, 2));
await t.shot('reporter-api', 'search.json: no hit by the description word; by subject the hit has an empty description');

await t.login('scoped');
await t.go(`/projects/${P}/search?q=Vidsearch&issues=1`);
if (!(await found()) || !(await descriptionShown())) t.problems.push('scoped: first-tracker issue not found by its description');
await t.shot('scoped-tracker-grant', 'scoped (view_issue_description for the first tracker) finds the first-tracker issue by its description');

await t.login('outsider');
await t.go(`/search?q=${encodeURIComponent('E2E private issue')}&issues=1`);
if (await t.page.locator(`dt a[href$="/issues/${priv}"]`).count()) t.problems.push('outsider: private issue found');
await t.shot('outsider-private', 'A non-member does not find the issue of the private project');

await t.done();
