#!/bin/bash

# FastDiag Toolkit 文档本地渲染和部署脚本
# 使用方法: ./render_and_deploy.sh [preview|build|deploy]

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 输出带颜色的信息
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查依赖
check_dependencies() {
    log_info "检查依赖..."
    
    if ! command -v quarto &> /dev/null; then
        log_error "Quarto 未安装。请访问 https://quarto.org/docs/get-started/ 安装。"
        exit 1
    fi
    
    if ! command -v git &> /dev/null; then
        log_error "Git 未安装。"
        exit 1
    fi
    
    log_success "所有依赖检查通过"
}

# 预览模式
preview() {
    log_info "启动预览模式..."
    log_warning "预览模式将在浏览器中打开，使用 Ctrl+C 停止"
    quarto preview
}

# 构建模式
build() {
    log_info "开始渲染 Quarto 项目..."

    # 避免环境变量 QUARTO_PYTHON 指向不存在的解释器导致大量警告
    if [ -n "${QUARTO_PYTHON:-}" ] && [ ! -x "${QUARTO_PYTHON}" ]; then
        log_warning "检测到 QUARTO_PYTHON 指向不存在的解释器：${QUARTO_PYTHON}，将改用系统 python3"
        export QUARTO_PYTHON="$(command -v python3)"
    fi

    # 清理旧的输出
    if [ -d "_site" ]; then
        log_info "清理旧的输出目录..."
        rm -rf _site
    fi

    # 可选：清理 freeze 缓存（当你修改了 execute/eval 配置但页面没有重新执行时很有用）
    if [ "${CLEAN_FREEZE:-0}" = "1" ] && [ -d "_freeze" ]; then
        log_info "清理 _freeze 缓存目录（CLEAN_FREEZE=1）..."
        rm -rf _freeze
    fi
    
    # 渲染项目
    log_info "渲染中..."
    quarto render
    
    if [ -d "_site" ]; then
        log_success "渲染完成！输出位于 _site/ 目录"
        total_html=$(find _site -type f -name "*.html" | wc -l | tr -d ' ')
        en_html=$(find _site -type f -name "*-en.html" | wc -l | tr -d ' ')
        zh_html=$(( total_html - en_html ))

        log_info "HTML 总数: ${total_html}（中文: ${zh_html}, English: ${en_html}）"
        if [ -f "_site/index.html" ]; then
            log_info "中文入口: _site/index.html"
        fi
        if [ -f "_site/index-en.html" ]; then
            log_info "English 入口: _site/index-en.html"
        fi

        log_info "示例（中文）："
        find _site -type f -name "*.html" ! -name "*-en.html" | sort | head -10
        if [ "${en_html}" -gt 0 ]; then
            log_info "示例（English）："
            find _site -type f -name "*-en.html" | sort | head -10
        fi
    else
        log_error "渲染失败！"
        exit 1
    fi
}

# 部署模式
deploy() {
    log_info "开始部署流程..."
        
    # 检查Git状态
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        log_error "当前目录不是 Git 仓库"
        exit 1
    fi
    
    # 精确添加需要的文件到Git
    log_info "添加必要文件到 Git..."
    
    # 添加源文件和配置文件
    git add *.qmd
    git add _quarto.yml
    git add .gitignore
    git add requirements.txt
    git add styles.css
    git add index.qmd
    git add index-en.qmd
    
    # 添加渲染后的_site目录（这是最终的网站文件）
    if [ -d "_site" ]; then
        git add _site/
        log_info "已添加 _site/ 目录"
    fi
    
    # 添加GitHub Actions工作流
    if [ -f ".github/workflows/quarto-publish.yml" ]; then
        git add .github/workflows/quarto-publish.yml
        log_info "已添加 GitHub Actions 工作流"
    fi
    
    # 添加脚本文件本身
    git add render_and_deploy.sh
    
    log_info "文件添加完成，检查状态..."
    
    # 显示将要提交的文件
    staged_files=$(git diff --staged --name-only)
    if [ -n "$staged_files" ]; then
        log_info "将要提交的文件："
        echo "$staged_files" | while read file; do
            echo "  ✓ $file"
        done
        
        # 显示文件大小统计
        total_size=$(git diff --staged --name-only | xargs -I {} stat -c%s "{}" 2>/dev/null | awk '{sum+=$1} END {print sum}')
        if [ -n "$total_size" ] && [ "$total_size" -gt 0 ]; then
            human_size=$(echo "$total_size" | awk '
                function human(x) {
                    if (x<1024) return x " bytes"
                    x/=1024
                    if (x<1024) return sprintf("%.1f KB", x)
                    x/=1024
                    if (x<1024) return sprintf("%.1f MB", x)
                    x/=1024
                    return sprintf("%.1f GB", x)
                }
                {print human($1)}')
            log_info "总大小: $human_size"
        fi
    else
        log_warning "没有检测到变化，跳过提交"
        return 0
    fi
    
    # 提交变化
    commit_message="Update site: $(date '+%Y-%m-%d %H:%M:%S')"
    log_info "提交变化: $commit_message"
    git commit -m "$commit_message"
    
    # 推送到GitHub
    log_info "推送到 GitHub..."
    git push origin master
    
    log_success "部署完成！"
    log_info "网站将在几分钟后在以下地址更新："
    log_info "https://fastdiag-toolbox.github.io/fastdiag-toolkit-docs/"
}

# 显示帮助
show_help() {
    echo "FastDiag Toolkit 文档渲染和部署脚本"
    echo ""
    echo "使用方法:"
    echo "  $0 preview   - 启动本地预览服务器"
    echo "  $0 build     - 仅渲染静态文件"
    echo "  $0 deploy    - 渲染并部署到 GitHub Pages"
    echo "  $0 help      - 显示此帮助信息"
    echo ""
    echo "示例："
    echo "  $0 preview   # 本地预览，实时查看变化"
    echo "  $0 build     # 生成静态文件到 _site/ 目录"
    echo "  $0 deploy    # 完整的构建和部署流程"
}

# 主逻辑
main() {
    check_dependencies
    
    case "${1:-help}" in
        preview)
            preview
            ;;
        build)
            build
            ;;
        deploy)
            deploy
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "未知命令: $1"
            show_help
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@"
