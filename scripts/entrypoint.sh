#!/usr/bin/env sh
set -eu

log() {
  printf '%s\n' "[entrypoint] $*" >&2
}

die() {
  printf '%s\n' "[entrypoint] error: $*" >&2
  exit 1
}

extract_profile_value() {
  key="$1"
  file="$2"
  awk -F '=' -v wanted="$key" '
    $1 ~ "^[[:space:]]*" wanted "[[:space:]]*$" {
      value=$2
      for (i=3; i<=NF; i++) value=value "=" $i
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      print value
      exit
    }
  ' "$file"
}

extract_profile_addresses() {
  file="$1"
  awk -F '=' '
    $1 ~ /^[[:space:]]*Address[[:space:]]*$/ {
      value=$2
      for (i=3; i<=NF; i++) value=value "=" $i
      gsub(/[[:space:]]+/, "", value)
      if (out == "") out=value; else out=out "," value
    }
    END { print out }
  ' "$file"
}

extract_reserved() {
  file="$1"
  [ -f "$file" ] || return 0
  awk -F '=' '
    $1 ~ /^[[:space:]]*reserved[[:space:]]*$/ {
      value=$2
      for (i=3; i<=NF; i++) value=value "=" $i
      gsub(/^[[:space:]]*\[/, "", value)
      gsub(/\][[:space:]]*$/, "", value)
      gsub(/[[:space:]]/, "", value)
      print value
      exit
    }
  ' "$file"
}

load_warp_profile() {
  WARP_CONF="${WARP_CONF:-/warp/wgcf-profile.conf}"
  WARP_ACCOUNT="${WARP_ACCOUNT:-/warp/wgcf-account.toml}"

  if [ -f "$WARP_CONF" ]; then
    WARP_PRIVATE_KEY="${WARP_PRIVATE_KEY:-$(extract_profile_value PrivateKey "$WARP_CONF")}"
    WARP_LOCAL_ADDRESS="${WARP_LOCAL_ADDRESS:-$(extract_profile_addresses "$WARP_CONF")}"
    WARP_PEER_PUBLIC_KEY="${WARP_PEER_PUBLIC_KEY:-$(extract_profile_value PublicKey "$WARP_CONF")}"

    endpoint="${WARP_ENDPOINT:-$(extract_profile_value Endpoint "$WARP_CONF")}"
    if [ -n "$endpoint" ]; then
      WARP_SERVER="${WARP_SERVER:-${endpoint%:*}}"
      WARP_SERVER_PORT="${WARP_SERVER_PORT:-${endpoint##*:}}"
    fi

    profile_mtu="$(extract_profile_value MTU "$WARP_CONF" || true)"
    WARP_MTU="${WARP_MTU:-${profile_mtu:-1280}}"
  fi

  WARP_RESERVED="${WARP_RESERVED:-$(extract_reserved "$WARP_ACCOUNT" || true)}"
}

require_env() {
  name="$1"
  eval "value=\${$name:-}"
  [ -n "$value" ] || die "$name is required"
}

render_config() {
  load_warp_profile

  CONFIG_PATH="${CONFIG_PATH:-/etc/sing-box/config.json}"
  LOG_LEVEL="${LOG_LEVEL:-info}"
  SS_LISTEN="${SS_LISTEN:-::}"
  SS_PORT="${SS_PORT:-8388}"
  SS_METHOD="${SS_METHOD:-chacha20-ietf-poly1305}"
  SS_NETWORK="${SS_NETWORK:-}"
  WARP_MTU="${WARP_MTU:-1280}"

  require_env SS_PASSWORD
  require_env WARP_PRIVATE_KEY
  require_env WARP_LOCAL_ADDRESS
  require_env WARP_PEER_PUBLIC_KEY
  require_env WARP_SERVER
  require_env WARP_SERVER_PORT

  mkdir -p "$(dirname "$CONFIG_PATH")"

  jq -n \
    --arg log_level "$LOG_LEVEL" \
    --arg ss_listen "$SS_LISTEN" \
    --arg ss_port "$SS_PORT" \
    --arg ss_method "$SS_METHOD" \
    --arg ss_password "$SS_PASSWORD" \
    --arg ss_network "$SS_NETWORK" \
    --arg warp_server "$WARP_SERVER" \
    --arg warp_server_port "$WARP_SERVER_PORT" \
    --arg warp_private_key "$WARP_PRIVATE_KEY" \
    --arg warp_peer_public_key "$WARP_PEER_PUBLIC_KEY" \
    --arg warp_local_address "$WARP_LOCAL_ADDRESS" \
    --arg warp_reserved "$WARP_RESERVED" \
    --arg warp_mtu "$WARP_MTU" \
    '
      def csv($s): $s | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0));

      {
        log: {
          level: $log_level,
          timestamp: true
        },
        inbounds: [
          ({
            type: "shadowsocks",
            tag: "ss-in",
            listen: $ss_listen,
            listen_port: ($ss_port | tonumber),
            method: $ss_method,
            password: $ss_password
          } + if ($ss_network | length) > 0 then { network: $ss_network } else {} end)
        ],
        endpoints: [
          ({
            type: "wireguard",
            tag: "warp",
            system: false,
            address: csv($warp_local_address),
            private_key: $warp_private_key,
            peers: [
              ({
                address: $warp_server,
                port: ($warp_server_port | tonumber),
                public_key: $warp_peer_public_key,
                allowed_ips: ["0.0.0.0/0", "::/0"]
              } + if ($warp_reserved | length) > 0 then { reserved: (csv($warp_reserved) | map(tonumber)) } else {} end)
            ],
            mtu: ($warp_mtu | tonumber)
          })
        ],
        outbounds: [
          {
            type: "direct",
            tag: "direct"
          }
        ],
        route: {
          final: "warp"
        }
      }
    ' > "$CONFIG_PATH"

  log "rendered sing-box config at $CONFIG_PATH"
}

register_warp() {
  WARP_DIR="${WARP_DIR:-/warp}"
  mkdir -p "$WARP_DIR"
  cd "$WARP_DIR"

  if [ ! -f wgcf-account.toml ]; then
    log "registering a new Cloudflare WARP device"
    wgcf register --accept-tos
  else
    log "using existing $WARP_DIR/wgcf-account.toml"
  fi

  log "generating WireGuard profile"
  wgcf generate

  if [ "$(id -u)" = "0" ]; then
    chown -R "${PUID:-1000}:${PGID:-1000}" "$WARP_DIR" 2>/dev/null || true
  fi

  log "created $WARP_DIR/wgcf-profile.conf"
}

case "${1:-run}" in
  register-warp)
    register_warp
    ;;
  render-config)
    render_config
    ;;
  run|sing-box)
    render_config
    exec sing-box run -c "${CONFIG_PATH:-/etc/sing-box/config.json}"
    ;;
  *)
    exec "$@"
    ;;
esac
