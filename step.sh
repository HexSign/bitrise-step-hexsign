#!/usr/bin/env bash
#
# HexSign — Fetch Signing Material
#
# Downloads the hexsign CLI from GitHub releases, verifies it, then fetches the
# requested Apple signing material into ${output_dir}. Exposes paths to downloaded
# files as env vars for downstream steps via `envman`.

set -euo pipefail

# ── input validation ────────────────────────────────────────────────────────────

if [[ -z "${certificate_id:-}" && -z "${certificate_type:-}" && -z "${profile_id:-}" && -z "${bundle_id:-}" ]]; then
  echo "::error::At least one of \`certificate_id\`, \`certificate_type\`, \`profile_id\`, or \`bundle_id\` must be provided."
  exit 1
fi

if [[ -n "${certificate_id:-}" && -n "${certificate_type:-}" ]]; then
  echo "::error::\`certificate_id\` and \`certificate_type\` are mutually exclusive."
  exit 1
fi

if [[ -n "${certificate_type:-}" && -z "${team_id:-}" ]]; then
  echo "::error::\`certificate_type\` requires \`team_id\`."
  exit 1
fi

if [[ -n "${profile_id:-}" && -n "${bundle_id:-}" ]]; then
  echo "::error::\`profile_id\` and \`bundle_id\` are mutually exclusive."
  exit 1
fi

if [[ -z "${client_id:-}" || -z "${client_secret:-}" ]]; then
  echo "::error::Both \`client_id\` and \`client_secret\` are required."
  exit 1
fi

mkdir -p "${output_dir}"
output_dir_abs="$(cd "${output_dir}" && pwd)"

# ── platform detection ──────────────────────────────────────────────────────────

case "$(uname -s)" in
  Darwin) os=darwin ;;
  Linux)  os=linux ;;
  *) echo "::error::Unsupported OS: $(uname -s)"; exit 1 ;;
esac

case "$(uname -m)" in
  x86_64|amd64) arch=amd64 ;;
  arm64|aarch64) arch=arm64 ;;
  *) echo "::error::Unsupported arch: $(uname -m)"; exit 1 ;;
esac

# ── resolve CLI version ─────────────────────────────────────────────────────────

cli_version_resolved="${cli_version}"
if [[ "${cli_version_resolved}" == "latest" || -z "${cli_version_resolved}" ]]; then
  echo "Resolving latest hexsign-cli release…"
  cli_version_resolved="$(curl -fsSL \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/hexsign/hexsign-cli/releases/latest" \
    | jq -r .tag_name)"
fi
version_no_v="${cli_version_resolved#v}"
echo "Using hexsign CLI ${cli_version_resolved}"

# ── download + verify CLI ───────────────────────────────────────────────────────

asset="hexsign_${version_no_v}_${os}_${arch}.tar.gz"
base_url="https://github.com/hexsign/hexsign-cli/releases/download/${cli_version_resolved}"

workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT
cd "${workdir}"

echo "Downloading ${asset}…"
curl -fsSL -o "${asset}"        "${base_url}/${asset}"
curl -fsSL -o "checksums.txt"   "${base_url}/checksums.txt"

echo "Verifying SHA-256…"
if command -v sha256sum >/dev/null 2>&1; then
  grep " ${asset}$" checksums.txt | sha256sum -c -
else
  grep " ${asset}$" checksums.txt | shasum -a 256 -c -
fi

tar -xzf "${asset}"
chmod +x hexsign
hexsign_bin="${workdir}/hexsign"
"${hexsign_bin}" --version || true

# ── fetch signing material ──────────────────────────────────────────────────────

export HEXSIGN_CLIENT_ID="${client_id}"
export HEXSIGN_CLIENT_SECRET="${client_secret}"
if [[ -n "${scopes:-}" ]]; then
  export HEXSIGN_CLIENT_SCOPES="${scopes}"
fi

# Download via the CLI; afterwards enumerate the output directory so single-id
# and bulk modes share one path-collection branch.
if [[ -n "${certificate_id:-}" ]]; then
  echo "Downloading certificate ${certificate_id}…"
  "${hexsign_bin}" certificates download "${certificate_id}" --output-dir "${output_dir_abs}"
elif [[ -n "${certificate_type:-}" ]]; then
  echo "Downloading every ${certificate_type} certificate for team ${team_id}…"
  "${hexsign_bin}" certificates download \
    --type "${certificate_type}" --team-id "${team_id}" \
    --output-dir "${output_dir_abs}"
fi

if [[ -n "${profile_id:-}" ]]; then
  echo "Downloading provisioning profile ${profile_id}…"
  "${hexsign_bin}" profiles download "${profile_id}" --output-dir "${output_dir_abs}"
elif [[ -n "${bundle_id:-}" ]]; then
  if [[ -n "${team_id:-}" ]]; then
    echo "Downloading every profile for bundle ${bundle_id} (team ${team_id})…"
    "${hexsign_bin}" profiles download \
      --bundle-id "${bundle_id}" --team-id "${team_id}" \
      --output-dir "${output_dir_abs}"
  else
    echo "Downloading every profile for bundle ${bundle_id}…"
    "${hexsign_bin}" profiles download \
      --bundle-id "${bundle_id}" \
      --output-dir "${output_dir_abs}"
  fi
fi

cert_paths=()
cert_password_paths=()
profile_paths=()

if [[ -n "${certificate_id:-}" || -n "${certificate_type:-}" ]]; then
  while IFS= read -r line; do cert_paths+=("${line}"); done \
    < <(find "${output_dir_abs}" -maxdepth 1 -type f -name "*.p12" | sort)
  while IFS= read -r line; do cert_password_paths+=("${line}"); done \
    < <(find "${output_dir_abs}" -maxdepth 1 -type f -name "*.password" | sort)
fi

if [[ -n "${profile_id:-}" || -n "${bundle_id:-}" ]]; then
  while IFS= read -r line; do profile_paths+=("${line}"); done \
    < <(find "${output_dir_abs}" -maxdepth 1 -type f -name "*.mobileprovision" | sort)
fi

# ── expose outputs ──────────────────────────────────────────────────────────────

join_lines() { printf "%s\n" "$@" | sed '/^$/d'; }

first_or_empty() {
  if [[ $# -ge 1 ]]; then printf "%s" "$1"; else printf ""; fi
}

cert_first="$(first_or_empty "${cert_paths[@]+"${cert_paths[@]}"}")"
cert_password_first="$(first_or_empty "${cert_password_paths[@]+"${cert_password_paths[@]}"}")"
profile_first="$(first_or_empty "${profile_paths[@]+"${profile_paths[@]}"}")"

cert_all="$(join_lines "${cert_paths[@]+"${cert_paths[@]}"}")"
cert_password_all="$(join_lines "${cert_password_paths[@]+"${cert_password_paths[@]}"}")"
profile_all="$(join_lines "${profile_paths[@]+"${profile_paths[@]}"}")"

envman add --key HEXSIGN_CERTIFICATE_PATH           --value "${cert_first}"
envman add --key HEXSIGN_CERTIFICATE_PASSWORD_PATH  --value "${cert_password_first}"
envman add --key HEXSIGN_PROFILE_PATH               --value "${profile_first}"
envman add --key HEXSIGN_CERTIFICATE_PATHS          --value "${cert_all}"
envman add --key HEXSIGN_CERTIFICATE_PASSWORD_PATHS --value "${cert_password_all}"
envman add --key HEXSIGN_PROFILE_PATHS              --value "${profile_all}"

echo ""
echo "✓ Done."
[[ ${#cert_paths[@]}          -gt 0 ]] && echo "  certificates (${#cert_paths[@]}):          ${cert_first}"
[[ ${#cert_password_paths[@]} -gt 0 ]] && echo "  certificate passwords (${#cert_password_paths[@]}): ${cert_password_first}"
[[ ${#profile_paths[@]}       -gt 0 ]] && echo "  provisioning profiles (${#profile_paths[@]}):       ${profile_first}"
