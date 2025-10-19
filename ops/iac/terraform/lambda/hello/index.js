// Node.js 20.x Lambda (CommonJS)
exports.handler = async (event) => {
  return {
    ok: true,
    ts: new Date().toISOString(),
    echo: event || null
  };
};
