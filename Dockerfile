FROM node:20.19-bullseye-slim AS base

# ======================================================
# APT stability
# ======================================================
RUN echo 'Acquire::Retries "5";' > /etc/apt/apt.conf.d/80-retries

# ======================================================
# System dependencies
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
# Engine dependency
# ======================================================
RUN cd /usr/src && bun i isolated-vm@5.0.1


# ======================================================
# ================== STAGE 1: BUILD ====================
# ======================================================
FROM base AS build

WORKDIR /usr/src/app

# Copy root dependency files
COPY .npmrc package.json bun.lock ./

# Install full workspace deps (dev + prod)
RUN bun install

# Copy source
COPY . .

# Build frontend
RUN npx nx run-many --target=build --projects=react-ui --skip-nx-cache

# Build API
RUN npx nx run-many --target=build --projects=server-api --configuration=production --skip-nx-cache

# Build Worker
RUN npx nx run server-worker:build --skip-nx-cache


# ======================================================
# ================== STAGE 2: RUN ======================
# ======================================================
FROM base AS run

WORKDIR /usr/src/app

# isolate config
COPY packages/server/api/src/assets/default.cf /usr/local/etc/isolate

# nginx config
COPY nginx.react.conf /etc/nginx/nginx.conf

# License
COPY --from=build /usr/src/app/LICENSE .

# Required directories
RUN mkdir -p \
    /usr/src/app/dist/packages/server \
    /usr/src/app/dist/packages/engine \
    /usr/src/app/dist/packages/shared

# Copy built artifacts
COPY --from=build /usr/src/app/dist/packages/engine/ /usr/src/app/dist/packages/engine/
COPY --from=build /usr/src/app/dist/packages/server/ /usr/src/app/dist/packages/server/
COPY --from=build /usr/src/app/dist/packages/shared/ /usr/src/app/dist/packages/shared/

# Copy workspace packages (needed by worker)
COPY --from=build /usr/src/app/packages packages

# Copy root package.json + lockfile for runtime install
COPY --from=build /usr/src/app/package.json .
COPY --from=build /usr/src/app/bun.lock .

# 🔥 CRITICAL FIX: Install production deps at ROOT
RUN bun install --production --force

# Frontend
COPY --from=build /usr/src/app/dist/packages/react-ui /usr/share/nginx/html/

LABEL service=activepieces

# Entrypoint
COPY docker-entrypoint.sh .
RUN chmod +x docker-entrypoint.sh

ENTRYPOINT ["./docker-entrypoint.sh"]

EXPOSE 80
