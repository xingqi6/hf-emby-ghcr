FROM debian:bookworm-slim

ARG DEBIAN_FRONTEND=noninteractive
ARG EMBY_VERSION=4.9.1.90

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg \
    python3 python3-venv \
    ffmpeg \
    socat \
    tzdata \
  && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL -o /tmp/emby.deb \
    "https://github.com/MediaBrowser/Emby.Releases/releases/download/${EMBY_VERSION}/emby-server-deb_${EMBY_VERSION}_amd64.deb" \
  && apt-get update \
  && apt-get install -y --no-install-recommends /tmp/emby.deb \
  && rm -f /tmp/emby.deb \
  && rm -rf /var/lib/apt/lists/*

RUN python3 -m venv /opt/venv \
  && /opt/venv/bin/pip install --no-cache-dir requests webdavclient3

ENV PATH="/opt/venv/bin:${PATH}"
ENV APP_PUBLIC_PORT=7860
ENV APP_INTERNAL_PORT=8096
ENV DATA_DIR=/data

RUN useradd -m -u 1000 appuser \
  && mkdir -p /data \
  && chown -R appuser:appuser /data

WORKDIR /home/appuser

COPY --chown=appuser:appuser entrypoint.sh /entrypoint.sh
COPY --chown=appuser:appuser snapshot.py /snapshot.py

RUN chmod +x /entrypoint.sh

USER appuser

EXPOSE 7860

ENTRYPOINT ["/entrypoint.sh"]
