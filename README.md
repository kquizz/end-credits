# End Credits

Small lookups for the things you wonder while watching. Built with Rails 8, Hotwire and Tailwind.

| Tool | Path | Status |
|---|---|---|
| Cast & EGOTs | `/cast` | live |
| Cast Ages | `/ages` | live |
| Co-star Web | `/costars` | live |
| Six Degrees (solo + live 2-player rooms) | `/degrees` | live |
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

## Deploy

Live at **https://credits.kquizz.com**. Same pattern as egot-tracker: Kamal builds the image,
pushes it to ghcr.io, and runs it on the homelab; a Cloudflare tunnel terminates HTTPS and
speaks plain HTTP to kamal-proxy.

```sh
bin/kamal deploy      # needs KAMAL_REGISTRY_PASSWORD and TMDB_API_KEY in your login shell
bin/kamal logs
```

One-time: add a public hostname `credits.kquizz.com` to the Cloudflare tunnel, pointing at the
homelab's HTTP port. SQLite databases (app, cache, queue, cable) persist in the
`end_credits_storage` volume, and `db:prepare` runs on boot.
