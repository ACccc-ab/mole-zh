#!/bin/bash
# Mole - Optimize command.
# Runs system maintenance tasks.
# Supports dry-run where applicable.

set -euo pipefail

# Fix locale issues.
export LC_ALL=C
export LANG=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/core/common.sh"

# Clean temp files on exit.
trap cleanup_temp_files EXIT INT TERM
source "$SCRIPT_DIR/lib/core/sudo.sh"
source "$SCRIPT_DIR/lib/optimize/diagnostics.sh"
source "$SCRIPT_DIR/lib/optimize/maintenance.sh"
source "$SCRIPT_DIR/lib/optimize/tasks.sh"
source "$SCRIPT_DIR/lib/check/health_json.sh"
source "$SCRIPT_DIR/lib/manage/whitelist.sh"

print_header() {
    printf '\n'
    echo -e "${PURPLE_BOLD}优化${NC}"
}

# Bash-native JSON parsing helpers (no jq dependency).
# Extract a simple numeric value from JSON by key.
json_get_value() {
    local json="$1"
    local key="$2"
    local value
    value=$(echo "$json" | grep -o "\"${key}\"[[:space:]]*:[[:space:]]*[0-9.]*" | head -1 | sed 's/.*:[[:space:]]*//')
    echo "${value:-0}"
}

# Validate JSON has expected structure (basic check).
json_validate() {
    local json="$1"
    # Check for required keys
    [[ "$json" == *'"memory_used_gb"'* ]] &&
        [[ "$json" == *'"optimizations"'* ]] &&
        [[ "$json" == *'{'* ]] && [[ "$json" == *'}'* ]]
}

# Parse optimization items from JSON array.
# Outputs pipe-delimited records: action|name|description|safe
# Single awk pass instead of per-item grep+sed to avoid subprocess overhead.
parse_optimization_items() {
    local json="$1"
    awk '
    function extract(line, key,    pat, val, start, end) {
        pat = "\"" key "\"[ \t]*:[ \t]*\""
        if (match(line, pat)) {
            start = RSTART + RLENGTH
            val = substr(line, start)
            # Find closing quote (skip escaped quotes)
            end = 1
            while (end <= length(val)) {
                if (substr(val, end, 1) == "\"" && substr(val, end-1, 1) != "\\") break
                end++
            }
            return substr(val, 1, end - 1)
        }
        return ""
    }
    /"optimizations".*\[/ { in_arr=1; next }
    !in_arr { next }
    /\]/ && !in_obj { exit }
    /{/ { in_obj=1; action=""; name=""; desc=""; safe="" }
    in_obj && /"action"/ { action = extract($0, "action") }
    in_obj && /"name"/ { name = extract($0, "name") }
    in_obj && /"description"/ { desc = extract($0, "description") }
    in_obj && /"safe"/ {
        val = $0; sub(/.*"safe"[[:space:]]*:[[:space:]]*/, "", val); sub(/[^a-z].*/, "", val); safe = val
    }
    /}/ { if (in_obj && action != "") print action "|" name "|" desc "|" safe; in_obj=0 }
    ' <<< "$json"
}

show_optimization_summary() {
    local safe_count="${OPTIMIZE_SAFE_COUNT:-0}"
    if ((safe_count == 0)); then
        return
    fi

    local summary_title
    local -a summary_details=()
    local total_applied=$safe_count

    if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
        summary_title="预览完成，未做任何更改"
        summary_details+=("将应用 ${YELLOW}${total_applied:-0}${NC} 项优化")
        summary_details+=("不带 ${YELLOW}--dry-run${NC} 运行以应用这些更改")
    else
        summary_title="优化完成"

        # Build statistics summary
        local -a stats=()
        local cache_kb="${OPTIMIZE_CACHE_CLEANED_KB:-0}"
        local db_count="${OPTIMIZE_DATABASES_COUNT:-0}"
        local config_count="${OPTIMIZE_CONFIGS_REPAIRED:-0}"

        if [[ "$cache_kb" =~ ^[0-9]+$ ]] && [[ "$cache_kb" -gt 0 ]]; then
            local cache_human=$(bytes_to_human "$((cache_kb * 1024))")
            stats+=("${cache_human} 缓存已清理")
        fi

        if [[ "$db_count" =~ ^[0-9]+$ ]] && [[ "$db_count" -gt 0 ]]; then
            stats+=("${db_count} 个数据库已优化")
        fi

        if [[ "$config_count" =~ ^[0-9]+$ ]] && [[ "$config_count" -gt 0 ]]; then
            stats+=("${config_count} 个配置已修复")
        fi

        # Build first summary line with most important stat only
        local key_stat=""
        if [[ "$cache_kb" =~ ^[0-9]+$ ]] && [[ "$cache_kb" -gt 0 ]]; then
            local cache_human=$(bytes_to_human "$((cache_kb * 1024))")
            key_stat="${cache_human} 缓存已清理"
        elif [[ "$db_count" =~ ^[0-9]+$ ]] && [[ "$db_count" -gt 0 ]]; then
            key_stat="${db_count} 个数据库已优化"
        elif [[ "$config_count" =~ ^[0-9]+$ ]] && [[ "$config_count" -gt 0 ]]; then
            key_stat="${config_count} 个配置已修复"
        fi

        if [[ -n "$key_stat" ]]; then
            summary_details+=("已应用 ${GREEN}${total_applied:-0}${NC} 项优化, ${key_stat}")
        else
            summary_details+=("已应用 ${GREEN}${total_applied:-0}${NC} 项优化，所有服务已调优")
        fi

        summary_details+=("系统已完全优化")
    fi

    print_summary_block "$summary_title" "${summary_details[@]}"
}

show_system_health() {
    local health_json="$1"

    local mem_used=$(json_get_value "$health_json" "memory_used_gb")
    local mem_total=$(json_get_value "$health_json" "memory_total_gb")
    local disk_used=$(json_get_value "$health_json" "disk_used_gb")
    local disk_total=$(json_get_value "$health_json" "disk_total_gb")
    local disk_percent=$(json_get_value "$health_json" "disk_used_percent")
    local uptime=$(json_get_value "$health_json" "uptime_days")

    mem_used=${mem_used:-0}
    mem_total=${mem_total:-0}
    disk_used=${disk_used:-0}
    disk_total=${disk_total:-0}
    disk_percent=${disk_percent:-0}
    uptime=${uptime:-0}

    printf "${ICON_ADMIN} System  %.0f/%.0f GB RAM | %.0f/%.0f GB Disk | Uptime %.0fd\n" \
        "$mem_used" "$mem_total" "$disk_used" "$disk_total" "$uptime"
}

announce_action() {
    local name="$1"
    local desc="$2"
    local kind="$3"

    if [[ "${FIRST_ACTION:-true}" == "true" ]]; then
        export FIRST_ACTION=false
    else
        echo ""
    fi
    echo -e "${BLUE}${ICON_ARROW} ${name}${NC}"
}

cleanup_all() {
    stop_inline_spinner 2> /dev/null || true
    stop_sudo_session
    cleanup_temp_files
    # Log session end
    log_operation_session_end "optimize" "${OPTIMIZE_SAFE_COUNT:-0}" "0"
}

handle_interrupt() {
    cleanup_all
    exit 130
}

main() {
    # Set current command for operation logging
    export MOLE_CURRENT_COMMAND="optimize"

    local health_json
    for arg in "$@"; do
        case "$arg" in
            "--help" | "-h")
                show_optimize_help
                exit 0
                ;;
            "--debug")
                export MO_DEBUG=1
                ;;
            "--dry-run")
                export MOLE_DRY_RUN=1
                ;;
            "--whitelist")
                manage_whitelist "optimize"
                exit 0
                ;;
            *)
                echo "未知的优化选项: $arg"
                echo "使用 'mo optimize --help' 查看支持的选项。"
                exit 1
                ;;
        esac
    done

    log_operation_session_start "optimize"

    trap cleanup_all EXIT
    trap handle_interrupt INT TERM

    if [[ -t 1 ]]; then
        clear_screen
    fi
    print_header

    # Dry-run indicator.
    if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
        echo -e "${YELLOW}${ICON_DRY_RUN} 预览模式${NC}，不会修改任何文件\n"
    fi

    if ! command -v bc > /dev/null 2>&1; then
        echo -e "${YELLOW}${ICON_ERROR}${NC} 缺少依赖: bc"
        echo -e "${GRAY}安装命令: ${GREEN}brew install bc${NC}"
        exit 1
    fi

    if [[ -t 1 ]]; then
        start_inline_spinner "正在收集系统信息..."
    fi

    if ! health_json=$(generate_health_json 2> /dev/null); then
        if [[ -t 1 ]]; then
            stop_inline_spinner
        fi
        echo ""
        log_error "收集系统健康数据失败"
        exit 1
    fi

    if ! json_validate "$health_json"; then
        if [[ -t 1 ]]; then
            stop_inline_spinner
        fi
        echo ""
        log_error "系统健康数据格式无效"
        echo -e "${GRAY}${ICON_REVIEW}${NC} 检查 awk、sysctl 和 df 命令是否可用"
        exit 1
    fi

    if [[ -t 1 ]]; then
        stop_inline_spinner
    fi

    load_whitelist "optimize"
    if [[ ${#CURRENT_WHITELIST_PATTERNS[@]} -gt 0 ]]; then
        local count=${#CURRENT_WHITELIST_PATTERNS[@]}
        if [[ $count -le 3 ]]; then
            local patterns_list=$(
                IFS=', '
                echo "${CURRENT_WHITELIST_PATTERNS[*]}"
            )
            echo -e "${ICON_ADMIN} Active Whitelist: ${patterns_list}"
        fi
    fi

    show_system_health "$health_json"

    run_optimize_diagnostics

    local -a items=()
    local opts_file
    opts_file=$(mktemp_file)
    parse_optimization_items "$health_json" > "$opts_file"

    while IFS='|' read -r action name desc safe; do
        [[ -z "$action" ]] && continue
        items+=("${name}|${desc}|${action}|")
    done < "$opts_file"

    echo ""
    # Track sudo availability so individual tasks can skip cleanly when admin
    # access was denied. Without this, every sudo task re-prompts for the
    # password and half-runs after a refusal. Default true in dry-run so the
    # task list still expands fully for inspection.
    export MOLE_OPTIMIZE_SUDO_AVAILABLE="false"
    if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
        MOLE_OPTIMIZE_SUDO_AVAILABLE="true"
    elif ensure_sudo_session "系统优化需要管理员权限"; then
        MOLE_OPTIMIZE_SUDO_AVAILABLE="true"
    else
        opt_msg "跳过需要 sudo 的优化：未获得管理员权限"
    fi

    export FIRST_ACTION=true
    for item in "${items[@]}"; do
        IFS='|' read -r name desc action path <<< "$item"
        if command -v is_whitelisted > /dev/null && is_whitelisted "$action"; then
            opt_msg "已跳过（白名单）: $name"
            continue
        fi
        announce_action "$name" "$desc" "safe"
        execute_optimization "$action" "$path"
    done

    local safe_count=${#items[@]}

    export OPTIMIZE_SAFE_COUNT=$safe_count
    export OPTIMIZE_CONFIRM_COUNT=0

    show_optimization_summary

    printf '\n'
}

main "$@"
