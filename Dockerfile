# Pinned to match /.tool-versions (elixir 1.20.2-otp-28, erlang 28.5).
# Lighter than platform/Dockerfile: no asset pipeline, req+floki only.
FROM hexpm/elixir:1.20.2-erlang-28.5.0.4-debian-bookworm-20260713-slim

RUN apt-get update -q && \
    apt-get install -y --no-install-recommends git ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=dev

COPY mix.exs mix.lock ./
RUN mix deps.get

COPY . .
RUN mix compile

# Source is bind-mounted over this at runtime, so a crawler pasted into
# lib/ on the host takes effect on the next container restart.
CMD ["sh", "-c", "elixir --sname ${NODE_NAME:?} --cookie ${ERL_COOKIE:?} -S mix run --no-halt bin/connect.exs"]
