#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$ROOT_DIR/lib/core/common.sh"
source "$ROOT_DIR/lib/core/commands.sh"

command_names=()
for entry in "${MOLE_COMMANDS[@]}"; do
    command_names+=("${entry%%:*}")
done
command_words="${command_names[*]}"
clean_option_words="--dry-run -n --external --whitelist --debug --help -h"
analyze_option_words="--json --help -h"
history_option_words="--json --limit --help -h"
purge_option_words="--paths --dry-run -n --include-empty --debug --help -h"

emit_zsh_subcommands() {
    for entry in "${MOLE_COMMANDS[@]}"; do
        printf "        '%s:%s'\n" "${entry%%:*}" "${entry#*:}"
    done
}

emit_fish_completions() {
    local cmd="$1"
    for entry in "${MOLE_COMMANDS[@]}"; do
        local name="${entry%%:*}"
        local desc="${entry#*:}"
        printf 'complete -f -c %s -n "__fish_mole_no_subcommand" -a %s -d "%s"\n' "$cmd" "$name" "$desc"
    done

    printf '\n'
    printf 'complete -f -c %s -n "__fish_seen_subcommand_from clean" -l dry-run -s n -d "Preview cleanup without making changes"\n' "$cmd"
    printf 'complete -c %s -n "__fish_seen_subcommand_from clean" -l external -r -a "(__fish_complete_directories)" -d "Clean OS metadata from an external volume"\n' "$cmd"
    printf 'complete -f -c %s -n "__fish_seen_subcommand_from clean" -l whitelist -d "Manage protected paths"\n' "$cmd"
    printf 'complete -f -c %s -n "__fish_seen_subcommand_from clean" -l debug -d "Show detailed logs"\n' "$cmd"
    printf 'complete -f -c %s -n "__fish_seen_subcommand_from clean" -l help -s h -d "Show help"\n' "$cmd"
    printf 'complete -f -c %s -n "__fish_seen_subcommand_from analyze analyse" -l json -d "Output analysis as JSON"\n' "$cmd"
    printf 'complete -f -c %s -n "__fish_seen_subcommand_from analyze analyse" -l help -s h -d "Show help"\n' "$cmd"
    printf 'complete -c %s -n "__fish_seen_subcommand_from analyze analyse; and not __fish_seen_argument -l json -l help -s h" -a "(__fish_complete_directories)" -d "Path to analyze"\n' "$cmd"
    printf 'complete -f -c %s -n "__fish_seen_subcommand_from history" -l json -d "Output history as JSON"\n' "$cmd"
    printf 'complete -f -c %s -n "__fish_seen_subcommand_from history" -l limit -r -d "Limit recent entries"\n' "$cmd"
    printf 'complete -f -c %s -n "__fish_seen_subcommand_from history" -l help -s h -d "Show help"\n' "$cmd"
    printf 'complete -f -c %s -n "__fish_seen_subcommand_from purge" -l paths -d "Edit custom scan directories"\n' "$cmd"
    printf 'complete -f -c %s -n "__fish_seen_subcommand_from purge" -l dry-run -s n -d "Preview purge actions without making changes"\n' "$cmd"
    printf 'complete -f -c %s -n "__fish_seen_subcommand_from purge" -l include-empty -d "Show zero-size project artifact directories"\n' "$cmd"
    printf 'complete -f -c %s -n "__fish_seen_subcommand_from purge" -l debug -d "Show detailed logs"\n' "$cmd"
    printf 'complete -f -c %s -n "__fish_seen_subcommand_from purge" -l help -s h -d "Show help"\n' "$cmd"
    printf '\n'
    printf 'complete -f -c %s -n "not __fish_mole_no_subcommand" -a bash -d "generate bash completion" -n "__fish_see_subcommand_path completion"\n' "$cmd"
    printf 'complete -f -c %s -n "not __fish_mole_no_subcommand" -a zsh -d "generate zsh completion" -n "__fish_see_subcommand_path completion"\n' "$cmd"
    printf 'complete -f -c %s -n "not __fish_mole_no_subcommand" -a fish -d "generate fish completion" -n "__fish_see_subcommand_path completion"\n' "$cmd"
}

remove_stale_completion_entries() {
    local config_file="$1"
    local success_message="$2"

    if [[ ! -f "$config_file" ]] || ! grep -Eq "(^# Mole shell completion$|(mole|mo)[[:space:]]+completion)" "$config_file" 2> /dev/null; then
        return 1
    fi

    local original_mode=""
    local temp_file
    original_mode="$(stat -f '%Mp%Lp' "$config_file" 2> /dev/null || true)"
    temp_file="$(mktemp)"
    grep -Ev "(^# Mole shell completion$|(mole|mo)[[:space:]]+completion)" "$config_file" > "$temp_file" || true
    mv "$temp_file" "$config_file"
    [[ -n "$original_mode" ]] && chmod "$original_mode" "$config_file" 2> /dev/null || true
    [[ -n "$success_message" ]] && echo -e "${GREEN}${ICON_SUCCESS}${NC} $success_message"
    return 0
}

if [[ $# -gt 0 ]]; then
    normalized_args=()
    for arg in "$@"; do
        case "$arg" in
            "--dry-run" | "-n")
                export MOLE_DRY_RUN=1
                ;;
            *)
                normalized_args+=("$arg")
                ;;
        esac
    done
    if [[ ${#normalized_args[@]} -gt 0 ]]; then
        set -- "${normalized_args[@]}"
    else
        set --
    fi
fi

# Auto-install mode when run without arguments
if [[ $# -eq 0 ]]; then
    if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
        echo -e "${YELLOW}${ICON_DRY_RUN} 预览模式${NC}，不会修改 shell 配置文件"
        echo ""
    fi

    # Detect current shell
    current_shell="${SHELL##*/}"
    if [[ -z "$current_shell" ]]; then
        current_shell="$(ps -p "$PPID" -o comm= 2> /dev/null | awk '{print $1}')"
    fi

    completion_name=""
    if command -v mole > /dev/null 2>&1; then
        completion_name="mole"
    elif command -v mo > /dev/null 2>&1; then
        completion_name="mo"
    fi

    # Fish uses a separate install path: write to ~/.config/fish/completions/ so
    # both `mole` and `mo` load completions independently on terminal startup.
    if [[ "$current_shell" == "fish" ]]; then
        fish_dir="${HOME}/.config/fish/completions"
        mole_file="${fish_dir}/mole.fish"
        mo_file="${fish_dir}/mo.fish"
        config_fish="${HOME}/.config/fish/config.fish"

        if [[ -z "$completion_name" ]]; then
            # Clean up any stale config.fish entries even when mole is not in PATH
            if [[ "${MOLE_DRY_RUN:-0}" != "1" ]]; then
                remove_stale_completion_entries "$config_fish" "已移除 config.fish 中的旧补全条目" || true
            fi
            log_error "在 PATH 中找不到 mole，请先安装 Mole 再启用补全"
            exit 1
        fi

        if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
            echo -e "${GRAY}${ICON_REVIEW} [预览] 将写入 Fish 补全文件到:${NC}"
            echo "  $mole_file"
            echo "  $mo_file"
            echo ""
            echo -e "${GREEN}${ICON_SUCCESS}${NC} 预览完成，未做任何更改"
            exit 0
        fi

        # Remove stale config.fish source-based entries (previous install method)
        if remove_stale_completion_entries "$config_fish" "已移除 config.fish 中旧的 source 条目"; then
            echo ""
        fi

        # Prompt only on first install; silently update if files exist
        if [[ ! -f "$mole_file" ]]; then
            echo ""
            echo -e "${GRAY}将写入 Fish 补全文件到:${NC}"
            echo "  $mole_file"
            echo "  $mo_file"
            echo ""
            echo -ne "${PURPLE}${ICON_ARROW}${NC} 为 ${GREEN}fish${NC} 启用补全？${GRAY}Enter 确认 / Q 取消${NC}: "
            IFS= read -r -s -n1 key || key=""
            drain_pending_input
            echo ""

            case "$key" in
                $'\e' | [Qq] | [Nn])
                    echo -e "${YELLOW}已取消${NC}"
                    exit 0
                    ;;
                "" | $'\n' | $'\r' | [Yy]) ;;
                *)
                    log_error "无效按键"
                    exit 1
                    ;;
            esac
        fi

        mkdir -p "$fish_dir"
        "$completion_name" completion fish > "$mole_file"
        # mo.fish sources mole.fish so Fish loads mo completions on `mo<Tab>`
        printf '# Mole completions for mo (alias) -- auto-generated, do not edit\n' > "$mo_file"
        printf 'source %s\n' "$mole_file" >> "$mo_file"

        if [[ -f "$mole_file" ]]; then
            echo -e "${GREEN}${ICON_SUCCESS}${NC} Fish 补全已写入 $fish_dir"
        fi
        echo ""
        exit 0
    fi

    case "$current_shell" in
        bash)
            config_file="${HOME}/.bashrc"
            [[ -f "${HOME}/.bash_profile" ]] && config_file="${HOME}/.bash_profile"
            # shellcheck disable=SC2016
            completion_line='if output="$('"$completion_name"' completion bash 2>/dev/null)"; then eval "$output"; fi'
            ;;
        zsh)
            config_file="${HOME}/.zshrc"
            # shellcheck disable=SC2016
            completion_line='if output="$('"$completion_name"' completion zsh 2>/dev/null)"; then eval "$output"; fi'
            ;;
        *)
            log_error "不支持的 shell: $current_shell"
            echo "  mole completion <bash|zsh|fish>"
            exit 1
            ;;
    esac

    if [[ -z "$completion_name" ]]; then
        if [[ -f "$config_file" ]] && grep -Eq "(^# Mole shell completion$|(mole|mo)[[:space:]]+completion)" "$config_file" 2> /dev/null; then
            if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
                echo -e "${GRAY}${ICON_REVIEW} [预览] 将移除 $config_file 中的旧补全条目${NC}"
                echo ""
            else
                original_mode=""
                original_mode="$(stat -f '%Mp%Lp' "$config_file" 2> /dev/null || true)"
                temp_file="$(mktemp)"
                grep -Ev "(^# Mole shell completion$|(mole|mo)[[:space:]]+completion)" "$config_file" > "$temp_file" || true
                mv "$temp_file" "$config_file"
                if [[ -n "$original_mode" ]]; then
                    chmod "$original_mode" "$config_file" 2> /dev/null || true
                fi
                echo -e "${GREEN}${ICON_SUCCESS}${NC} 已移除 $config_file 中的旧补全条目"
                echo ""
            fi
        fi
        log_error "mole not found in PATH, install Mole before enabling completion"
        exit 1
    fi

    # Check if already installed and normalize to latest line
    if [[ -f "$config_file" ]] && grep -Eq "(mole|mo)[[:space:]]+completion" "$config_file" 2> /dev/null; then
        if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
            echo -e "${GRAY}${ICON_REVIEW} [预览] 将规范化 $config_file 中的补全条目${NC}"
            echo ""
            exit 0
        fi

        original_mode=""
        original_mode="$(stat -f '%Mp%Lp' "$config_file" 2> /dev/null || true)"
        temp_file="$(mktemp)"
        grep -Ev "(^# Mole shell completion$|(mole|mo)[[:space:]]+completion)" "$config_file" > "$temp_file" || true
        mv "$temp_file" "$config_file"
        if [[ -n "$original_mode" ]]; then
            chmod "$original_mode" "$config_file" 2> /dev/null || true
        fi
        {
            echo ""
            echo "# Mole shell completion"
            echo "$completion_line"
        } >> "$config_file"
        echo ""
        echo -e "${GREEN}${ICON_SUCCESS}${NC} Shell 补全已更新到 $config_file"
        echo ""
        exit 0
    fi

    # Prompt user for installation
    echo ""
    echo -e "${GRAY}将添加到 ${config_file}:${NC}"
    echo "  $completion_line"
    echo ""
    if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
        echo -e "${GREEN}${ICON_SUCCESS}${NC} Dry run complete, no changes made"
        exit 0
    fi

    echo -ne "${PURPLE}${ICON_ARROW}${NC} 为 ${GREEN}${current_shell}${NC} 启用补全？${GRAY}Enter 确认 / Q 取消${NC}: "
    IFS= read -r -s -n1 key || key=""
    drain_pending_input
    echo ""

    case "$key" in
        $'\e' | [Qq] | [Nn])
            echo -e "${YELLOW}Cancelled${NC}"
            exit 0
            ;;
        "" | $'\n' | $'\r' | [Yy]) ;;
        *)
            log_error "Invalid key"
            exit 1
            ;;
    esac

    # Create config file if it doesn't exist
    if [[ ! -f "$config_file" ]]; then
        mkdir -p "$(dirname "$config_file")"
        touch "$config_file"
    fi

    # Remove previous Mole completion lines to avoid duplicates
    if [[ -f "$config_file" ]]; then
        original_mode=""
        original_mode="$(stat -f '%Mp%Lp' "$config_file" 2> /dev/null || true)"
        temp_file="$(mktemp)"
        grep -Ev "(^# Mole shell completion$|(mole|mo)[[:space:]]+completion)" "$config_file" > "$temp_file" || true
        mv "$temp_file" "$config_file"
        if [[ -n "$original_mode" ]]; then
            chmod "$original_mode" "$config_file" 2> /dev/null || true
        fi
    fi

    # Add completion line
    {
        echo ""
        echo "# Mole shell completion"
        echo "$completion_line"
    } >> "$config_file"

    echo -e "${GREEN}${ICON_SUCCESS}${NC} 补全已添加到 $config_file"
    echo ""
    echo ""
    echo -e "${GRAY}立即激活:${NC}"
    echo -e "  ${GREEN}source $config_file${NC}"
    exit 0
fi

case "$1" in
    bash)
        cat << EOF
_mole_completions()
{
    local cur_word prev_word subcommand
    cur_word="\${COMP_WORDS[\$COMP_CWORD]}"
    prev_word="\${COMP_WORDS[\$COMP_CWORD-1]}"
    subcommand="\${COMP_WORDS[1]}"

    if [ "\$COMP_CWORD" -eq 1 ]; then
        COMPREPLY=( \$(compgen -W "$command_words" -- "\$cur_word") )
    else
        case "\$subcommand" in
            clean)
                case "\$prev_word" in
                    --external)
                        COMPREPLY=( \$(compgen -d -- "\$cur_word") )
                        ;;
                    *)
                        COMPREPLY=( \$(compgen -W "$clean_option_words" -- "\$cur_word") )
                        ;;
                esac
                ;;
            analyze|analyse)
                if [[ "\$cur_word" == -* ]]; then
                    COMPREPLY=( \$(compgen -W "$analyze_option_words" -- "\$cur_word") )
                else
                    COMPREPLY=( \$(compgen -f -- "\$cur_word") )
                fi
                ;;
            history)
                COMPREPLY=( \$(compgen -W "$history_option_words" -- "\$cur_word") )
                ;;
            purge)
                COMPREPLY=( \$(compgen -W "$purge_option_words" -- "\$cur_word") )
                ;;
            completion)
                COMPREPLY=( \$(compgen -W "bash zsh fish" -- "\$cur_word") )
                ;;
            *)
                COMPREPLY=()
                ;;
        esac
    fi
}

complete -F _mole_completions mole mo
EOF
        ;;
    zsh)
        printf '#compdef mole mo\n\n'
        printf '_mole() {\n'
        printf '    local -a subcommands\n'
        printf '    subcommands=(\n'
        emit_zsh_subcommands
        printf '    )\n'
        printf '    if (( CURRENT == 2 )); then\n'
        printf "        _describe 'subcommand' subcommands\n"
        printf '        return\n'
        printf '    fi\n'
        printf "    case \"\$words[2]\" in\n"
        printf '        clean)\n'
        printf '            _arguments \\\n'
        printf "                '--dry-run[Preview cleanup without making changes]' \\\\\n"
        printf "                '-n[Preview cleanup without making changes]' \\\\\n"
        printf "                '--external[Clean OS metadata from an external volume]:path:_files -/' \\\\\n"
        printf "                '--whitelist[Manage protected paths]' \\\\\n"
        printf "                '--debug[Show detailed logs]' \\\\\n"
        printf "                '(-h --help)'{-h,--help}'[Show help]'\n"
        printf '            ;;\n'
        printf '        analyze|analyse)\n'
        printf '            _arguments \\\n'
        printf "                '--json[Output analysis as JSON]' \\\\\n"
        printf "                '(-h --help)'{-h,--help}'[Show help]' \\\\\n"
        printf "                '*:path:_files'\n"
        printf '            ;;\n'
        printf '        history)\n'
        printf '            _arguments \\\n'
        printf "                '--json[Output history as JSON]' \\\\\n"
        printf "                '--limit[Limit recent entries]:limit:' \\\\\n"
        printf "                '(-h --help)'{-h,--help}'[Show help]'\n"
        printf '            ;;\n'
        printf '        purge)\n'
        printf '            _arguments \\\n'
        printf "                '--paths[Edit custom scan directories]' \\\\\n"
        printf "                '--dry-run[Preview purge actions without making changes]' \\\\\n"
        printf "                '-n[Preview purge actions without making changes]' \\\\\n"
        printf "                '--include-empty[Show zero-size project artifact directories]' \\\\\n"
        printf "                '--debug[Show detailed logs]' \\\\\n"
        printf "                '(-h --help)'{-h,--help}'[Show help]'\n"
        printf '            ;;\n'
        printf '        completion)\n'
        printf "            _arguments '1:shell:(bash zsh fish)'\n"
        printf '            ;;\n'
        printf '        *)\n'
        printf "            _describe 'subcommand' subcommands\n"
        printf '            ;;\n'
        printf '    esac\n'
        printf '}\n\n'
        printf 'compdef _mole mole mo\n'
        ;;
    fish)
        printf '# Completions for mole\n'
        emit_fish_completions mole
        printf '\n# Completions for mo (alias)\n'
        emit_fish_completions mo
        printf '\nfunction __fish_mole_no_subcommand\n'
        printf '    for i in (commandline -opc)\n'
        # shellcheck disable=SC2016
        printf '        if contains -- $i %s\n' "$command_words"
        printf '            return 1\n'
        printf '        end\n'
        printf '    end\n'
        printf '    return 0\n'
        printf 'end\n\n'
        printf 'function __fish_see_subcommand_path\n'
        printf '    string match -q -- "completion" (commandline -opc)[1]\n'
        printf 'end\n'
        ;;
    *)
        cat << 'EOF'
用法: mole completion [bash|zsh|fish]

为 mole 和 mo 命令设置 Shell Tab 补全。

自动安装:
  mole completion              # 自动检测 shell 并安装
  mole completion --dry-run    # 预览配置更改，不写入文件

手动安装:
  mole completion bash         # 生成 bash 补全脚本
  mole completion zsh          # 生成 zsh 补全脚本
  mole completion fish         # 生成 fish 补全脚本

示例:
  # 自动安装（推荐）
  mole completion

  # 手动安装 - Bash
  eval "$(mole completion bash)"

  # 手动安装 - Zsh
  eval "$(mole completion zsh)"

  # 手动安装 - Fish
  mole completion fish | source
EOF
        exit 1
        ;;
esac
