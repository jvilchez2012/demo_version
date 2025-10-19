# -------- build stage --------
FROM node:20-alpine AS build
WORKDIR /app

# Tools for git-based deps & native addons
RUN apk add --no-cache git openssh-client ca-certificates python3 make g++ libc6-compat \
  && git config --global url."https://github.com/".insteadOf "git@github.com:" \
  && git config --global url."https://".insteadOf "git://"

# Copy manifests exactly
COPY ./package.json /app/package.json
COPY ./package-lock.json /app/package-lock.json

# Install deps 
RUN npm ci || npm install

# Bring in the rest and build the frontend
COPY . .
ARG BUILD_SHA=dev
ARG BUILD_TIME=unknown
ENV REACT_APP_BUILD_SHA=$BUILD_SHA
ENV REACT_APP_BUILD_TIME=$BUILD_TIME
RUN npm run build

# Prune dev deps HERE 
RUN npm prune --omit=dev

# -------- runtime stage --------
FROM node:20-alpine
WORKDIR /app

ENV NODE_ENV=production
ENV SERVE_BUILD=true
ENV PORT=4000

# Copy only what's needed at runtime
COPY --from=build /app/package.json ./package.json
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/server       ./server
COPY --from=build /app/build        ./build

EXPOSE 4000


HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:4000/api/ping >/dev/null 2>&1 || exit 1

CMD ["node","server/server.local.js"]
