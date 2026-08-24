#!/usr/bin/env bash
#
# 断言给定目录（或单文件）内所有 ELF 二进制引用的最高 GLIBC 符号版本
# 不超过指定基线。用于防止在过新的 glibc 上编译导致产物无法在旧发行版运行。
#
# 用法: assert-glibc-max.sh <目录或文件> [最大版本] [标签]
#   例: assert-glibc-max.sh dist/tools/mariadb-linux-x86_64 2.31 MariaDB
#
set -euo pipefail

TARGET="$1"
MAX_VER="${2:-2.31}"
LABEL="${3:-glibc}"

if [[ ! -e "$TARGET" ]]; then
    echo "断言目标不存在: $TARGET" >&2
    exit 1
fi

for tool in objdump grep sort head; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "缺少工具: $tool（binutils/coreutils）" >&2
        exit 1
    fi
done

# a <= b（版本比较，支持 2.2.5 / 2.31 等）
ver_le() {
    local lo
    lo="$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)"
    [[ "$lo" == "$1" ]]
}

max_found="0.0"
checked=0

check_file() {
    local f="$1" v
    # 只处理 ELF 文件
    if [[ "$(head -c4 "$f" 2>/dev/null || true)" != $'\x7fELF' ]]; then
        return 0
    fi
    checked=$((checked + 1))
    while IFS= read -r v; do
        [[ -n "$v" ]] || continue
        if ! ver_le "$v" "$MAX_VER"; then
            echo "GLIBC_ABOVE_BASELINE: $f 需要 GLIBC_$v（超过基线 GLIBC_$MAX_VER）" >&2
            return 1
        fi
        if ver_le "$max_found" "$v"; then
            max_found="$v"
        fi
    done < <(objdump -T "$f" 2>/dev/null | grep -o 'GLIBC_[0-9][0-9.]*' | sed 's/^GLIBC_//' || true)
    return 0
}

if [[ -f "$TARGET" ]]; then
    check_file "$TARGET"
else
    while IFS= read -r -d '' f; do
        check_file "$f" || exit 1
    done < <(find "$TARGET" -type f -print0)
fi

echo "GLIBC_BASELINE_OK label=$LABEL max=GLIBC_$max_found baseline=GLIBC_$MAX_VER checked=$checked"
