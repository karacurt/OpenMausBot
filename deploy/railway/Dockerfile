# OpenMausBot on Railway, private to a Tailscale tailnet.
#
# Unmodified official server image (release v0.1.119, pinned by digest) plus:
#   - tailscale/tailscaled (userspace networking; no TUN or NET_ADMIN needed)
#   - Claude Code CLI (sign in from Settings -> Engines with your own subscription)
#   - tini as PID 1 (the bots' browsers leave orphans to reap)
# No public Railway domain: the only way in is https://<TS_HOSTNAME>.<tailnet>.ts.net
#
# To upgrade: change the image digest to a newer release's (ghcr tag sha-<commit>)
# and bump the pinned versions below, one at a time.
FROM ghcr.io/milind-soni/openmausbot@sha256:87d4535231d93dfa04ece1b7bdc71c563f43363fc38f9ad4b669509845e349d3

USER root

RUN apt-get update \
  && apt-get install -y --no-install-recommends tini \
  && rm -rf /var/lib/apt/lists/* \
  && command -v setpriv

ARG TAILSCALE_VERSION=1.104.2
RUN curl -fsSL "https://pkgs.tailscale.com/stable/tailscale_${TAILSCALE_VERSION}_amd64.tgz" | tar -xz -C /tmp \
  && install -m 0755 /tmp/tailscale_${TAILSCALE_VERSION}_amd64/tailscale /tmp/tailscale_${TAILSCALE_VERSION}_amd64/tailscaled /usr/local/bin/ \
  && rm -rf /tmp/tailscale_* \
  && tailscale version

ARG CLAUDE_CODE_VERSION=2.1.304
RUN HOME=/tmp/omb-build-home npm install -g "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
  && rm -rf /tmp/omb-build-home /tmp/node-compile-cache \
  && claude --version

COPY deploy/railway/entrypoint.sh /usr/local/bin/omb-railway-entrypoint
RUN chmod 0755 /usr/local/bin/omb-railway-entrypoint

ENV HOME=/data
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/usr/local/bin/omb-railway-entrypoint"]
