#!/usr/bin/env bash
# install-shadowsocks-rust.sh
#
# Minimal installer/manager for shadowsocks-rust (ssserver).
#
# - Download ssserver from GitHub releases
# - Multi-port multi-password: --entry NAME:PORT:PASS (repeatable)
# - Single-port: --port PORT --password PASS
# - Write JSON configs without jq/python (strict validation)
# - Create systemd units: ssserver-<NAME>.service (enabled + started)
# - Manage: --list / --remove <NAME>
#
# Notes:
# - No firewall changes
# - No dependency auto-install
# - NO "log" field by default (to avoid CONFIG issues); optional --log-level

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"

BIN_PATH="/usr/local/bin/ssserver"
CONF_DIR="/etc/shadowsocks-rust"
UNIT_DIR="/etc/systemd/system"

SS_USER="shadowsocks"
SS_GROUP="shadowsocks"

# Defaults
METHOD=""
MODE="tcp_only"
TIMEOUT="300"
RELEASE_TAG="latest"

# Optional: write log only if explicitly provided
LOG_LEVEL=""

# Install inputs
ENTRIES=()            # NAME:PORT:PASS
PORT=""               # single-port
PASSWORD=""           # single-port

# Ops
ACTION="install"      # install | list | remove
REMOVE_NAME=""

DRY_RUN="false"
FORCE="false"

# ---------- helpers ----------
log()  { echo -e "[+] $*"; }
warn() { echo -e "[!] $*"; }
die()  { echo -e "[x] $*" >&2; exit 1; }

has_cmd() { command -v "$1" >/dev/null 2>&1; }

run() {
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] $*"
  else
    eval "$@"
  fi
}

need_root() { [[ "${EUID}" -eq 0 ]] || die "Please run as root (sudo)"; }
re_match() { [[ "$1" =~ $2 ]]; }

usage() {
  cat <<'EOF'
Usage:

  # Install (multi-port):
  sudo ./install-shadowsocks-rust.sh --method chacha20-ietf-poly1305 \
    --entry NAME:PORT:PASS [--entry ...] [options]

  # Install (single-port):
  sudo ./install-shadowsocks-rust.sh --method chacha20-ietf-poly1305 \
    --port PORT --password PASS [options]

  # List instances:
  sudo ./install-shadowsocks-rust.sh --list

  # Remove one instance:
  sudo ./install-shadowsocks-rust.sh --remove NAME

Required for install:
  --method <METHOD>

Choose ONE install mode:
  A) Multi-port:  --entry <NAME:PORT:PASS> (repeatable)
  B) Single-port: --port <PORT> --password <PASS>

Options:
  --mode <tcp_only|tcp_and_udp>  Default: tcp_only
  --timeout <SECONDS>            Default: 300
  --tag <TAG|latest>             Release tag (default: latest)
  --log-level <LEVEL>            Optional: error|warn|info|debug|trace (default: unset => no "log" field written)
  --force                        Overwrite existing config/unit with same NAME (or PORT)
  --dry-run                      Print only
  -h, --help                     Help

Input constraints (no jq/python JSON escaping):
  NAME   : [A-Za-z0-9_-]{1,32}
  PASS   : [A-Za-z0-9._~+=-]{8,128}  (PASS must NOT contain ':')
  METHOD : [A-Za-z0-9._+-]{3,64}

Tip:
  Always wrap --entry in single quotes.

EOF
}

# ---------- arg parse ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --method) METHOD="${2:-}"; shift 2;;
    --mode) MODE="${2:-}"; shift 2;;
    --timeout) TIMEOUT="${2:-}"; shift 2;;
    --tag) RELEASE_TAG="${2:-}"; shift 2;;
    --log-level) LOG_LEVEL="${2:-}"; shift 2;;

    --entry) ENTRIES+=("${2:-}"); shift 2;;
    --port) PORT="${2:-}"; shift 2;;
    --password) PASSWORD="${2:-}"; shift 2;;

    --list) ACTION="list"; shift 1;;
    --remove) ACTION="remove"; REMOVE_NAME="${2:-}"; shift 2;;

    --force) FORCE="true"; shift 1;;
    --dry-run) DRY_RUN="true"; shift 1;;
    -h|--help) usage; exit 0;;
    *) die "Unknown argument: $1 (use --help)";;
  esac
done

# ---------- validation ----------
validate_common_install() {
  [[ -n "$METHOD" ]] || die "--method is required for install"
  re_match "$METHOD" '^[A-Za-z0-9._+-]{3,64}$' || die "--method contains unsupported characters"

  case "$MODE" in tcp_only|tcp_and_udp) ;; *) die "--mode must be tcp_only or tcp_and_udp" ;; esac
  re_match "$TIMEOUT" '^[0-9]+$' || die "--timeout must be a number"

  if [[ -n "$LOG_LEVEL" ]]; then
    case "$LOG_LEVEL" in error|warn|info|debug|trace) ;; *) die "--log-level must be one of error|warn|info|debug|trace" ;; esac
  fi
}

ENTRY_NAME="" ENTRY_PORT="" ENTRY_PASS=""
parse_and_validate_entry() {
  local entry="$1"
  local name port pass

  IFS=':' read -r name port pass <<< "$entry"
  [[ -n "${name:-}" && -n "${port:-}" && -n "${pass:-}" ]] || die "--entry must be NAME:PORT:PASS (got: $entry)"
  [[ "$entry" != *:*:*:* ]] || die "--entry PASS must not contain ':' (got: $entry)"

  re_match "$name" '^[A-Za-z0-9_-]{1,32}$' || die "Entry NAME '$name' invalid"
  re_match "$port" '^[0-9]+$' || die "Entry PORT '$port' must be a number"
  (( port >= 1 && port <= 65535 )) || die "Entry PORT '$port' out of range (1..65535)"
  re_match "$pass" '^[A-Za-z0-9._~+=-]{8,128}$' || die "Entry PASS for '$name' invalid"

  ENTRY_NAME="$name"
  ENTRY_PORT="$port"
  ENTRY_PASS="$pass"
}

validate_single_install() {
  [[ -n "$PORT" ]] || die "--port is required for single-port mode"
  [[ -n "$PASSWORD" ]] || die "--password is required for single-port mode"
  re_match "$PORT" '^[0-9]+$' || die "--port must be a number"
  (( PORT >= 1 && PORT <= 65535 )) || die "--port out of range"
  re_match "$PASSWORD" '^[A-Za-z0-9._~+=-]{8,128}$' || die "--password invalid"
}

validate_install_choice() {
  if [[ ${#ENTRIES[@]} -gt 0 ]]; then
    [[ -z "$PORT" && -z "$PASSWORD" ]] || die "Use either --entry... OR --port+--password, not both"
    for e in "${ENTRIES[@]}"; do parse_and_validate_entry "$e" >/dev/null; done
  else
    validate_single_install
  fi
}

validate_remove() {
  [[ -n "$REMOVE_NAME" ]] || die "--remove requires NAME"
  re_match "$REMOVE_NAME" '^[A-Za-z0-9_-]{1,32}$' || die "Remove NAME invalid"
}

# ---------- deps ----------
ensure_deps() {
  has_cmd systemctl || die "systemctl not found (systemd required)"
  case "$ACTION" in
    list|remove) return 0;;
    install)
      has_cmd curl || die "curl not found"
      has_cmd tar  || die "tar not found"
      has_cmd xz   || warn "xz not found; extracting .tar.xz may fail (install xz/xz-utils)"
      ;;
  esac
}

# ---------- download ssserver ----------
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
  [[ -n "$tag" ]] || die "Failed to detect latest release tag"
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
    die "Failed to download release asset"
  fi

  run "tar -C '$tmp' -xJf '$tmp/pkg.tar.xz'"

  local bin
  bin="$(find "$tmp" -type f -name ssserver -perm -u+x | head -n1 || true)"
  [[ -n "$bin" ]] || die "ssserver binary not found in package"

  run "install -m 0755 '$bin' '$BIN_PATH'"
  log "Installed ssserver to $BIN_PATH"
}

cleanup() { [[ -n "${INSTALL_DIR:-}" && -d "${INSTALL_DIR:-}" ]] && rm -rf "${INSTALL_DIR}" || true; }
trap cleanup EXIT

# ---------- user/dirs ----------
create_user_and_dirs() {
  if ! id -u "$SS_USER" >/dev/null 2>&1; then
    log "Creating system user: $SS_USER"
    run "useradd --system --no-create-home --shell /usr/sbin/nologin '$SS_USER'"
  fi
  run "mkdir -p '$CONF_DIR'"
  run "chmod 0755 '$CONF_DIR'"
}

# ---------- paths ----------
config_path_for_name() { echo "${CONF_DIR}/${1}.json"; }
unit_name_for_name() { echo "ssserver-${1}.service"; }
unit_path_for_name() { echo "${UNIT_DIR}/$(unit_name_for_name "$1")"; }

# ---------- write config (NO log by default) ----------
write_config_file() {
  local name="$1" port="$2" pass="$3"
  local conf_path; conf_path="$(config_path_for_name "$name")"

  if [[ -f "$conf_path" && "$FORCE" != "true" ]]; then
    die "Config exists: $conf_path (use --force to overwrite)"
  fi

  log "Writing config: ${conf_path}"
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] would write ${conf_path}"
    return 0
  fi

  {
    echo "{"
    echo "  \"server\": \"0.0.0.0\","
    echo "  \"server_port\": ${port},"
    echo "  \"method\": \"${METHOD}\","
    echo "  \"mode\": \"${MODE}\","
    echo "  \"timeout\": ${TIMEOUT},"
    echo -n "  \"password\": \"${pass}\""
    if [[ -n "$LOG_LEVEL" ]]; then
      echo ","
      echo "  \"log\": { \"level\": \"${LOG_LEVEL}\" }"
    else
      echo
    fi
    echo "}"
  } > "$conf_path"

  chmod 0644 "$conf_path"
}

# ---------- write unit (stable minimal) ----------
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
  local unit; unit="$(unit_name_for_name "$name")"
  run "systemctl daemon-reload"
  run "systemctl enable --now '${unit}'"
}

verify_listen_best_effort() {
  local port="$1" name="$2"
  if has_cmd ss && ss -lnt 2>/dev/null | grep -qE "[:.]${port}\b"; then
    log "Listen OK: ${port} (${name})"
    return 0
  fi
  if has_cmd nc && nc -vz 127.0.0.1 "$port" >/dev/null 2>&1; then
    log "Connect OK: 127.0.0.1:${port} (${name})"
    return 0
  fi
  warn "Could not auto-confirm listening on ${port} (${name}). Check:"
  warn "  sudo journalctl -u 'ssserver-${name}' -n 120 --no-pager"
  warn "  sudo ss -lnt | grep ${port}"
  warn "  nc -vz 127.0.0.1 ${port}"
  return 1
}

# ---------- list/remove ----------
do_list() {
  [[ -d "$CONF_DIR" ]] || { echo "No config dir: $CONF_DIR"; exit 0; }
  shopt -s nullglob
  local files=("$CONF_DIR"/*.json)
  if [[ ${#files[@]} -eq 0 ]]; then
    echo "No instances found in $CONF_DIR"
    exit 0
  fi

  printf "%-16s %-8s %-28s %-12s %-8s\n" "NAME" "PORT" "METHOD" "MODE" "TIMEOUT"
  printf "%-16s %-8s %-28s %-12s %-8s\n" "----" "----" "------" "----" "-------"

  for f in "${files[@]}"; do
    local name port method mode timeout
    name="$(basename "$f" .json)"
    port="$(sed -n 's/.*"server_port":[[:space:]]*\([0-9]\+\).*/\1/p' "$f" | head -n1)"
    method="$(sed -n 's/.*"method":[[:space:]]*"\([^"]\+\)".*/\1/p' "$f" | head -n1)"
    mode="$(sed -n 's/.*"mode":[[:space:]]*"\([^"]\+\)".*/\1/p' "$f" | head -n1)"
    timeout="$(sed -n 's/.*"timeout":[[:space:]]*\([0-9]\+\).*/\1/p' "$f" | head -n1)"
    printf "%-16s %-8s %-28s %-12s %-8s\n" "$name" "${port:-?}" "${method:-?}" "${mode:-?}" "${timeout:-?}"
  done
}

do_remove() {
  validate_remove
  local name="$REMOVE_NAME"
  local conf_path unit_path unit_name
  conf_path="$(config_path_for_name "$name")"
  unit_path="$(unit_path_for_name "$name")"
  unit_name="$(unit_name_for_name "$name")"

  log "Removing instance: ${name}"

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] systemctl disable --now '${unit_name}'"
    echo "[dry-run] rm -f '${unit_path}'"
    echo "[dry-run] rm -f '${conf_path}'"
    echo "[dry-run] systemctl daemon-reload"
    exit 0
  fi

  if systemctl list-unit-files | grep -q "^${unit_name}"; then
    systemctl disable --now "${unit_name}" >/dev/null 2>&1 || true
    systemctl reset-failed "${unit_name}" >/dev/null 2>&1 || true
  fi

  rm -f "$unit_path" || true
  rm -f "$conf_path" || true
  systemctl daemon-reload

  log "Removed: ${name}"
}

# ---------- main ----------
main() {
  need_root
  ensure_deps

  case "$ACTION" in
    list) do_list; exit 0;;
    remove) do_remove; exit 0;;
    install) ;;
    *) die "Unknown action";;
  esac

  validate_common_install
  validate_install_choice

  log "Starting install (dry-run=${DRY_RUN}, force=${FORCE})"
  install_ssserver
  create_user_and_dirs

  if [[ ${#ENTRIES[@]} -gt 0 ]]; then
    for entry in "${ENTRIES[@]}"; do
      parse_and_validate_entry "$entry"
      local name="$ENTRY_NAME" port="$ENTRY_PORT" pass="$ENTRY_PASS"
      write_config_file "$name" "$port" "$pass"
      write_unit_file "$name"
      enable_start_unit "$name"
      verify_listen_best_effort "$port" "$name" || true
    done
  else
    local name="$PORT"
    write_config_file "$name" "$PORT" "$PASSWORD"
    write_unit_file "$name"
    enable_start_unit "$name"
    verify_listen_best_effort "$PORT" "$name" || true
  fi

  echo
  log "Done."
  echo "  binary : ${BIN_PATH}"
  echo "  config : ${CONF_DIR}/"
  echo "  method : ${METHOD}"
  echo "  mode   : ${MODE}"
  if [[ -n "$LOG_LEVEL" ]]; then
    echo "  log    : ${LOG_LEVEL} (written)"
  else
    echo "  log    : (not written)"
  fi
  echo
  echo "Commands:"
  echo "  systemctl list-units 'ssserver-*' --no-pager"
  echo "  journalctl -u 'ssserver-*' -f"
  echo "  sudo ${SCRIPT_NAME} --list"
  echo "  sudo ${SCRIPT_NAME} --remove <NAME>"
}

main
