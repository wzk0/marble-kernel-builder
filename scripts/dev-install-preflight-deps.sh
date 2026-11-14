#!/usr/bin/env bash
# 安装本机 preflight 静态检查缺的两个包（需要 sudo 密码，由用户在终端执行一次）。
# 用法：bash scripts/dev-install-preflight-deps.sh
set -euo pipefail

missing=()
command -v patch >/dev/null 2>&1 || missing+=(patch)
command -v shellcheck >/dev/null 2>&1 || missing+=(ShellCheck)

if [[ "${#missing[@]}" -eq 0 ]]; then
  echo "patch / shellcheck 已安装，无需操作"
else
  echo "将安装：${missing[*]}"
  sudo dnf install -y "${missing[@]}"
fi

command -v actionlint >/dev/null 2>&1 || [[ -x "${HOME}/.local/bin/actionlint" ]] || {
  echo "缺少 actionlint：可从 https://github.com/rhysd/actionlint/releases 下载 1.7.12 的 linux_amd64 包放到 ~/.local/bin/" >&2
  exit 1
}

echo
echo "验证："
patch --version | head -1
shellcheck --version | head -3
"$(command -v actionlint || echo "${HOME}/.local/bin/actionlint")" --version | head -1