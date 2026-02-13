FROM node:20.19-bullseye-slim AS base

RUN echo 'Acquire::Retries "5";' > /etc/apt/apt.conf.d/80-retries

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

RUN npm install -g \
    bun@1.3.1 \
    npm@9.9.3 \
    pnpm@9.15.0 \
    pm2@6.0.10 \
    typescript@4.9.4 \
    node-gyp

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8
ENV NX_DAEMON=false
ENV NX_NO_CLOUD=true

RUN cd /usr/src && bun i isolated-vm@5.0.1


# ================= BUILD STAGE =================

FROM base AS build

WORKDIR /usr/src/app

COPY .npmrc package.json bun.lock ./
RUN bun install

COPY . .

RUN npx nx run-many --target=build --projects=react-ui --skip-nx-cache
RUN npx nx run-many --target=build --projects=server-api --configuration=production --skip-nx-cache
RUN npx nx run server-worker:build --skip-nx-cache


# ================= RUN STAGE =================

FROM base AS run

WORKDIR /usr/src/app

COPY packages/server/api/src/assets/default.cf /usr/local/etc/isolate
COPY nginx.react.conf /etc/nginx/nginx.conf
COPY --from=build /usr/src/app/LICENSE .

RUN mkdir -p \
    /usr/src/app/dist/packages/server \
    /usr/src/app/dist/packages/engine \
    /usr/src/app/dist/packages/shared

# Copy built output
COPY --from=build /usr/src/app/dist/packages/engine/ dist/packages/engine/
COPY --from=build /usr/src/app/dist/packages/server/ dist/packages/server/
COPY --from=build /usr/src/app/dist/packages/shared/ dist/packages/shared/

# Copy workspace packages
COPY --from=build /usr/src/app/packages packages

# ✅ CRITICAL: Copy node_modules from build stage
COPY --from=build /usr/src/app/node_modules node_modules

# Frontend
COPY --from=build /usr/src/app/dist/packages/react-ui /usr/share/nginx/html/

LABEL service=activepieces

COPY docker-entrypoint.sh .
RUN chmod +x docker-entrypoint.sh

ENTRYPOINT ["./docker-entrypoint.sh"]

EXPOSE 80
