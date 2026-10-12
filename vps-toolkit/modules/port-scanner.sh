#!/usr/bin/env bash
# ==============================================================================
# Android VPS Toolkit — Port Scanner (modules/port-scanner.sh)
# Проверка открытых портов на серверах и локальный аудит сокетов
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

port_scanner_listen() {
    local target="$1"
    print_header "СЛУШАЮЩИЕ ПОРТЫ: ${target}" "Внутренний аудит служб (LISTEN)"
    ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}"         "echo -e 'Proto\tRecv-Q\tSend-Q\tLocal Address:Port\tProcess';
         ss -tulpn 2>/dev/null | grep LISTEN || netstat -tulpn 2>/dev/null | grep LISTEN || echo 'Нет данных.'"
    press_enter
}

port_scanner_range() {
    local target="$1"
    local hn
    hn=$(ssh -F "${CONFIG_FILE}" -G "${target}" 2>/dev/null | awk '$1=="hostname"{print $2}')
    hn="${hn:-${target}}"

    print_header "СКАНИРОВАНИЕ ПОРТОВ: ${target}" "Внешний опрос со стороны телефона"
    echo -e "Целевой хост: ${BOLD}${hn}${NC}\n"

    read -rp "Список портов через пробел (по умолчанию: 22 80 443 1241 8080 8443): " ports_input
    ports_input="${ports_input:-22 80 443 1241 8080 8443}"

    echo -e "\n${CYAN}Сканирование сокетов...${NC}"
    for p in ${ports_input}; do
        printf "  Порт %-6s ... " "${p}"
        if (timeout 2 bash -c "echo > /dev/tcp/${hn}/${p}") 2>/dev/null; then
            echo -e "${GREEN}✓ ОТКРЫТ (OPEN)${NC}"
        else
            echo -e "${RED}✗ ЗАКРЫТ / ТАЙМАУТ${NC}"
        fi
    done
    press_enter
}

port_scanner_main() {
    while true; do
        clear 2>/dev/null || true
        echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
        echo -e "${BOLD}                 PORT SCANNER                       ${NC}"
        echo -e "${DIM}     Проверка открытых портов и конфликтов сокетов  ${NC}"
        echo -e "${BLUE}════════════════════════════════════════════════════${NC}\n"

        echo "  1. Просмотреть все слушающие порты на сервере (LISTEN)"
        echo "  2. Просканировать список внешних портов со смартфона"
        echo "  3. Проверить произвольный сторонний IP/хост"
        echo ""
        echo "  0. Назад в главное меню"
        print_divider
        read -rp "Выберите действие [0–3]: " choice

        case "${choice}" in
            1)
                local s_alias
                s_alias=$(prompt_select_server "Выберите сервер")
                [[ -n "${s_alias}" ]] && port_scanner_listen "${s_alias}"
                ;;
            2)
                local s_alias
                s_alias=$(prompt_select_server "Выберите сервер")
                [[ -n "${s_alias}" ]] && port_scanner_range "${s_alias}"
                ;;
            3)
                print_header "ВНЕШНИЙ СКАНЕР ПОРТОВ"
                read -rp "IP или хост: " ext_h
                read -rp "Порты (например: 22 80 443): " ext_p
                ext_p="${ext_p:-22 80 443}"
                if [[ -n "${ext_h}" ]]; then
                    echo -e "\n${CYAN}Опрос ${ext_h}...${NC}"
                    for p in ${ext_p}; do
                        printf "  Порт %-6s ... " "${p}"
                        if (timeout 2 bash -c "echo > /dev/tcp/${ext_h}/${p}") 2>/dev/null; then
                            echo -e "${GREEN}✓ OPEN${NC}"
                        else
                            echo -e "${RED}✗ CLOSED${NC}"
                        fi
                    done
                    press_enter
                fi
                ;;
            0|[qQ]) return ;;
            *) echo -e "${RED}Неверный ввод.${NC}"; sleep 1 ;;
        esac
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    port_scanner_main "$@"
fi
