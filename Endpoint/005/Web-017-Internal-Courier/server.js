const express = require('express');
const fs = require('fs');

const publicApp = express();
const internalApp = express();

const PUBLIC_PORT = Number(process.env.PORT || 80);
const INTERNAL_PORT = 9001;

let FLAG;

try {
  FLAG = fs.readFileSync('/flag.txt', 'utf8').trim();
} catch {
  FLAG = process.env.FLAG || 'NECROX{internal_courier_default_fallback}';
}

const COURIER_SERVICE_TOKEN = 'CRX_INTERNAL_7f8a21c9d44e';

publicApp.use(express.json());
publicApp.use(express.urlencoded({ extended: false }));

internalApp.use(express.json());
internalApp.use(express.urlencoded({ extended: false }));

function esc(value = '') {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function page(title, body) {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">

<title>${esc(title)}</title>

<style>
body {
  margin: 0;
  background: #07111f;
  color: #e6edf5;
  font-family: Arial, Helvetica, sans-serif;
}

main {
  max-width: 900px;
  margin: 50px auto;
  padding: 30px;
  background: #0d1b2a;
  border: 1px solid #1f3550;
  border-radius: 14px;
}

h1 {
  color: #8be9fd;
  margin-top: 0;
}

h2 {
  color: #c6e2ff;
}

a {
  color: #7dd3fc;
}

code,
pre {
  background: #06101a;
  padding: 4px 7px;
  border-radius: 5px;
}

.box {
  border: 1px solid #29435f;
  border-radius: 10px;
  padding: 16px;
  margin: 18px 0;
}

.small {
  color: #97a9bb;
  font-size: 13px;
}

.flag {
  font-size: 24px;
  color: #8df7b5;
  word-break: break-word;
}
</style>
</head>

<body>
<main>
${body}
</main>
</body>
</html>`;
}

publicApp.get('/', (req, res) => {
  res.send(page('Northstar Logistics', `
    <h1>Northstar Logistics</h1>

    <p>
      Import shipment tracking information from one of our
      external courier partners.
    </p>

    <div class="box">
      <h2>Tracking Import</h2>

      <p>
        Our tracking gateway retrieves carrier information
        on behalf of the logistics team.
      </p>

      <p class="small">
        Authorized CyberAnzen security-training environment.
      </p>
    </div>

    <p>
      <a href="/api/docs">
        API Documentation
      </a>
    </p>
  `));
});

publicApp.get('/api/docs', (req, res) => {
  res.json({
    service: 'Northstar Logistics Tracking Gateway',
    version: '3.8.2',
    endpoints: {
      health: 'GET /api/health',
      importTracking: 'POST /api/tracking/import'
    },
    trackingImport: {
      method: 'POST',
      body: {
        url: 'string'
      },
      description:
        'Fetches the carrier tracking endpoint and returns the upstream response.'
    },
    note:
      'The tracking gateway communicates with an internal courier service used by support operations.'
  });
});

publicApp.get('/api/health', (req, res) => {
  res.json({
    status: 'ok',
    service: 'tracking-gateway'
  });
});

publicApp.post('/api/tracking/import', async (req, res) => {
  const { url } = req.body;

  if (!url) {
    return res.status(400).json({
      error: 'missing_url'
    });
  }

  let target;

  try {
    target = new URL(url);
  } catch {
    return res.status(400).json({
      error: 'invalid_url'
    });
  }

  if (!['http:', 'https:'].includes(target.protocol)) {
    return res.status(400).json({
      error: 'unsupported_protocol'
    });
  }

  try {
    const response = await fetch(target.toString(), {
      method: 'GET',
      redirect: 'follow',
      signal: AbortSignal.timeout(5000)
    });

    const body = await response.text();

    return res.json({
      upstream: {
        url: target.toString(),
        status: response.status,
        contentType:
          response.headers.get('content-type') || 'unknown'
      },
      body: body.slice(0, 12000)
    });
  } catch (error) {
    return res.status(502).json({
      error: 'upstream_request_failed',
      message: error.message
    });
  }
});

internalApp.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    service: 'internal-courier-service',
    version: '2.1.4'
  });
});

internalApp.get('/internal/status', (req, res) => {
  res.json({
    service: 'internal-courier-service',
    environment: 'production',
    region: 'ap-south-1',
    workers: 4,
    queue: 'courier-events',
    status: 'healthy'
  });
});

internalApp.get('/internal/config', (req, res) => {
  res.json({
    service: 'courier-service',
    environment: 'production',

    upstreams: {
      tracking: 'https://carrier.northstar.example/api/v2',
      billing: 'http://127.0.0.1:9001/internal/billing'
    },

    internalApi: {
      host: '127.0.0.1',
      port: INTERNAL_PORT
    },

    serviceCredentials: {
      courierServiceToken: COURIER_SERVICE_TOKEN
    },

    comments: [
      'Used by support tooling for shipment investigation.',
      'Do not expose this endpoint outside the internal network.'
    ]
  });
});

internalApp.get('/internal/routes', (req, res) => {
  res.json({
    routes: [
      'GET /health',
      'GET /internal/status',
      'GET /internal/config',
      'GET /internal/routes',
      'GET /internal/admin/report'
    ]
  });
});

internalApp.get('/internal/admin/report', (req, res) => {
  const suppliedToken =
    req.query.service_token ||
    req.headers['x-courier-service-token'];

  if (suppliedToken !== COURIER_SERVICE_TOKEN) {
    return res.status(403).json({
      error: 'forbidden',
      message: 'valid courier service credentials required'
    });
  }

  res.json({
    report: 'Northstar Internal Courier Security Report',
    classification: 'RESTRICTED',
    generatedBy: 'courier-admin-service',
    finding: 'internal service credentials exposed through a diagnostic endpoint',
    flag: FLAG
  });
});

publicApp.use((req, res) => {
  res.status(404).send(
    page(
      'Not Found',
      `
      <h1>404</h1>
      <p>The requested endpoint does not exist.</p>
      `
    )
  );
});

internalApp.use((req, res) => {
  res.status(404).json({
    error: 'not_found'
  });
});

publicApp.listen(PUBLIC_PORT, '0.0.0.0', () => {
  console.log(
    `[Public] Tracking gateway listening on ${PUBLIC_PORT}`
  );
});

internalApp.listen(INTERNAL_PORT, '127.0.0.1', () => {
  console.log(
    `[Internal] Courier service listening on 127.0.0.1:${INTERNAL_PORT}`
  );
});

console.log(
  '[Challenge] Internal Courier initialized'
);

console.log(
  '[Challenge] Dynamic flag loaded from /flag.txt'
);
