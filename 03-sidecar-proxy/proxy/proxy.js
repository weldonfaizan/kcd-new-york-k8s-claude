const http = require("http");
const https = require("https");

const REAL_API_KEY = process.env.ANTHROPIC_API_KEY;
const UPSTREAM_HOST = process.env.UPSTREAM_HOST || "api.anthropic.com";
const UPSTREAM_PORT = parseInt(process.env.UPSTREAM_PORT || "443");
const LISTEN_PORT = parseInt(process.env.LISTEN_PORT || "8080");

if (!REAL_API_KEY) {
  console.error("Error: ANTHROPIC_API_KEY not set in proxy sidecar");
  process.exit(1);
}

const server = http.createServer((req, res) => {
  const headers = { ...req.headers };

  // Replace the API key header with the real one
  headers["x-api-key"] = REAL_API_KEY;
  // Remove host header so upstream gets the correct one
  headers["host"] = UPSTREAM_HOST;

  const options = {
    hostname: UPSTREAM_HOST,
    port: UPSTREAM_PORT,
    path: req.url,
    method: req.method,
    headers: headers,
  };

  const proxyReq = https.request(options, (proxyRes) => {
    res.writeHead(proxyRes.statusCode, proxyRes.headers);
    proxyRes.pipe(res);
  });

  proxyReq.on("error", (err) => {
    console.error(`Proxy error: ${err.message}`);
    res.writeHead(502);
    res.end("Bad Gateway");
  });

  req.pipe(proxyReq);
});

server.listen(LISTEN_PORT, "127.0.0.1", () => {
  console.log(`Credential proxy listening on 127.0.0.1:${LISTEN_PORT}`);
  console.log(`Forwarding to ${UPSTREAM_HOST}:${UPSTREAM_PORT}`);
});
