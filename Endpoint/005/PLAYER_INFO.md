# Web/017 — Internal Courier

## Title

Internal Courier

## Category

Web / SSRF

## Difficulty

Hard

## Description

Northstar Logistics exposes a shipment tracking gateway that retrieves
tracking information from external courier services.

Investigate the application architecture, identify the server-side
request weakness, pivot into the internal courier service, recover the
service credential exposed by a diagnostic endpoint, and access the
restricted administrative report.

## Objective

Reach the restricted internal courier report and recover the flag.

## Hints

1. The tracking gateway makes requests from the server rather than from
   your browser.

2. Once you reach an internal service, enumerate its endpoints instead
   of immediately looking for the flag.

3. A diagnostic or configuration endpoint may reveal credentials used by
   another internal component.

## Flag format

NECROX{...}
