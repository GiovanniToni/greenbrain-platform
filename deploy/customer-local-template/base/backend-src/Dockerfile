FROM python:3.11-slim

LABEL org.opencontainers.image.title="GreenBrain Backend" \
      org.opencontainers.image.description="GreenBrain FastAPI backend service" \
      org.opencontainers.image.base.name="python:3.11-slim"

# ── Runtime defaults (non-secret; override via env or docker-compose) ─────────
ENV APP_ENV=production \
    PORT=8000 \
    WORKERS=2 \
    LOG_LEVEL=info \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# ── System deps: only what is strictly needed ─────────────────────────────────
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        gcc \
        libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# ── Non-root user ─────────────────────────────────────────────────────────────
RUN useradd --create-home --shell /bin/sh appuser

WORKDIR /app

# ── Python dependencies (separate layer for cache efficiency) ─────────────────
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r requirements.txt

# ── Application source ────────────────────────────────────────────────────────
COPY app/ ./app/

# ── Entrypoint script ─────────────────────────────────────────────────────────
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# ── Drop to non-root ──────────────────────────────────────────────────────────
USER appuser

EXPOSE 8000

# ── Health check via built-in urllib (no curl needed) ─────────────────────────
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD python -c \
        "import urllib.request, sys; \
         r=urllib.request.urlopen('http://localhost:${PORT:-8000}/health', timeout=8); \
         sys.exit(0 if r.status == 200 else 1)" \
    || exit 1

ENTRYPOINT ["/entrypoint.sh"]
