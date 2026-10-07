// Function (q3, 2026-10-07): the notification mail of a new issue and of an
// update leaves the description out for a recipient who may not open the
// issue; the mail is still sent. reader (no view_issue_description) and
// scoped (view_issue_description for the first tracker) are notified of every
// event in e2e-project.
import { e2e } from '../../.codex/e2e/lib.mjs';
import { P, showApi } from './_helpers.mjs';

const t = await e2e('mail_description');
const stamp = Date.now();
const subject = `E2E mail issue ${stamp}`;
const secret = `Vidmail secret ${stamp}`;

async function mailTo(login, needle) {
  for (let i = 0; i < 40; i++) {
    const m = t.mails(stamp - 1000).find(x => x.to === `${login}@example.net` && x.body.includes(needle));
    if (m) return m.body.slice(m.body.lastIndexOf('Date:'));
    await new Promise(r => setTimeout(r, 500));
  }
  return null;
}
function excerpt(body) {
  return body.split('\n').filter(l => !/^(Message-ID|In-Reply-To|References|X-|List-Id|Auto-Submitted|Mime-Version|Content-Transfer)/i.test(l)).slice(0, 60).join('\n');
}

await t.login('manager');
await t.go(`/projects/${P}/issues/new`);
await t.page.fill('#issue_subject', subject);
await t.page.fill('#issue_description', secret);
await t.page.click('input[name=commit]');
await t.settle();
t.check('create issue');
await t.shot('manager-created', 'Manager creates an issue (first tracker) with a description');
const issuePath = t.page.url().replace(t.BASE, '').replace(/\?.*$/, '');

const reader = await mailTo('reader', subject);
const scoped = await mailTo('scoped', subject);
if (!reader) t.problems.push('reader: no mail for the new issue');
else if (reader.includes(secret)) t.problems.push('reader: description in the mail');
if (!scoped || !scoped.includes(secret)) t.problems.push('scoped: mail without the description');
await showApi(t, 'Mail to reader (may not open the issue)', `tmp/mails/reader@example.net, "${subject}"`, reader ? 'sent' : 'missing', excerpt(reader || ''));
await t.shot('reader-mail-new', 'reader still gets the mail of the new issue, without the description');
await showApi(t, 'Mail to scoped (view_issue_description for this tracker)', `tmp/mails/scoped@example.net, "${subject}"`, scoped ? 'sent' : 'missing', excerpt(scoped || ''));
await t.shot('scoped-mail-new', 'scoped (may open the issue) gets the mail with the description');

await t.go(`${issuePath}/edit`);
await t.page.fill('#issue_notes', `Vidmail note ${stamp}`);
await t.page.click('#issue-form input[name=commit]');
await t.settle();
t.check('update issue');
const readerEdit = await mailTo('reader', `Vidmail note ${stamp}`);
if (!readerEdit) t.problems.push('reader: no mail for the update');
else if (readerEdit.includes(secret)) t.problems.push('reader: description in the update mail');
await showApi(t, 'Update mail to reader', `tmp/mails/reader@example.net, note ${stamp}`, readerEdit ? 'sent' : 'missing', excerpt(readerEdit || ''));
await t.shot('reader-mail-update', 'The update mail to reader has the note, not the description');

const outsider = t.mails(stamp - 1000).find(x => x.to === 'outsider@example.net' && x.body.includes(subject));
if (outsider) t.problems.push('outsider: got a mail');
const reporter = t.mails(stamp - 1000).find(x => x.to === 'reporter@example.net' && x.body.includes(subject) && x.body.includes(secret));
if (reporter) t.problems.push('reporter: got the description by mail');

await t.done();
