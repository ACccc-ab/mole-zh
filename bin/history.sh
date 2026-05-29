#!/bin/bash
# Mole - History command.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$ROOT_DIR/lib/core/history.sh"

HISTORY_JSON=false
HISTORY_LIMIT="$MOLE_HISTORY_DEFAULT_LIMIT"

show_history_help() {
    echo "用法: mo history [选项]"
    echo ""
    echo "查看最近的 Mole 操作和删除记录。"
    echo ""
    echo "选项:"
    echo "  --json           以 JSON 格式输出历史"
    echo "  --limit N        显示最近 N 条记录，1-200"
    echo "  -h, --help       显示此帮助信息"
}

main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            "--json")
                HISTORY_JSON=true
                ;;
            "--limit")
                shift
                if [[ $# -eq 0 ]]; then
                    echo "缺少 --limit 的值" >&2
                    exit 1
                fi
                if ! HISTORY_LIMIT=$(history_parse_limit "$1"); then
                    echo "--limit 的值无效: $1" >&2
                    exit 1
                fi
                ;;
            "--help" | "-h")
                show_history_help
                exit 0
                ;;
            -*)
                echo "mo history 的未知选项: $1" >&2
                echo "运行 'mo history --help' 查看用法。" >&2
                exit 1
                ;;
            *)
                echo "mo history 的意外参数: $1" >&2
                echo "运行 'mo history --help' 查看用法。" >&2
                exit 1
                ;;
        esac
        shift
    done

    history_load_operations "$(history_operations_log_file)"
    history_load_deletions "$(history_deletions_log_file)"

    if [[ "$HISTORY_JSON" == "true" ]]; then
        history_render_json "$HISTORY_LIMIT"
    else
        history_render_text "$HISTORY_LIMIT"
    fi
}

main "$@"
