# syntax=docker/dockerfile:1
#
# FRAMPP 官方镜像：复用 Linux x86_64 自包含安装包，单镜像内置
# FrankenPHP + MariaDB + Redis + Agent/MCP + 控制面板 + Python。
#
# 构建前请先生成 Linux 安装包：
#   pwsh -File installer/scripts/build-linux-package.ps1 -Env linux-x86_64
# 然后：
#   docker build -t frampp:0.5.0 \
#     --build-arg FRAMPP_PACKAGE=dist/installer/frampp-setup-8.5-0.5.0-linux-x86_64.run .
#
ARG BASE_IMAGE=debian:bookworm-slim

FROM ${BASE_IMAGE} AS runtime

ARG FRAMPP_PACKAGE=dist/installer/frampp-setup-8.5-0.5.0-linux-x86_64.run

ENV FRAMPP_HOME=/opt/frampp \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# ca-certificates 供容器内 Composer / Adminer 走 HTTPS；passwd 用于创建非 root
# 用户；其余为 MariaDB 运行时依赖（libssl/libpcre2/ncurses/liburing，libaio 已在
# 精简构建中通过 IGNORE_AIO_CHECK 移除）。
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        passwd \
        libssl3 \
        libpcre2-8-0 \
        zlib1g \
        libncurses6 \
        libtinfo6 \
        liburing2; \
    rm -rf /var/lib/apt/lists/*

COPY ${FRAMPP_PACKAGE} /tmp/frampp.run

RUN set -eux; \
    chmod +x /tmp/frampp.run; \
    /tmp/frampp.run --prefix /opt/frampp --extract-only; \
    rm -f /tmp/frampp.run; \
    chmod +x \
        /opt/frampp/bin/frampp \
        /opt/frampp/installer/scripts/linux/init.sh \
        /opt/frampp/installer/scripts/linux/docker-entrypoint.sh \
        /opt/frampp/installer/scripts/linux/docker-healthcheck.sh \
        /opt/frampp/frankenphp/frankenphp \
        /opt/frampp/redis/redis-server \
        /opt/frampp/redis/redis-cli; \
    groupadd --system frampp; \
    useradd --system --gid frampp --home-dir /opt/frampp --shell /usr/sbin/nologin frampp; \
    chown -R frampp:frampp /opt/frampp

USER frampp

VOLUME ["/opt/frampp/data", "/opt/frampp/logs", "/opt/frampp/htdocs"]

EXPOSE 8080 8081 3306 6379

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD ["/opt/frampp/installer/scripts/linux/docker-healthcheck.sh"]

ENTRYPOINT ["/opt/frampp/installer/scripts/linux/docker-entrypoint.sh"]
