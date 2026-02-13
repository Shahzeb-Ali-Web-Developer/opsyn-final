# ======================================================
# BASE IMAGE
# ======================================================
FROM node:20.19-bullseye-slim AS base

RUN apt-get update && \
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
    && rm -rf /var/lib/apt/lists/*

# Install bun
RUN npm install -g bun@1.3.1

ENV NX_DAEMON=false
ENV NX_NO_CLOUD=true

# ======================================================
# BUILD STAGE
# ======================================================
FROM base AS build

WORKDIR /usr/src/app

# Copy dependency files
COPY package.json bun.lock ./
COPY .npmrc ./

# Install full deps
RUN bun install

# Copy source
COPY . .

# Build all required projects
RUN npx nx run-many --target=build --projects=react-ui --skip-nx-cache
RUN npx nx run-many --target=build --projects=server-api --configuration=production --skip-nx-cache
RUN npx nx run server-worker:build --skip-nx-cache

# ======================================================
# RUN STAGE
# ======================================================
FROM base AS run

WORKDIR /usr/src/app

# Copy node_modules
COPY --from=build /usr/src/app/node_modules ./node_modules

# Copy dist
COPY --from=build /usr/src/app/dist ./dist

# Copy workspace packages
COPY --from=build /usr/src/app/packages ./packages

# Copy frontend
COPY --from=build /usr/src/app/dist/packages/react-ui /usr/share/nginx/html/

# Copy entrypoint
COPY docker-entrypoint.sh .
RUN chmod +x docker-entrypoint.sh

# ======================================================
# 🔥 REAL FIX — link using package.json name
# ======================================================
RUN mkdir -p node_modules/@activepieces && \
    find dist/packages -name package.json | while read pkg; do \
        name=$(node -p "require('./$pkg').name"); \
        target=$(dirname "$pkg"); \
        if echo "$name" | grep -q "@activepieces/"; then \
            short=${name#@activepieces/}; \
            ln -s "/usr/src/app/$target" "node_modules/@activepieces/$short" || true; \
        fi; \
    done

LABEL service=activepieces

EXPOSE 80
ENTRYPOINT ["./docker-entrypoint.sh"]
