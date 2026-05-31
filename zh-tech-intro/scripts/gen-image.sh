#!/usr/bin/env bash
# gen-image.sh — 画图提示 → 真实图片 → 图床 URL
#
# 用法：
#   bash gen-image.sh --check                              # 检测环境，缺什么装什么
#   bash gen-image.sh --prompt "..." --out /tmp/x.png      # 仅生成（存本地）
#   bash gen-image.sh --prompt "..." --out /tmp/x.png --upload  # 生成并上传图床
#
# 依赖：
#   1. codex CLI          — 驱动 GPT Image 2 生成图片
#   2. gpt-image-2 skill  — gen.sh 生成脚本（由 codex 调用）
#   3. picgo              — 上传图床（可选；缺失时图片存本地）

set -euo pipefail

# ── 终端颜色 ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✅ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $*${NC}"; }
err()  { echo -e "${RED}❌ $*${NC}"; }
info() { echo -e "${BLUE}ℹ️  $*${NC}"; }
step() { echo -e "\n${BLUE}▶ $*${NC}"; }

# ── 参数解析 ───────────────────────────────────────────────────────────────────
MODE=""        # check | generate
PROMPT=""
OUT_PATH=""
DO_UPLOAD=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)   MODE="check"; shift ;;
    --prompt)  PROMPT="$2"; shift 2 ;;
    --out)     OUT_PATH="$2"; shift 2 ;;
    --upload)  DO_UPLOAD=true; shift ;;
    -h|--help)
      echo "用法："
      echo "  bash gen-image.sh --check"
      echo "  bash gen-image.sh --prompt \"画图描述\" --out /tmp/out.png [--upload]"
      exit 0 ;;
    *) err "未知参数：$1"; exit 2 ;;
  esac
done

[[ -z "$MODE" ]] && MODE="generate"

# ── 工具查找 ───────────────────────────────────────────────────────────────────

find_codex() {
  command -v codex 2>/dev/null \
    || [[ -x /opt/homebrew/bin/codex ]] && echo /opt/homebrew/bin/codex \
    || true
}

find_gen_sh() {
  local candidates=(
    "$HOME/.claude/skills/gpt-image-2/scripts/gen.sh"
    ".claude/skills/gpt-image-2/scripts/gen.sh"
    "$HOME/.config/claude/skills/gpt-image-2/scripts/gen.sh"
  )
  for p in "${candidates[@]}"; do
    [[ -f "$p" ]] && echo "$p" && return
  done
}

find_picgo() {
  # 优先找用户建的 wrapper（最常见）
  [[ -x "$HOME/bin/picgo-typora" ]] && echo "$HOME/bin/picgo-typora" && return
  # PATH 里的 picgo
  local p; p=$(command -v picgo 2>/dev/null || true)
  [[ -n "$p" ]] && echo "$p" && return
  # pnpm 全局目录（macOS 默认路径）
  [[ -x "$HOME/Library/pnpm/picgo" ]] && echo "$HOME/Library/pnpm/picgo" && return
  # mise 管理的 node 下的 picgo
  local mise_bin="$HOME/.local/share/mise/installs/node/lts/bin/picgo"
  [[ -x "$mise_bin" ]] && echo "$mise_bin" && return
  # npm 全局目录
  local npm_prefix; npm_prefix=$(npm config get prefix 2>/dev/null || true)
  [[ -n "$npm_prefix" && -x "$npm_prefix/bin/picgo" ]] \
    && echo "$npm_prefix/bin/picgo" && return
}

find_pkg_manager() {
  # 返回当前系统可用的 Node.js 包管理器
  for pm in pnpm npm yarn bun; do
    command -v "$pm" &>/dev/null && echo "$pm" && return
  done
}

picgo_configured() {
  local cfg="$HOME/.picgo/config.json"
  [[ -f "$cfg" ]] || return 1
  python3 -c "
import json, sys
try:
    d = json.load(open('$cfg'))
    uploader = d.get('picBed', {}).get('uploader', '')
    sys.exit(0 if uploader else 1)
except Exception:
    sys.exit(1)
" 2>/dev/null
}

get_uploader_name() {
  python3 -c "
import json
d = json.load(open('$HOME/.picgo/config.json'))
print(d.get('picBed', {}).get('uploader', '未知'))
" 2>/dev/null || echo "未知"
}

# ── 自动安装 picgo ─────────────────────────────────────────────────────────────
install_picgo() {
  local pm; pm=$(find_pkg_manager)

  if [[ -z "$pm" ]]; then
    err "未找到 Node.js 包管理器（pnpm / npm / yarn / bun）"
    echo ""
    info "请先安装 Node.js，推荐使用 Homebrew："
    echo "   brew install node"
    echo "   安装完成后重新运行：bash gen-image.sh --check"
    return 1
  fi

  info "使用 $pm 安装 picgo..."
  case "$pm" in
    pnpm) pnpm install -g picgo ;;
    npm)  npm install -g picgo ;;
    yarn) yarn global add picgo ;;
    bun)  bun install -g picgo ;;
  esac

  # 找到刚装好的 picgo 路径
  local picgo_bin; picgo_bin=$(find_picgo || true)
  if [[ -z "$picgo_bin" ]]; then
    err "picgo 安装后未能找到可执行文件，请手动检查 $pm 的全局 bin 目录是否在 PATH 中"
    return 1
  fi

  ok "picgo 安装成功：$picgo_bin"

  # 如果 ~/bin/picgo-typora 不存在，自动创建 wrapper
  if [[ ! -x "$HOME/bin/picgo-typora" ]]; then
    mkdir -p "$HOME/bin"
    local picgo_dir; picgo_dir=$(dirname "$picgo_bin")
    cat > "$HOME/bin/picgo-typora" << WRAPPER
#!/bin/zsh
# 自动生成的 picgo wrapper，由 zh-tech-intro skill 创建
export PATH="${picgo_dir}:\$PATH"
exec picgo upload "\$@"
WRAPPER
    chmod +x "$HOME/bin/picgo-typora"
    ok "已创建 ~/bin/picgo-typora"
    info "如果 ~/bin 不在你的 PATH 里，可以把以下内容加到 ~/.zshrc 或 ~/.bash_profile："
    echo '   export PATH="$HOME/bin:$PATH"'
  fi
}

# ── CHECK 模式 ─────────────────────────────────────────────────────────────────
run_check() {
  echo ""
  echo "══════════════════════════════════════════════"
  echo "        图片生成环境检测"
  echo "══════════════════════════════════════════════"

  local all_ok=true

  # ── 1. codex CLI ──
  step "检测 codex CLI（驱动 GPT Image 2）"
  local codex_bin; codex_bin=$(find_codex)
  if [[ -n "$codex_bin" ]]; then
    local ver; ver=$("$codex_bin" --version 2>/dev/null | head -1 || echo "version unknown")
    ok "codex CLI 已安装：$codex_bin（$ver）"
  else
    all_ok=false
    err "codex CLI 未安装"
    echo ""
    echo "   安装方法（任选一种）："
    echo "   ┌─ 方法 A：Homebrew（推荐）"
    echo "   │   brew install codex"
    echo "   │"
    echo "   └─ 方法 B：npm"
    echo "       npm install -g @openai/codex"
    echo ""
    echo "   安装完成后必须登录 ChatGPT 账号："
    echo "   codex login"
    echo ""
    echo "   ⚠️  需要 ChatGPT Plus 或 Pro 订阅才能使用图片生成功能"
  fi

  # ── 2. gpt-image-2 skill ──
  step "检测 gpt-image-2 skill（图片生成脚本）"
  local gen_sh; gen_sh=$(find_gen_sh)
  if [[ -n "$gen_sh" ]]; then
    ok "gpt-image-2 skill 已安装：$gen_sh"
  else
    all_ok=false
    err "gpt-image-2 skill 未安装"
    echo ""
    echo "   安装方法（在终端运行）："
    echo "   npx skills add https://github.com/agentspace-so/agent-skills --skill gpt-image-2"
    echo ""
    echo "   安装完成后重新运行：bash scripts/gen-image.sh --check"
  fi

  # ── 3. picgo（上传图床）──
  step "检测 picgo（图片上传工具）"
  local picgo_bin; picgo_bin=$(find_picgo)

  if [[ -z "$picgo_bin" ]]; then
    warn "picgo 未安装，正在尝试自动安装..."
    echo ""
    if install_picgo; then
      picgo_bin=$(find_picgo)
    else
      all_ok=false
      echo ""
      echo "   自动安装失败，请手动安装："
      echo "   pnpm install -g picgo   （推荐）"
      echo "   npm install -g picgo"
      echo ""
      echo "   ℹ️  没有 picgo 也可以生成图片，但图片只会保存在本地，"
      echo "      不会自动上传，需要手动把路径替换为图床 URL。"
    fi
  else
    ok "picgo 已安装：$picgo_bin"
  fi

  # ── 4. picgo 图床配置 ──
  if [[ -n "$(find_picgo)" ]]; then
    step "检测 picgo 图床配置"
    if picgo_configured; then
      ok "图床已配置（$(get_uploader_name)）"
    else
      all_ok=false
      warn "图床尚未配置"
      echo ""
      echo "   运行以下命令，按提示选择并填写图床信息："
      echo "   picgo set uploader"
      echo ""
      echo "   常用图床及所需信息："
      echo "   ┌─ SM.MS（免费，推荐新手）"
      echo "   │   注册：https://smms.app  → 获取 Token"
      echo "   │   配置：选 smms，填入 Token"
      echo "   │"
      echo "   ├─ 腾讯云 COS"
      echo "   │   需要：SecretId、SecretKey、Bucket 名、Region（如 ap-nanjing）"
      echo "   │"
      echo "   └─ 阿里云 OSS"
      echo "       需要：accessKeyId、accessKeySecret、bucket、区域"
      echo ""
      echo "   配置完成后测试上传（用任意图片）："
      echo "   picgo upload /path/to/test.png"
      echo "   看到 https:// 开头的 URL 说明配置成功"
    fi
  fi

  # ── 汇总 ──
  echo ""
  echo "══════════════════════════════════════════════"
  if $all_ok; then
    ok "环境就绪，可以生成图片！"
    echo "STATUS: ready"
  else
    warn "请按上方提示完成配置，然后重新运行："
    echo "   bash scripts/gen-image.sh --check"
    echo "STATUS: not_ready"
  fi
  echo "══════════════════════════════════════════════"
  echo ""
}

# ── 生成模式 ───────────────────────────────────────────────────────────────────
run_generate() {
  if [[ -z "$PROMPT" || -z "$OUT_PATH" ]]; then
    err "缺少参数"
    echo "用法：bash gen-image.sh --prompt \"画图描述\" --out /tmp/output.png [--upload]"
    exit 2
  fi

  # 检查 codex
  local codex_bin; codex_bin=$(find_codex)
  if [[ -z "$codex_bin" ]]; then
    err "codex CLI 未安装，无法生成图片"
    echo "请先运行：bash scripts/gen-image.sh --check"
    exit 3
  fi

  # 检查 gen.sh
  local gen_sh; gen_sh=$(find_gen_sh)
  if [[ -z "$gen_sh" ]]; then
    err "gpt-image-2 skill 未安装，无法生成图片"
    echo "请先运行：bash scripts/gen-image.sh --check"
    exit 3
  fi

  # 生成图片
  info "正在生成图片（通常需要 1～3 分钟）..."
  if ! bash "$gen_sh" --prompt "$PROMPT" --out "$OUT_PATH" 2>&1; then
    err "图片生成失败"
    echo "可能原因："
    echo "  • codex 未登录 → 运行 codex login"
    echo "  • ChatGPT 账号无图片生成权限（需要 Plus/Pro）"
    echo "  • 网络问题 → 检查网络后重试"
    exit 5
  fi
  ok "图片已生成：$OUT_PATH"

  # 不需要上传，直接返回本地路径
  if ! $DO_UPLOAD; then
    echo "URL: file://$OUT_PATH"
    return
  fi

  # ── 上传到图床 ──
  local picgo_bin; picgo_bin=$(find_picgo)

  # 找不到 picgo，尝试自动安装
  if [[ -z "$picgo_bin" ]]; then
    warn "picgo 未安装，尝试自动安装..."
    echo ""
    install_picgo || true
    picgo_bin=$(find_picgo || true)
  fi

  # 安装失败，降级为本地路径
  if [[ -z "$picgo_bin" ]]; then
    warn "picgo 安装失败，图片保存在本地"
    echo "本地路径：$OUT_PATH"
    echo "请手动上传后把路径替换为图床 URL"
    echo "URL: file://$OUT_PATH"
    return
  fi

  # picgo 未配置，降级为本地路径
  if ! picgo_configured; then
    warn "picgo 尚未配置图床，图片保存在本地"
    echo "本地路径：$OUT_PATH"
    echo "请运行 picgo set uploader 配置图床，然后手动上传"
    echo "URL: file://$OUT_PATH"
    return
  fi

  # 上传
  info "正在上传到图床..."
  local upload_out; upload_out=$("$picgo_bin" "$OUT_PATH" 2>&1 || true)
  local url; url=$(echo "$upload_out" | grep -E '^https?://' | head -1 | tr -d '[:space:]' || true)

  if [[ -n "$url" ]]; then
    ok "上传成功"
    echo "URL: $url"
  else
    warn "上传失败，图片保存在本地：$OUT_PATH"
    echo ""
    echo "上传错误信息："
    echo "$upload_out" | sed 's/^/   /'
    echo ""
    echo "URL: file://$OUT_PATH"
  fi
}

# ── 入口 ───────────────────────────────────────────────────────────────────────
case "$MODE" in
  check)    run_check ;;
  generate) run_generate ;;
  *)        err "未知模式：$MODE"; exit 2 ;;
esac
