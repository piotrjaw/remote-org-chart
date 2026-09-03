FROM node:22-bookworm-slim AS frontend

WORKDIR /app/assets
COPY assets/package.json assets/package-lock.json ./
RUN npm ci
COPY assets/ ./
RUN npm run build

FROM hexpm/elixir:1.18.5-erlang-27.3.4.17-debian-bookworm-20260824-slim AS builder

RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential git \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app
RUN mix local.hex --force \
  && mix local.rebar --force

ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod

COPY config/config.exs config/prod.exs config/
RUN mix deps.compile

COPY lib/ lib/
COPY config/runtime.exs config/runtime.exs
RUN mix compile

COPY --from=frontend /app/priv/static/ priv/static/
RUN mix phx.digest \
  && mix release

FROM debian:bookworm-slim AS runner

RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates libstdc++6 openssl libncurses6 \
  && rm -rf /var/lib/apt/lists/* \
  && useradd --system --uid 10001 --create-home app

WORKDIR /app
ENV LANG=C.UTF-8

COPY --from=builder --chown=app:app /app/_build/prod/rel/remote_org_chart ./

USER app
EXPOSE 4000

CMD ["/app/bin/remote_org_chart", "start"]
