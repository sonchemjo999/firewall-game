FROM node:18-alpine

LABEL maintainer="NRO Shield"
LABEL description="NRO Shield - DDoS Protection System"

WORKDIR /app

RUN apk add --no-cache \
    bash \
    curl \
    iptables \
    ipset \
    iproute2 \
    python3 \
    py3-pip \
    net-tools \
    procps

COPY backend/package*.json ./backend/
RUN cd backend && npm install --omit=dev

COPY backend/ ./backend/
COPY firewall/ ./firewall/
COPY web/ ./web/

RUN chmod +x ./firewall/*.sh

EXPOSE 5000 8000

ENV NODE_ENV=production
ENV API_PORT=5000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:5000/api/system/health || exit 1

CMD ["node", "backend/server.js"]
