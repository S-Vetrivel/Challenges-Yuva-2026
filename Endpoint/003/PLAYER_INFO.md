# Web/003 Player Information

## Title

Forgotten Password

## Category

Web / Authentication

## Difficulty

Easy-Medium

## Story

Northstar's identity service handles account recovery.

A security review found that the password-reset workflow may have been implemented incorrectly. Your objective is to obtain access to the administrator account and recover the flag.

## Objective

Recover the flag from the administrator password-reset flow.

## Hints

1. The browser is only the frontend. Look at the API calls it makes.
2. Password recovery has more than one endpoint. Examine what the identity service tells you about an account.
3. The reset timestamp is more useful than it first appears.

## Flag

`CYBERANZEN{forgotten_password_chain}`
