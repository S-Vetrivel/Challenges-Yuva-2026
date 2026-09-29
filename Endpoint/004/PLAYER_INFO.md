# Web/021 — OAuth Trap

**Story:** Northstar's customer portal uses a legacy OAuth migration that contains redirect and account-linking mistakes.

**Objective:** Reconstruct the OAuth flow, obtain an administrator session through the vulnerable account-linking logic, and recover the flag.

**Hints:**

1. OAuth metadata and client configuration can reveal endpoints the frontend does not advertise.
2. Compare the redirect destination expected by the client with the destination the authorization server actually accepts.
3. The provider returns `email_verified: false`. Check whether the application enforces it.

**Flag format:** `NECROX{...}`
