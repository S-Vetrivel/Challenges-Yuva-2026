#!/bin/sh
set -eu

export PORT="${PORT:-3000}"
export FLAG="${FLAG:-CYBERANZEN{forgotten_password_chain}}"

exec node /app/server.js
