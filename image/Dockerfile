FROM debian:bookworm-slim

ARG DEBIAN_FRONTEND=noninteractive
ARG EMBY_VERSION=4.9.1.90

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg \
    python3 python3-venv \
    ffmpeg \
    libsqlite3-0 \
    socat \
    tzdata \
  && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
  echo '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d; \
  chmod +x /usr/sbin/policy-rc.d; \
  mkdir -p /etc/init.d; \
  echo '#!/bin/sh\nexit 0\n' > /etc/init.d/emby-server; \
  chmod +x /etc/init.d/emby-server; \
  curl -fsSL -o /tmp/emby.deb \
    "https://github.com/MediaBrowser/Emby.Releases/releases/download/${EMBY_VERSION}/emby-server-deb_${EMBY_VERSION}_amd64.deb"; \
  apt-get update; \
  apt-get install -y --no-install-recommends /tmp/emby.deb; \
  rm -f /tmp/emby.deb; \
  rm -f /usr/sbin/policy-rc.d /etc/init.d/emby-server; \
  rm -rf /var/lib/apt/lists/*

RUN set -eux; \
  if [ -f /usr/lib/x86_64-linux-gnu/libsqlite3.so.0 ] && [ -d /opt/emby-server/system ]; then \
    ln -sf /usr/lib/x86_64-linux-gnu/libsqlite3.so.0 /opt/emby-server/system/libsqlite3.so; \
    ln -sf /usr/lib/x86_64-linux-gnu/libsqlite3.so.0 /opt/emby-server/system/sqlite3.so; \
  fi

RUN set -eux; \
  mkdir -p /var/lib/emby/programdata; \
  if [ -e /opt/emby-server/programdata ] && [ ! -L /opt/emby-server/programdata ]; then \
    rm -rf /opt/emby-server/programdata; \
  fi; \
  ln -sfn /var/lib/emby/programdata /opt/emby-server/programdata

RUN python3 -m venv /opt/venv \
  && /opt/venv/bin/pip install --no-cache-dir requests webdavclient3

ENV PATH="/opt/venv/bin:${PATH}"
ENV APP_PUBLIC_PORT=7860
ENV APP_INTERNAL_PORT=8096
ENV DATA_DIR=/var/lib/emby

RUN useradd -m -u 1000 appuser \
  && mkdir -p /var/lib/emby \
  && chown -R appuser:appuser /var/lib/emby

WORKDIR /home/appuser

COPY --chown=appuser:appuser entrypoint.sh /entrypoint.sh
COPY --chown=appuser:appuser snapshot.py /snapshot.py

RUN chmod +x /entrypoint.sh

USER appuser

EXPOSE 7860

ENTRYPOINT ["/entrypoint.sh"]
