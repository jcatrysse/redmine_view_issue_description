# Redmine 7 migration: redmine_view_issue_description

Start a Claude Code (or Codex) session on this repository, branch `redmine70-migration`, with:

> Read CLAUDE.md and docs/REDMINE7-MIGRATION.md, then carry out the Redmine 7 migration of this
> plugin as described there, on branch redmine70-migration. That includes the plugin's tests on
> PostgreSQL, every function exercised end to end on a real running Redmine in a
> browser (with and without permissions, failure paths included) with screenshots you looked at,
> and an OpenAI review of the diff when OPENAI_API_KEY is set. Report to me in Dutch at the end.

This file is the plan and the memory of that work. Update it as you go: verdicts, results,
what is left. Written 2026-10-06 from a measured analysis (report at the bottom).

## Status

| | |
|---|---|
| Plugin id | `redmine_view_issue_description` |
| GEOxyz runs today | `main` |
| Upstream | redminetrustteam/redmine_view_issue_description (main @ 07d5be9, 2023-08-07, voorouder van main) |
| Runs on Redmine 7 as is | JA (analysis); the migration session found 4 defects, fixed on this branch |
| Upstream sync | NIET NODIG |
| After sync | n.v.t. |
| Complexity (1 trivial .. 5 rewrite) | 2 |
| Measured on | Redmine 7.0.1 (7.0-stable-GEOxyz @ 8067e23), Rails 8.1.3.1, Ruby 3.3.6, PostgreSQL 16.15 and MariaDB 10.11.14; Redmine 5.1-stable (Rails 6.1.7.10, Ruby 3.2.6) |
| Migration session | 2026-10-06, done: every work list item fixed or answered, tests and e2e green on both databases, OpenAI review without open findings |
| Plugin version | 0.3.0 |

## Already on this branch

Commits after the plan (`8a43e9c..`), one concern each:

| commit | what |
|---|---|
| 7e3604e, 0493f1d, 136470b | test tooling: 7.0-stable-GEOxyz from jcatrysse/redmine, `RMP_DB=mariadb`, `RMP_EXTRA_PLUGINS`, Ruby on PATH, databases created with the client (contacts reads the DB at boot) |
| 1938c64, af8ba03 | work list 1: helpdesk 4.3 `ticket.contact` (fallback `customer` for older helpdesk), spec + integration test + e2e on real helpdesk 4.3.1 |
| 9b446eb | work list 2/3: webhooks, issue events only to hook owners who may open the issue |
| 7f2e8b9, a397f23 | work list 5: no description in issue lists (API index, CSV, PDF, Atom, block column) for issues the user may not open; preload against N+1 (OpenAI finding) |
| 2289618 | work list 4: watcher modal keeps checked users across its pages |
| badf0c3 | combination finding: refusal in a `before_action` (helpdesk after_action gave 500 on a refused update) |
| 74bac69 | e2e scenarios for every function (`test/e2e/`) |
| a5a8057, 0d46145 | e2e evidence MariaDB, PostgreSQL, 5.1 before/after; MariaDB optimizer finding |
| c2fd015, e109318 | OpenAI reviews (`docs/reviews/`) |
| b1f50b2 | version 0.3.0, CHANGELOG, README |

## Work list for the migration session

In this order: things that break, security, the GEOxyz changes, the open items, then the checks.

**Priority items**

1. Helpdesk 4.3.x renamed HelpdeskTicket#customer to #contact (and Issue#customer to #helpdesk_contact): lib/redmine_view_issue_description/patches/issues_controller_patch.rb lines 161-162 and 276-277 call `ticket.customer` and raise NoMethodError in the API output once helpdesk 4.3.1 is installed. Use `ticket.contact`; test with redmine_contacts_helpdesk@redmine70-migration installed.
   **Done** (1938c64, af8ba03). The NoMethodError was rescued and logged, so `helpdesk_ticket` silently disappeared from the API. Now `ticket.contact`, with `customer` as fallback for older helpdesk (5.1). Verified with redmine_contacts + redmine_contacts_helpdesk 4.3.1 @ redmine70-migration: `test/integration/issues_api_helpdesk_test.rb` (5 tests; on the old code 2 failures + 2 errors, log "undefined method `customer' for an instance of HelpdeskTicket") and `test/e2e/helpdesk_api.mjs`. `Issue#customer` is not used by this plugin.
2. Redmine 7 webhooks (#29664) send the core issue API payload (app/views/issues/show.api.rsb, rendered as the webhook owner) and bypass plugin hooks and patches on controllers/views. Check whether this plugin changes what an issue shows, hides or adds, and make webhook payloads consistent with that. Here: the description reaches webhook owners who lack view_issue_description; also GET /issues.json (index) is not filtered.
   **Done** (9b446eb). The plugin refuses the whole issue page (and API show) without detail access, so `Webhook.hooks_for` now drops issue hooks whose owner fails `Issue#detail_access_granted?` (admin, view_issue_description, assignee, watcher with view_watched_issues). News and wiki hooks unchanged; loads only where `Webhook` exists. The plugin's own API additions (changesets_new, helpdesk_ticket) are not added to webhook payloads (core renders show.api.rsb without the include param), same as before. Tests: `test/unit/webhook_issue_detail_test.rb`; e2e `test/e2e/webhooks.mjs` with a real receiver (hookuser gets nothing, manager gets the update; hookuser gets it once assignee). Choice recorded under "Open questions for Jan" (1).

**Open items from the analysis** (Dutch; where they conflict with a decision or a priority item above, those win)

3. Redmine 7 webhooks (#29664) sturen issues/show.api.rsb incl. description naar webhook-eigenaars die alleen visible? nodig hebben: afschermen of use_webhooks niet toekennen
   **Gedaan**: afgeschermd, zie 2.
4. Watcher-modal deface overrides (watchers/_new, watchers/autocomplete_for_user) handmatig testen op 7.0 (selectors statisch identiek)
   **Gedaan**: beide overrides werken op 7.0 (paginering 25 per pagina, zoeken, lege zoekopdracht, toevoegen; `test/e2e/watchers_modal.mjs`). Gevonden en opgelost (2289618): een op pagina 1 aangevinkte gebruiker was na paginawissel niet meer aangevinkt; 7.0 core bewaart vinkjes bij zoeken (`checkboxSelector`), de plugin-paginatie omzeilde dat. Op 5.1 ging het altijd verloren. Restbeperking, core: in 7.0 verdwijnen de bewaarde vinkjes zolang een zoekopdracht nul resultaten heeft (core `restoreChecked` vindt dan geen veldnaam); zoekveld leegmaken brengt ze terug. Op 5.1 bewaart core bij zoeken niets.
5. Pre-existing: GET /issues.json bevat description, niet afgeschermd
   **Gedaan** (7f2e8b9, a397f23): `IssueQuery#issues` markeert issues die de gebruiker niet mag openen, `Issue#description` geeft daar `nil` (attribuut ongewijzigd, wordt nooit teruggeschreven). Geldt voor API index (JSON/XML: `"description": null`), CSV, PDF, Atom en de HTML-beschrijvingskolom; dat dekt ook tracker-beperkte rechten, die vroeger alle beschrijvingen in de kolom toonden. Tests: `test/integration/issues_api_index_description_test.rb` (incl. query-telling), e2e `description_lists.mjs`; before-beelden op 5.1 in `docs/e2e/before/`.

**Checks**

6. Run the plugin's whole test suite on Redmine 7.0-stable-GEOxyz with PostgreSQL AND MariaDB, and once on 5.1-stable if the branch is meant to stay 5.1-compatible.
   **Done**, see "Results".
7. Verify every feature of the plugin by hand on a running Redmine 7 (screenshots).
   **Done**, see "Inventory of functions" and "Results".

**Found during the session**

8. With redmine_contacts_helpdesk installed, a refused `PATCH /issues/:id` answered 500 (helpdesk's `after_action :flash_helpdesk` reads `@issue.current_journal`, which a refused update never built). **Fixed** (badf0c3): the refusal is a `before_action`, which halts the chain. Test `test/integration/issue_detail_refusal_test.rb` (fails on the old code). The helpdesk after_action itself (`current_journal.is_send_note` without nil check) could get a guard in redmine_contacts_helpdesk as well; not changed there.
9. MariaDB 10.11.14 returns no rows for Redmine core's `Issue.visible_condition` with a project (project issue list) for a member of a public project whose role sees all issues; PostgreSQL returns them. Not this plugin's SQL. Standalone reproduction `docs/findings/mariadb-10.11-semijoin.sql` (0, and 8 with `optimizer_switch='semijoin=off'`); failing run kept in `docs/findings/`. Note only: GEOxyz production runs PostgreSQL 16 (Jan, q4: nothing to do).
10. Pre-existing, not fixed (no item in the work list, larger than a migration fix): the description still reaches users who may not open the issue through `/search` and `/search.json` (measured: reporter gets "Description of E2E second tracker issue" for #8, while `/issues/8` is refused), through the activity stream (event description, only for roles with `view_activities`), and possibly through issue notification mails to members who see but may not open the issue (not measured). See "Open questions for Jan" (3).
11. Core's own webhook tests (`test/unit/webhook_test.rb`) assume an owner with `view_issues` gets issue hooks; with this plugin installed they would fail for owners without detail access. Intended; only relevant if core tests run with the plugin.
12. `init.rb` url/author_url still point to redminetrustteam (analysis remark); left unchanged.

## GEOxyz changes to review or re-apply

Own plugin: all of it is GEOxyz code, so there is nothing to re-apply. While migrating, hold the code you touch to the rules below; list larger quality problems you find in the work list instead of fixing them in passing.

## After the upgrade (production)

Actions the person doing the upgrade must take, or know about, for this plugin:

- `bundle install` (deface 1.9.0 resolves next to Rails 8.1); no plugin migrations; restart.
- Webhooks (if enabled): issue events now reach only hook owners who may open the issue (`view_issue_description`, assignee, or watcher with `view_watched_issues`). Owners that only have `view_issues` + `use_webhooks` get no issue events: grant `view_issue_description` to roles whose webhooks must keep working.
- API clients of `GET /issues.json` / `.xml` and CSV/Atom exports: the description is now `null`/empty for issues the user may not open. Integrations that read descriptions from the index need a user with `view_issue_description` (or admin).
- As before (README): roles need `view_activities` for the activity tab.

## How to test

This repo already has its own `.codex/` scripts (older variant). Read their headers and use them; check they accept `7.0-stable-GEOxyz` (clone from https://github.com/jcatrysse/redmine.git). The shared variant from the other plugin repos may replace them if that is simpler.

Then the real Redmine and the browser checks (shared scripts, they use the checkout in `redmine/` or `REDMINE_DIR`):

```sh
./.codex/start_server.sh       # real Redmine (production mode) with this plugin, seeded users and projects
./.codex/e2e.sh                # browser: smoke over the plugin's pages, core issue flows, test/e2e/*.mjs
./.codex/openai_review.sh      # independent OpenAI review of the diff, only when OPENAI_API_KEY is set
```
Write one scenario per function in `test/e2e/<function>.mjs` (example at the top of
`.codex/e2e/lib.mjs`); screenshots and a table per scenario land in `docs/e2e/`. Users:
`admin`, `manager` (every permission), `reporter` (no plugin permissions), `outsider` (no
membership); password `Redmine7Test!`. Needs Node with Playwright and Chromium
(`npm install -g playwright && npx playwright install --with-deps chromium`).

The coordinator's harness (`plugin-check.sh` in the migration kit, kept outside this repo) adds a
browser smoke test of every page the plugin adds and runs all GEOxyz plugins together; the
results quoted in the analysis come from it.

## How the migration session works (same for every plugin)

1. **Start**: `git fetch && git checkout redmine70-migration && git pull`. Read this whole file,
   including the analysis report at the bottom. Do not reopen decisions recorded here.
2. **Baseline, before you change anything**:
   - the plugin's tests on Redmine 7.0-stable-GEOxyz with PostgreSQL;
   - a real running Redmine with this plugin (`./.codex/start_server.sh`) and the browser run
     (`./.codex/e2e.sh`: smoke over every page the plugin adds, plus the core issue flows).
   Write the numbers here. Something already broken now is a finding, not your regression.
3. **Inventory of functions**: list every function of the plugin in this file, in a table
   "function | how a user reaches it | scenario | screenshot". Take them from the README,
   `init.rb` (permissions, menus, settings, project modules), routes, hooks and view
   overrides, macros, mail handling, API endpoints, rake tasks and cron jobs. This table is the
   coverage list for step 8; a function that is not in it will not be tested.
4. **GEOxyz changes**: go through the table above, one item at a time. Each kept or re-made change
   is its own commit with a test that proves it. Record the verdict in the table.
5. **Work list**: then the numbered list, in order. One concern per commit.
6. **Database**: GEOxyz runs PostgreSQL 16 only (Jan, 2026-10-07). Tests and e2e run on
   PostgreSQL; keep SQL portable where that costs nothing; a MariaDB-only problem is a note, not a
   blocker. Migrations must be reversible and are run down and up on PostgreSQL.
7. **Together**: run with the other GEOxyz plugins installed (the migration kit's harness, or
   `RMP_EXTRA_PLUGINS`). A failure that only appears in combination is a finding to record here.
8. **End to end, visually, every function**: on the real Redmine from `start_server.sh`
   (production mode, the way GEOxyz runs it), write one scenario per function in
   `test/e2e/<function>.mjs` with `.codex/e2e/lib.mjs` and run them with `./.codex/e2e.sh`.
   - Each function as the users that matter: `admin`, `manager` (every permission, the
     plugin's included), `reporter` (member without the plugin's permissions), `outsider`
     (no membership, private project must stay invisible).
   - The failure paths too: setting off, permission absent, empty state, invalid input, the
     value that used to raise. A refusal that is shown is evidence as much as a success.
   - One screenshot per function and per path, with a caption saying what it proves. Open
     every screenshot and look at it: a picture nobody looked at proves nothing. Commit them
     in `docs/e2e/` and list them in the inventory table.
   - Functions without a page (mail in and out, REST API, rake tasks, cron, webhooks): exercise
     them against the same running instance (mails land in `redmine/tmp/mails`, `t.mails()`
     reads them; API through `t.page.request`) and record command and result.
   - Before pictures where behaviour or layout changes: the code before the change, same
     scenarios, `RMP_E2E_OUT=docs/e2e/before`.
9. **Independent review**: first your own, adversarial: re-read the whole diff as if someone
   else wrote it and you are paid to reject it. Then, **when `OPENAI_API_KEY` is set in the
   session**, `./.codex/openai_review.sh`: it sends the diff of this branch to an OpenAI model
   and writes `docs/reviews/openai-<date>-<sha>.md`. Every finding gets a `Resolution:` line
   there (fixed in <commit>, with a test, or why not). Fix, re-run the tests and the e2e set,
   and run the review again until it has nothing new that you accept. Without the key: write
   "OpenAI review: skipped, no OPENAI_API_KEY" in the report; never send code anywhere else.
10. **After the upgrade**: anything the production upgrade must do for this plugin (data fixes,
    settings, cron, files, removed features) goes into the section "After the upgrade".
11. **Finish**: update "Status", the inventory and the work list in this file, push
    `redmine70-migration`, and report: what changed, test numbers on PostgreSQL, e2e
    numbers (scenarios, screenshots, problems), the review result, what is left, what needs Jan.

### Stop and ask Jan when
- a GEOxyz change would be lost or behave differently for users;
- a new gem, a new setting with user impact, or a schema change not required by Redmine 7 seems needed;
- the change would send data to an external service (the OpenAI review of the code diff is the
  one exception Jan approved, and only when the key is present);
- upstream and GEOxyz disagree on behaviour and both are defensible.

## Rules

- **Target**: Redmine 7.0-stable-GEOxyz (https://github.com/jcatrysse/redmine), Rails 8.1, Ruby 3.3+.
  Core sources for comparison: branches `5.1-stable`, `6.1-stable`, `7.0-stable`, `7.0-stable-GEOxyz`.
- **Evidence**: never report a test, lint, browser check or review as passed without having seen
  it. Quote the summary lines; list the screenshots. "Should work" is not a result, and a green
  test suite is not proof that a feature works in the browser.
- **Tests**: never skip, delete or weaken a test. A test that encodes Redmine 5 markup or
  behaviour is updated to Redmine 7, with the reason in the commit. Every fix gets a test that
  fails without it.
- **Minimal diffs** in the plugin's own style. No reformatting, no unrelated refactoring.
  Something wrong elsewhere: write it down here, do not fix it in passing.
- **Security**: authorization on every action and entry point; `safe_attributes`, never
  `to_unsafe_hash` into `update`; no SQL built from params; no secrets in logs; no `html_safe` on
  user input.
- **Webhooks (new in Redmine 7)**: core sends issue payloads (core `issues/show.api.rsb`, rendered
  as the webhook owner) to webhook endpoints, past plugin hooks and controller patches. If the
  plugin hides, adds or changes issue data, make webhooks consistent with that or record why not.
- **Redmine 7 conventions**: SVG icons through `sprite_icon` (the `icon icon-*` CSS is gone),
  Propshaft assets under `assets/` (`/assets/plugin_assets/<id>/...`), the new header and user menu,
  `ContextMenus::*Controller`, Loofah-based text formatting, Chart.js as an ES module, sudo mode
  (on by default: `t.sudo()` in a scenario). The breaker list is in the migration kit's CHECKLIST.md.
- **Locales**: keep the locales the plugin ships in sync; translate a new key by matching the
  closest existing key in the same file, not from scratch; do not add new languages.
- **Redmine 7 only** (Jan, 2026-10-07): no 5.1 compatibility, no code paths that exist only for 5.1,
  nothing cherry-picked to `main`.
- **Core patches**: a core method that other installed plugins also patch is patched with
  `prepend`, never with `alias_method` (mixing both on one method recurses).
- **Git**: work on `redmine70-migration` only; never push to the default branch; never force-push
  a branch someone else uses. Descriptive commit messages (what and why). Push after every
  commit, together with the updated status in this file: a cloud session can stop at a usage
  limit, and work that is not pushed is lost with its container.
- **GitHub Actions**: manual only (`workflow_dispatch`). Do not add push, pull_request or schedule
  triggers.

## Definition of done

- All items of the work list are done or explicitly deferred with a reason, in this file.
- The plugin's tests are green on Redmine 7.0-stable-GEOxyz with PostgreSQL
  (numbers in this file); boot, production-like eager load, migrations up/down OK.
- Every function in the inventory exercised end to end on a real running Redmine, with and
  without permissions and on its failure paths; `./.codex/e2e.sh` green; screenshots looked at,
  committed in `docs/e2e/` and listed.
- Review done: your own, and the OpenAI review when the key is present, every finding resolved
  in `docs/reviews/`.
- No new failure when run together with the other GEOxyz plugins.
- "After the upgrade" lists every action production needs; "Status" is current.


## Baseline (before any change, 2026-10-06)

- Redmine 7.0-stable-GEOxyz, PostgreSQL, plugin at `8a43e9c` (= main code): rspec 120 examples, 0 failures. Note: the specs are plain RSpec with stubs; they do not touch the database. The Rails tests in `test/` (added in this session) do.
- Real Redmine (production mode) + browser: smoke 13 screenshots, 0 problems; core flows 1 problem: `/issues/1 as reporter: HTTP 403` - intended plugin behaviour (reporter has no view_issue_description); `e2e.sh` now expects 403 there (`RMP_CORE_REPORTER_ISSUE_STATUS`).

## Inventory of functions

| function | how a user reaches it | scenario | screenshots |
|---|---|---|---|
| Issue page gate (show, edit, update, API show) | `/issues/:id`, `/edit`, PATCH, `.json` | `issue_access.mjs`, `test/integration/issue_detail_refusal_test.rb` | `issue_access-*.png` (manager show/edit, reporter 403 page/edit/API+PATCH, assignee path, watcher path + refusal, outsider) |
| Permissions `view_issue_description`, `view_watched_issues` per tracker (Deface on roles/_form) | Administration, Roles | `role_form.mjs` | `role_form-tracker-columns`, `-saved`, `-no-view-issues` |
| Watched issues visible beyond role visibility (`visible?`, `visible_condition`) | issue list, issue page | `watched_issues.mjs`, specs | `watched_issues-list`, `-self-watch-refused`, `-manager-watch` |
| Self-watch block without detail access | Watch link, `POST /watchers/watch` | `watched_issues.mjs`, specs | `watched_issues-self-watch-refused` |
| Watcher candidates only with `view_watched_issues`, paginated, search (Deface on watchers/_new, autocomplete_for_user) | Add watchers modal | `watchers_modal.mjs` | `watchers_modal-page1`, `-page1-again`, `-page2`, `-search`, `-search-empty`, `-back-to-page1`, `-added` |
| `view_activities` / `view_activities_global` (menus, 403) | Activity tab, `/activity` | `activities.mjs`, specs | `activities-*.png` |
| Description column offered only with permission (QueryPatch) | issue list options | `description_lists.mjs`, specs | `description_lists-reporter` |
| Description in lists only for openable issues (new) | list column, CSV, Atom, `/issues.json`, `.xml` | `description_lists.mjs`, `issues_api_index_description_test.rb` | `description_lists-manager`, `-scoped`, `-scoped-csv`, `-reporter-api-index` |
| API `include=changesets_new` | `/issues/:id.json`, `.xml` | `api_includes.mjs` | `api_includes-changesets-json`, `-changesets-xml`, `-no-include` |
| API `include=helpdesk_ticket`, `journal_messages` | `/issues/:id.json`, `.xml` with helpdesk | `helpdesk_api.mjs`, `issues_api_helpdesk_test.rb` | `helpdesk_api-plugins`, `-ticket-json`, `-ticket-xml` |
| Webhooks only to owners with detail access (new, Redmine 7) | My account, Webhooks | `webhooks.mjs`, `webhook_issue_detail_test.rb` | `webhooks-hookuser-hooks`, `-manager-new`, `-manager-hooks`, `-deliveries` |
| Plugin stylesheet (watcher pagination) | every page head | smoke (no missing assets) | `smoke-*.png`, `watchers_modal-*` |

No settings page, routes of its own, mail handling, rake tasks or cron jobs.

## Results

| run | rspec (spec/) | Rails tests (test/) | e2e (`.codex/e2e.sh`) |
|---|---|---|---|
| 7.0-stable-GEOxyz, PostgreSQL 16, plugin alone | 124 examples, 0 failures | 22 runs, 64 assertions, 0 failures, 5 skips (helpdesk absent) | 12 scripts (smoke, core, 10 scenarios), 0 problems (helpdesk_api not applicable) |
| 7.0-stable-GEOxyz, PostgreSQL 16, with redmine_contacts + helpdesk 4.3.1 | 124 examples, 0 failures | 22 runs, 77 assertions, 0 failures, 0 skips | 12 scripts, 62 screenshots, 0 problems (`docs/e2e/`) |
| 7.0-stable-GEOxyz, MariaDB 10.11.14, with contacts + helpdesk | 124 examples, 0 failures | 22 runs, 77 assertions, 0 failures, 0 skips (default optimizer_switch) | 12 scripts, 62 screenshots, 0 problems with `semijoin=off` (`docs/e2e/mariadb/`); without it description_lists failed on core's query (finding 9) |
| 5.1-stable, PostgreSQL, plugin alone | 124 examples, 0 failures | 22 runs, 50 assertions, 0 failures, 10 skips (no webhooks in 5.1, helpdesk absent) | 7 scenarios (no webhooks/helpdesk): green except 2 search steps of watchers_modal, a 5.1 core limitation (`docs/e2e/redmine51/`) |
| 5.1-stable, main code (before) | | | `docs/e2e/before/`: description_lists 5 problems (descriptions leak), watchers_modal 4 problems (checks lost), issue_access 0 |

Boot and eager load: the production server (eager loading) started on every run; plugin migrations: none (nothing to run down/up). Smoke lists 2 plugin GET routes now (activities); show/edit are no longer method overrides.

Reviews: own adversarial review of the diff (performance of the per-issue check noted, then confirmed by OpenAI). OpenAI (`gpt-5`): `docs/reviews/openai-2026-10-06-a5a8057.md`, 1 finding (N+1 in the list check), fixed in a397f23 with a test; rerun `docs/reviews/openai-2026-10-06-c2fd015.md`: no findings.

Not testable here: nothing of this plugin needs external credentials. Real mail delivery not tested (file delivery only).

## Decided by Jan (2026-10-07)

Jan answered the open questions on 2026-10-07 in the coordinating session
(https://claude.ai/code/session_01GiSsYPm3bxvqrpZkdCxNoi); recorded as given in
`docs/DECISIONS-2026-10-07.md` (fdb025c). No open questions remain.

General decisions, for every GEOxyz plugin:
- **Straight to Redmine 7**: no backports to 5.1, nothing cherry-picked to `main`; `redmine70-migration` goes live with Redmine 7. Redmine 5.1 compatibility is no longer a requirement (rule dropped below). Existing fallbacks on this branch that only matter for 5.1 (helpdesk `customer`, the pre-7.0 `Preloader` call) stay; no new ones are added.
- **PostgreSQL only**: production runs PostgreSQL 16. Tests and e2e run on PostgreSQL; SQL stays portable where that costs nothing; a MariaDB-only problem is a note, not a blocker.
- **deface without a version constraint**: the Gemfile already has `gem 'deface'` without one.
- **`prepend`, never `alias_method`, on a core method other plugins also patch**: checked, see finding 13.
- **GitHub Actions manual only** (`workflow_dispatch`): unchanged.

Decisions for this plugin:
1. **q1 Webhooks for owners who may not open the issue**: A, "Niet versturen naar wie het issue niet mag openen (gebouwd)" (Klopt met de issuepagina en vraagt geen discipline bij rollen; zo'n eigenaar krijgt geen issue-events.). Already built (9b446eb), kept.
2. **q2 Description in lists and the API for issues you may not open**: A, "Leeg ('null'), zelfde vorm als Redmine (gebouwd)" (Koppelingen die de API lezen zien hetzelfde veld, alleen leeg.). Already built (7f2e8b9, a397f23), kept.
3. **q3 Remaining description leaks (search, activity, mails)**: A, "Oplossen in een vervolgwijziging, minstens zoeken" (Sluit het lek met eigen tests, maar vraagt extra werk na de migratie.). Built on this branch, see work list 14.
4. **q4 MariaDB 10.11 in production?**: C, "Geen MariaDB 10.11 in productie: niets doen" (Geldt als productie PostgreSQL draait of het script op de productieserver gewoon issues teruggeeft.). Nothing to do: production runs PostgreSQL 16. Finding 9 stays as a note; the MariaDB line under "After the upgrade" is removed.

## Analysis report (2026-10-06, Dutch)

# redmine_view_issue_description
- Gebruikte branch: main @ e289ec6 (2026-08-01) - plugin id redmine_view_issue_description, versie 0.2.2
- Upstream: redminetrustteam/redmine_view_issue_description (url in init.rb; Jan's vroegere organisatie-repo) - upstream HEAD main @ 07d5be9 (2023-08-07)
- Fork t.o.v. upstream: 9 eigen commits, 0 upstream-commits ontbreken (07d5be9 is voorouder van origin/main, lokaal geverifieerd). De GitHub-pagina van jcatrysse/redmine_view_issue_description toont geen fork-relatie.
- Andere relevante branches: geen. Geen migraties. Gems: `deface` (runtime), `rspec` (test).

## 1. Werkt out of the box op Redmine 7?   JA
Harness `redmine_view_issue_description@origin/main` (1006-090024-s2):
- OK bundle (deface resolvet naast Rails 8.1.3.1), boot (0.2.2), eager load, plugin migrations dev+test
- OK rspec: 120 examples, 0 failures
- OK smoke: 60/60 pages+actions zonder serverfout; geen deprecation warnings
- development.log: `Deface: 'view_issue_description_tracker_permission' matched 1 times with 'erb[silent]:contains('permissions = [:view_issues,')'` (bij /roles/1/edit) - de role-form override werkt op 7.0. Deface-waarschuwing "No :original defined" is cosmetisch.

Deface-selectors tegen 7.0-markup (statisch, `git show origin/7.0-stable:...`):
- `roles/_form`: `erb[silent]:contains('permissions = [:view_issues,')` - regel 75 identiek in 5.1 en 7.0; runtime match bevestigd (zie boven).
- `watchers/_new`: `erb[loud]:contains("principals_check_box_tags('watcher[user_ids][]', users)")` - regel 42 in 7.0, tekst identiek; `#users_for_watcher` bestaat nog. Niet runtime bevestigd (de smoke opent de watcher-modal niet).
- `watchers/autocomplete_for_user`: `erb[loud]:contains("principals_check_box_tags 'watcher[user_ids][]', @users")` - regel 1, identiek. Niet runtime bevestigd.
- Deface-versie: niet vastgelegd (alleen dat hij laadt en matcht op Rails 8.1).

## 2. Upstream sync?   NIET NODIG
redminetrustteam main (07d5be9, 2023-08-07) zit volledig in origin/main; upstream heeft niets nieuwers. De url/author_url in init.rb wijzen nog naar redminetrustteam; optioneel aanpassen naar jcatrysse.

## 3. Werkt na sync op Redmine 7?   n.v.t.

## 4. Complexiteit en blokkers   score 2
- Blokkers: geen.
- Gepatchte core-methodes 5.1 vs 7.0 (allemaal nog aanwezig, zelfde signatuur): `Issue#visible?(usr=nil)`, `Issue.visible_condition(user, options={})`, `Issue#valid_watcher?(user)`, `Query#columns`, `#available_block_columns`, `#has_column?(column)`, `IssuesController#show/edit/update` (prepend), `WatchersController#users_for_new_watcher`, `ActivitiesController#index`.
- Stille breuken:
  - lib/redmine_view_issue_description/patches/issue_patch.rb (`addable_watcher_users` alias): `addable_watcher_users` is in 7.0 uit acts_as_watchable verwijderd (#43429); de patch wordt door zijn `if instance_methods.include?` stil overgeslagen. Geen gedragsverschil: de methode werd in 5.1 al door niets in core aangeroepen.
  - NIEUW in 7.0: webhooks (#29664). `Webhook.hooks_for` stuurt een issue-payload als `object.visible?(hook.user)`; de payload is core `app/views/issues/show.api.rsb` gerenderd als de webhook-eigenaar en bevat `description` en journal-details. De plugin bewaakt de beschrijving alleen in `IssuesController#show/edit/update` en via Query-kolommen, dus een gebruiker met `use_webhooks` maar zonder `view_issue_description` krijgt de beschrijving via de webhook. Alleen relevant als GEOxyz webhooks aanzet.
  - Pre-existing (ook 5.1): `GET /issues.json` (index.api.rsb) bevat `description` per issue; niet door de plugin afgeschermd.
  - Watcher-modal in 7.0 krijgt `checkboxSelector` in `observeSearchfield` (behoud aangevinkte boxen bij zoeken); de plugin vervangt de kandidatenlijst door zijn eigen gepagineerde partial. Niet runtime getest.
- Overlap met Redmine 7 core: geen (core kent geen per-tracker beschrijvingsrecht).
- Pairwise (statisch): `IssuesController` wordt ook gepatcht door redmine_extended_api (prepend create/update, render_api_ok) - verschillende acties, geen conflict. API issue-show: deze plugin injecteert in de JSON/XML response (after_action), redmine_itil_priority vervangt `issues/show.api.rsb` - verdragen elkaar. `Query#columns` (alias) vs redmine_issue_field_visibility (`IssueQuery#available_columns` alias) - verschillende methodes.
- Open werk voor ansif:
  - Webhooks: beslissen of GEOxyz webhooks gebruikt; zo ja de beschrijving in de webhook-payload afschermen (bv. `Issue#webhook_payload` patchen) of `use_webhooks` niet toekennen aan rollen zonder `view_issue_description`.
  - De twee watcher-overrides handmatig testen op 7.0 (watcher toevoegen-modal, zoeken, pagineren).

## Branch redmine70-migration
- Niet aangemaakt: geen fixes nodig.
- Eindresultaat harness (bijgewerkte harness van 09:26, `origin/main`, 1006-093047-s2): OK bundle, boot 0.2.2, eager load, migrations dev+test, OK rspec 120 examples 0 failures, OK smoke 60/60.
- Rollback migraties: n.v.t. (geen migraties)


## Aanvulling coordinator
Branch `redmine70-migration` is wel gepusht, als startpunt zonder commits: gelijk aan de gebruikte branch (e289ec6). Fixes die hierboven als diff staan, zijn nog niet gecommit.

