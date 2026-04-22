# Zero-dependency Node 20 runtime. The project has no `npm install` step —
# everything lives in `node:*` builtins — so this image is effectively
# Node + source + Language Server binary.
FROM node:20-alpine AS base

# Non-root user for the app
RUN addgroup -S app && adduser -S app -G app

WORKDIR /app

# Copy source. `.dockerignore` keeps runtime artefacts (accounts.json, .env,
# stats.json, data/, logs/) out even if they exist in the build context.
COPY --chown=app:app package.json ./
COPY --chown=app:app src ./src
COPY --chown=app:app docs ./docs

# ── Download Language Server binary from Exafunction/codeium ──
# TARGETARCH is automatically set by Docker buildx (amd64 / arm64).
ARG TARGETARCH
RUN set -eux; \
    case "${TARGETARCH}" in \
      amd64) ASSET="language_server_linux_x64" ;; \
      arm64) ASSET="language_server_linux_arm" ;; \
      *)     echo "Unsupported arch: ${TARGETARCH}"; exit 1 ;; \
    esac; \
    mkdir -p /opt/windsurf; \
    # Fetch latest release download URL from GitHub API
    RELEASE_URL=$(wget -qO- https://api.github.com/repos/Exafunction/codeium/releases/latest \
      | grep -oE "https://[^\"]+/${ASSET}" | head -1); \
    if [ -z "$RELEASE_URL" ]; then echo "Failed to find asset $ASSET"; exit 1; fi; \
    echo "Downloading $ASSET from $RELEASE_URL ..."; \
    wget -q -O "/opt/windsurf/${ASSET}" "$RELEASE_URL"; \
    chmod +x "/opt/windsurf/${ASSET}"; \
    ls -lh /opt/windsurf/

ENV PORT=3003
ENV LS_PORT=42100
ENV LOG_LEVEL=info
# LS_BINARY_PATH is auto-detected by src/config.js based on process.arch.
# No need to set it explicitly.

# Writable locations for runtime state
RUN mkdir -p /app/logs /tmp/windsurf-workspace \
    && chown -R app:app /app /tmp/windsurf-workspace

USER app

EXPOSE 3003

# Simple healthcheck — /health is served by the HTTP server even when the
# account pool is empty.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://127.0.0.1:3003/health || exit 1

CMD ["node", "src/index.js"]
