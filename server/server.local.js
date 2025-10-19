const app = require("./app.local");
const PORT = process.env.PORT || 4000;

const server = app.listen(PORT, () => {
  console.log(`Local stub API listening on http://localhost:${PORT}`);
});

process.on("uncaughtException", (err) => {
  console.error("uncaughtException:", err);
  process.exit(1);
});
process.on("unhandledRejection", (err) => {
  console.error("unhandledRejection:", err);
});
