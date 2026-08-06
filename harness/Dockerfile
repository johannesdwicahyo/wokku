# Self-host image: the harness app + the engine (repo root). Build from
# the REPO ROOT: docker build -f harness/Dockerfile .
# wokkud binary — served by the control plane at /install/wokkud so the
# connect-a-server one-liner works pre-release and air-gapped.
FROM golang:1.26 AS wokkud-builder
WORKDIR /src
COPY wokkud/ .
RUN CGO_ENABLED=0 GOOS=linux go build -o /wokkud-bin .

FROM ruby:3.4-slim AS base
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    build-essential libpq-dev libyaml-dev git curl postgresql-client && \
    rm -rf /var/lib/apt/lists/*
WORKDIR /srv/wokku
COPY . .
COPY --from=wokkud-builder /wokkud-bin /srv/wokku/wokkud-dist/wokkud
WORKDIR /srv/wokku/harness
ENV WOKKUD_BINARY_PATH=/srv/wokku/wokkud-dist/wokkud RAILS_ENV=production RAILS_LOG_TO_STDOUT=1 RAILS_SERVE_STATIC_FILES=1 \
    SOLID_QUEUE_IN_PUMA=1 HARNESS_EAGER_LOAD=1
RUN bundle install --jobs 4
RUN SECRET_KEY_BASE=build-dummy-not-a-real-secret-build-dummy bin/rails tailwindcss:build && \
    SECRET_KEY_BASE=build-dummy-not-a-real-secret-build-dummy bin/rails assets:precompile
EXPOSE 3000
CMD ["sh", "-c", "bin/rails db:prepare db:seed && bundle exec puma -p 3000"]
