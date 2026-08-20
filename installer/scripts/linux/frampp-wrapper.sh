#!/usr/bin/env sh
#
# FRAMPP CLI 包装器：用内置 FrankenPHP 的 PHP 运行控制面板 CLI。
# 用法: bin/frampp {status|start|stop|logs|ports|version|new-project} [...]
#
set -e

PRG="$0"
while [ -h "$PRG" ]; do
    LS=$(ls -ld "$PRG")
    LINK=$(expr "$LS" : '.*-> \(.*\)$')
    case "$LINK" in
        /*) PRG="$LINK" ;;
        *) PRG="$(dirname "$PRG")/$LINK" ;;
    esac
done

FRAMPP_HOME=$(cd "$(dirname "$PRG")/.." && pwd)
export FRAMPP_HOME

PHP_INI="$FRAMPP_HOME/frankenphp/php.ini"
export PHPRC="$PHP_INI"

exec "$FRAMPP_HOME/frankenphp/frankenphp" php-cli -c "$PHP_INI" \
    "$FRAMPP_HOME/control-panel/bin/frampp" "$@"
