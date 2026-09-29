#!/bin/sh

echo "${FLAG:-NECROX{DEFAULT_CSRF_FLAG}}" > /flag.txt

unset FLAG

exec node server.js
