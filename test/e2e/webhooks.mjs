// Function (Redmine 7): webhooks for issues reach only owners who may open the
// issue. hookuser (use_webhooks, no plugin permission) owns a hook from the seed;
// manager creates one through the UI. A receiver in this script records what
// Redmine posts.
import http from 'node:http';
import os from 'node:os';
import { e2e } from '../../.codex/e2e/lib.mjs';
import { P, issueId } from './_helpers.mjs';

const port = Number(process.env.RMP_HOOK_PORT || 3999);
const host = process.env.RMP_HOOK_HOST ||
  Object.values(os.networkInterfaces()).flat().find(a => a.family === 'IPv4' && !a.internal).address;
const received = [];
const server = http.createServer((req, res) => {
  let body = '';
  req.on('data', c => { body += c; });
  req.on('end', () => {
    if (req.method === 'POST') {
      let p = {};
      try { p = JSON.parse(body); } catch { /* keep raw */ }
      received.push({ path: req.url, type: p.type, issue: p.data?.issue?.id, description: p.data?.issue?.description ?? null,
                      journal: p.data?.journal?.notes ?? null });
      res.end('ok');
    } else {
      const rows = received.map(r => `<tr><td>${r.path}</td><td>${r.type}</td><td>#${r.issue}</td><td>${r.journal ?? ''}</td><td>${r.description ? 'yes' : 'no'}</td></tr>`).join('');
      res.setHeader('Content-Type', 'text/html');
      res.end(`<html><body style="font:14px sans-serif;margin:16px"><h3>Webhook deliveries received (${received.length})</h3>
        <table border="1" cellpadding="4" style="border-collapse:collapse"><tr><th>hook URL path</th><th>event</th><th>issue</th><th>journal notes</th><th>description in payload</th></tr>${rows}</table></body></html>`);
    }
  });
});
await new Promise(r => server.listen(port, '0.0.0.0', r));
const waitFor = async (pred, ms = 15000) => { const end = Date.now() + ms; while (Date.now() < end) { if (pred()) return true; await new Promise(r => setTimeout(r, 300)); } return false; };

const t = await e2e('webhooks');
await t.login('admin');
const issue = await issueId(t, 'E2E unassigned issue');

await t.login('hookuser');
await t.go('/webhooks');
await t.shot('hookuser-hooks', 'hookuser (use_webhooks, no view_issue_description) owns an active issue hook on the project');
await t.go(`/issues/${issue}`, { status: 403 });

await t.login('manager');
await t.go('/webhooks');
const managerUrl = `http://${host}:${port}/manager`;
const row = t.page.locator('#content tr', { hasText: managerUrl });
if (await row.count()) {
  // a hook from an earlier run: open it and make sure it is active
  await t.go(await row.locator('a[href*="/edit"]').first().getAttribute('href'));
  await t.sudo();
} else {
  await t.go('/webhooks/new');
  await t.sudo();
  await t.page.fill('#webhook_url', managerUrl);
}
await t.page.check('#webhook_active');
await t.page.check('#webhook_events_issue\\.updated');
await t.page.locator('#webhook_project_ids label', { hasText: 'E2E project' }).locator('input').check();
await t.shot('manager-new', 'Manager sets up an active issue.updated hook for the E2E project');
await t.page.click('#content input[type=submit]');
await t.settle();
t.check('save hook');
await t.go('/webhooks');
await t.shot('manager-hooks', 'The manager hook is listed');

const note = `Webhook check ${Date.now()}`;
await t.go(`/issues/${issue}/edit`);
await t.page.fill('#issue_notes', note);
await t.page.click('#issue-form input[name=commit]');
await t.settle();
t.check('add note');
if (!(await waitFor(() => received.some(r => r.journal === note && r.path === '/manager')))) t.problems.push('manager hook: no delivery for the note');
await new Promise(r => setTimeout(r, 3000)); // give a wrong delivery time to arrive
if (received.some(r => r.journal === note && r.path === '/hookuser')) t.problems.push('hookuser hook received the issue without detail access');

// Assigned to hookuser, the issue opens for it, so its hook fires as well.
await t.go(`/issues/${issue}/edit`);
await t.page.selectOption('#issue_assigned_to_id', { label: 'Hook E2E' });
await t.page.fill('#issue_notes', `${note} assigned`);
await t.page.click('#issue-form input[name=commit]');
await t.settle();
t.check('assign');
if (!(await waitFor(() => received.some(r => r.journal === `${note} assigned` && r.path === '/hookuser')))) t.problems.push('hookuser hook: no delivery once assignee');

await t.page.goto(`http://127.0.0.1:${port}/`);
await t.shot('deliveries', 'Receiver: the note reached only the manager hook; after assigning hookuser, its hook got the update too');

// back to unassigned for the next run
await t.go(`/issues/${issue}/edit`);
await t.page.selectOption('#issue_assigned_to_id', { value: '' });
await t.page.click('#issue-form input[name=commit]');
await t.settle();

server.close();
await t.done();
