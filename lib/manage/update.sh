#!/bin/bash
# Update Manager
# Unified update execution for all update types

set -euo pipefail

# Format Homebrew update details for display
format_brew_update_detail() {
    local total="${BREW_OUTDATED_COUNT:-0}"
    if [[ -z "$total" || "$total" -le 0 ]]; then
        return
    fi

    local -a details=()
    local formulas="${BREW_FORMULA_OUTDATED_COUNT:-0}"
    local casks="${BREW_CASK_OUTDATED_COUNT:-0}"

    ((formulas > 0)) && details+=("${formulas} formula")
    ((casks > 0)) && details+=("${casks} cask")

    local detail_str="${total} 个更新"
    if ((${#details[@]} > 0)); then
        detail_str="$(
            IFS=', '
            printf '%s' "${details[*]}"
        )"
    fi
    printf "%s" "$detail_str"
}

populate_brew_update_counts_if_unset() {
    local need_probe=false
    [[ -z "${BREW_OUTDATED_COUNT:-}" ]] && need_probe=true
    [[ -z "${BREW_FORMULA_OUTDATED_COUNT:-}" ]] && need_probe=true
    [[ -z "${BREW_CASK_OUTDATED_COUNT:-}" ]] && need_probe=true

    if [[ "$need_probe" == "false" ]]; then
        return 0
    fi

    local formula_count="${BREW_FORMULA_OUTDATED_COUNT:-0}"
    local cask_count="${BREW_CASK_OUTDATED_COUNT:-0}"

    if command -v brew > /dev/null 2>&1; then
        local formula_outdated=""
        local cask_outdated=""

        formula_outdated=$(run_with_timeout 8 brew outdated --formula --quiet 2> /dev/null || true) # 8s: brew outdated, see lib/core/timeouts.sh
        cask_outdated=$(run_with_timeout 8 brew outdated --cask --quiet 2> /dev/null || true)       # 8s: brew outdated, see lib/core/timeouts.sh

        formula_count=$(printf '%s\n' "$formula_outdated" | awk 'NF {count++} END {print count + 0}')
        cask_count=$(printf '%s\n' "$cask_outdated" | awk 'NF {count++} END {print count + 0}')
    fi

    BREW_FORMULA_OUTDATED_COUNT="$formula_count"
    BREW_CASK_OUTDATED_COUNT="$cask_count"
    BREW_OUTDATED_COUNT="$((formula_count + cask_count))"
}

# Ask user if they want to update
# Returns: 0 if yes, 1 if no
ask_for_updates() {
    populate_brew_update_counts_if_unset

    local has_updates=false
    if [[ -n "${BREW_OUTDATED_COUNT:-}" && "${BREW_OUTDATED_COUNT:-0}" -gt 0 ]]; then
        has_updates=true
    fi

    if [[ -n "${APPSTORE_UPDATE_COUNT:-}" && "${APPSTORE_UPDATE_COUNT:-0}" -gt 0 ]]; then
        has_updates=true
    fi

    if [[ -n "${MACOS_UPDATE_AVAILABLE:-}" && "${MACOS_UPDATE_AVAILABLE}" == "true" ]]; then
        has_updates=true
    fi

    if [[ -n "${MOLE_UPDATE_AVAILABLE:-}" && "${MOLE_UPDATE_AVAILABLE}" == "true" ]]; then
        has_updates=true
    fi

    if [[ "$has_updates" == "false" ]]; then
        return 1
    fi

    if [[ "${MOLE_UPDATE_AVAILABLE:-}" == "true" ]]; then
        echo -ne "${YELLOW}现在更新 Mole？${NC} ${GRAY}Enter 确认 / ESC 取消${NC}: "

        local key
        if ! key=$(read_key); then
            echo "跳过"
            return 1
        fi

        if [[ "$key" == "ENTER" ]]; then
            echo "是"
            return 0
        fi
    fi

    if [[ -n "${BREW_OUTDATED_COUNT:-}" && "${BREW_OUTDATED_COUNT:-0}" -gt 0 ]]; then
        echo -e "  ${GRAY}${ICON_REVIEW}${NC} 运行 ${GREEN}brew upgrade${NC} 以更新"
    fi
    if [[ -n "${MACOS_UPDATE_AVAILABLE:-}" && "${MACOS_UPDATE_AVAILABLE}" == "true" ]]; then
        echo -e "  ${GRAY}${ICON_REVIEW}${NC} 打开 ${GREEN}系统设置${NC} → ${GREEN}通用${NC} → ${GREEN}软件更新${NC}"
    fi
    if [[ -n "${APPSTORE_UPDATE_COUNT:-}" && "${APPSTORE_UPDATE_COUNT:-0}" -gt 0 ]]; then
        echo -e "  ${GRAY}${ICON_REVIEW}${NC} 打开 ${GREEN}App Store${NC} → ${GREEN}更新${NC}"
    fi

    return 1
}
