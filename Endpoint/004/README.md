# Web/021 — OAuth Trap

## Challenge information

- **Title:** OAuth Trap
- **Category:** Web / OAuth Misconfiguration
- **Difficulty:** Hard
- **Access:** WEB
- **Internal port:** 80
- **Flag variable:** `FLAG`

## Scenario

Northstar's customer portal was migrated to a legacy OAuth integration. During the migration, the security review was skipped and several trust-boundary checks were left in compatibility mode.

You have access to the public portal. Your objective is to reconstruct the OAuth flow, identify the redirect and account-linking weaknesses, obtain an administrator session, and recover the protected training flag.

## Intended vulnerabilities

This challenge intentionally combines three OAuth implementation mistakes:

1. **Loose redirect handling** — the challenge accepts a redirect URI without enforcing an exact registered redirect destination.
2. **Missing state binding** — the callback does not bind the OAuth `state` value to the browser session that started the flow.
3. **Unsafe account linking** — the client uses the provider's `email` field as a local account identifier without requiring `email_verified: true`.

The mock identity provider is deliberately simplified for deterministic CTF behavior. It allows the player to submit an identity email and returns it with `email_verified: false`.

## Intended solve path

1. Open `/` and follow the OAuth login flow.
2. Inspect `/.well-known/openid-configuration` and `/api/client-info`.
3. Notice the weak redirect handling and that the client ignores `email_verified` during account linking.
4. Start an authorization request using the administrator email `admin@northstar.local`.
5. Route the authorization response through `/capture` so the returned authorization code is visible.
6. Send the captured `code` to `/oauth/callback`.
7. The callback accepts the code without validating the originating browser state and links the provider identity to the existing administrator account solely by email.
8. Visit `/dashboard` and recover the flag shown to the administrator role.

## Useful endpoints

- `/`
- `/login`
- `/oauth/authorize`
- `/oauth/callback`
- `/capture`
- `/.well-known/openid-configuration`
- `/api/client-info`
- `/api/me`
- `/dashboard`

## Defender lesson

A production OAuth/OIDC client should use exact redirect URI registration, bind and validate `state`, verify the token issuer/audience, validate identity claims, and never link an existing local account from an unverified email claim. Modern deployments should also use PKCE where appropriate.

## Flag

The runtime flag is injected through the `FLAG` environment variable by `entrypoint.sh`.

The local fallback is:

`NECROX{oauth_trap_default_local_flag}`
