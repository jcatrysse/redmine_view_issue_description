// Function: include=helpdesk_ticket / journal_messages on GET /issues/:id.json
// and .xml, with redmine_contacts_helpdesk 4.3 installed (helpdesk renamed the
// ticket's #customer to #contact). Without that plugin the scenario only
// records that it was not applicable.
import { e2e } from '../../.codex/e2e/lib.mjs';
import { api, issueId, showApi } from './_helpers.mjs';

const t = await e2e('helpdesk_api');
await t.login('admin');
await t.go('/admin/plugins');
if (!(await t.page.locator('#content', { hasText: 'Redmine Helpdesk plugin' }).count())) {
  console.log('helpdesk_api: redmine_contacts_helpdesk not installed, nothing to check');
  await t.done();
  process.exit(0);
}
await t.shot('plugins', 'redmine_contacts and redmine_contacts_helpdesk are installed next to this plugin');
const issue = await issueId(t, 'E2E related issue');

const json = await api(t, 'manager', `/issues/${issue}.json?include=helpdesk_ticket`);
const ticket = json.json?.issue?.helpdesk_ticket;
if (ticket?.contact?.name !== 'Jane Customer') t.problems.push(`helpdesk_ticket JSON: ${JSON.stringify(ticket)}`);
await showApi(t, 'Manager: include=helpdesk_ticket', `GET /issues/${issue}.json?include=helpdesk_ticket`, json.status,
  JSON.stringify({ helpdesk_ticket: ticket }, null, 2));
await t.shot('ticket-json', 'JSON: the helpdesk_ticket section with its contact (the 4.3 #contact)');

const xml = await api(t, 'manager', `/issues/${issue}.xml?include=journal_messages`);
if (!/<helpdesk_ticket>[\s\S]*<contact id="\d+" name="Jane Customer"\/>[\s\S]*<journal_messages type="array"/.test(xml.text)) t.problems.push('helpdesk_ticket XML: contact or journal_messages missing');
await showApi(t, 'Manager: include=journal_messages (XML)', `GET /issues/${issue}.xml?include=journal_messages`, xml.status,
  (xml.text.match(/<helpdesk_ticket>[\s\S]*<\/helpdesk_ticket>/) || ['(missing)'])[0]);
await t.shot('ticket-xml', 'XML: helpdesk_ticket with contact and journal_messages');

const refused = await api(t, 'reporter', `/issues/${issue}.json?include=helpdesk_ticket`);
if (refused.status !== 403) t.problems.push(`reporter: HTTP ${refused.status}, expected 403`);

await t.done();
