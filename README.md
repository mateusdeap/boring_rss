# Boring RSS

A small, boring RSS and Atom feed reader built with Rails and Hotwire.

Add a feed by URL and it's polled for new items in the background, live-updating
your open tab over Action Cable as they arrive — no polling or refresh
required. Unread items are tracked per item, with a count next to each feed
in the sidebar and a marker on each unread item. Accounts are private: every
user has their own feeds and their own reading state.

## Running it locally

Ruby version is pinned via [mise](https://mise.jdx.dev) (see `mise.toml`).
With mise installed:

```
mise install
bin/setup
bin/dev
```

`bin/setup` installs dependencies and prepares the SQLite databases (no
external database server needed). `bin/dev` runs the web server, the
Tailwind watcher, and the background job worker together.

Visit `http://localhost:3000`, sign up for an account, and add a feed by its
URL to get started.

### Running the tests

```
bin/rails test
```

## License

MIT. See [LICENSE](LICENSE).
