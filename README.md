# FileBrowser — Containerized Deployment

[![CI — Build and Test](https://github.com/DynamicKarabo/filebrowser-deployment/actions/workflows/ci.yml/badge.svg)](https://github.com/DynamicKarabo/filebrowser-deployment/actions/workflows/ci.yml)
[![GitHub Stars](https://img.shields.io/badge/dynamic/json?logo=github&label=stars&color=gold&query=stargazers_count&url=https%3A%2F%2Fapi.github.com%2Frepos%2Ffilebrowser%2Ffilebrowser)](https://github.com/filebrowser/filebrowser)

**FileBrowser** — **45k⭐** on GitHub. Web-based file management UI for browsing, uploading, and managing files on a server through a browser interface.

---

## Why This Deployment

The upstream [filebrowser/filebrowser](https://github.com/filebrowser/filebrowser) ships a working Dockerfile with a busybox runtime, but the CI pipeline is basic — no vulnerability scanning, no SBOM generation, no automated push to a container registry with security gates. This repo delivers a **full CI/CD pipeline** that builds, tests, scans, and publishes a hardened image to GHCR, with automated Dependabot updates keeping actions current.

---

## Before: Manual Docker Approach

| Area | The Old Way |
|------|------------|
| **Deploy** | Pull latest image from Docker Hub, hope it works |
| **Security** | No scanning — vulnerabilities discovered post-deploy |
| **Build** | Manual docker build, no reproducibility |
| **Updates** | Manual `docker pull` and restart |
| **SBOM** | None — unknown dependency chain |

## After: Automated Pipeline

```mermaid
git push → GitHub Actions → docker buildx → smoke test → Trivy scan → GHCR push → SBOM
```

Every push to main goes through:

| Step | What it does | Gate |
|------|-------------|------|
| **Build** | Multi-stage build with cache, `CGO_ENABLED=0`, stripped | Build fails → stop |
| **Smoke test** | Container runs, health endpoint returns `{"status":"OK"}` | Health fails → stop |
| **Trivy scan** | Scans for CRITICAL/HIGH CVEs, generates SARIF | Informational (exit 0) |
| **SBOM** | SPDX-format bill of materials via Anchore | Artifact uploaded |
| **Push** | Tags `latest` + commit SHA to GHCR | Image available |
| **Dependabot** | Weekly auto-update for GitHub Actions | PR → CI → auto-merge |

---

## Image Specs

| Property | Value |
|----------|-------|
| **Size** | **47MB** (Alpine slim) |
| **Base image** | `alpine:3.23` (digest-pinned at build time) |
| **Language/version** | Go 1.25 |
| **User** | root (tini init) |
| **HEALTHCHECK** | `wget --spider http://localhost:8080/health` (30s interval) |
| **Build flags** | `CGO_ENABLED=0`, `-trimpath`, `-ldflags="-s -w"`, `osusergo,netgo` tags |
| **Entrypoint** | `/sbin/tini --` (zombie reaping) |
| **Ports** | 8080 (web UI) |

---

## Fires Fought

### Fire 1: `file` command not found in Alpine builder

**Error:**
```
/bin/sh: file: not found
Dockerfile:20
--------------------
  20 | >>> RUN ... && \
  21 | >>>     file /usr/bin/filebrowser && \
```

**Cause:** The `file` utility isn't included in the `golang:1.25-alpine` base image and wasn't added to the `apk add` list. The builder stage only installs `git` and `ca-certificates`.

**Fix:** Removed the `file` command from the builder RUN step. The `ls -lh` line still reports binary size, and the image size is verified in CI.

**Lesson:** Alpine-based images are minimal by design — debug commands like `file` won't be available unless explicitly installed. Always verify which packages are in your builder image before using system utilities.

### Fire 2: SARIF upload fails, cascading to skip GHCR push

**Error:**
```
##[error]Resource not accessible by integration
```

**Cause:** The `github/codeql-action/upload-sarif@v3` step requires `security-events: write` permission on the GITHUB_TOKEN. Our workflow has `contents: read` and `packages: write` only. When this step failed, GitHub Actions skipped all subsequent steps (including Push to GHCR), even though the build and tests passed.

**Fix:** Added `continue-on-error: true` to the Upload Trivy results step. This prevents a SARIF permission error from cascading and killing the image push. SARIF results still upload when permissions allow; the image still ships when they don't.

**Lesson:** Any step that fails in GitHub Actions blocks all downstream steps by default. `continue-on-error: true` is essential for optional/reporting steps that shouldn't gate the pipeline.

### Fire 3: GHCR case-sensitivity on mixed-case org name

**Error:**
```
denied: permission_denied: write_package
```

**Cause:** GitHub Actions uses env var `GHCR_OWNER: DynamicKarabo` (mixed case). Docker images are stored in lower-case paths (`ghcr.io/dynamickarabo/...`), but `docker push ghcr.io/DynamicKarabo/repo` fails because GHCR enforces lower-case paths.

**Fix:** Set `GHCR_OWNER: dynamickarabo` (lowercase) in the workflow env. All image references use `${{ env.GHCR_OWNER }}` consistently across Trivy, push, and smoke-test steps.

**Lesson:** GHCR/OCI registries are case-insensitive on the wire but case-sensitive in API calls. Always lowercase your org name in CI config to avoid hard-to-debug permission errors.

---

## CI/CD Pipeline

```
git push main → GitHub Actions → build (buildx cache) → smoke test → Trivy scan → SBOM → push to GHCR
```

**Total CI time:** ~2m30s (build: 1m40s, Trivy: 30s, push: 20s)
**Image:** `ghcr.io/dynamickarabo/filebrowser-deployment:latest` (47MB, Alpine slim)

[![CI — Build and Test](https://github.com/DynamicKarabo/filebrowser-deployment/actions/workflows/ci.yml/badge.svg)](https://github.com/DynamicKarabo/filebrowser-deployment/actions/workflows/ci.yml)

### Pipeline Gates

| Stage | What fails the build? |
|-------|----------------------|
| Build | Compilation error, missing deps |
| Smoke test | Container crash, health endpoint down |
| Trivy | Informational only (exit 0) — results in SARIF |
| Dependabot | PR CI must pass — auto-merge enabled for patches |

---

## Deployment

### Docker
```bash
docker run -d \
  --name filebrowser \
  -p 8080:8080 \
  -v filebrowser-data:/database \
  -v /path/to/files:/srv \
  ghcr.io/dynamickarabo/filebrowser-deployment:latest
```

### Verify
```bash
curl -s http://localhost:8080/health
# → {"status":"OK"}
```

### Docker Compose
```yaml
services:
  filebrowser:
    image: ghcr.io/dynamickarabo/filebrowser-deployment:latest
    ports:
      - "8080:8080"
    volumes:
      - filebrowser-data:/database
      - /srv:/srv
    healthcheck:
      test: ["CMD", "wget", "--spider", "http://localhost:8080/health"]
      interval: 30s
      timeout: 5s
      retries: 3
```

---

## The Bottom Line

This repo demonstrates a complete CI/CD pipeline around an open-source file management tool — automated builds with Docker layer caching, integrated vulnerability scanning via Trivy, SBOM generation for supply-chain transparency, and automated publishing to GitHub Container Registry. The pipeline catches build failures and container crashes before they reach production, while Dependabot keeps the action ecosystem current. It proves the capability to take any OSS application and wrap it in a production-grade delivery pipeline.
