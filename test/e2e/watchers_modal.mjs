// Function: the "Add watchers" modal lists only users with view_watched_issues,
// 25 per page with search (Deface overrides of watchers/_new and
// watchers/autocomplete_for_user), and keeps users checked on another page.
import { e2e } from '../../.codex/e2e/lib.mjs';
import { issueId } from './_helpers.mjs';

const t = await e2e('watchers_modal');
await t.login('admin');
const issue = await issueId(t, 'E2E related issue');
async function removeWatchers() {
  await t.go(`/issues/${issue}`);
  for (let n = await t.page.locator('#watchers a.delete').count(); n > 0; n -= 1) {
    await t.page.locator('#watchers a.delete').first().click();
    await t.page.waitForFunction(k => document.querySelectorAll('#watchers a.delete').length < k, n, { timeout: 10000 });
  }
}
// start without watchers
await removeWatchers();

await t.login('manager');
await t.go(`/issues/${issue}`);
await t.page.click('#watchers a[href*="watchers/new"]');
await t.page.waitForSelector('#users_for_watcher label');
const names = await t.page.locator('#users_for_watcher label').allInnerTexts();
if (names.length !== 25) t.problems.push(`page 1: ${names.length} candidates, expected 25`);
for (const n of ['Reporter', 'Hook', 'Scoped']) {
  if (names.some(x => x.includes(n))) t.problems.push(`candidate "${n}" lacks view_watched_issues but is listed`);
}
await t.page.locator('#users_for_watcher label', { hasText: 'Watcher 01' }).locator('input').check();
await t.shot('page1', 'Page 1 of the candidates: only users with view_watched_issues, 25 per page; Watcher 01 checked', { full: false });

// To page 2 and back through the pagination links: Watcher 01 stays checked.
await t.page.click('#users_for_watcher .pagination a:has-text("2")');
await t.page.waitForSelector('#users_for_watcher label:has-text("Watcher 27")');
await t.page.click('#users_for_watcher .pagination a:has-text("1")');
await t.page.waitForSelector('#users_for_watcher label:has-text("Watcher 01")');
if (!(await t.page.locator('#users_for_watcher label', { hasText: 'Watcher 01' }).locator('input').isChecked())) {
  t.problems.push('page 2 and back: Watcher 01 is no longer checked');
}
await t.shot('page1-again', 'Page 2 and back to page 1: Watcher 01 is still checked', { full: false });
await t.page.click('#users_for_watcher .pagination a:has-text("2")');
await t.page.waitForSelector('#users_for_watcher label:has-text("Watcher 27")');
t.check('page 2');
await t.page.locator('#users_for_watcher label', { hasText: 'Watcher 27' }).locator('input').check();
await t.shot('page2', 'Page 2; Watcher 27 checked, Watcher 01 is kept as a hidden field', { full: false });

await t.page.fill('#user_search', 'Watcher 3');
await t.page.waitForFunction(() => {
  const l = [...document.querySelectorAll('#users_for_watcher label')].map(e => e.innerText);
  return l.length > 0 && l.length < 25 && l.every(x => x.includes('Watcher') && x.includes('3'));
}, null, { timeout: 10000 }).catch(() => t.problems.push('search did not filter on "Watcher 3"'));
t.check('search');
await t.shot('search', 'Searching "Watcher 3" filters the candidates (every word must match: 03, 13, 23, 30)', { full: false });

await t.page.fill('#user_search', 'nobody-matches-this');
await t.page.waitForFunction(() => document.querySelectorAll('#users_for_watcher label').length === 0, null, { timeout: 10000 })
  .catch(() => t.problems.push('a search without match still lists candidates'));
await t.shot('search-empty', 'A search without a match lists no candidates', { full: false });

// Back to the full list: Watcher 01 (page 1) is checked again. (Core's own
// observeSearchfield drops the kept values while a search has no result at all;
// clearing the search brings them back, see the migration plan.)
await t.page.fill('#user_search', '');
await t.page.waitForFunction(() => document.querySelectorAll('#users_for_watcher label').length === 25, null, { timeout: 10000 })
  .catch(() => t.problems.push('clearing the search did not bring page 1 back'));
if (!(await t.page.locator('#users_for_watcher label', { hasText: 'Watcher 01' }).locator('input').isChecked())) {
  t.problems.push('Watcher 01 is no longer checked on page 1');
}
await t.shot('back-to-page1', 'Search cleared: page 1 again, Watcher 01 still checked', { full: false });

await t.page.click('#new-watcher-form input[type=submit]');
await t.settle();
t.check('add watchers');
const watchers = await t.page.locator('#watchers ul.watchers').innerText().catch(() => '');
for (const n of ['Watcher 01', 'Watcher 27']) if (!watchers.includes(n)) t.problems.push(`${n} was checked but not added`);
await t.shot('added', 'Add: the users checked on page 1 and page 2 are both watchers now');

// leave the issue without watchers for the other scenarios
await removeWatchers();

await t.done();
