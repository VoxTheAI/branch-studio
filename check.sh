#!/bin/bash
# Extract the app's inline script (last <script> block) and syntax-check it.
set -e
cd "$(dirname "$0")"
START=$(grep -n '^<script>$' index.html | tail -1 | cut -d: -f1)
END=$(grep -n '^</script>$' index.html | tail -1 | cut -d: -f1)
sed -n "$((START+1)),$((END-1))p" index.html > /tmp/bs-app.js
if node --check /tmp/bs-app.js 2>/tmp/bs-syntax.err; then
  echo "SYNTAX OK  (lines $START-$END, $(wc -l < /tmp/bs-app.js) lines of JS)"
else
  echo "SYNTAX ERROR"
  head -12 /tmp/bs-syntax.err
  exit 1
fi
