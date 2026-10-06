// Function: the extra API sections on GET /issues/:id.json and .xml:
// include=changesets_new (changesets with their repository), and
// include=helpdesk_ticket / journal_messages (only with redmine_contacts_helpdesk:
// see helpdesk_api.mjs).
import { e2e } from '../../.codex/e2e/lib.mjs';
import { api, issueId, showApi } from './_helpers.mjs';

const t = await e2e('api_includes');
await t.login('admin');
const assigned = await issueId(t, 'E2E assigned issue');

const json = await api(t, 'manager', `/issues/${assigned}.json?include=changesets_new`);
const cs = json.json?.issue?.changesets_new;
if (!Array.isArray(cs) || cs.length !== 1) t.problems.push(`changesets_new: ${JSON.stringify(cs)}`);
else if (cs[0].repository?.identifier !== 'e2e') t.problems.push(`changesets_new: no repository info (${JSON.stringify(cs[0])})`);
await showApi(t, 'Manager: include=changesets_new', `GET /issues/${assigned}.json?include=changesets_new`, json.status,
  JSON.stringify({ changesets_new: cs }, null, 2));
await t.shot('changesets-json', 'JSON: changesets_new carries revision, comments and the repository');

const xml = await api(t, 'manager', `/issues/${assigned}.xml?include=changesets_new`);
if (!/<changesets_new type="array">\s*<changeset revision="[0-9a-f]+">/.test(xml.text) || !xml.text.includes('identifier="e2e"')) {
  t.problems.push('changesets_new XML: section or repository missing');
}
await showApi(t, 'Manager: include=changesets_new (XML)', `GET /issues/${assigned}.xml?include=changesets_new`, xml.status,
  (xml.text.match(/<changesets_new[\s\S]*<\/changesets_new>/) || ['(missing)'])[0]);
await t.shot('changesets-xml', 'XML: the same section');

const plain = await api(t, 'manager', `/issues/${assigned}.json`);
if ('changesets_new' in (plain.json?.issue || {})) t.problems.push('changesets_new present without the include');
const helpdesk = await api(t, 'manager', `/issues/${assigned}.json?include=helpdesk_ticket`);
if ('helpdesk_ticket' in (helpdesk.json?.issue || {})) t.problems.push('helpdesk_ticket present on an issue without ticket');
await showApi(t, 'Without the include, and include=helpdesk_ticket on an issue without ticket', `GET /issues/${assigned}.json[?include=helpdesk_ticket]`,
  `${plain.status} / ${helpdesk.status}`, `keys without include: ${Object.keys(plain.json.issue).join(', ')}\nhelpdesk_ticket in the answer: ${'helpdesk_ticket' in helpdesk.json.issue}`);
await t.shot('no-include', 'No extra sections without the include, none for an issue without helpdesk ticket');

const refused = await api(t, 'reporter', `/issues/${assigned}.json?include=changesets_new`);
if (refused.status !== 403) t.problems.push(`reporter: HTTP ${refused.status}, expected 403`);

await t.done();
