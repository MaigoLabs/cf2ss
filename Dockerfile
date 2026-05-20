# syntax=docker/dockerfile:1

FROM alpine:3.20

ARG TARGETARCH
ARG SING_BOX_VERSION=1.13.12
ARG WGCF_VERSION=2.2.30

RUN apk add --no-cache ca-certificates curl jq tar \
    && case "${TARGETARCH:-$(uname -m)}" in \
        amd64|x86_64) bin_arch="amd64" ;; \
        arm64|aarch64) bin_arch="arm64" ;; \
        *) echo "unsupported architecture: ${TARGETARCH:-$(uname -m)}; supported: amd64, arm64" >&2; exit 1 ;; \
    esac \
    && curl -fsSL -o /tmp/sing-box.tar.gz \
        "https://github.com/SagerNet/sing-box/releases/download/v${SING_BOX_VERSION}/sing-box-${SING_BOX_VERSION}-linux-${bin_arch}-musl.tar.gz" \
    && tar -xzf /tmp/sing-box.tar.gz -C /tmp \
    && mv "/tmp/sing-box-${SING_BOX_VERSION}-linux-${bin_arch}-musl/sing-box" /usr/local/bin/sing-box \
    && chmod +x /usr/local/bin/sing-box \
    && curl -fsSL -o /usr/local/bin/wgcf \
        "https://github.com/ViRb3/wgcf/releases/download/v${WGCF_VERSION}/wgcf_${WGCF_VERSION}_linux_${bin_arch}" \
    && chmod +x /usr/local/bin/wgcf \
    && rm -rf /tmp/*

COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod +x /usr/local/bin/entrypoint.sh \
    && addgroup -S proxy \
    && adduser -S -G proxy -h /var/lib/proxy proxy \
    && mkdir -p /etc/sing-box /warp \
    && chown -R proxy:proxy /etc/sing-box /warp /var/lib/proxy

USER proxy
WORKDIR /var/lib/proxy

EXPOSE 8388/tcp 8388/udp 1080/tcp 1080/udp

ENTRYPOINT ["entrypoint.sh"]
CMD ["run"]
