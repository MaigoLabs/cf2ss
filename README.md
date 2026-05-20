# Cloudflare WARP to Shadowsocks

This runs a local Shadowsocks server and sends all proxied outbound traffic through Cloudflare WARP using sing-box's user-space WireGuard endpoint. It does not require a privileged container or host WireGuard setup.

## Files

- `Dockerfile` builds an Alpine-based image with `sing-box` and `wgcf`.
- `docker-compose.yml` defines the runtime service and a one-shot WARP registration service.
- `./warp` stores generated WARP credentials and is intentionally ignored by git.

## Setup

1. Create your env file and set a strong password:

   ```sh
   cp .env.example .env
   ${EDITOR:-vi} .env
   ```

   On Linux, set `PUID` and `PGID` in `.env` to `id -u` and `id -g` if your user is not `1000:1000`.

2. Register a WARP device and generate `./warp/wgcf-profile.conf`:

   ```sh
   docker compose --profile init run --rm warp-register
   ```

3. Start the Shadowsocks proxy:

   ```sh
   docker compose up -d --build warp-shadowsocks
   ```

Your Shadowsocks client should use:

- Server: `127.0.0.1`
- Port: the `SS_PORT` value from `.env`, default `8388`
- Method: the `SS_METHOD` value from `.env`, default `chacha20-ietf-poly1305`
- Password: the `SS_PASSWORD` value from `.env`

By default Docker only publishes the proxy on localhost. To expose it to your LAN, set `SS_BIND_HOST=0.0.0.0` in `.env` and restart the service.

## Operations

View logs:

```sh
docker compose logs -f warp-shadowsocks
```

Regenerate the WARP profile after account changes:

```sh
docker compose --profile init run --rm warp-register
docker compose restart warp-shadowsocks
```

Check whether traffic exits via WARP by sending traffic through a Shadowsocks client to Cloudflare's trace endpoint and looking for `warp=on`:

```sh
curl https://www.cloudflare.com/cdn-cgi/trace
```

Run that curl through your Shadowsocks client, not directly from the host shell.

## Direct environment mode

If you already have WARP WireGuard values, you can skip `wgcf` and provide these variables to `warp-shadowsocks` instead of mounting `./warp`:

- `WARP_PRIVATE_KEY`
- `WARP_LOCAL_ADDRESS`, comma-separated, for example `172.16.0.2/32,2606:4700:110:.../128`
- `WARP_PEER_PUBLIC_KEY`
- `WARP_SERVER`, for example `engage.cloudflareclient.com`
- `WARP_SERVER_PORT`, usually `2408`
- `WARP_RESERVED`, optional comma-separated reserved bytes if your account has them
