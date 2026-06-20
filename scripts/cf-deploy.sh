#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_PATH="$(bash "${SCRIPT_DIR}/cf-config.sh")"

cd "${REPO_ROOT}"

section_has_key() {
  local section="$1"
  local key="$2"
  local file="$3"

  awk -v section="${section}" -v key="${key}" '
    $0 == "[[" section "]]" { in_section = 1; next }
    /^\[\[/ && $0 != "[[" section "]]" { in_section = 0 }
    in_section && $1 == key {
      gsub(/"/, "", $3)
      if ($3 != "") {
        found = 1
        exit
      }
    }
    END {
      if (found == 1) exit 0
      exit 1
    }
  ' "${file}"
}

if ! section_has_key "d1_databases" "database_id" "${CONFIG_PATH}" \
  || ! section_has_key "r2_buckets" "bucket_name" "${CONFIG_PATH}"; then
  echo "==> concrete D1/R2 bindings missing; initializing Cloudflare resources"
  bash "${SCRIPT_DIR}/cf-init.sh" --site-url="${NEXT_PUBLIC_SITE_URL:-https://xuanmu-blog.workers.dev}"
  CONFIG_PATH="$(bash "${SCRIPT_DIR}/cf-config.sh")"
fi

echo "==> using wrangler config: ${CONFIG_PATH}"
bash "${SCRIPT_DIR}/cf-validate-config.sh" "${CONFIG_PATH}"

rm -rf .next .open-next
npx opennextjs-cloudflare build

echo "==> applying D1 schema"
npx wrangler d1 execute DB \
  --remote \
  --file="${REPO_ROOT}/db/schema.sql" \
  -c "${CONFIG_PATH}"

if [[ -f "${REPO_ROOT}/db/seed-template.sql" ]]; then
  echo "==> applying template defaults"
  npx wrangler d1 execute DB \
    --remote \
    --file="${REPO_ROOT}/db/seed-template.sql" \
    -c "${CONFIG_PATH}"
fi

npx opennextjs-cloudflare deploy -c "${CONFIG_PATH}"
