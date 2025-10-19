#!/bin/bash
set -euxo pipefail

IMAGE_REPO="${IMAGE_REPO}"
IMAGE_TAG="${IMAGE_TAG}"
HTTP_PORT="${HTTP_PORT}"
APP_PORT="${APP_PORT}"
NAME="${NAME}"

dnf update -y
dnf install -y docker git
systemctl enable --now docker

dnf install -y amazon-ssm-agent || true
systemctl enable --now amazon-ssm-agent

mkdir -p /usr/lib/docker/cli-plugins
curl -sSL "https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-x86_64" \
  -o /usr/lib/docker/cli-plugins/docker-compose
chmod +x /usr/lib/docker/cli-plugins/docker-compose

docker pull "${IMAGE_REPO}:${IMAGE_TAG}" || true

cat >/opt/docker-compose.yml <<YAML
version: "3.9"
services:
  app:
    image: ${IMAGE_REPO}:${IMAGE_TAG}
    container_name: ${NAME}
    environment:
      - NODE_ENV=production
      - SERVE_BUILD=true
      - PORT=${APP_PORT}
    ports:
      - "${HTTP_PORT}:${APP_PORT}"
    restart: unless-stopped
YAML

docker compose -f /opt/docker-compose.yml up -d
