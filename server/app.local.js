const express = require("express");
const path = require("path");
const cookieParser = require("cookie-parser");
const morgan = require("morgan");
const client = require("prom-client");

const app = express();

// Load .env if present
try { require("dotenv").config({ path: "server/config/config.env" }); } catch (_) {}

app.use(express.json());
app.use(cookieParser());
app.use(morgan("combined"));

// Prometheus metrics
const register = new client.Registry();
client.collectDefaultMetrics({ register });
app.get("/metrics", async (_req, res) => {
  res.set("Content-Type", register.contentType);
  res.end(await register.metrics());
});

// Health
app.get("/api/ping", (_req, res) => {
  res.json({ ok: true, ts: new Date().toISOString() });
});

// Serve CRA build in "prod-like" mode
if (process.env.SERVE_BUILD === "true") {
  const buildPath = path.join(__dirname, "../build");
  app.use(express.static(buildPath));
  app.get("*", (_req, res) => res.sendFile(path.join(buildPath, "index.html")));
} else {
  app.get("/", (_req, res) => res.send("Server is running"));
}

module.exports = app;
