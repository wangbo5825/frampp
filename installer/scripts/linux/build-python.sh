#!/usr/bin/env bash
#
# 准备精简版 Python 3.13（Linux x86_64）。
#
# 使用 astral-sh/python-build-standalone 的 install_only_stripped 构建：
#   - 自包含：无系统包依赖（除 glibc）
#   - install_only：不含头文件 / 测试 / 文档
#   - stripped：已去除符号
# 再做二次精简：删除 test / tkinter / idlelib / turtledemo / __pycache__，
# 保留 ensurepip / pip 等常用组件。
#
# 用法: build-python.sh <python-tar.gz> <输出目录> [版本]
#
set -euo pipefail

PY_TAR="$1"
OUT_DIR="$2"
PY_VERSION="${3:-unknown}"

if [[ ! -f "$PY_TAR" ]]; then
    echo "缺少 Python 包: $PY_TAR" >&2
    exit 1
fi
mkdir -p "$OUT_DIR"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

tar -xzf "$PY_TAR" -C "$WORK"
tar -tzf "$PY_TAR" > "$WORK/list.txt"
SRC_NAME="$(head -n1 "$WORK/list.txt" | cut -d/ -f1)"
cp -a "$WORK/$SRC_NAME/." "$OUT_DIR/"

echo "==> 二次精简 Python $PY_VERSION ..."
STDLIB="$OUT_DIR/lib/python3.13"
rm -rf \
    "$STDLIB/test" \
    "$STDLIB/tkinter" \
    "$STDLIB/idlelib" \
    "$STDLIB/turtledemo" \
    "$STDLIB/site-packages/ensurepip/_bundled" 2>/dev/null || true
find "$OUT_DIR" -type d -name __pycache__ -prune -exec rm -rf {} + 2>/dev/null || true
find "$STDLIB" -type f \( -name '*.pyc' -o -name '*.pyo' \) -delete 2>/dev/null || true

chmod +x "$OUT_DIR/bin/python3" "$OUT_DIR/bin/python3.13" 2>/dev/null || true

echo "==> 验证:"
"$OUT_DIR/bin/python3" --version
du -sh "$OUT_DIR"
echo "PYTHON_BUILD_OK version=$PY_VERSION"
