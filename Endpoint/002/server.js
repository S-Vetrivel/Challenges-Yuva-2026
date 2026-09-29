const express = require("express");
const crypto = require("crypto");
const fs = require("fs");

const app = express();

app.use(express.json());
app.use(express.urlencoded({ extended: false }));

const PORT = process.env.PORT || 80;

let FLAG;

try {
    FLAG = fs.readFileSync("/flag.txt", "utf8").trim();
} catch {
    FLAG = "NECROX{DEFAULT_CSRF_FLAG}";
}

const sessions = new Map([
    ["pp_admin_demo", {
        id: "usr_treasury_01",
        username: "taylor.foster",
        role: "treasury_admin",
        tenant: "northstar"
    }]
]);

const state = {
    accountName: "Northstar Holdings Treasury",
    accountNumber: "0011004821",
    routingCode: "HDFC0001204",
    ticket: "FIN-2026-0917",
    lastMutation: null
};

const auditLog = [];

function parseCookies(header) {
    const cookies = {};

    if (!header) {
        return cookies;
    }

    for (const part of header.split(";")) {
        const index = part.indexOf("=");

        if (index === -1) {
            continue;
        }

        const key = part.slice(0, index).trim();
        const value = part.slice(index + 1).trim();

        cookies[key] = decodeURIComponent(value);
    }

    return cookies;
}

function getSession(req) {
    const cookies = parseCookies(req.headers.cookie);

    return sessions.get(cookies.pp_session);
}

function authenticate(req, res, next) {
    const session = getSession(req);

    if (!session) {
        return res.status(401).json({
            error: "authentication_required"
        });
    }

    req.user = session;

    next();
}

app.get("/", (req, res) => {
    res.type("html").send(
        fs.readFileSync("/app/frontend.html", "utf8")
    );
});

app.get("/login", (req, res) => {
    res.type("html").send(`
<!doctype html>
<html>
<head>
<title>PayPilot Login</title>
</head>
<body style="font-family:Arial,sans-serif;background:#f4f6f8;padding:50px">

<div style="max-width:520px;margin:auto;background:white;padding:30px;border:1px solid #ddd;border-radius:10px">

<h1>PayPilot</h1>

<p>Training administrator session</p>

<form method="POST" action="/login">

<input
name="username"
value="taylor.foster"
style="display:block;width:100%;padding:10px;margin:10px 0"
>

<input
name="password"
value="ManualOnly-2026!"
type="password"
style="display:block;width:100%;padding:10px;margin:10px 0"
>

<button style="padding:10px 15px">Sign in</button>

</form>

</div>

</body>
</html>
    `);
});

app.post("/login", (req, res) => {
    if (
        req.body.username !== "taylor.foster" ||
        req.body.password !== "ManualOnly-2026!"
    ) {
        return res.status(401).send("invalid_credentials");
    }

    res.setHeader(
        "Set-Cookie",
        "pp_session=pp_admin_demo; Path=/; HttpOnly; Secure; SameSite=None"
    );

    res.redirect("/");
});

app.get("/api/session", authenticate, (req, res) => {
    res.json({
        id: req.user.id,
        username: req.user.username,
        role: req.user.role,
        tenant: req.user.tenant
    });
});

app.get("/api/challenge/status", (req, res) => {
    res.json({
        accountName: state.accountName,
        accountNumber: state.accountNumber
            .slice(-4)
            .padStart(state.accountNumber.length, "•"),
        routingCode: state.routingCode,
        ticket: state.ticket,
        lastMutation: state.lastMutation
            ? {
                origin: state.lastMutation.origin,
                secFetchSite: state.lastMutation.secFetchSite
            }
            : null
    });
});

app.post("/api/treasury/payout-destination", authenticate, (req, res) => {

    if (req.user.role !== "treasury_admin") {
        return res.status(403).json({
            error: "treasury_admin_required"
        });
    }

    const {
        accountName,
        accountNumber,
        routingCode,
        ticket
    } = req.body;

    if (
        !accountName ||
        !accountNumber ||
        !routingCode ||
        !ticket
    ) {
        return res.status(400).json({
            error: "all_fields_required"
        });
    }

    state.accountName = String(accountName);
    state.accountNumber = String(accountNumber);
    state.routingCode = String(routingCode);
    state.ticket = String(ticket);

    state.lastMutation = {
        origin: req.get("origin") || null,
        referer: req.get("referer") || null,
        secFetchSite: req.get("sec-fetch-site") || null,
        timestamp: new Date().toISOString()
    };

    auditLog.push({
        event: "treasury.payout_destination.updated",
        actor: req.user.id,
        accountNumber: state.accountNumber,
        origin: state.lastMutation.origin,
        secFetchSite: state.lastMutation.secFetchSite,
        timestamp: state.lastMutation.timestamp
    });

    res.json({
        ok: true,
        message: "Settlement destination updated"
    });
});

app.get("/api/challenge/claim", authenticate, (req, res) => {

    if (req.user.role !== "treasury_admin") {
        return res.status(403).json({
            error: "treasury_admin_required"
        });
    }

    const mutation = state.lastMutation;

    const crossSite =
        mutation &&
        mutation.secFetchSite === "cross-site" &&
        mutation.origin &&
        !mutation.origin.includes(
            req.protocol + "://" + req.get("host")
        );

    if (!crossSite) {
        return res.status(403).json({
            error: "challenge_condition_not_met"
        });
    }

    if (state.accountNumber !== "7777000011112222") {
        return res.status(403).json({
            error: "target_state_not_reached"
        });
    }

    res.json({
        flag: FLAG,
        proof: {
            event: "cross_site_state_change",
            endpoint: "/api/treasury/payout-destination"
        }
    });
});

app.get("/api/audit", authenticate, (req, res) => {
    res.json({
        events: auditLog
    });
});

app.use((req, res) => {
    res.status(404).json({
        error: "route_not_found"
    });
});

app.listen(PORT, () => {
    console.log(
        `PayPilot CSRF challenge listening on port ${PORT}`
    );
});
