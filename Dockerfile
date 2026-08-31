# syntax=docker/dockerfile:1
#
# FRAMPP 官方镜像：复用 Linux x86_64 自包含安装包，单镜像内置
# FrankenPHP + MySQL 8.0 + Redis + Agent/MCP + 控制面板 + Python。
#
# 构建前请先生成 Linux 安装包：
#   pwsh -File installer/scripts/build-linux-package.ps1 -Env linux-x86_64
# 然后：
#   docker build -t frampp:0.7.0 \
#     --build-arg FRAMPP_PACKAGE=dist/installer/frampp-0.7.0-linux-x86_64.run .
#
ARG BASE_IMAGE=debian:bookworm-slim

FROM ${BASE_IMAGE} AS runtime

ARG FRAMPP_PACKAGE=dist/installer/frampp-0.7.0-linux-x86_64.run

ENV FRAMPP_HOME=/opt/frampp \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# ca-certificates 供容器内 Composer / Adminer 走 HTTPS；passwd 用于创建非 root
# 用户；libaio1 为 MySQL 8.0 服务端运行时依赖（官方 glibc 2.17 通用包）。
# mysql CLI 在 Debian 12 可能缺 libtinfo.so.5，仅影响命令行客户端，
# PHP（mysqli / PDO mysqlnd）与控制面板不受影响。
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        passwd \
        libaio1 \
        libnuma1; \
    rm -rf /var/lib/apt/lists/*

COPY ${FRAMPP_PACKAGE} /tmp/frampp.run

RUN set -eux; \
    chmod +x /tmp/frampp.run; \
    /tmp/frampp.run --prefix /opt/frampp --extract-only; \
    rm -f /tmp/frampp.run; \
    chmod +x \
        /opt/frampp/bin/frampp \
        /opt/frampp/bin/init.sh \
        /opt/frampp/bin/docker-entrypoint.sh \
        /opt/frampp/bin/docker-healthcheck.sh \
        /opt/frampp/modules/frankenphp/frankenphp \
        /opt/frampp/modules/redis/redis-server \
        /opt/frampp/modules/redis/redis-cli; \
    groupadd --system frampp; \
    useradd --system --gid frampp --home-dir /opt/frampp --shell /usr/sbin/nologin frampp; \
    chown -R frampp:frampp /opt/frampp

USER frampp

VOLUME ["/opt/frampp/var", "/opt/frampp/logs", "/opt/frampp/htdocs"]

EXPOSE 8080 8081 3306 6379

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD ["/opt/frampp/bin/docker-healthcheck.sh"]

ENTRYPOINT ["/opt/frampp/bin/docker-entrypoint.sh"]
