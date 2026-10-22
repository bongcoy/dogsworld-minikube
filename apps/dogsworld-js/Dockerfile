# Stage 1: install dependency di arsitektur mesin pembuat (tanpa emulasi). Semua paket murni JavaScript.
FROM --platform=$BUILDPLATFORM node:20-slim AS deps
WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev

# Stage 2: image akhir (multi-arch)
FROM node:20-slim
WORKDIR /app

# Tracer Datadog TIDAK dipasang di image ini.
# Di Kubernetes, tracer disuntikkan otomatis oleh Single Step Instrumentation (SSI).

COPY --from=deps /app/node_modules ./node_modules
COPY package.json ./
COPY src ./src

ENV PORT=8080
EXPOSE 8080
USER node
CMD ["node", "src/server.js"]
