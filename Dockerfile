FROM node:20.19-bullseye-slim AS base

# ======================================================
# APT stability (VERY IMPORTANT)
# ======================================================
RUN echo 'Acquire::Retries "5";' > /etc/apt/apt.conf.d/80-retries

# ======================================================
# System dependencies (NO locales-all)
# ======================================================
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        openssh-client \
        procps \
        python3 \
        build-essential \
        g++ \
        libcap-dev \
        poppler-utils \
        poppler-data \
        nginx \
        gettext \
        locales \
    && rm -rf /var/lib/apt/lists/*

# ======================================================
# Tooling
# ======================================================
RUN npm install -g \
    bun@1.3.1 \
    npm@9.9.3 \
    pnpm@9.15.0 \
    pm2@6.0.10 \
    typescript@4.9.4 \
    node-gyp

# ======================================================
# Environment
# ======================================================
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8
ENV NX_DAEMON=false
ENV NX_NO_CLOUD=true

# ======================================================
# Engine dependency (isolated-vm)
# ======================================================
RUN cd /usr/src && bun i isolated-vm@5.0.1

# Required TS runtime deps (FIXES tslib crash)
RUN bun add -g tslib@2.6.2

# ======================================================
# STAGE 1: BUILD
# ======================================================
FROM base AS build

WORKDIR /usr/src/app

# Root deps
COPY .npmrc package.json bun.lock ./
RUN bun install

# Source
COPY . .

# ======================================================
# Build projects
# ======================================================
RUN npx nx run-many --target=build --projects=react-ui --skip-nx-cache
RUN npx nx run-many --target=build --projects=server-api --configuration=production --skip-nx-cache
RUN npx nx run server-worker:build --skip-nx-cache

# ======================================================
# PROD deps (API ONLY)
# ======================================================
RUN cd dist/packages/server/api && bun install --production --force

# ❌ DO NOT install worker prod deps
# Worker depends on workspace packages that are NOT published

# ======================================================
# STAGE 2: RUN
# ======================================================
FROM base AS run

WORKDIR /usr/src/app

# isolate config
COPY packages/server/api/src/assets/default.cf /usr/local/etc/isolate

# nginx config
COPY nginx.react.conf /etc/nginx/nginx.conf

# License
COPY --from=build /usr/src/app/LICENSE .

# Required dirs
RUN mkdir -p \
    /usr/src/app/dist/packages/server \
    /usr/src/app/dist/packages/engine \
    /usr/src/app/dist/packages/shared

# ======================================================
# Copy built artifacts
# ======================================================
COPY --from=build /usr/src/app/dist/packages/engine/ /usr/src/app/dist/packages/engine/
COPY --from=build /usr/src/app/dist/packages/server/ /usr/src/app/dist/packages/server/
COPY --from=build /usr/src/app/dist/packages/shared/ /usr/src/app/dist/packages/shared/

# ======================================================
# Runtime deps (API ONLY)
# ======================================================
RUN cd /usr/src/app/dist/packages/server/api && bun install --production --force

# Workspace packages (needed by worker at runtime)
COPY --from=build /usr/src/app/packages packages

# Frontend
COPY --from=build /usr/src/app/dist/packages/react-ui /usr/share/nginx/html/

LABEL service=activepieces

# Entrypoint
COPY docker-entrypoint.sh .
RUN chmod +x docker-entrypoint.sh

ENTRYPOINT ["./docker-entrypoint.sh"]

EXPOSE 80
