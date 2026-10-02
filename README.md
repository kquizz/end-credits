# End Credits

Small lookups for the things you wonder while watching. Built with Rails 8, Hotwire and Tailwind.

| Tool | Path | Status |
|---|---|---|
| Cast & EGOTs | `/cast` | live |
| Cast Ages | `/ages` | live |
| Co-star Web | — | designed |
| Six Degrees | — | designed |
| EGOT Tracker (person search) | — | to migrate from `egot-tracker` |

Design docs live in `docs/`.

## Data

- **TMDb** for titles, casts, people and credits. Set `TMDB_API_KEY` (a v3 key) or
  `TMDB_API_TOKEN` (a v4 read token), or put `tmdb_api_token` in Rails credentials.
- **Wikidata** maps a person's IMDb id to their English Wikipedia article (exact, not
  name matching). **Wikipedia** category membership gives award wins. Neither needs a key.

## Develop

```sh
bundle install
bin/dev            # server + Tailwind watcher
bundle exec rspec
bin/rubocop
```

New Tailwind classes only appear after a rebuild; `bin/dev` does that for you.
