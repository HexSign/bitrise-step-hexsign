#!/usr/bin/env bash
#
# HexSign — Fetch Signing Material
#
# Downloads the hexsign CLI from GitHub releases, verifies it, then fetches the
# requested Apple signing material into ${output_dir}. Exposes paths to downloaded
# files as env vars for downstream steps via `envman`.

set -euo pipefail

# ── input validation ────────────────────────────────────────────────────────────

if [[ -z "${certificate_id:-}" && -z "${profile_id:-}" ]]; then
  echo "::error::At least one of \`certificate_id\` or \`profile_id\` must be provided."
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

cert_path=""
cert_password_path=""
profile_path=""

if [[ -n "${certificate_id:-}" ]]; then
  echo "Downloading certificate ${certificate_id}…"
  "${hexsign_bin}" certificates download "${certificate_id}" --output-dir "${output_dir_abs}"
  cert_path="$(find "${output_dir_abs}" -maxdepth 1 -type f -name "*.p12" -print -quit)"
  cert_password_path="$(find "${output_dir_abs}" -maxdepth 1 -type f -name "*.password" -print -quit)"
fi

if [[ -n "${profile_id:-}" ]]; then
  echo "Downloading provisioning profile ${profile_id}…"
  "${hexsign_bin}" profiles download "${profile_id}" --output-dir "${output_dir_abs}"
  profile_path="$(find "${output_dir_abs}" -maxdepth 1 -type f -name "*.mobileprovision" -print -quit)"
fi

# ── expose outputs ──────────────────────────────────────────────────────────────

envman add --key HEXSIGN_CERTIFICATE_PATH          --value "${cert_path}"
envman add --key HEXSIGN_CERTIFICATE_PASSWORD_PATH --value "${cert_password_path}"
envman add --key HEXSIGN_PROFILE_PATH              --value "${profile_path}"

echo ""
echo "✓ Done."
[[ -n "${cert_path}"          ]] && echo "  certificate:          ${cert_path}"
[[ -n "${cert_password_path}" ]] && echo "  certificate password: ${cert_password_path}"
[[ -n "${profile_path}"       ]] && echo "  provisioning profile: ${profile_path}"
