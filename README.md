# player

Your starting point. This is a real OTP app: it compiles, connects to the
platform node, and declares the `WikiRace.Crawler` behaviour, but doesn't
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
     cheap and non-blocking. It's polled roughly every 250ms.
   - See `lib/wiki_race/crawler.ex` and `lib/wiki_race/status.ex` for the full
     contract, typespecs and docs. Nothing there needs to change. It's what
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
Pass them straight to `Req.get/1`. Never request `wikipedia.org`. The offline
snapshot is the only legal source.

See `../SCORING.md` for how races are ranked and scored.

## What the harness expects

- **Article URLs.** An article URL has the form `BASE/content/BOOK/Title`,
  with underscores for spaces. In the local setup that is, for example,
  `http://kiwix1:8080/content/wikipedia_en_all_nopic/Tiger`. A reported path
  is a list of such URLs, from the start article to the target, both
  included.
- **Path verification.** The harness fetches every page of a reported path
  and checks that each article links to the next one. URLs are compared
  after percent-decoding, so a query string, a fragment or a trailing `/`
  makes no difference. A path that visits an article twice is rejected. A
  rejected path scores a flat -1.0 (see `../SCORING.md`).
- **Timing.** A tournament race lasts 120 seconds and `status/1` is polled
  every 250ms. `start/2` is called with a 15 second timeout, and each
  `status/1` call with a 250ms timeout. Both values are fixed in
  `WikiRacePlatform.Tournament.Server` and `WikiRacePlatform.Race.Instance`.
- **Exactly one crawler module.** The harness finds your crawler by scanning
  the modules loaded on your node for `@behaviour WikiRace.Crawler`. If no
  module declares it, or more than one does, the harness cannot pick your
  crawler and the race does not start. Keep the behaviour on
  `Player.Crawler`, or on the one module that replaces it.
- **Keep `lib/wiki_race/`.** `WikiRace.Crawler`, `WikiRace.Status` and
  `WikiRace.Harness` must ship with your release unchanged. The harness
  reads `WikiRace.Status` structs from your node, and `WikiRace.Harness.report/1`
  runs on your node.

## Shipping your crawler

The platform builds your deliverable from a tagged commit of your GitHub
repository with `MIX_ENV=prod mix release`, with no other command. Check
that this command succeeds on a fresh clone before you tag. Your release
does not connect to the platform by itself. The platform starts it and
connects to it. `bin/connect.exs` is not used on competition day.

## Local iteration

`bin/connect.exs` and the `PLATFORM_NODE`/`ERL_COOKIE`/`NODE_NAME` environment
variables are docker-compose plumbing, not part of the assignment. See the
repo root `RUNNING.md` for how this container is started. Edits to `lib/`
take effect on the next `docker compose restart player1 player2`, since the
source tree is bind-mounted, not baked into the image.
