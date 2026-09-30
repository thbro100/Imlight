FROM mcr.microsoft.com/dotnet/sdk:10.0

ARG IMLIGHT_SOURCE_REPOSITORY=https://github.com/Revive101/Imlight.git
ARG IMLIGHT_SOURCE_REVISION

LABEL org.opencontainers.image.title="Imlight" \
      org.opencontainers.image.description="Imlight runtime bootstrap image" \
      org.opencontainers.image.licenses="AGPL-3.0-or-later"

ENV IMLIGHT_SOURCE_REPOSITORY=${IMLIGHT_SOURCE_REPOSITORY} \
    IMLIGHT_SOURCE_REVISION=${IMLIGHT_SOURCE_REVISION} \
    IMLIGHT_DATA_DIR=/data \
    IMLIGHT_TYPE_INPUT_DIR=/data/imcodec-inputs/types \
    IMLIGHT_MESSAGE_INPUT_DIR=/data/imcodec-inputs/messages \
    IMLIGHT_CONFIG_DIR=/data/config \
    IMLIGHT_BUILD_CACHE_DIR=/data/build-cache \
    HOME=/data/home \
    DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    DOTNET_NOLOGO=1

RUN mkdir -p /data/app /data/build-cache /data/home \
    && chown -R 10001:10001 /data

RUN apt-get update \
    && apt-get install --yes --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 10001 imlight \
    && useradd --uid 10001 --gid imlight --create-home --home-dir /home/imlight --shell /usr/sbin/nologin imlight

COPY --chmod=755 container-entrypoint.sh /usr/local/bin/imlight-entrypoint

WORKDIR /data/app
USER 10001:10001

EXPOSE 12000/tcp 12333/tcp 12334/tcp 12335/tcp 12500/tcp

ENTRYPOINT ["/usr/local/bin/imlight-entrypoint"]
