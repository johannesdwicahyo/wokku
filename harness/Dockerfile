# Self-host image: the harness app + the engine (repo root). Build from
# the REPO ROOT: docker build -f harness/Dockerfile .
# Published prebuilt as ghcr.io/johannesdwicahyo/wokku (bin/release-image);
# install.sh pulls it instead of building on the user's server.

# wokkud binary — served by the control plane at /install/wokkud so the
# connect-a-server one-liner works pre-release and air-gapped.
FROM golang:1.26 AS wokkud-builder
WORKDIR /src
COPY wokkud/ .
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /wokkud-bin .

# Gems + assets need compilers; none of that ships in the final image.
FROM ruby:3.4-slim AS build
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    build-essential libpq-dev libyaml-dev git && \
    rm -rf /var/lib/apt/lists/*
WORKDIR /srv/wokku
COPY . .
# Test suites never run in the image. (wokkud/ stays: the app reads its
# deploy units from the engine root at runtime.)
RUN rm -rf spec harness/spec
WORKDIR /srv/wokku/harness
ENV RAILS_ENV=production BUNDLE_DEPLOYMENT=1
RUN bundle install --jobs 4 && rm -rf /usr/local/bundle/cache
RUN SECRET_KEY_BASE=build-dummy-not-a-real-secret-build-dummy bin/rails tailwindcss:build && \
    SECRET_KEY_BASE=build-dummy-not-a-real-secret-build-dummy bin/rails assets:precompile && \
    rm -rf tmp/cache

FROM ruby:3.4-slim
ARG WOKKU_VERSION=dev
LABEL org.opencontainers.image.source="https://github.com/johannesdwicahyo/wokku" \
      org.opencontainers.image.title="wokku" \
      org.opencontainers.image.description="Wokku self-host control plane with the wokkud agent binary" \
      org.opencontainers.image.licenses="AGPL-3.0-only" \
      org.opencontainers.image.version="${WOKKU_VERSION}"
# Runtime libraries only (git/curl/psql are used by the app at runtime).
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    libpq5 libyaml-0-2 git curl postgresql-client ca-certificates && \
    rm -rf /var/lib/apt/lists/*
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /srv/wokku /srv/wokku
COPY --from=wokkud-builder /wokkud-bin /srv/wokku/wokkud-dist/wokkud
WORKDIR /srv/wokku/harness
# tmp/ and log/ are excluded from the build context; puma needs them.
RUN mkdir -p tmp/pids log
ENV WOKKUD_BINARY_PATH=/srv/wokku/wokkud-dist/wokkud RAILS_ENV=production RAILS_LOG_TO_STDOUT=1 RAILS_SERVE_STATIC_FILES=1 \
    SOLID_QUEUE_IN_PUMA=1 HARNESS_EAGER_LOAD=1 BUNDLE_DEPLOYMENT=1 WOKKU_VERSION=${WOKKU_VERSION}
EXPOSE 3000
CMD ["sh", "-c", "bin/rails db:prepare db:seed && bundle exec puma -p 3000"]
