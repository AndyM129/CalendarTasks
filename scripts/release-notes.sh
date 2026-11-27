#!/bin/zsh
# 从 CHANGELOG.md 取出指定版本的更新说明，输出为 Release 正文（Markdown）
# 用法：./scripts/release-notes.sh <版本号，如 0.3.4>
# 说明：
#   - 取「## x.y、v<版本号>（…）」到下一个「## 」或「# 」标题之间的内容；
#   - 去掉小节标题里的编号（「### 2.1.1、新增」→「### 新增」），去掉首尾空行；
#   - 找不到该版本时输出为空、退出码 0，不阻断发版（CI 里会给出警告）。

set -euo pipefail

VERSION="${1:?用法: release-notes.sh <版本号>}"
ROOT="${0:A:h:h}"

awk -v ver="v${VERSION}" '
  /^#{1,2} / {
    if (found) exit
    if ($0 ~ /^## / && (index($0, ver "（") > 0 || $0 ~ ("、" ver "$"))) { found = 1; next }
  }
  found {
    sub(/^### [0-9.]+、/, "### ")
    lines[++n] = $0
  }
  END {
    first = 1; while (first <= n && lines[first] ~ /^[[:space:]]*$/) first++
    last = n; while (last >= first && lines[last] ~ /^[[:space:]]*$/) last--
    for (i = first; i <= last; i++) print lines[i]
  }
' "$ROOT/CHANGELOG.md"
