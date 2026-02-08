FROM node:20.19-bullseye-slim AS base

# ----------------------
# System dependencies
# ----------------------
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
        procps \
        locales \
        locales-all \
        libcap-dev \
        nginx \
        gettext \
    && rm -rf /var/lib/apt/lists/*

# ----------------------
# Tooling
# ----------------------
RUN npm install -g \
    bun@1.3.1 \
    npm@9.9.3 \
    pnpm@9.15.0 \
    pm2@6.0.10 \
    typescript@4.9.4 \
    node-gyp

# ----------------------
# Environment
# ----------------------
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8
ENV NX_DAEMON=false
ENV NX_NO_CLOUD=true

# ----------------------
# Engine dependency
# ----------------------
RUN cd /usr/src && bun i isolated-vm@5.0.1

RUN pnpm store add @tsconfig/node18@1.0.0
RUN pnpm store add @types/node@18.17.1
RUN pnpm store add typescript@4.9.4

# ======================================================
# STAGE 1: BUILD
# ======================================================
FROM base AS build

WORKDIR /usr/src/app

# Install root deps
COPY .npmrc package.json bun.lock ./
RUN bun install

# Copy source
COPY . .

# ----------------------
# Build projects
# ----------------------
RUN npx nx run-many --target=build --projects=react-ui --skip-nx-cache
RUN npx nx run-many --target=build --projects=server-api --configuration production --skip-nx-cache
RUN npx nx run server-worker:build --skip-nx-cache

# ----------------------
# Install PROD deps (CRITICAL)
# ----------------------
RUN cd dist/packages/server/api && bun install --production --force

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

# Create required dirs
RUN mkdir -p /usr/src/app/dist/packages/server \
    && mkdir -p /usr/src/app/dist/packages/engine \
    && mkdir -p /usr/src/app/dist/packages/shared

# ----------------------
# Copy built artifacts
# ----------------------
COPY --from=build /usr/src/app/dist/packages/engine/ /usr/src/app/dist/packages/engine/
COPY --from=build /usr/src/app/dist/packages/server/ /usr/src/app/dist/packages/server/
COPY --from=build /usr/src/app/dist/packages/shared/ /usr/src/app/dist/packages/shared/

# ----------------------
# Runtime dependencies (API + WORKER)
# ----------------------
RUN cd /usr/src/app/dist/packages/server/api && bun install --production --force
RUN cd /usr/src/app/dist/packages/server/worker && bun install --production --force

# Runtime assets
COPY --from=build /usr/src/app/packages packages

# Frontend
COPY --from=build /usr/src/app/dist/packages/react-ui /usr/share/nginx/html/

LABEL service=activepieces

# Entrypoint
COPY docker-entrypoint.sh .
RUN chmod +x docker-entrypoint.sh

ENTRYPOINT ["./docker-entrypoint.sh"]

EXPOSE 80
