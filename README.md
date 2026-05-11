# FileBrowser — Production Deployment Pipeline

> Multi-stage Docker build, CI/CD with security scanning, healthcheck, and automated deployment.

## Before & After

| Metric | Before (Official Dockerfile) | After (This Pipeline) |
|--------|-----------------------------|-----------------------|
| Base image | `busybox:1.37.0-musl` + `alpine:3.23` | `alpine:3.23` (single-stage runtime) |
| Build stages | 2 | 3 (frontend → Go → runtime) |
| Image size | ~85MB | ~25MB |
| Security scanning | None | Trivy (CRITICAL/HIGH blocks build) |
| SBOM generation | None | SPDX JSON per build |
| Healthcheck | Shell script | Built-in wget |
| Init system | tini | tini |

## Pipeline

```
[Push/PR] → Docker build → Smoke test → Trivy scan → SBOM → GHCR push → Done
```

## Quick Start

```bash
docker compose up -d
```

Or pull from GHCR:

```bash
docker pull ghcr.io/dynamickarabo/filebrowser-deployment:latest
docker run -d -p 8080:8080 \
  -v filebrowser-data:/srv \
  -v filebrowser-config:/database \
  ghcr.io/dynamickarabo/filebrowser-deployment:latest
```

## Tech Stack

- **Runtime:** Alpine 3.23
- **Language:** Go 1.25
- **Frontend:** Vue 3 + Vite
- **CI/CD:** GitHub Actions
- **Security:** Trivy, SBOM (SPDX)
- **Registry:** GitHub Container Registry (GHCR)

## Troubleshooting

**Healthcheck failing on first run?** Give it 10s for the start period.

**Port conflict?** Change `8081:8080` in docker-compose.yml to your desired port.
