# Ohne Vorgabewert: BuildKit setzt TARGETARCH je Plattform. Ein Default (=amd64) würde das überschreiben.
ARG TARGETARCH

# Build und Abhängigkeiten laufen auf der Plattform des Runners (kein Emulator beim ARM-Build).
# Geht, weil alles reines JavaScript ist (web-push hat keine nativen Module).
FROM --platform=$BUILDPLATFORM node:22-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM --platform=$BUILDPLATFORM node:22-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

# Node-Server: liefert dist/ aus und schickt die Push-Erinnerungen (server/server.ts)
FROM node:22-alpine AS runtime
RUN apk add --no-cache tzdata
ENV TZ=Europe/Berlin NODE_ENV=production PORT=8080
WORKDIR /app
COPY package.json ./
COPY --from=deps /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY --from=build /app/dist-server ./dist-server
COPY start.sh ./
EXPOSE 8080
CMD ["sh", "/app/start.sh"]

# Home-Assistant-Labels je Architektur
FROM runtime AS runtime-amd64
LABEL io.hass.arch="amd64"
FROM runtime AS runtime-arm64
LABEL io.hass.arch="aarch64"

FROM runtime-${TARGETARCH}
ARG HA_VERSION=dev
LABEL io.hass.type="addon" io.hass.version="${HA_VERSION}"
