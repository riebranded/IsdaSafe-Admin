#!/usr/bin/env bash
# Vercel build entrypoint for the admin panel (same approach as the farmer
# app's vercel-build.sh). Vercel's build image has no Flutter SDK, so we fetch
# it, then write the gitignored .env asset (see pubspec.yaml `assets: - .env`)
# from the project's Vercel Environment Variables before building.
set -euo pipefail

FLUTTER_VERSION="3.44.1"

cat > .env <<EOF
SUPABASE_URL=${SUPABASE_URL:-}
SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY:-}
TURNSTILE_SITE_KEY=${TURNSTILE_SITE_KEY:-}
GOOGLE_WEB_CLIENT_ID=${GOOGLE_WEB_CLIENT_ID:-}
EOF

git clone https://github.com/flutter/flutter.git --depth 1 --branch "$FLUTTER_VERSION" _flutter
export PATH="$PATH:$(pwd)/_flutter/bin"

flutter config --enable-web
flutter pub get
flutter build web --release
