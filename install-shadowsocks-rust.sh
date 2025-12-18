#!/usr/bin/env bash
# install-shadowsocks-rust.sh
#
# Minimal, production-friendly installer for shadowsocks-rust (ssserver).
#
# Features:
# - Download ssserver from GitHub releases
# - Multi-port multi-password via --entry NAME:PORT:PASS (repeatable)
# - Single-port via --port PORT --password PASS
# - Generate JSON configs WITHOUT jq/python (strict validation to avoid JSON escaping issues)
# - Create systemd units and enable autostart
# - NO firewall changes, NO dependency auto-install
#
# Fixes included:
# - Robust --entry parsing (no field shifting)
# - systemd unit uses stable minimal settings (avoid sandbox options that can break bind)
# - Optional --force to overwrite existing configs/units
# - Post-install listen verification hints

set -euo pipefail

# -------------------- constants --------------------
SCRIPT_NAME="$(basename "$0")"

BIN_PATH="/usr/local/bin/ssserver"
CONF_DIR="/etc/shadowsocks-rust"
UNIT_DIR="/etc/systemd/system"

SS_USER="shadowsocks"
SS_GROUP="shadowsocks"

# -------------------- defaults --------------------
METHOD=""
MODE="tcp_only"       # tcp_only | tcp_and_udp
TIMEOUT="300"
RELEASE_TAG="latest"

# Multi-port entries: NAME:PORT:PASS
ENTRIES=()

# Single-port fallback
PORT=""
PASSWORD=""

DRY_RUN="false"
FORCE="false"         # overwrite existing config/unit

# -------------------- helpers --------------------
log()  { echo -e "[+] $*"; }
warn() { echo -e "[!] $*" >&2; }
die()  { echo -e "[x] $*" >&2; exit 1; }

has_cmd() { command -v "$1" >/dev/null 2>&1; }

run() {
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] $*"
  else
    eval "$@"
  fi
}

need_root() {
  [[ "${EUID}" -eq 0 ]] || die "Please run as root (sudo)"
}

re_match() { [[ "$1" =~ $2 ]]; }

usage() {
  cat <<'EOF'
Usage:
  sudo ./install-shadowsocks-rust.sh --method chacha20-ietf-poly1305 [options] --entry NAME:PORT:PASS [--entry ...]
  sudo ./install-shadowsocks-rust.sh --method chacha20-ietf-poly1305 --port PORT --password PASS [options]

Required:
  --method <METHOD>              Encryption method (e.g. chacha20-ietf-poly1305)

Choose ONE mode:

A) Multi-port (recommended):
  --entry <NAME:PORT:PASS>       Repeatable. Each entry creates one config + one systemd unit.
                                 Example:
                                   --entry A1:62668:PASS_A1_12345678
                                   --entry A2:62669:PASS_A2_12345678

B) Single-port:
  --port <PORT>                  Listening port
  --password <PASS>              Password

Options:
  --mode <tcp_only|tcp_and_udp>  Default: tcp_only
  --timeout <SECONDS>            Default: 300
  --tag <TAG|latest>             shadowsocks-rust release tag (default: latest)
  --force                        Overwrite existing configs/units with same NAME (or PORT)
  --dry-run                      Print only
  -h, --help                     Show help

Minimal JSON writer input constraints (NO jq/python JSON escaping):
  NAME   : [A-Za-z0-9_-]{1,32}
  PASS   : [A-Za-z0-9._~+=-]{8,128}   (note: ':' not allowed in PASS for --entry)
  METHOD : [A-Za-z0-9._+-]{3,64}

Examples:
  # Multi-port:
  sudo ./install-shadowsocks-rust.sh \
    --method chacha20-ietf-poly1305 \
    --mode tcp_only \
    --entry dmit:62668:A9fL2Qm8R-P3dKX+=Z \
    --entry bgh:62669:R2Q9-m8PLX3ZKAdf+=

  # Single-port:
  sudo ./install-shadowsocks-rust.sh \
    --method chacha20-ietf-poly1305 \
    --port 62666 \
    --password PASS_A1_12345678
EOF
}

# -------------------- arg parse --------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --method) METHOD="${2:-}"; shift 2;;
    --mode) MODE="${2:-}"; shift 2;;
    --timeout) TIMEOUT="${2:-}"; shift 2;;
    --tag) RELEASE_TAG="${2:-}"; shift 2;;

    --entry) ENTRIES+=("${2:-}"); shift 2;;

    --port) PORT="${2:-}"; shift 2;;
    --password) PASSWORD="${2:-}"; shift 2;;

    --force) FORCE="true"; shift 1;;
    --dry-run) DRY_RUN="true"; shift 1;;
    -h|--help) usage; exit 0;;
    *) die "Unknown argument: $1 (use --help)";;
  esac
done

# -------------------- validation --------------------
validate_common() {
  [[ -n "$METHOD" ]] || die "--method is required"
  re_match "$METHOD" '^[A-Za-z0-9._+-]{3,64}$' || die "--method contains unsupported characters"

  case "$MODE" in
    tcp_only|tcp_and_udp) ;;
    *) die "--mode must be tcp_only or tcp_and_udp" ;;
  esac

  re_match "$TIMEOUT" '^[0-9]+$' || die "--timeout must be a number"
}

# Validate one entry and also return parsed fields via global vars
ENTRY_NAME=""
ENTRY_PORT=""
ENTRY_PASS=""

parse_and_validate_entry() {
  local entry="$1"

  # Robust parse into exactly 3 fields. PASS may NOT contain ':' (by design).
  local name port pass
  IFS=':' read -r name port pass <<< "$entry"

  [[ -n "${name:-}" && -n "${port:-}" && -n "${pass:-}" ]] || die "--entry must be NAME:PORT:PASS (got: $entry)"
  # Ensure there isn't a 4th field (meaning PASS contained ':')
  if [[ "$entry" == *:*:*:* ]]; then
    die "--entry PASS must not contain ':' (got: $entry)"
  fi

  re_match "$name" '^[A-Za-z0-9_-]{1,32}$' || die "Entry NAME '$name' invalid (allowed: [A-Za-z0-9_-]{1,32})"
  re_match "$port" '^[0-9]+$' || die "Entry PORT '$port' must be a number"
  (( port >= 1 && port <= 65535 )) || die "Entry PORT '$port' out of range (1..65535)"
  re_match "$pass" '^[A-Za-z0-9._~+=-]{8,128}$' || die "Entry PASS for '$name' invalid (allowed: [A-Za-z0-9._~+=-]{8,128})"

  ENTRY_NAME="$name"
  ENTRY_PORT="$port"
  ENTRY_PASS="$pass"
}

validate_single() {
  [[ -n "$PORT" ]] || die "--port is required for single-port mode"
  [[ -n "$PASSWORD" ]] || die "--password is required for single-port mode"
  re_match "$PORT" '^[0-9]+$' || die "--port must be a number"
  (( PORT >= 1 && PORT <= 65535 )) || die "--port out of range (1..65535)"
  re_match "$PASSWORD" '^[A-Za-z0-9._~+=-]{8,128}$' || die "--password must match [A-Za-z0-9._~+=-]{8,128}"
}

validate_mode_choice() {
  if [[ ${#ENTRIES[@]} -gt 0 ]]; then
    if [[ -n "${PORT}" || -n "${PASSWORD}" ]]; then
      die "Use either multi-port (--entry ...) OR single-port (--port + --password), not both"
    fi
    for e in "${ENTRIES[@]}"; do
      parse_and_validate_entry "$e" >/dev/null
    done
  else
    validate_single
  fi
}

# -------------------- deps --------------------
ensure_deps() {
  has_cmd curl || die "curl not found (install it manually)"
  has_cmd tar  || die "tar not found (install it manually)"
  has_cmd xz   || warn "xz not found; extracting .tar.xz may fail. Install xz/xz-utils."
  has_cmd systemctl || die "systemctl not found (systemd required for this script)"
}

# -------------------- download ssserver --------------------
INSTALL_DIR=""

detect_arch_triple() {
  case "$(uname -m)" in
    x86_64|amd64) echo "x86_64-unknown-linux-gnu" ;;
    aarch64|arm64) echo "aarch64-unknown-linux-gnu" ;;
    *) die "Unsupported architecture: $(uname -m)" ;;
  esac
}

get_latest_tag() {
  local tag
  tag="$(curl -fsSL https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases/latest \
    | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  [[ -n "$tag" ]] || die "Failed to detect latest release tag from GitHub"
  echo "$tag"
}

install_ssserver() {
  local triple tag tmp base1 base2 url1 url2
  triple="$(detect_arch_triple)"
  tag="$RELEASE_TAG"
  [[ "$tag" != "latest" ]] || tag="$(get_latest_tag)"

  tmp="$(mktemp -d)"
  INSTALL_DIR="$tmp"

  base1="shadowsocks-${tag}.${triple}.tar.xz"
  base2="shadowsocks-${tag#v}.${triple}.tar.xz"
  url1="https://github.com/shadowsocks/shadowsocks-rust/releases/download/${tag}/${base1}"
  url2="https://github.com/shadowsocks/shadowsocks-rust/releases/download/${tag}/${base2}"

  log "Downloading ssserver (${tag}, ${triple})"
  if curl -fL --retry 3 --retry-delay 1 -o "${tmp}/pkg.tar.xz" "$url1" >/dev/null 2>&1; then
    :
  elif curl -fL --retry 3 --retry-delay 1 -o "${tmp}/pkg.tar.xz" "$url2" >/dev/null 2>&1; then
    :
  else
    die "Failed to download release asset. Tried:
  - ${url1}
  - ${url2}"
  fi

  run "tar -C '$tmp' -xJf '$tmp/pkg.tar.xz'"

  local bin
  bin="$(find "$tmp" -type f -name ssserver -perm -u+x | head -n1 || true)"
  [[ -n "$bin" ]] || die "ssserver binary not found in release package"

  run "install -m 0755 '$bin' '$BIN_PATH'"
  log "Installed ssserver to $BIN_PATH"
}

cleanup() {
  if [[ -n "${INSTALL_DIR:-}" && -d "${INSTALL_DIR:-}" ]]; then
    rm -rf "${INSTALL_DIR}" || true
  fi
}
trap cleanup EXIT

# -------------------- user / dirs --------------------
create_user_and_dirs() {
  if ! id -u "$SS_USER" >/dev/null 2>&1; then
    log "Creating system user: $SS_USER"
    run "useradd --system --no-create-home --shell /usr/sbin/nologin '$SS_USER'"
  fi
  run "mkdir -p '$CONF_DIR'"
  run "chmod 0755 '$CONF_DIR'"
}

# -------------------- config + systemd --------------------
config_path_for_name() {
  local name="$1"
  echo "${CONF_DIR}/${name}.json"
}

unit_name_for_name() {
  local name="$1"
  echo "ssserver-${name}.service"
}

unit_path_for_name() {
  local name="$1"
  echo "${UNIT_DIR}/$(unit_name_for_name "$name")"
}

write_config_file() {
  local name="$1" port="$2" pass="$3"
  local conf_path
  conf_path="$(config_path_for_name "$name")"

  if [[ -f "$conf_path" && "$FORCE" != "true" ]]; then
    die "Config exists: $conf_path (use --force to overwrite)"
  fi

  log "Writing config: ${conf_path}"
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] would write ${conf_path}"
    return 0
  fi

  cat > "$conf_path" <<EOF
{
  "server": "0.0.0.0",
  "server_port": ${port},
  "method": "${METHOD}",
  "mode": "${MODE}",
  "timeout": ${TIMEOUT},
  "password": "${pass}",
  "log": { "level": "warn" }
}
EOF

  chmod 0644 "$conf_path"
}

write_unit_file() {
  local name="$1"
  local conf_path unit_path unit_name
  conf_path="$(config_path_for_name "$name")"
  unit_path="$(unit_path_for_name "$name")"
  unit_name="$(unit_name_for_name "$name")"

  if [[ -f "$unit_path" && "$FORCE" != "true" ]]; then
    die "Unit exists: $unit_path (use --force to overwrite)"
  fi

  log "Writing systemd unit: ${unit_name}"
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] would write ${unit_path}"
    return 0
  fi

  # IMPORTANT:
  # Use a stable minimal unit.
  # Avoid sandbox options that can lead to "running but not listening" on some systems.
  cat > "$unit_path" <<EOF
[Unit]
Description=Shadowsocks Rust Server (${name})
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${SS_USER}
Group=${SS_GROUP}
ExecStart=${BIN_PATH} -c ${conf_path}
Restart=on-failure
RestartSec=2
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

  chmod 0644 "$unit_path"
}

enable_start_unit() {
  local name="$1"
  local unit
  unit="$(unit_name_for_name "$name")"
  run "systemctl daemon-reload"
  run "systemctl enable --now '${unit}'"
}

# -------------------- verification --------------------
verify_listen() {
  local port="$1" name="$2"

  # If ss exists, try to check listening
  if has_cmd ss; then
    if ss -lnt 2>/dev/null | grep -qE "[:.]${port}\b"; then
      log "Listen check OK: port ${port} (unit ${name})"
      return 0
    fi
  fi

  # Fallback to nc if available
  if has_cmd nc; then
    if nc -vz 127.0.0.1 "$port" >/dev/null 2>&1; then
      log "Connect check OK: 127.0.0.1:${port} (unit ${name})"
      return 0
    fi
  fi

  warn "Could not confirm listening on port ${port} automatically."
  warn "Run these to confirm:"
  warn "  sudo ss -lnt | grep ${port}"
  warn "  nc -vz 127.0.0.1 ${port}"
  warn "  sudo journalctl -u 'ssserver-${name}' -n 80 --no-pager"
  return 1
}

# -------------------- main --------------------
main() {
  need_root
  validate_common
  validate_mode_choice
  ensure_deps

  log "Starting install (dry-run=${DRY_RUN}, force=${FORCE})"
  install_ssserver
  create_user_and_dirs

  if [[ ${#ENTRIES[@]} -gt 0 ]]; then
    for entry in "${ENTRIES[@]}"; do
      parse_and_validate_entry "$entry"
      local name="$ENTRY_NAME"
      local port="$ENTRY_PORT"
      local pass="$ENTRY_PASS"

      write_config_file "$name" "$port" "$pass"
      write_unit_file "$name"
      enable_start_unit "$name"

      # Verify (best-effort, non-fatal)
      verify_listen "$port" "$name" || true
    done
  else
    # Single-port mode => use name = port (avoids collisions, consistent unit naming)
    local name="$PORT"
    write_config_file "$name" "$PORT" "$PASSWORD"
    write_unit_file "$name"
    enable_start_unit "$name"
    verify_listen "$PORT" "$name" || true
  fi

  echo
  log "Done."
  echo "  ssserver binary : ${BIN_PATH}"
  echo "  config dir      : ${CONF_DIR}"
  echo "  method          : ${METHOD}"
  echo "  mode            : ${MODE}"
  echo
  echo "Useful commands:"
  echo "  systemctl list-units 'ssserver-*' --no-pager"
  echo "  journalctl -u 'ssserver-*' -f"
  echo "  ss -lnt | grep -E 'PORT1|PORT2'   # replace with your ports"
}

main
