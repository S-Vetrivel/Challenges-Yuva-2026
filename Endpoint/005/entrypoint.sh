#!/bin/sh

set -eu

echo "${FLAG:-NECROX{internal_courier_default_flag}}" > /flag.txt
unset FLAG

exec node server.js
