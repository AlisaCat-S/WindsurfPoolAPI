# Zero-dependency Node 20 runtime.
FROM node:20-alpine

WORKDIR /app

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
    echo '{}' | tee /app/accounts.json /app/stats.json /app/runtime-config.json \
                     /app/proxy-config.json /app/model-access.json > /dev/null && \
    mkdir -p /app/logs /tmp/windsurf-workspace

EXPOSE 3003

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://127.0.0.1:3003/health || exit 1

ENTRYPOINT ["/app/entrypoint.sh"]
