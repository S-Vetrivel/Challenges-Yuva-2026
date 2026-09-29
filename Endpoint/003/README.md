# Web/003 — Forgotten Password

## Challenge Information

- ID: Web/003
- Title: Forgotten Password
- Category: Web / Authentication
- Difficulty: Easy-Medium
- Access mode: WEB
- Internal port: 3000
- Flag format: `CYBERANZEN{...}`

## Player Scenario

Northstar's identity service handles account recovery.

A security review found that the password-reset workflow may have been implemented incorrectly. Your objective is to obtain access to the administrator account and recover the flag.

You are authorized to test this CyberAnzen training application.

## Description

The application provides:

- Login
- Password-reset request
- Password-reset confirmation
- Account status
- Basic API documentation

The intended weakness is in the password-reset implementation.

The reset token is deterministically derived from:

1. the account ID
2. the exact reset-request timestamp rounded to the minute

The account-status API also exposes the exact timestamp of a reset request.

This creates a predictable password-reset token.

## Intended Solve

1. Discover the available API endpoints.
2. Identify the administrator account.
3. Request a password reset for the administrator.
4. Query the administrator's reset status.
5. Obtain the exact `requestedAt` timestamp.
6. Reconstruct the vulnerable token-generation scheme.
7. Submit the token to `/api/password-reset/confirm`.
8. Set a new administrator password.
9. Recover the flag returned after the administrator password reset.

## Intended Flag

`CYBERANZEN{forgotten_password_chain}`

The deployed `FLAG` environment variable overrides the fallback value.

## Hints

### Hint 1

The browser is only the frontend. Look at the API calls it makes.

### Hint 2

Password recovery has more than one endpoint. Examine what the identity service tells you about an account.

### Hint 3

The reset timestamp is more useful than it first appears.

## Vulnerability

The challenge intentionally combines two implementation mistakes:

- predictable reset-token generation
- disclosure of the exact password-reset timestamp

A real password-reset token should be generated using cryptographically secure randomness, stored server-side, expire quickly, and be single-use.

## Deployment

Build:

```bash
docker build -t cyberanzen-web-003 .
```

Run:

```bash
docker run --rm -p 3000:3000 \
  -e FLAG='CYBERANZEN{forgotten_password_chain}' \
  cyberanzen-web-003
```

Open:

```text
http://127.0.0.1:3000
```

## Author Notes

The challenge is intentionally self-contained and has no external dependencies at runtime.

The vulnerable token formula is implemented in `server.js`:

```text
SHA256(accountId + ":" + floor(requestedAt / 60000))
```

with the first 32 hexadecimal characters used as the reset token.

The formula is not exposed directly to players.
