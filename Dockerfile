FROM ghcr.io/anomalyco/opencode:2.0.0

# The upstream image is Alpine-based and already ships opencode v2, ripgrep,
# wget and a Mozilla CA bundle. Add the few tools this project relies on.
# `ca-certificates` is what provides `update-ca-certificates` (the base image
# only ships the bundle, not the tooling).
RUN apk add --no-cache \
      bash \
      ca-certificates \
      curl \
      git \
      py3-pip \
      python3

# Russian Trusted Root/Sub CA. The T-Bank Invest MCP endpoint
# (invest-public-api.tbank.ru) is signed by these roots, which are not in the
# default Mozilla bundle, so TLS otherwise fails with
# "self signed certificate in certificate chain".
# gu-st.ru is intermittently unreachable, so retry the downloads.
RUN curl -fsSL --retry 5 --retry-delay 2 --retry-all-errors \
      https://gu-st.ru/content/lending/russian_trusted_root_ca_pem.crt \
      -o /usr/local/share/ca-certificates/russian_trusted_root_ca_pem.crt \
 && curl -fsSL --retry 5 --retry-delay 2 --retry-all-errors \
      https://gu-st.ru/content/lending/russian_trusted_sub_ca_pem.crt \
      -o /usr/local/share/ca-certificates/russian_trusted_sub_ca_pem.crt \
 && update-ca-certificates

# The opencode binary is Bun-based and honours Node's extra CA override.
ENV NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt

COPY opencode.json /root/.config/opencode/opencode.json

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 4444
WORKDIR /root/work
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
