# syntax=docker/dockerfile:1.4

# ---- Build stage ----
FROM node:22-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .

RUN npm run build

# ---- Runtime stage ----
FROM node:22-alpine
WORKDIR /app
RUN npm i -g serve
COPY --from=build /app/dist ./dist

# Run as non-root user
RUN chown -R node:node /app
USER node

EXPOSE 3000
CMD ["serve", "-s", "dist", "-l", "3000"]
