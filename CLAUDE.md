# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Ruby version manager

This project pins its Ruby version via `mise` (see `mise.toml`), not system Ruby. The shell is not mise-activated in this environment, so any bare `bin/*` script (`bin/rails`, `bin/rubocop`, `bin/ci`, ...) resolves to the system Ruby (2.6) and fails with a Bundler platform error on this Gemfile. Prefix every `bin/*` invocation with `mise exec --`, e.g.:

```bash
mise exec -- bin/rails db:migrate
mise exec -- bin/rails generate migration AddFooToBar
mise exec -- bin/rails test
```

## Commands

- Run the dev server (web + Tailwind watcher + Solid Queue jobs, via Foreman): `bin/dev`
- Run all tests: `mise exec -- bin/rails test`
- Run a single test file: `mise exec -- bin/rails test test/models/item_test.rb`
- Run a single test by line: `mise exec -- bin/rails test test/models/item_test.rb:12`
- Lint (Omakase Rubocop): `bin/rubocop`
- Full CI pipeline locally (setup, rubocop, bundler-audit, importmap audit, brakeman, tests, seed replant): `bin/ci`

## Architecture

This is a feed reader: `Feed has_many :items`. Feeds are polled and parsed with Ruby's stdlib `rss` gem, which supports both RSS and Atom — parsing is normalized behind a small adapter layer so the rest of the app never branches on format.

- `ParsedFeed` (`app/services/parsed_feed.rb`) — wraps `RSS::Parser.parse`'s result (either an `RSS::Rss` or `RSS::Atom::Feed` instance) and exposes format-agnostic `#title`/`#description`/`#link`/`#entries`. `ParsedFeedEntry` (`app/services/parsed_feed_entry.rb`) does the same per-entry (`#title`/`#summary`/`#link`/`#guid`/`#published_at`), preferring Atom's `summary` over `content` and falling back to `updated` when `published` is absent (it's optional in Atom). `AtomLink` (`app/services/atom_link.rb`) picks the `rel="alternate"` link out of Atom's multi-`<link>` elements (RSS only ever has one link, no resolution needed). This is the layer to extend for any new source format or field.
- `InitializeFeed` (`app/services/initialize_feed.rb`) — parses a feed URL via `ParsedFeed.parse`, builds an unsaved `Feed` with nested `items` (via `accepts_nested_attributes_for`). Rescues `RSS::Error` (covers both malformed XML and schema-validation failures, e.g. an Atom feed missing a required `<author>`) and returns an unsaved `Feed` with a validation error on `:link` instead of raising, so the controller can re-render the form.
- `InitializeItems` (`app/services/initialize_items.rb`) — maps `ParsedFeedEntry` objects into unsaved `Item` records.
- `UpdateFeedsJob` (`app/jobs/update_feeds_job.rb`) — scheduled job (see `config/recurring.yml`, runs every minute in development via Solid Queue's recurring scheduler) that re-polls each `Feed.feed_url` and appends newly-published items. Dedup is identity-based (`guid.presence || link`, compared against existing items' `guid`/`link`), not date-based — this is required for Atom, where `published` is optional, and is more robust for RSS too. A per-feed `rescue RSS::Error` keeps one broken/unreachable feed from blocking the others on this every-minute job.
- Background jobs run on Solid Queue with a separate `queue` database (`config/database.yml`); Mission Control Jobs is mounted at `/jobs` (`config/routes.rb`) for inspecting job state.
- New items broadcast live to the feed show page over Action Cable: `Item#after_create_commit` calls `broadcast_prepend_to feed, target: "items", partial: "items/list_item"`, and `feeds/show.html.erb` subscribes via `turbo_stream_from @feed`, prepending into `<div id="items">`. This fires for items created anywhere (nested-attributes save on feed creation, or `UpdateFeedsJob`), not just the job.
- Feed creation is Turbo-Stream driven: `FeedsController#create` appends a rendered `feeds/feed` partial to the `feeds` list on success, or re-renders `new` with errors for a Turbo Stream response.
- `ItemsController` is a standard Rails scaffold (full CRUD + JSON), not currently wired into the main feed-reading UI flow, which reads items only through `feed.items` on the feed show page.

### Nomenclature: RSS vs. Atom

`Item#published_at` (not `pub_date`) and `Item#summary` (not `description`) are named to stay parser-agnostic: they map to either RSS (`pubDate`/`description`) or Atom (`published`/`summary`|`content`) source fields via the `ParsedFeed`/`ParsedFeedEntry` adapter above. `Item#guid` (nullable, unique per `feed_id`) holds RSS's optional `<guid>` or Atom's required `<id>`, and is the dedup key `UpdateFeedsJob` uses.

## Database

SQLite, with separate `primary`/`queue`/`cache`/`cable` databases per `config/database.yml` (Solid Cache/Queue/Cable, each with their own `migrations_paths`). Migrations for the primary app schema live in `db/migrate/` and are generated with `mise exec -- bin/rails generate migration ...`.

## Notes

- Action Cable uses `solid_cable` (DB-backed) in **both** development and production (`config/cable.yml`), not the Rails-default `async` adapter. `async` only pub-subs within a single process, and `bin/dev` runs the web server and the Solid Queue worker/scheduler as separate OS processes — a broadcast triggered from a job (e.g. `UpdateFeedsJob`) would never reach a browser connected to the web process under `async`. If Action Cable broadcasts silently don't arrive in development, check `config/cable.yml` hasn't reverted to `async` before debugging anything else. Action Cable config is only read at boot, so changing it requires restarting `bin/dev`, not just waiting for code reloading.
- `config/initializers/field_with_errors.rb` disables Rails' default error-wrapping `<div class="field_with_errors">` around invalid form fields (it just returns the tag unwrapped), since that wrapper breaks Tailwind styling. Keep this in mind when debugging why invalid-field styling isn't showing up automatically — error state has to be styled explicitly in the view/`error_class:` rather than relying on the wrapper.
- `ItemsController`'s full CRUD scaffold (new/edit/create/update/destroy) is leftover from `rails generate scaffold` and isn't linked from the UI — don't treat it as a real feature surface to build around.
- Test depth for this prototype: model/controller/job tests only. Don't add Capybara system tests unless asked.
