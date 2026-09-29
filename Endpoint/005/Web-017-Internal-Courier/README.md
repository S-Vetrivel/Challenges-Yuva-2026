# Web/017 — Internal Courier

## Metadata

- Title: Internal Courier
- Category: Web / SSRF
- Level: Hard
- Difficulty: Hard
- Access Mode: WEB
- Internal Port: 80

## Scenario

Northstar Logistics operates a shipment tracking gateway that retrieves
tracking information from external carrier systems.

The gateway was introduced during a platform migration and now has access
to an internal courier management service that is not directly exposed
to the Internet.

Your objective is to investigate the tracking application, identify
the server-side request weakness, access the internal courier service,
recover a service credential from an exposed diagnostic endpoint, and
use that credential to access a restricted administrative report.

## Intended attack chain

Public tracking API

-> SSRF

-> internal courier service

-> internal route enumeration

-> configuration disclosure

-> service credential

-> restricted admin report

-> flag

## Public endpoint

POST /api/tracking/import

JSON body:

{
  "url": "https://example.com"
}

The server fetches the supplied URL and returns the upstream response.

## Internal architecture

The public application listens on port 80.

The internal courier service listens on:

127.0.0.1:9001

It is intentionally unreachable directly from outside the container.

The internal service exposes several endpoints which can be discovered
through the SSRF primitive.

## Intended solution

A player should first discover the tracking import endpoint.

The player can then make the public server request an internal address:

http://127.0.0.1:9001/

The internal service exposes useful operational endpoints.

The configuration endpoint reveals a service credential.

That credential can then be supplied to the restricted administrative
report endpoint.

The administrative report contains the challenge flag.

## Learning objectives

- Identify server-side request forgery.
- Understand the difference between public and internal services.
- Enumerate internal HTTP services.
- Recognize secrets exposed through diagnostic configuration endpoints.
- Understand how SSRF can become a multi-stage attack rather than a
  single-request vulnerability.

## Defensive lesson

Production SSRF defenses should not rely only on string-based blocking.

Applications should validate destinations using strict allowlists,
resolve and validate DNS results, prevent access to loopback/private
networks, restrict redirects, and isolate outbound HTTP clients from
sensitive internal services.

Sensitive diagnostic endpoints should also require authentication and
should never expose service credentials.
