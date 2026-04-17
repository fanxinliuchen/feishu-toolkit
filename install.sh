#!/bin/bash
#
# feishu-toolkit install script for Hermes
# Usage:
#   curl -sSL https://raw.githubusercontent.com/fanxinliuchen/feishu-toolkit/main/install.sh | bash
#

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
success() { echo -e "${GREEN}✅ $1${NC}"; }
warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
error() { echo -e "${RED}❌ $1${NC}"; }

detect_hermes_home() {
    if [ -n "$HERMES_HOME" ] && [ -d "$HERMES_HOME" ]; then
        echo "$HERMES_HOME"
    elif [ -d "$HOME/.hermes" ]; then
        echo "$HOME/.hermes"
    elif [ -d "/root/.hermes" ]; then
        echo "/root/.hermes"
    else
        echo ""
    fi
}

main() {
    echo ""
    echo "📄 feishu-toolkit"
    echo "================="
    echo ""

    HERMES_DIR=$(detect_hermes_home)
    if [ -z "$HERMES_DIR" ]; then
        error "未找到 Hermes 目录"
        echo "请先确保 ~/.hermes 已存在，或设置 HERMES_HOME。"
        exit 1
    fi

    info "检测到 Hermes 目录: $HERMES_DIR"

    SKILL_DIR="$HERMES_DIR/skills/productivity"
    mkdir -p "$SKILL_DIR"

    if [ -d "$SKILL_DIR/feishu-toolkit" ]; then
        warning "feishu-toolkit 已存在，执行更新..."
        cd "$SKILL_DIR/feishu-toolkit"
        git pull origin main
        success "已更新到最新 main 分支"
    else
        info "正在安装 feishu-toolkit..."
        cd "$SKILL_DIR"
        git clone https://github.com/fanxinliuchen/feishu-toolkit.git
        success "安装完成"
    fi

    echo ""
    echo "📋 安装位置: $SKILL_DIR/feishu-toolkit"
    echo "📘 文档: $SKILL_DIR/feishu-toolkit/README.md"
    echo ""
    warning "请确认已设置 FEISHU_APP_ID 和 FEISHU_APP_SECRET"
    echo ""
    success "安装成功！"
    echo ""
}

main
