# Demo Version – DevOps Test by Jonathan Vilchez

A small React + Node app packaged in a single container and deployed to EC2 with Terraform and a GitHub Actions pipeline. Metrics are scraped  via Prometheus + Grafana.

---

## Table of Contents
- [Fixes Applied](#fixes-applied)
- [Run Locally](#run-locally)
- [Container Build](#container-build)
- [Infrastructure (Terraform)](#infrastructure-terraform)
- [CI/CD (GitHub Actions)](#cicd-github-actions)
- [Metrics (Prometheus + Grafana)](#metrics-prometheus--grafana)
- [Lambda (AWS CLI Task Proof)](#lambda-aws-cli-task-proof)
- [Health Checks](#health-checks)
- [Rollback](#rollback)


---

##  Fixes Applied

**1) Bad dotenv path**  
`server/app.js` loaded `.env` from a non-existent folder.  
✅ Use a real path (either the server folder or repo root):
```js
// server/app.js
require("dotenv").config({ path: "server/config/config.env" });
// or simply: require("dotenv").config();
```

**2) Static build path incorrect (production)**  
Prod served `frontend/build`; CRA outputs to `/build` at repo root.  
✅ Serve the correct folder:
```js
// server/app.js
const path = require("path");
const buildPath = path.resolve(__dirname, "../build");
app.use(express.static(buildPath));
app.get("*", (_req, res) => res.sendFile(path.join(buildPath, "index.html")));
```

**3) Database connection disabled**  
`connectDatabase()` was commented out.  
✅ Re-enable and use `MONGO_URI` from env (for local/dev you can add a Mongo sidecar).

**4) Dangerous npm hook**  
`"prepare": "npm start"` auto-runs on install → breaks CI/Docker.  
✅ Remove the `prepare` script from `package.json`.

**5) Duplicate `index.html`**  
Both `/index.html` and `/public/index.html` existed; CRA uses `/public/index.html`.  
✅ Remove the top-level `/index.html`.

**6) Tailwind config module type**  
ESM config without `"type":"module"` caused loader issues.  
✅ Keep Tailwind config in CJS:
```js
// tailwind.config.js
module.exports = {
  // ...existing content
};
```

**7) `.gitignore` not CRA-aligned**  
Didn’t ignore the production build.  
✅ Add:
```
build/
```

With those 7 fixes, local dev and prod serving via Express both work reliably.

---

## Run Locally

### Option A: Node (DEV)
```bash
# install deps
npm install

# run dev (adjust to your scripts)
npm run start        # or: npm run start:dev

# health
curl http://localhost:4000/api/ping
```

### Option B: Docker (single container, prod-like)
```bash
# build & run
docker build -t demo_version:local .
docker run -d --name demo-version-app   -e NODE_ENV=production -e SERVE_BUILD=true -e PORT=4000   -p 4000:4000 demo_version:local

# test
curl http://localhost:4000/api/ping
open http://localhost:4000/
```

---

## Container Build

Single multi-stage Dockerfile builds the React app and ships the Node API + static build.  
The app listens on **4000** internally; infra maps **host 80 → container 4000** in EC2.

```bash
# local build
docker build -t demo_version:local .

# local run
docker run -d --name demo-version-app   -e NODE_ENV=production -e SERVE_BUILD=true -e PORT=4000   -p 80:4000 demo_version:local
```

---

## Infrastructure (Terraform)

Creates:
- 1× Amazon Linux 2023 EC2 in the default VPC/subnet
- Security Group allowing inbound **80/tcp**
- Instance Profile with **AmazonSSMManagedInstanceCore**
- `user_data` installs Docker + Compose, pulls image, runs container mapping `80:4000`
- Tag `Name=demo-version-app` (CI deploys by tag; no hardcoded instance IDs)

**Key variables**
- `image_repo` → e.g. `jvilchez2012/demo_version`  
- `image_tag`  → `latest` or `sha-<12>`  
- `name`       → `demo-version-app`  
- `key_name`   → SSH keypair (optional but useful)

**Example `terraform.tfvars`**
```hcl
region     = "us-east-1"
name       = "demo-version-app"
image_repo = "jvilchez2012/demo_version"
image_tag  = "latest"
key_name   = "your-keypair-name"
```

**Apply**
```bash
cd ops/iac/terraform
terraform init
terraform plan
terraform apply -auto-approve

# test after apply
PUBLIC_IP=$(terraform output -raw public_ip)
curl http://$PUBLIC_IP/api/ping
```

> `user_data` also makes `/opt/docker-compose.yml` that maps **80:4000** and starts the container named `demo-version-app`.

---

## CI/CD (GitHub Actions)

Multi-job pipeline (keeps your static-keys auth):

1. **manifest** – compute image tag `sha-<12>`  
2. **build_push** – build & push `:<sha>` and `:latest` to Docker Hub  
3. **deploy** – SSM `AWS-RunShellScript` to instances *tagged* `Name=demo-version-app`  
4. **verify** – resolve public IP, `curl /api/ping`, check a static asset `Content-Type`

**Secrets required**
- `DOCKERHUB_USERNAME`  
- `DOCKERHUB_TOKEN` (needed to push)  
- `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`  
  - permissions: `ssm:SendCommand`, `ssm:ListCommandInvocations`, `ec2:DescribeInstances`

**What deploy does on the instance**
```bash
docker rm -f demo-version-app || true
docker pull <DOCKERHUB_USER>/demo_version:<sha>
docker run -d --name demo-version-app   -e NODE_ENV=production -e SERVE_BUILD=true -e PORT=4000   -p 80:4000 --restart unless-stopped   <DOCKERHUB_USER>/demo_version:<sha>
```

---

## Metrics (Prometheus + Grafana)

**Passive scrape** without touching the app box (you can also run this *on* the same EC2):

**prometheus.yml**
```yaml
global:
  scrape_interval: 15s
scrape_configs:
  - job_name: "demo-version-app"
    metrics_path: /metrics
    static_configs:
      - targets: ["localhost:80"]   # or "<public-ip>:80"
        labels:
          env: "prod"
          app: "demo-version-app"
```

**docker-compose.yml**
```yaml
services:
  prometheus:
    image: prom/prometheus:v2.54.1
    command: ["--config.file=/etc/prometheus/prometheus.yml", "--storage.tsdb.retention.time=3d"]
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml:ro
    ports: ["9090:9090"]

  grafana:
    image: grafana/grafana:11.1.3
    ports: ["3000:3000"]
    depends_on: [prometheus]
```

**Run**
```bash
docker compose up -d
# Prometheus: http://<host>:9090  (Status → Targets = UP)
# Grafana:    http://<host>:3000  (admin/admin) → add datasource http://prometheus:9090
```

---

## Lambda (AWS CLI Task Proof)

A tiny Lambda proves AWS CLI + IAM wiring:

```bash
# payload.json
{ "ping": 1, "source": "cli" }

aws lambda invoke   --function-name demo-version-app-hello   --payload fileb://payload.json   out.json --region us-east-1

cat out.json   # should echo the payload back
```

Not used by the app—purely to satisfy the “AWS CLI Task” portion.

---

## Health Checks

```bash
# API
curl http://<public_ip>/api/ping

# Landing should NOT include dev import in prod
curl -s http://<public_ip>/ | grep -n "src/main.jsx" || echo "OK: no dev import"

# Static asset Content-Type should be JS
ASSET=$(curl -s http://<public_ip>/ | grep -o '/static/js/[^"]\+\.js' | head -n1)
curl -I "http://<public_ip>$ASSET" | grep -i '^Content-Type:'

# Metrics visible
curl -s http://<public_ip>/metrics | head
```

---

## Rollback

Re-deploy a previous `sha-<12>` tag via SSM:
```bash
aws ssm send-command   --document-name "AWS-RunShellScript"   --targets "Key=tag:Name,Values=demo-version-app"   --parameters commands='[
    "docker rm -f demo-version-app || true",
    "docker pull <DOCKERHUB_USER>/demo_version:sha-XXXXXXXXXXXX",
    "docker run -d --name demo-version-app -e NODE_ENV=production -e SERVE_BUILD=true -e PORT=4000 -p 80:4000 --restart unless-stopped <DOCKERHUB_USER>/demo_version:sha-XXXXXXXXXXXX",
    "docker ps"
  ]'   --region us-east-1
```

---

