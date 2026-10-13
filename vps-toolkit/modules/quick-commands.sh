#!/usr/bin/env bash
# ==============================================================================
# Android VPS Toolkit — Quick Commands (modules/quick-commands.sh)
# Библиотека быстрых команд и однострочников для частого администрирования
# ==============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "")"
LIB_DIR="${SCRIPT_DIR}/../lib"
if [[ -f "${LIB_DIR}/common.sh" ]]; then
    source "${LIB_DIR}/common.sh"
else
    SSH_DIR="${HOME}/.ssh"
    CONFIG_FILE="${SSH_DIR}/config"
    CONN_TIMEOUT="4"
    BOLD='\033[1m'; DIM='\033[2m'; RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
    print_header() { clear 2>/dev/null || true; echo -e "${BOLD}=== $1 ===${NC}\n"; }
    print_divider() { echo -e "----------------------------------------"; }
    press_enter() { read -rp "Нажмите Enter..."; }
    prompt_select_server() { echo ""; }
fi

QUICK_CMD_FILE="${SSH_DIR}/quick-commands.list"

init_quick_cmds() {
    if [[ ! -f "${QUICK_CMD_FILE}" ]]; then
        cat << 'LIST' > "${QUICK_CMD_FILE}"
Очистка диска и кэша apt|sudo apt-get autoremove -y && sudo apt-get clean && journalctl --vacuum-time=3d
Перезапуск Nginx|sudo systemctl restart nginx && systemctl status nginx --no-pager
Статус Docker и контейнеров|docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
Проверка температуры и CPU|sensors 2>/dev/null || lscpu | grep -i 'mhz\|model name' || cat /proc/cpuinfo | grep 'model name' | head -n 1
Прослушиваемые порты|ss -tulpn | grep LISTEN
Сводка памяти и Swap|free -h && swapon --show
LIST
        chmod 600 "${QUICK_CMD_FILE}"
    fi
}

quick_commands_run() {
    init_quick_cmds
    local s_alias
    s_alias=$(prompt_select_server "Выберите сервер для запуска команды")
    [[ -z "${s_alias}" ]] && return

    while true; do
        clear 2>/dev/null || true
        print_header "БЫСТРЫЕ КОМАНДЫ: ${s_alias}" "Запуск однострочника на сервере"

        local titles=()
        local cmds=()
        while IFS='|' read -r t c; do
            [[ -z "$t" || -z "$c" ]] && continue
            titles+=("$t")
            cmds+=("$c")
        done < "${QUICK_CMD_FILE}"

        for (( i=0; i<${#titles[@]}; i++ )); do
            printf "  %2d. %s\n" "$((i+1))" "${titles[$i]}"
        done
        echo ""
        echo "  A. Добавить свою команду"
        echo "  0. Назад к выбору сервера"
        print_divider
        read -rp "Выберите команду [1-${#titles[@]}]: " q_sel

        case "${q_sel}" in
            0|[qQ]) return ;;
            [Aa])
                read -rp "Название команды: " new_t
                read -rp "Текст команды (bash): " new_c
                if [[ -n "${new_t}" && -n "${new_c}" ]]; then
                    echo "${new_t}|${new_c}" >> "${QUICK_CMD_FILE}"
                    echo -e "${GREEN}✓ Команда сохранена.${NC}"; sleep 1
                fi
                continue
                ;;
            *)
                if [[ "${q_sel}" =~ ^[0-9]+$ ]] && (( q_sel >= 1 && q_sel <= ${#titles[@]} )); then
                    local sel_t="${titles[$((q_sel-1))]}"
                    local sel_c="${cmds[$((q_sel-1))]}"
                    clear 2>/dev/null || true
                    print_header "ВЫПОЛНЕНИЕ: ${sel_t}" "${sel_c}"
                    ssh -F "${CONFIG_FILE}" -o ConnectTimeout="${CONN_TIMEOUT}" "${s_alias}" "${sel_c}" || echo "Ошибка выполнения."
                    press_enter
                else
                    echo -e "${RED}Неверный номер.${NC}"; sleep 1
                fi
                ;;
        esac
    done
}

quick_commands_main() {
    init_quick_cmds
    while true; do
        clear 2>/dev/null || true
        echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
        echo -e "${BOLD}               QUICK COMMANDS                       ${NC}"
        echo -e "${DIM}      Библиотека быстрых команд для серверов        ${NC}"
        echo -e "${BLUE}════════════════════════════════════════════════════${NC}\n"

        echo "  1. Запустить быструю команду на сервере"
        echo "  2. Просмотреть список команд"
        echo "  3. Добавить новую команду"
        echo ""
        echo "  0. Назад в главное меню"
        print_divider
        read -rp "Выберите действие [0–3]: " choice

        case "${choice}" in
            1) quick_commands_run ;;
            2)
                print_header "СПИСОК БЫСТРЫХ КОМАНД"
                cat -n "${QUICK_CMD_FILE}"
                press_enter
                ;;
            3)
                print_header "ДОБАВЛЕНИЕ КОМАНДЫ"
                read -rp "Название: " new_t
                read -rp "Команда bash: " new_c
                if [[ -n "${new_t}" && -n "${new_c}" ]]; then
                    echo "${new_t}|${new_c}" >> "${QUICK_CMD_FILE}"
                    echo -e "${GREEN}✓ Команда добавлена.${NC}"
                fi
                press_enter
                ;;
            0|[qQ]) return ;;
            *) echo -e "${RED}Неверный ввод.${NC}"; sleep 1 ;;
        esac
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    quick_commands_main "$@"
fi
