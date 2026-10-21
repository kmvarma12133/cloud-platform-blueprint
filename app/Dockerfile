# syntax=docker/dockerfile:1.7
# Multi-stage build: dependencies are compiled in a builder stage and only the
# virtualenv is copied into a slim, non-root runtime image.

# Base image pinned by digest (Dependabot proposes updates), so a rebuild of
# the same commit uses exactly the same OS and Python layers.
FROM python:3.14.7-slim-trixie@sha256:51dafde81dbdb6ebde285137a295cf18a47ca95234fe388a343719cb97305b3d AS builder
ENV PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1
WORKDIR /build
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
COPY requirements.txt .
RUN pip install -r requirements.txt

FROM python:3.14.7-slim-trixie@sha256:51dafde81dbdb6ebde285137a295cf18a47ca95234fe388a343719cb97305b3d AS runtime
ARG VERSION=0.0.0-dev
LABEL org.opencontainers.image.title="orders-api" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.source="https://github.com/Kmvarma12133/cloud-platform-blueprint"
ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    SERVICE_VERSION=${VERSION}
RUN groupadd --system --gid 10001 app && useradd --system --uid 10001 --gid app --no-create-home app
WORKDIR /srv
COPY --from=builder /opt/venv /opt/venv
COPY --chown=app:app src/ ./
USER 10001
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8080/healthz').status==200 else 1)"
CMD ["uvicorn", "orders_api.main:app", "--host", "0.0.0.0", "--port", "8080", "--proxy-headers"]
