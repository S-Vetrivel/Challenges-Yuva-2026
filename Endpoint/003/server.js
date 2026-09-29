const express = require("express");
const crypto = require("crypto");
const cookieParser = require("cookie-parser");

const app = express();
const PORT = Number(process.env.PORT || 3000);
const FLAG = process.env.FLAG || "CYBERANZEN{forgotten_password_chain}";

app.use(express.json());
app.use(express.urlencoded({ extended: false }));
app.use(cookieParser());
app.use(express.static("/app/public"));

const accounts = new Map([
  [
    "admin@northstar.local",
    {
      id: 1001,
      email: "admin@northstar.local",
      name: "Northstar Administrator",
      password: "NeverGuessThisPassword",
      role: "admin",
      resetRequestedAt: null
    }
  ],
  [
    "analyst@northstar.local",
    {
      id: 1002,
      email: "analyst@northstar.local",
      name: "Security Analyst",
      password: "AnalystPassword2026!",
      role: "user",
      resetRequestedAt: null
    }
  ]
]);

const sessions = new Map();

function normalizeEmail(value) {
  return String(value || "").trim().toLowerCase();
}

function minuteBucket(timestamp) {
  return Math.floor(timestamp / 60000);
}

/*
 * Intentionally vulnerable reset-token design.
 *
 * A production reset token should be generated with cryptographically
 * secure randomness and stored server-side with expiry/one-time use.
 *
 * This challenge instead derives the token from two predictable values:
 * account ID + minute bucket.
 */
function generateResetToken(account, timestamp) {
  const bucket = minuteBucket(timestamp);
  return crypto
    .createHash("sha256")
    .update(`${account.id}:${bucket}`)
    .digest("hex")
    .slice(0, 32);
}

function publicAccount(account) {
  return {
    id: account.id,
    email: account.email,
    name: account.name,
    role: account.role
  };
}

app.get("/api/health", (_req, res) => {
  res.json({ status: "ok", service: "northstar-auth" });
});

app.get("/api/account/status", (req, res) => {
  const email = normalizeEmail(req.query.email);

  if (!email) {
    return res.status(400).json({ error: "email is required" });
  }

  const account = accounts.get(email);

  if (!account) {
    return res.status(404).json({ error: "account not found" });
  }

  /*
   * Intentional information disclosure:
   * the password-reset status exposes the exact request timestamp.
   * Combined with the predictable token construction, this permits
   * recovery of another user's reset token.
   */
  res.json({
    account: publicAccount(account),
    passwordReset: {
      requested: Boolean(account.resetRequestedAt),
      requestedAt: account.resetRequestedAt
    }
  });
});

app.post("/api/password-reset/request", (req, res) => {
  const email = normalizeEmail(req.body.email);

  if (!email) {
    return res.status(400).json({ error: "email is required" });
  }

  const account = accounts.get(email);

  if (!account) {
    return res.status(202).json({
      message: "If the account exists, a reset email will be sent."
    });
  }

  const now = Date.now();
  account.resetRequestedAt = now;

  /*
   * The application would normally send an email here.
   * The token itself is deliberately NOT returned by this endpoint.
   */
  res.status(202).json({
    message: "If the account exists, a reset email will be sent.",
    requestedAt: now
  });
});

app.post("/api/password-reset/confirm", (req, res) => {
  const email = normalizeEmail(req.body.email);
  const token = String(req.body.token || "");
  const newPassword = String(req.body.newPassword || "");

  if (!email || !token || !newPassword) {
    return res.status(400).json({
      error: "email, token and newPassword are required"
    });
  }

  if (newPassword.length < 8) {
    return res.status(400).json({
      error: "newPassword must contain at least 8 characters"
    });
  }

  const account = accounts.get(email);

  if (!account || !account.resetRequestedAt) {
    return res.status(400).json({ error: "invalid or expired reset" });
  }

  const expected = generateResetToken(account, account.resetRequestedAt);

  if (token !== expected) {
    return res.status(403).json({ error: "invalid reset token" });
  }

  account.password = newPassword;
  account.resetRequestedAt = null;

  if (account.role === "admin") {
    return res.json({
      success: true,
      message: "Password reset completed.",
      flag: FLAG
    });
  }

  res.json({
    success: true,
    message: "Password reset completed."
  });
});

app.post("/api/login", (req, res) => {
  const email = normalizeEmail(req.body.email);
  const password = String(req.body.password || "");
  const account = accounts.get(email);

  if (!account || account.password !== password) {
    return res.status(401).json({ error: "invalid credentials" });
  }

  const sessionId = crypto.randomBytes(24).toString("hex");
  sessions.set(sessionId, account.email);

  res.cookie("session", sessionId, {
    httpOnly: true,
    sameSite: "lax"
  });

  res.json({
    success: true,
    account: publicAccount(account)
  });
});

app.get("/api/me", (req, res) => {
  const email = sessions.get(req.cookies.session);

  if (!email) {
    return res.status(401).json({ error: "not authenticated" });
  }

  const account = accounts.get(email);
  res.json({ account: publicAccount(account) });
});

app.get("/api/docs", (_req, res) => {
  res.json({
    service: "Northstar Identity Service",
    version: "2.4.1",
    endpoints: [
      "POST /api/password-reset/request",
      "POST /api/password-reset/confirm",
      "GET /api/account/status?email=",
      "POST /api/login",
      "GET /api/me"
    ],
    note: "Password recovery is handled by the identity service."
  });
});

app.listen(PORT, "0.0.0.0", () => {
  console.log(`[Northstar] Identity service listening on ${PORT}`);
});
