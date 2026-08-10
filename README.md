# player

Your starting point. This is a real OTP app: it compiles, connects to the
platform node, and declares the `WikiRace.Crawler` behavior, but doesn't
implement it yet. `lib/player/crawler.ex`'s `start/2` and `status/1` both
raise `"TODO"`.

This one source tree is mounted into both the `player1` and `player2`
docker-compose services. They're still two independent containers/nodes,
just built from the same starting point. Give one side an artificial
disadvantage the same way `RUNNING.md`'s manual flow does today: a config
knob your crawler reads at runtime, not a second copy of the code.

## What to do

1. Implement `Player.Crawler` (`lib/player/crawler.ex`):
   - `start/2` takes the start and target URLs, starts whatever process tree
     your search needs under your own supervision, and returns `{:ok, pid}`.
   - `status/1` takes that pid and returns a `WikiRace.Status.t()`. Keep it
     cheap and non-blocking, it's polled roughly every 250ms.
   - See `lib/wiki_race/crawler.ex` and `lib/wiki_race/status.ex` for the full
     contract, typespecs and docs. Nothing there needs to change; it's what
     the harness calls verbatim.
2. Call `WikiRace.Harness.report/1` (`lib/wiki_race/harness.ex`) the moment
   you have a path. This, not `status/1`, is what actually decides the race.
3. Wire your supervision tree into `lib/player/application.ex`. Its
   `children` list starts empty.
4. `mix test` runs the contract test (`test/wiki_race/contract_test.exs`),
   which fails until `start/2`/`status/1` do something real. It's a local
   sanity check, not something graded directly.

## Constraints

Only `req` (HTTP) and `floki` (HTML parsing) as external dependencies. See
`mix.exs`. Everything else (concurrency, distribution, coordination) has to
be standard OTP: `GenServer`, `DynamicSupervisor`, ETS, Erlang distribution.

Both URLs `start/2` receives are absolute, fetchable Kiwix article URLs.
Pass them straight to `Req.get/1`. Never request `wikipedia.org`; the offline
snapshot is the only legal source.

See `../SCORING.md` for how races are ranked and scored.

## Local iteration

`bin/connect.exs` and the `PLATFORM_NODE`/`ERL_COOKIE`/`NODE_NAME` environment
variables are docker-compose plumbing, not part of the assignment. See the
repo root `RUNNING.md` for how this container is started. Edits to `lib/`
take effect on the next `docker compose restart player1 player2`, since the
source tree is bind-mounted, not baked into the image.
