# Zero-dependency Node 20 runtime (Debian slim for glibc compatibility).
# Alpine (musl) cannot run the Codeium Language Server binary which is
# dynamically linked against glibc.
FROM node:20-slim

WORKDIR /app

# Install CA certificates for TLS verification (needed by the Go-based LS binary).
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && \
    rm -rf /var/lib/apt/lists/*

COPY package.json ./
COPY src ./src
COPY docs ./docs
COPY entrypoint.sh ./
RUN chmod +x /app/entrypoint.sh

ENV PORT=3003
ENV LS_PORT=42100
ENV LOG_LEVEL=info

# Create default runtime state files.
RUN touch /app/accounts.json /app/stats.json /app/runtime-config.json \
          /app/proxy-config.json /app/model-access.json && \
    echo "{}" | tee /app/accounts.json /app/stats.json /app/runtime-config.json \
                     /app/proxy-config.json /app/model-access.json > /dev/null && \
    mkdir -p /app/logs /tmp/windsurf-workspace

EXPOSE 3003

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "const h=require('http');h.get('http://127.0.0.1:3003/health',(r)=>{process.exit(r.statusCode===200?0:1)}).on('error',()=>process.exit(1))" || exit 1

ENTRYPOINT ["/app/entrypoint.sh"]
