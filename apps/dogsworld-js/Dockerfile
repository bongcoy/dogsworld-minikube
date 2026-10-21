FROM node:20-slim
WORKDIR /app

# Tracer Datadog TIDAK dipasang di image ini.
# Di Kubernetes, tracer disuntikkan otomatis oleh Single Step Instrumentation (SSI).

COPY package.json ./
RUN npm install --omit=dev
COPY src ./src

ENV PORT=8080
EXPOSE 8080
USER node
CMD ["node", "src/server.js"]
