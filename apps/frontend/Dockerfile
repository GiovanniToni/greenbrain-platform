# ─────────────────────────────────────────────────────────────────────────────
# Stage 1 — Build
# ─────────────────────────────────────────────────────────────────────────────
FROM node:20-alpine AS builder

WORKDIR /build

# Dependency layer: install before copying source so this layer is cached
# unless package-lock.json changes.
COPY package.json package-lock.json ./
RUN npm ci --frozen-lockfile

# Source
COPY . .

# Production build: Vite outputs to dist/
# componentTagger is already guarded by mode === "development" in vite.config.ts
RUN npm run build

# ─────────────────────────────────────────────────────────────────────────────
# Stage 2 — Serve
# ─────────────────────────────────────────────────────────────────────────────
FROM nginx:1.27-alpine AS runner

LABEL org.opencontainers.image.title="GreenBrain Frontend" \
      org.opencontainers.image.description="GreenBrain React SPA served by nginx"

# BACKEND_HOST is injected into nginx.conf at container start via envsubst.
# Set to the docker-compose service name + port of the backend.
ENV BACKEND_HOST=backend:8000

# Drop default nginx config; template is processed by the nginx docker entrypoint
RUN rm -f /etc/nginx/conf.d/default.conf

COPY --from=builder /build/dist /usr/share/nginx/html
COPY nginx.conf.template /etc/nginx/templates/default.conf.template

EXPOSE 80

# Default nginx image entrypoint runs envsubst on /etc/nginx/templates/*.template
# then execs nginx -g 'daemon off;' — no override needed.
