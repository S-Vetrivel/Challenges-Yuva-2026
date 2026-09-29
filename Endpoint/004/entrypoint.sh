#!/bin/sh

set -eu

echo "${FLAG:-NECROX{oauth_trap_default_local_flag}}" > /flag.txt
unset FLAG

exec node server.js
