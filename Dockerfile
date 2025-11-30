ARG REGISTRY=docker.io

FROM ${REGISTRY}/python:3.13-slim-bookworm AS python
FROM ${REGISTRY}/node:22-bookworm-slim AS node

FROM ${REGISTRY}/buildpack-deps:bookworm AS base

COPY --from=python /usr/local/ /usr/local/
COPY --from=node /usr/local/ /usr/local/
COPY --from=node /opt/ /opt/

# Add app user/group! Clean packages and fix links! Check version! And install some extra packages!
RUN set -ex \
	&& groupadd -r app --gid=999 \
	&& useradd --system --create-home --home /app --gid 999 --uid=999 --shell /bin/bash app \
	&& rm -f /usr/local/bin/docker-entrypoint.sh \
	&& python --version \
	&& pip --version \
	&& node --version \
	&& yarn --version \
	&& python3 -m pip install 'psycopg2-binary==2.9.10' && python3 -m pip install 'Django==5.2' \
    && echo "OK"

# Builder - combines install and build in one stage for simplicity
FROM base AS builder

ARG TURBO_TEAM
ARG TURBO_TOKEN
ARG TURBO_API
ARG TURBO_REMOTE_ONLY=false

WORKDIR /app

# Copy everything
COPY --chown=app:app . /app

ENV TURBO_TEAM=$TURBO_TEAM
ENV TURBO_TOKEN=$TURBO_TOKEN
ENV TURBO_API=$TURBO_API
ENV TURBO_REMOTE_ONLY=$TURBO_REMOTE_ONLY

# Create build-time .env
RUN echo "# Build time .env config!" >> /app/.env && \
	echo "COOKIE_SECRET=undefined" >> /app/.env && \
	echo "DATABASE_URL=undefined" >> /app/.env && \
	echo "REDIS_URL=undefined" >> /app/.env && \
	echo "FILE_FIELD_ADAPTER=local" >> /app/.env && \
	echo "NEXT_TELEMETRY_DISABLED=1" >> /app/.env && \
	echo "NODE_ENV=production" >> /app/.env

# Install dependencies
RUN yarn install --inline-builds

# Make scripts executable
RUN chmod +x ./bin/run_condo_domain_tests.sh || true

# Build the application
RUN set -ex \
    && yarn build \
    && rm -rf /app/.env  \
    && rm -rf /app/.config /app/.cache /app/.docker  \
    && ls -lah /app/

# Runtime container
FROM base
USER app:app
WORKDIR /app
COPY --from=builder --chown=app:app /app /app

# Default command - can be overridden
CMD ["yarn", "start"]
