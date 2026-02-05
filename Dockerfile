FROM node:20.19-bullseye-slim AS base

# Use a cache mount for apt to speed up the process
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        openssh-client \
        python3 \
        g++ \
        build-essential \
        git \
        poppler-utils \
        poppler-data \
        procps && \
    yarn config set python /usr/bin/python3 && \
    npm install -g node-gyp

RUN npm i -g bun@1.3.1 npm@9.9.3 pnpm@9.15.0 pm2@6.0.10 typescript@4.9.4

# Locale
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8
ENV NX_DAEMON=false
ENV NX_NO_CLOUD=true

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    locales \
    locales-all \
    libcap-dev \
 && rm -rf /var/lib/apt/lists/*

# install isolated-vm globally (required by engine)
RUN cd /usr/src && bun i isolated-vm@5.0.1

RUN pnpm store add @tsconfig/node18@1.0.0
RUN pnpm store add @types/node@18.17.1
RUN pnpm store add typescript@4.9.4

# ======================
# STAGE 1: BUILD
# ======================
FROM base AS build

WORKDIR /usr/src/app

COPY .npmrc package.json bun.lock ./
RUN bun install

COPY . .

# Build frontend
RUN npx nx run-many --target=build --projects=react-ui --skip-nx-cache

# Build backend API
RUN npx nx run-many --target=build --projects=server-api --configuration production --skip-nx-cache

# 🔥 REQUIRED: Build background worker
RUN npx nx run server-worker:build --skip-nx-cache

# Install production deps for API
RUN cd dist/packages/server/api && bun install --production --force

# ======================
# STAGE 2: RUN
# ======================
FROM base AS run

WORKDIR /usr/src/app

# isolate config
COPY packages/server/api/src/assets/default.cf /usr/local/etc/isolate

# nginx + envsubst
RUN apt-get update && apt-get install -y nginx gettext

COPY nginx.react.conf /etc/nginx/nginx.conf

COPY --from=build /usr/src/app/LICENSE .

# Required directories
RUN mkdir -p /usr/src/app/dist/packages/server
RUN mkdir -p /usr/src/app/dist/packages/engine
RUN mkdir -p /usr/src/app/dist/packages/shared

# Copy built artifacts
COPY --from=build /usr/src/app/dist/packages/engine/ /usr/src/app/dist/packages/engine/
COPY --from=build /usr/src/app/dist/packages/server/ /usr/src/app/dist/packages/server/
COPY --from=build /usr/src/app/dist/packages/shared/ /usr/src/app/dist/packages/shared/

# API production deps
RUN cd /usr/src/app/dist/packages/server/api && bun install --production --force

# Needed for runtime assets
COPY --from=build /usr/src/app/packages packages

# Frontend
COPY --from=build /usr/src/app/dist/packages/react-ui /usr/share/nginx/html/

LABEL service=activepieces

COPY docker-entrypoint.sh .
RUN chmod +x docker-entrypoint.sh

ENTRYPOINT ["./docker-entrypoint.sh"]

EXPOSE 80
