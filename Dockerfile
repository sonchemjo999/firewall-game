FROM node:18-alpine

LABEL maintainer="NRO Shield"
LABEL description="NRO Shield Backend API"

WORKDIR /app

RUN apk add --no-cache \
    bash \
    curl \
    net-tools \
    procps \
    mariadb-client

COPY backend/package*.json ./backend/
RUN cd backend && npm install --omit=dev

COPY backend/ ./backend/
COPY web/ ./web/
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 5000

ENV NODE_ENV=production
ENV API_PORT=5000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://127.0.0.1:5000/api/system/health || exit 1

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
