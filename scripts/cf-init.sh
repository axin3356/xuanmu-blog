#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEMPLATE_PATH="${REPO_ROOT}/wrangler.toml"
LOCAL_CONFIG_PATH="${REPO_ROOT}/wrangler.local.toml"
DB_NAME="${CF_D1_NAME:-xuanmu-blog-db}"
R2_NAME="${CF_R2_NAME:-xuanmu-blog-images}"
KV_NAME="${CF_KV_NAME:-xuanmu-blog-cache}"
SITE_URL="${SITE_URL:-${NEXT_PUBLIC_SITE_URL:-https://your-domain.com}}"
SEED_TEMPLATE_PATH="${REPO_ROOT}/db/seed-template.sql"
WITH_KV=0

for arg in "$@"; do
  case "$arg" in
    --with-kv)
      WITH_KV=1
      ;;
    --site-url=*)
      SITE_URL="${arg#*=}"
      ;;
    --db-name=*)
      DB_NAME="${arg#*=}"
      ;;
    --r2-name=*)
      R2_NAME="${arg#*=}"
      ;;
    --kv-name=*)
      KV_NAME="${arg#*=}"
      ;;
    *)
      echo "Unknown argument: ${arg}" >&2
      echo "Usage: npm run cf:init -- [--with-kv] [--site-url=https://your-domain.com] [--db-name=qiaomu-blog-db] [--r2-name=qiaomu-blog-images] [--kv-name=qiaomu-blog-cache]" >&2
      exit 1
      ;;
  esac
done

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

strip_array_section() {
  local section="$1"
  local file="$2"
  local tmp_file

  tmp_file="$(mktemp)"

  awk -v section="${section}" '
    $0 == "[[" section "]]" {
      skip = 1
      next
    }
    skip && /^\[\[/ {
      skip = 0
    }
    !skip {
      print
    }
  ' "${file}" > "${tmp_file}"

  mv "${tmp_file}" "${file}"
}

append_d1_binding() {
  local file="$1"
  local database_id="$2"

  cat >> "${file}" <<EOF

[[d1_databases]]
binding = "DB"
database_name = "${DB_NAME}"
database_id = "${database_id}"
EOF
}

append_r2_binding() {
  local file="$1"

  cat >> "${file}" <<EOF

[[r2_buckets]]
binding = "IMAGES"
bucket_name = "${R2_NAME}"
EOF
}

find_d1_database_id() {
  local info_json=""
  local list_json=""

  if info_json="$(npx wrangler d1 info "${DB_NAME}" --json -c "${LOCAL_CONFIG_PATH}" 2>/dev/null)"; then
    DB_NAME="${DB_NAME}" node -e '
const data = JSON.parse(process.argv[1])
const candidates = [data, data.result, data.database].filter(Boolean)
const match = candidates.find((row) => row.name === process.env.DB_NAME || row.database_name === process.env.DB_NAME) || candidates[0]
if (match) process.stdout.write(match.uuid || match.id || match.database_id || "")
' "${info_json}"
    return
  fi

  list_json="$(npx wrangler d1 list --json -c "${LOCAL_CONFIG_PATH}")"
  DB_NAME="${DB_NAME}" node -e '
const data = JSON.parse(process.argv[1])
const rows = Array.isArray(data)
  ? data
  : Array.isArray(data.result)
    ? data.result
    : Array.isArray(data.databases)
      ? data.databases
      : []
const match = rows.find((row) => row.name === process.env.DB_NAME || row.database_name === process.env.DB_NAME)
if (match) process.stdout.write(match.uuid || match.id || match.database_id || "")
' "${list_json}"
}

create_or_reuse_d1_database() {
  local existing_database_id

  existing_database_id="$(find_d1_database_id)"
  if [[ -n "${existing_database_id}" ]]; then
    echo "==> reusing existing D1 database: ${DB_NAME}"
    append_d1_binding "${LOCAL_CONFIG_PATH}" "${existing_database_id}"
    return
  fi

  if npx wrangler d1 create "${DB_NAME}" \
    --binding DB \
    --use-remote \
    --update-config \
    -c "${LOCAL_CONFIG_PATH}"; then
    return
  fi

  existing_database_id="$(find_d1_database_id)"
  if [[ -n "${existing_database_id}" ]]; then
    echo "==> D1 database already exists; reusing: ${DB_NAME}"
    append_d1_binding "${LOCAL_CONFIG_PATH}" "${existing_database_id}"
    return
  fi

  echo "❌ Failed to create or find D1 database: ${DB_NAME}" >&2
  exit 1
}

bucket_exists() {
  npx wrangler r2 bucket list -c "${LOCAL_CONFIG_PATH}" | grep -Fq "${R2_NAME}"
}

create_or_reuse_r2_bucket() {
  if bucket_exists; then
    echo "==> reusing existing R2 bucket: ${R2_NAME}"
    append_r2_binding "${LOCAL_CONFIG_PATH}"
    return
  fi

  if npx wrangler r2 bucket create "${R2_NAME}" \
    --binding IMAGES \
    --update-config \
    -c "${LOCAL_CONFIG_PATH}"; then
    return
  fi

  if bucket_exists; then
    echo "==> R2 bucket already exists; reusing: ${R2_NAME}"
    append_r2_binding "${LOCAL_CONFIG_PATH}"
    return
  fi

  echo "❌ Failed to create or find R2 bucket: ${R2_NAME}" >&2
  exit 1
}

cd "${REPO_ROOT}"

if ! npx wrangler whoami >/dev/null 2>&1; then
  echo "❌ 未登录 Cloudflare，请先运行: npx wrangler login"
  exit 1
fi

if [[ ! -f "${LOCAL_CONFIG_PATH}" ]]; then
  cp "${TEMPLATE_PATH}" "${LOCAL_CONFIG_PATH}"
  echo "==> created local config: ${LOCAL_CONFIG_PATH}"
else
  echo "==> reusing local config: ${LOCAL_CONFIG_PATH}"
fi

site_url_override="${SITE_URL}" perl -0pi -e 's/NEXT_PUBLIC_SITE_URL = ".*?"/NEXT_PUBLIC_SITE_URL = "$ENV{site_url_override}"/g' "${LOCAL_CONFIG_PATH}"

if ! section_has_key "d1_databases" "database_id" "${LOCAL_CONFIG_PATH}"; then
  if grep -Eq '^\[\[d1_databases\]\]' "${LOCAL_CONFIG_PATH}"; then
    strip_array_section "d1_databases" "${LOCAL_CONFIG_PATH}"
  fi

  create_or_reuse_d1_database
fi

if ! section_has_key "r2_buckets" "bucket_name" "${LOCAL_CONFIG_PATH}"; then
  if grep -Eq '^\[\[r2_buckets\]\]' "${LOCAL_CONFIG_PATH}"; then
    strip_array_section "r2_buckets" "${LOCAL_CONFIG_PATH}"
  fi

  create_or_reuse_r2_bucket
fi

if [[ "${WITH_KV}" == "1" ]] && ! grep -Eq '^\[\[kv_namespaces\]\]' "${LOCAL_CONFIG_PATH}"; then
  npx wrangler kv namespace create "${KV_NAME}" \
    --binding CACHE \
    --update-config \
    -c "${LOCAL_CONFIG_PATH}"
fi

npx wrangler d1 execute DB \
  --remote \
  --file="${REPO_ROOT}/db/schema.sql" \
  -c "${LOCAL_CONFIG_PATH}"

if [[ -f "${SEED_TEMPLATE_PATH}" ]]; then
  npx wrangler d1 execute DB \
    --remote \
    --file="${SEED_TEMPLATE_PATH}" \
    -c "${LOCAL_CONFIG_PATH}"
fi

cat <<EOF
✅ Cloudflare 基础资源初始化完成

当前配置文件:
  ${LOCAL_CONFIG_PATH}

下一步:
  1. 配置本地环境变量: cp .env.example .env.local
  2. 设置线上 secrets:
     npx wrangler secret put ADMIN_PASSWORD -c ${LOCAL_CONFIG_PATH}
     npx wrangler secret put ADMIN_TOKEN_SALT -c ${LOCAL_CONFIG_PATH}
     npx wrangler secret put AI_CONFIG_ENCRYPTION_SECRET -c ${LOCAL_CONFIG_PATH}
     npx wrangler secret put AI_API_KEY -c ${LOCAL_CONFIG_PATH}   # 如果你要启用 AI
  3. 首次初始化已写入默认主题、字体和导航
  4. 生成类型: npm run cf-typegen
  5. 部署: npm run deploy
EOF
