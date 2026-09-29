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
    FLAG = "NECROX{DEFAULT_LOCAL_FLAG}";
}

const tenants = {
    acme: {
        id: "tnt_acme",
        name: "Acme Engineering"
    },

    northstar: {
        id: "tnt_northstar",
        name: "Northstar Finance"
    }
};

const users = {
    "employee-token": {
        id: "usr_1042",
        username: "v3",
        tenant: "acme",
        role: "employee"
    },

    "manager-token": {
        id: "usr_1001",
        username: "alice",
        tenant: "acme",
        role: "manager"
    },

    "finance-service-token": {
        id: "svc_finance",
        username: "finance-worker",
        tenant: "northstar",
        role: "service"
    }
};

const expenses = [
    {
        id: "EXP-10492",
        tenant: "acme",
        owner: "usr_1042",
        description: "USB-C docking station",
        amount: 12999,
        currency: "INR",
        status: "approved"
    },

    {
        id: "EXP-10493",
        tenant: "acme",
        owner: "usr_1001",
        description: "Conference accommodation",
        amount: 28600,
        currency: "INR",
        status: "approved"
    },

    {
        id: "EXP-77192",
        tenant: "northstar",
        owner: "usr_finance",
        description: "Quarterly settlement reconciliation",
        amount: 9200000,
        currency: "INR",
        status: "settled"
    }
];

const exportJobs = new Map();

const auditLog = [];

function authenticate(req, res, next) {
    const authorization = req.headers.authorization;

    if (!authorization) {
        return res.status(401).json({
            error: "authentication_required"
        });
    }

    const user = users[authorization];

    if (!user) {
        return res.status(401).json({
            error: "invalid_session"
        });
    }

    req.user = user;

    next();
}

function createId(prefix) {
    return `${prefix}_${crypto.randomBytes(6).toString("hex")}`;
}

app.get("/", (req, res) => {
    res.send(`
<!DOCTYPE html>
<html>
<head>
    <title>LedgerFlow</title>
    <style>
        body {
            margin: 0;
            font-family: Arial, sans-serif;
            background: #f4f6f8;
            color: #17202a;
        }

        header {
            background: #17202a;
            color: white;
            padding: 20px 40px;
        }

        main {
            max-width: 1000px;
            margin: 40px auto;
            padding: 0 20px;
        }

        .card {
            background: white;
            border-radius: 8px;
            padding: 25px;
            margin-bottom: 20px;
            box-shadow: 0 2px 8px rgba(0,0,0,.08);
        }

        code {
            background: #eef1f4;
            padding: 3px 6px;
            border-radius: 4px;
        }
    </style>
</head>

<body>

<header>
    <strong>LedgerFlow</strong>
    <span style="float:right">Corporate Expense Platform</span>
</header>

<main>

    <div class="card">
        <h1>Expense Management</h1>
        <p>
            Submit, review and export corporate expenses.
        </p>
    </div>

    <div class="card">
        <h2>Available API</h2>

        <p><code>GET /api/me</code></p>
        <p><code>GET /api/expenses</code></p>
        <p><code>GET /api/expenses/:id</code></p>
        <p><code>POST /api/expenses</code></p>
        <p><code>POST /api/exports</code></p>
        <p><code>GET /api/exports/:id</code></p>
        <p><code>GET /api/reports/:id</code></p>
    </div>

</main>

</body>
</html>
    `);
});

app.get("/api/me", authenticate, (req, res) => {
    res.json({
        id: req.user.id,
        username: req.user.username,
        tenant: req.user.tenant,
        role: req.user.role
    });
});

app.get("/api/expenses", authenticate, (req, res) => {
    const result = expenses.filter(
        expense => expense.tenant === req.user.tenant
    );

    res.json({
        tenant: tenants[req.user.tenant],
        count: result.length,
        expenses: result
    });
});

app.get("/api/expenses/:id", authenticate, (req, res) => {
    const expense = expenses.find(
        item => item.id === req.params.id
    );

    if (!expense) {
        return res.status(404).json({
            error: "expense_not_found"
        });
    }

    if (expense.tenant !== req.user.tenant) {
        return res.status(404).json({
            error: "expense_not_found"
        });
    }

    res.json(expense);
});

app.post("/api/expenses", authenticate, (req, res) => {
    const {
        description,
        amount,
        currency
    } = req.body;

    if (!description || !amount) {
        return res.status(400).json({
            error: "description_and_amount_required"
        });
    }

    const expense = {
        id: `EXP-${Math.floor(Math.random() * 90000) + 10000}`,
        tenant: req.user.tenant,
        owner: req.user.id,
        description,
        amount,
        currency: currency || "INR",
        status: "pending"
    };

    expenses.push(expense);

    auditLog.push({
        event: "expense.created",
        actor: req.user.id,
        tenant: req.user.tenant,
        expense: expense.id,
        timestamp: new Date().toISOString()
    });

    res.status(201).json(expense);
});

app.post("/api/exports", authenticate, (req, res) => {
    const exportJob = {
        id: createId("export"),
        tenant: req.user.tenant,
        requestedBy: req.user.id,
        status: "queued",
        createdAt: new Date().toISOString()
    };

    exportJobs.set(exportJob.id, exportJob);

    auditLog.push({
        event: "export.created",
        actor: req.user.id,
        tenant: req.user.tenant,
        exportId: exportJob.id,
        timestamp: new Date().toISOString()
    });

    setTimeout(() => {
        const current = exportJobs.get(exportJob.id);

        if (!current) {
            return;
        }

        current.status = "completed";
        current.objectKey =
            `exports/${current.tenant}/${current.id}.csv`;

        current.completedAt = new Date().toISOString();

        exportJobs.set(current.id, current);
    }, 1500);

    res.status(202).json({
        id: exportJob.id,
        status: exportJob.status
    });
});

app.get("/api/exports/:id", authenticate, (req, res) => {
    const exportJob = exportJobs.get(req.params.id);

    if (!exportJob) {
        return res.status(404).json({
            error: "export_not_found"
        });
    }

    if (exportJob.tenant !== req.user.tenant) {
        return res.status(404).json({
            error: "export_not_found"
        });
    }

    res.json(exportJob);
});

app.get("/api/reports/:id", authenticate, (req, res) => {
    const exportJob = exportJobs.get(req.params.id);

    if (!exportJob) {
        return res.status(404).json({
            error: "report_not_found"
        });
    }

    if (exportJob.status !== "completed") {
        return res.status(409).json({
            error: "report_not_ready"
        });
    }

    res.json({
        reportId: exportJob.id,
        objectKey: exportJob.objectKey,
        generatedAt: exportJob.completedAt,
        format: "csv"
    });
});

app.get("/internal/audit", authenticate, (req, res) => {
    if (req.user.role !== "manager") {
        return res.status(403).json({
            error: "manager_required"
        });
    }

    res.json({
        events: auditLog
    });
});

app.get("/internal/finance/settlement", (req, res) => {
    const serviceToken = req.headers["x-service-token"];

    if (serviceToken !== "finance-service-token") {
        return res.status(403).json({
            error: "service_authentication_required"
        });
    }

    res.json({
        service: "finance",
        tenant: "northstar",
        settlement: {
            period: "2026-Q3",
            status: "completed",
            amount: 9200000
        },
        internalReference: FLAG
    });
});

app.use((req, res) => {
    res.status(404).json({
        error: "route_not_found"
    });
});

app.listen(PORT, () => {
    console.log(`LedgerFlow listening on port ${PORT}`);
});
