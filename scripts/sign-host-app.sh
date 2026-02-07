#!/usr/bin/env bash
set -euo pipefail

HOST_APP_PATH="${HOME}/Applications/macos-mcp-operator-host.app"
DEFAULT_TEAM_ID="MW4GWYGX56"
TEAM_ID="${MACOS_TEAM_ID:-${1:-${DEFAULT_TEAM_ID}}}"
IDENTITY="${MACOS_CODESIGN_IDENTITY:-}"

if [[ ! -d "${HOST_APP_PATH}" ]]; then
  echo "Host app not found at ${HOST_APP_PATH}. Run scripts/package-host-app.sh first." >&2
  exit 1
fi

if [[ -z "${IDENTITY}" ]]; then
  IDENTITIES_OUTPUT="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  if [[ -n "${TEAM_ID}" ]]; then
    IDENTITY="$(
      echo "${IDENTITIES_OUTPUT}" \
        | grep "(${TEAM_ID})" \
        | sed -E 's/^[[:space:]]*[0-9]+\) ([A-F0-9]+) "([^"]+)".*/\2/' \
        | head -n 1 \
        || true
    )"
  fi

  if [[ -z "${IDENTITY}" ]]; then
    IDENTITY="$(
      echo "${IDENTITIES_OUTPUT}" \
        | grep "Apple Development" \
        | sed -E 's/^[[:space:]]*[0-9]+\) ([A-F0-9]+) "([^"]+)".*/\2/' \
        | head -n 1 \
        || true
    )"
  fi
fi

if [[ -z "${IDENTITY}" ]]; then
  IDENTITY="-"
  echo "Warning: no signing identity found. Using ad-hoc signature; TCC stability may be reduced." >&2
fi

codesign --force --deep --options runtime --sign "${IDENTITY}" "${HOST_APP_PATH}"
codesign --verify --deep --strict --verbose=2 "${HOST_APP_PATH}"

echo "Signed host app: ${HOST_APP_PATH}"
echo "Identity: ${IDENTITY}"
echo "TeamID hint: ${TEAM_ID}"
