#!/usr/bin/env bash
# DemoVersion – EC2 bootstrap
# - Installs Docker + Compose v2 plugin
# - (Optionally) installs SSM agent on AL2023
# - Pulls ${IMAGE_REPO}:${IMAGE_TAG} and runs container as demo-version-app
# - Exposes container 4000 on host port 80 
# - SERVE_BUILD=true tells the Node API to serve the React build from /build

# Inputs provided by Terraform templatefile():
#   IMAGE_REPO, IMAGE_TAG, HTTP_PORT (80), APP_PORT (4000), NAME

set -euxo pipefail
# log everything so you can debug later
exec > >(tee -a /var/log/user-data.log) 2>&1

# -------- vars from Terraform templatefile() --------
IMAGE_REPO="${IMAGE_REPO}"
IMAGE_TAG="${IMAGE_TAG}"
HTTP_PORT="${HTTP_PORT}"
APP_PORT="${APP_PORT}"
NAME="${NAME}"

# -------- system prep --------
# NOTE: do NOT install "curl" (conflicts with curl-minimal on AL2023)
# Use --allowerasing to resolve any repo-version conflicts cleanly
dnf install -y --allowerasing docker git jq amazon-ssm-agent amazon-cloudwatch-agent

# services
systemctl enable --now amazon-ssm-agent
systemctl enable --now docker

# docker compose v2 (plugin)
# AL2023 ships docker without compose; install plugin via GitHub release
mkdir -p /usr/libexec/docker/cli-plugins
curl -fsSL "https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-x86_64" \
  -o /usr/libexec/docker/cli-plugins/docker-compose
chmod +x /usr/libexec/docker/cli-plugins/docker-compose
# (compat path some distros use)
mkdir -p /usr/lib/docker/cli-plugins || true
ln -sf /usr/libexec/docker/cli-plugins/docker-compose /usr/lib/docker/cli-plugins/docker-compose || true

# -------- CloudWatch Agent: scrape Prometheus metrics from our app --------
cat >/opt/cwagent.json <<'JSON'
{
  "agent": { "metrics_collection_interval": 60 },
  "metrics": {
    "namespace": "CWAgent",
    "append_dimensions": { "InstanceId": "$${aws:InstanceId}" },
    "metrics_collected": {
      "prometheus": {
        "emf_processor": {
          "metric_declaration": [
            {
              "source_labels": ["job"],
              "label_matcher": "node-app",
              "dimensions": [["job","InstanceId"]],
              "metric_selectors": [
                "process_cpu_seconds_total",
                "process_resident_memory_bytes"
              ]
            }
          ]
        },
        "prometheus_config": {
          "scrape_configs": [
            {
              "job_name": "node-app",
              "static_configs": [
                { "targets": ["localhost:80"], "labels": { "job": "node-app" } }
              ]
            }
          ]
        }
      }
    }
  }
}
JSON

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -c file:/opt/cwagent.json -s || true
systemctl enable --now amazon-cloudwatch-agent || true

# -------- app compose --------
cat >/opt/docker-compose.yml <<YAML
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
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://localhost:${APP_PORT}/api/ping >/dev/null 2>&1 || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 5
YAML

docker compose -f /opt/docker-compose.yml up -d

echo "user-data completed at $(date -Is)" > /var/log/user-data.done
