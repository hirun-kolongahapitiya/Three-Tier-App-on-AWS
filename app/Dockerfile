# --- Build stage ---
FROM node:20-alpine AS build
WORKDIR /app

# Install only prod deps for the runtime image
COPY package*.json ./
RUN npm ci --omit=dev

# --- Runtime stage ---
FROM node:20-alpine AS runtime
WORKDIR /app

# Install dumb-init for proper signal handling (PID 1 problem)
RUN apk add --no-cache dumb-init && \
    addgroup -S app && adduser -S app -G app

COPY --from=build /app/node_modules ./node_modules
COPY --chown=app:app src ./src
COPY --chown=app:app package*.json ./

USER app
EXPOSE 3000

# Healthcheck used by ECS
HEALTHCHECK --interval=30s --timeout=5s --retries=3 --start-period=15s \
  CMD wget --quiet --tries=1 --spider http://localhost:3000/healthz || exit 1

ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "src/index.js"]
