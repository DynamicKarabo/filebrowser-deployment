# =============================================================================
# FileBrowser — Multi-stage Docker Build
# Target: Alpine slim image (~25MB)
# =============================================================================

# Stage 1: Build frontend
FROM node:24-alpine AS frontend
WORKDIR /src
COPY src/frontend/package.json src/frontend/pnpm-lock.yaml ./
RUN corepack enable && pnpm install --frozen-lockfile
COPY src/frontend/ .
RUN pnpm build

# Stage 2: Build Go binary
FROM golang:1.25-alpine AS builder
RUN apk add --no-cache git ca-certificates
WORKDIR /src
COPY src/ .
COPY --from=frontend /src/dist /src/frontend/dist
RUN CGO_ENABLED=0 go build \
    -trimpath \
    -tags "osusergo,netgo" \
    -ldflags="-s -w -X github.com/filebrowser/filebrowser/v2/version.CommitSHA=$(git rev-parse --short HEAD 2>/dev/null || echo 'dev') -X github.com/filebrowser/filebrowser/v2/version.Version=$(git describe --tags 2>/dev/null || echo 'latest')" \
    -o /usr/bin/filebrowser . && \
    file /usr/bin/filebrowser && \
    echo "Binary size:" && ls -lh /usr/bin/filebrowser

# Stage 3: Runtime — Alpine slim
FROM alpine:3.23

RUN apk add --no-cache ca-certificates tini wget

LABEL org.opencontainers.image.title="FileBrowser — file management UI"
LABEL org.opencontainers.image.description="FileBrowser provides a file managing interface within a specified directory"
LABEL org.opencontainers.image.source="https://github.com/DynamicKarabo/filebrowser-deployment"
LABEL org.opencontainers.image.authors="Karabo Oliphant"

ENV FB_PORT=8080
ENV FB_ADDRESS=0.0.0.0
ENV FB_ROOT=/srv
ENV FB_DATABASE=/database/filebrowser.db

WORKDIR /app

COPY --from=builder /usr/bin/filebrowser /usr/bin/filebrowser
COPY --from=builder /etc/ssl/certs /etc/ssl/certs

EXPOSE ${FB_PORT}

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:${FB_PORT:-8080}/health || exit 1

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/usr/bin/filebrowser", "--port=8080", "--address=0.0.0.0", "--root=/srv", "--database=/database/filebrowser.db"]
