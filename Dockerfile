# Zero-dependency Node 20 runtime. The project has no `npm install` step —
# everything lives in `node:*` builtins — so this image is effectively
# Node + source + Language Server binary.
FROM node:20-alpine

WORKDIR /app

# Copy source and entrypoint.
COPY package.json ./
COPY src ./src
COPY docs ./docs
COPY entrypoint.sh ./
RUN chmod +x /app/entrypoint.sh

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

# Create default runtime state files.
RUN touch /app/accounts.json /app/stats.json /app/runtime-config.json \
          /app/proxy-config.json /app/model-access.json && \
    echo '{}' | tee /app/accounts.json /app/stats.json /app/runtime-config.json \
                     /app/proxy-config.json /app/model-access.json > /dev/null && \
    mkdir -p /app/logs /tmp/windsurf-workspace

EXPOSE 3003

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://127.0.0.1:3003/health || exit 1

ENTRYPOINT ["/app/entrypoint.sh"]
