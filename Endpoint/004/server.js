const express = require('express');
const crypto = require('crypto');
const fs = require('fs');

const app = express();
const PORT = Number(process.env.PORT || 80);

app.set('trust proxy', true);

let FLAG;

try {
  FLAG = fs.readFileSync('/flag.txt', 'utf8').trim();
} catch {
  FLAG = process.env.FLAG || 'NECROX{oauth_trap_default_fallback}';
}

app.use(express.urlencoded({ extended: false }));
app.use(express.json());

const OAUTH_CLIENT = {
  client_id: 'northstar-web',
  client_name: 'Northstar Customer Portal'
};

const accounts = [
  {
    id: 'acct-1001',
    email: 'admin@northstar.local',
    name: 'Northstar Administrator',
    role: 'admin'
  },
  {
    id: 'acct-1002',
    email: 'analyst@northstar.local',
    name: 'Northstar Analyst',
    role: 'user'
  }
];

const authorizationCodes = new Map();
const sessions = new Map();

function getBaseUrl(req) {
  const forwardedProto = req.get('x-forwarded-proto');
  const protocol = forwardedProto
    ? forwardedProto.split(',')[0].trim()
    : req.protocol;

  return `${protocol}://${req.get('host')}`;
}

function esc(value = '') {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function randomToken(bytes = 24) {
  return crypto.randomBytes(bytes).toString('hex');
}

function parseCookies(req) {
  const raw = req.headers.cookie || '';
  const out = {};

  for (const part of raw.split(';')) {
    const index = part.indexOf('=');

    if (index === -1) {
      continue;
    }

    const key = part.slice(0, index).trim();
    const value = decodeURIComponent(part.slice(index + 1).trim());

    out[key] = value;
  }

  return out;
}

function getSession(req) {
  const sid = parseCookies(req).sid;

  if (!sid) {
    return null;
  }

  return sessions.get(sid) || null;
}

function createSession(account) {
  const sid = randomToken(24);

  sessions.set(sid, {
    accountId: account.id,
    createdAt: Date.now()
  });

  return sid;
}

function accountByEmail(email) {
  return accounts.find(
    account =>
      account.email.toLowerCase() === String(email).toLowerCase()
  ) || null;
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
  margin-top: 0;
  color: #8be9fd;
}

h2 {
  color: #c6e2ff;
}

a {
  color: #7dd3fc;
}

input,
button {
  font: inherit;
  padding: 10px 12px;
  border-radius: 8px;
  border: 1px solid #38536f;
}

input {
  background: #08131f;
  color: #fff;
  width: 100%;
  box-sizing: border-box;
}

button {
  background: #2c7be5;
  color: white;
  border: 0;
  cursor: pointer;
  margin-top: 12px;
}

code,
pre {
  background: #06101a;
  padding: 3px 6px;
  border-radius: 5px;
}

.box {
  padding: 16px;
  border: 1px solid #29435f;
  border-radius: 10px;
  margin: 15px 0;
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

app.get('/', (req, res) => {
  res.send(page('Northstar Customer Portal', `
    <h1>Northstar Customer Portal</h1>

    <p>
      Sign in with the corporate identity provider.
    </p>

    <div class="box">
      <h2>OAuth Sign-In</h2>

      <p class="small">
        Legacy SSO migration is currently enabled.
      </p>

      <a href="/login">
        <button>Continue with Northstar ID</button>
      </a>
    </div>

    <p class="small">
      Authorized CyberAnzen security-training environment.
    </p>
  `));
});

app.get('/login', (req, res) => {
  const state = randomToken(16);

  const defaultRedirectUri =
    `${getBaseUrl(req)}/oauth/callback`;

  const redirectUri =
    req.query.redirect_uri || defaultRedirectUri;

  res.send(page('OAuth Login', `
    <h1>Northstar Identity Provider</h1>

    <p>
      Authorize
      <code>${esc(OAUTH_CLIENT.client_name)}</code>.
    </p>

    <form method="POST" action="/oauth/authorize">

      <input
        type="hidden"
        name="client_id"
        value="${esc(OAUTH_CLIENT.client_id)}"
      >

      <input
        type="hidden"
        name="redirect_uri"
        value="${esc(redirectUri)}"
      >

      <input
        type="hidden"
        name="response_type"
        value="code"
      >

      <input
        type="hidden"
        name="state"
        value="${esc(state)}"
      >

      <label>
        Identity email
      </label>

      <br><br>

      <input
        name="email"
        value="admin@northstar.local"
        autocomplete="off"
      >

      <p class="small">
        Legacy test provider: email ownership is not verified during this flow.
      </p>

      <button type="submit">
        Authorize
      </button>

    </form>
  `));
});

app.get('/oauth/authorize', (req, res) => {
  const {
    client_id,
    redirect_uri,
    response_type,
    state
  } = req.query;

  if (
    client_id !== OAUTH_CLIENT.client_id ||
    response_type !== 'code'
  ) {
    return res.status(400).send('invalid_request');
  }

  if (!redirect_uri) {
    return res.status(400).send('missing_redirect_uri');
  }

  res.send(page('Authorize Application', `
    <h1>Northstar Identity Provider</h1>

    <p>
      Authorization request received.
    </p>

    <div class="box">

      <p>
        <strong>Client:</strong>
        ${esc(client_id)}
      </p>

      <p>
        <strong>Redirect:</strong>
        <code>${esc(redirect_uri)}</code>
      </p>

    </div>

    <form method="POST" action="/oauth/authorize">

      <input
        type="hidden"
        name="client_id"
        value="${esc(client_id)}"
      >

      <input
        type="hidden"
        name="redirect_uri"
        value="${esc(redirect_uri)}"
      >

      <input
        type="hidden"
        name="response_type"
        value="${esc(response_type)}"
      >

      <input
        type="hidden"
        name="state"
        value="${esc(state || '')}"
      >

      <label>
        Identity email
      </label>

      <br><br>

      <input
        name="email"
        value="admin@northstar.local"
        autocomplete="off"
      >

      <button type="submit">
        Allow Access
      </button>

    </form>
  `));
});

app.post('/oauth/authorize', (req, res) => {
  const {
    client_id,
    redirect_uri,
    response_type,
    state,
    email
  } = req.body;

  if (
    client_id !== OAUTH_CLIENT.client_id ||
    response_type !== 'code'
  ) {
    return res.status(400).send('invalid_client');
  }

  if (!email || !redirect_uri) {
    return res.status(400).send('missing_parameters');
  }

  const code = randomToken(18);

  authorizationCodes.set(code, {
    email: String(email).trim().toLowerCase(),
    email_verified: false,
    name: String(email).split('@')[0],
    client_id,
    redirect_uri,
    issuedAt: Date.now()
  });

  let target;

  try {
    target = new URL(
      redirect_uri,
      getBaseUrl(req)
    );
  } catch {
    return res.status(400).send('invalid_redirect_uri');
  }

  target.searchParams.set('code', code);

  if (state) {
    target.searchParams.set('state', state);
  }

  return res.redirect(target.toString());
});

app.get('/oauth/callback', (req, res) => {
  const {
    code
  } = req.query;

  const grant = authorizationCodes.get(code);

  if (!grant) {
    return res.status(400).send('invalid_or_expired_code');
  }

  authorizationCodes.delete(code);

  const account = accountByEmail(grant.email);

  if (!account) {
    return res.status(403).send(page(
      'Account Link Failed',
      `
      <h1>Account linking failed</h1>

      <p>
        No Northstar account exists for
        <code>${esc(grant.email)}</code>.
      </p>

      <p>
        <a href="/">
          Return to portal
        </a>
      </p>
      `
    ));
  }

  const sid = createSession(account);

  res.setHeader(
    'Set-Cookie',
    `sid=${encodeURIComponent(sid)}; Path=/; HttpOnly; SameSite=Lax`
  );

  res.redirect('/dashboard');
});

app.get('/capture', (req, res) => {
  res.send(page('OAuth Capture', `
    <h1>OAuth Capture Endpoint</h1>

    <p>
      This endpoint is intentionally exposed in the training
      environment so players can inspect where the authorization
      server sends a code.
    </p>

    <div class="box">

      <p>
        <strong>code:</strong>
        <code>
          ${esc(req.query.code || '(none)')}
        </code>
      </p>

      <p>
        <strong>state:</strong>
        <code>
          ${esc(req.query.state || '(none)')}
        </code>
      </p>

    </div>

    <p class="small">
      Use the captured authorization code only against the
      challenge callback.
    </p>
  `));
});

app.get('/dashboard', (req, res) => {
  const session = getSession(req);

  if (!session) {
    return res.redirect('/');
  }

  const account = accounts.find(
    item => item.id === session.accountId
  );

  if (!account) {
    return res.redirect('/');
  }

  const flagBlock =
    account.role === 'admin'
      ? `
        <div class="box">

          <h2>
            Administrator Vault
          </h2>

          <p class="flag">
            ${esc(FLAG)}
          </p>

        </div>
      `
      : `
        <div class="box">

          <h2>
            Standard Account
          </h2>

          <p>
            Welcome,
            ${esc(account.name)}.
          </p>

          <p>
            No protected training artifact is assigned
            to this role.
          </p>

        </div>
      `;

  res.send(page('Northstar Dashboard', `
    <h1>
      Northstar Dashboard
    </h1>

    <p>
      Signed in as
      <strong>
        ${esc(account.email)}
      </strong>.
    </p>

    <p>
      Role:
      <code>
        ${esc(account.role)}
      </code>
    </p>

    ${flagBlock}

    <p>
      <a href="/api/me">
        View session details
      </a>
    </p>
  `));
});

app.get('/api/me', (req, res) => {
  const session = getSession(req);

  if (!session) {
    return res.status(401).json({
      authenticated: false
    });
  }

  const account = accounts.find(
    item => item.id === session.accountId
  );

  if (!account) {
    return res.status(401).json({
      authenticated: false
    });
  }

  res.json({
    authenticated: true,
    account
  });
});

app.get('/oauth/userinfo', (req, res) => {
  const code = req.query.code;

  const grant = authorizationCodes.get(code);

  if (!grant) {
    return res.status(404).json({
      error: 'unknown_code'
    });
  }

  res.json({
    sub: crypto
      .createHash('sha256')
      .update(grant.email)
      .digest('hex')
      .slice(0, 16),

    email: grant.email,

    email_verified: grant.email_verified,

    name: grant.name
  });
});

app.get('/.well-known/openid-configuration', (req, res) => {
  const baseUrl = getBaseUrl(req);

  res.json({
    issuer: baseUrl,

    authorization_endpoint:
      `${baseUrl}/oauth/authorize`,

    userinfo_endpoint:
      `${baseUrl}/oauth/userinfo`,

    response_types_supported: [
      'code'
    ],

    code_challenge_methods_supported: [
      'plain'
    ],

    note:
      'Legacy compatibility mode is enabled for the training challenge.'
  });
});

app.get('/api/client-info', (req, res) => {
  const baseUrl = getBaseUrl(req);

  res.json({
    client: {
      client_id: OAUTH_CLIENT.client_id,

      client_name: OAUTH_CLIENT.client_name,

      registered_redirect_uri:
        `${baseUrl}/oauth/callback`
    },

    securityNotes: [
      'Legacy redirect handling is intentionally weak.',
      'OAuth state is not bound to the browser session.',
      'Account linking trusts email even when email_verified is false.'
    ]
  });
});

app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    service: 'northstar-oauth'
  });
});

app.use((req, res) => {
  res.status(404).send(
    page(
      'Not Found',
      `
      <h1>404</h1>
      <p>
        The requested route does not exist.
      </p>
      `
    )
  );
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(
    `[Challenge] OAuth Trap listening on ${PORT}`
  );

  console.log(
    '[Challenge] Dynamic flag loaded from /flag.txt'
  );
});