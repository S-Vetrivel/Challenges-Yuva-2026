#!/bin/sh

echo "${FLAG:-NECROX{DEFAULT_LOCAL_FLAG}}" > /flag.txt

unset FLAG

exec node server.js
