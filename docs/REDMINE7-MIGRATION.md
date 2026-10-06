# Redmine 7 migration: redmine_view_issue_description

Start a Claude Code (or Codex) session on this repository, branch `redmine70-migration`, with:

> Read CLAUDE.md and docs/REDMINE7-MIGRATION.md, then carry out the Redmine 7 migration of this
> plugin as described there, on branch redmine70-migration. That includes the plugin's tests on
> PostgreSQL and MariaDB, every function exercised end to end on a real running Redmine in a
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
| Runs on Redmine 7 as is | JA |
| Upstream sync | NIET NODIG |
| After sync | n.v.t. |
| Complexity (1 trivial .. 5 rewrite) | 2 |
| Measured on | Redmine 7.0.1 (7.0-stable-GEOxyz + latest 7.0-stable), Rails 8.1.3.1, Ruby 3.3.6, PostgreSQL 16 and MariaDB 10.11 |
| Branch head when this file was written | `644fb4e` |

## Already on this branch

- nothing: the branch equals the branch GEOxyz runs today.

## Work list for the migration session

In this order: things that break, security, the GEOxyz changes, the open items, then the checks.

**Priority items**

1. Helpdesk 4.3.x renamed HelpdeskTicket#customer to #contact (and Issue#customer to #helpdesk_contact): lib/redmine_view_issue_description/patches/issues_controller_patch.rb lines 161-162 and 276-277 call `ticket.customer` and raise NoMethodError in the API output once helpdesk 4.3.1 is installed. Use `ticket.contact`; test with redmine_contacts_helpdesk@redmine70-migration installed.
2. Redmine 7 webhooks (#29664) send the core issue API payload (app/views/issues/show.api.rsb, rendered as the webhook owner) and bypass plugin hooks and patches on controllers/views. Check whether this plugin changes what an issue shows, hides or adds, and make webhook payloads consistent with that. Here: the description reaches webhook owners who lack view_issue_description; also GET /issues.json (index) is not filtered.

**Open items from the analysis** (Dutch; where they conflict with a decision or a priority item above, those win)

3. Redmine 7 webhooks (#29664) sturen issues/show.api.rsb incl. description naar webhook-eigenaars die alleen visible? nodig hebben: afschermen of use_webhooks niet toekennen
4. Watcher-modal deface overrides (watchers/_new, watchers/autocomplete_for_user) handmatig testen op 7.0 (selectors statisch identiek)
5. Pre-existing: GET /issues.json bevat description, niet afgeschermd

**Checks**

6. Run the plugin's whole test suite on Redmine 7.0-stable-GEOxyz with PostgreSQL AND MariaDB, and once on 5.1-stable if the branch is meant to stay 5.1-compatible.
7. Verify every feature of the plugin by hand on a running Redmine 7 (screenshots).

## GEOxyz changes to review or re-apply

Own plugin: all of it is GEOxyz code, so there is nothing to re-apply. While migrating, hold the code you touch to the rules below; list larger quality problems you find in the work list instead of fixing them in passing.

## After the upgrade (production)

Actions the person doing the upgrade must take, or know about, for this plugin:

- None known. Add here what the session finds.

## How to test

This repo already has its own `.codex/` scripts (older variant). Read their headers and use them; check they accept `7.0-stable-GEOxyz` (clone from https://github.com/jcatrysse/redmine.git) and MariaDB. The shared variant from the other plugin repos may replace them if that is simpler.

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
   - the plugin's tests on Redmine 7.0-stable-GEOxyz with PostgreSQL and with MariaDB;
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
6. **Portability**: everything must run on Redmine's supported databases (PostgreSQL,
   MySQL/MariaDB; SQLite where the plugin already supports it). Migrations must be reversible and
   are run down and up on PostgreSQL and MariaDB.
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
   - Before pictures where behaviour or layout changes: the branch GEOxyz runs today, on
     Redmine 5.1, same scenarios, `RMP_E2E_OUT=docs/e2e/before`.
   - Run the whole e2e set once on MariaDB as well (`RMP_DB=mariadb`, then `start_server.sh --reset`).
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
    `redmine70-migration`, and report: what changed, test numbers on both databases, e2e
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
- **5.1 compatibility**: prefer fixes that also run on Redmine 5.1 so they can be merged early;
  say so when a fix cannot.
- **Git**: work on `redmine70-migration` only; never push to the default branch; never force-push
  a branch someone else uses. Descriptive commit messages (what and why). Push after every
  commit, together with the updated status in this file: a cloud session can stop at a usage
  limit, and work that is not pushed is lost with its container.
- **GitHub Actions**: manual only (`workflow_dispatch`). Do not add push, pull_request or schedule
  triggers.

## Definition of done

- All items of the work list are done or explicitly deferred with a reason, in this file.
- The plugin's tests are green on Redmine 7.0-stable-GEOxyz with PostgreSQL and MariaDB
  (numbers in this file); boot, production-like eager load, migrations up/down OK.
- Every function in the inventory exercised end to end on a real running Redmine, with and
  without permissions and on its failure paths; `./.codex/e2e.sh` green; screenshots looked at,
  committed in `docs/e2e/` and listed.
- Review done: your own, and the OpenAI review when the key is present, every finding resolved
  in `docs/reviews/`.
- No new failure when run together with the other GEOxyz plugins.
- "After the upgrade" lists every action production needs; "Status" is current.


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

