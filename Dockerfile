FROM node:22-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

# Node-Server: liefert dist/ aus und schickt die Push-Erinnerungen (server/server.ts)
FROM node:22-alpine
RUN apk add --no-cache tzdata
ENV TZ=Europe/Berlin NODE_ENV=production PORT=8080
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev
COPY --from=build /app/dist ./dist
COPY --from=build /app/dist-server ./dist-server
EXPOSE 8080
CMD ["node", "dist-server/server.js"]
