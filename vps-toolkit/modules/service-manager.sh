#!/usr/bin/env bash
# ==============================================================================
# Android VPS Toolkit — Service Manager (modules/service-manager.sh)
# Управление systemd службами: статус, запуск, остановка, перезапуск и журнал
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
    LOG_LINES="30"
    BOLD='\033[1m'; DIM='\033[2m'; RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
    print_header() { clear 2>/dev/null || true; echo -e "${BOLD}=== $1 ===${NC}\n"; }
    print_divider() { echo -e "----------------------------------------"; }
    press_enter() { read -rp "Нажмите Enter..."; }
    prompt_select_server() { echo ""; }
fi

service_manager_server() {
    local target="$1"

    while true; do
        clear 2>/dev/null || true
        print_header "СЛУЖБЫ SYSTEMD: ${target}" "Управление сервисами Linux"

        echo -e "${CYAN}Ключевые системные службы:${NC}"
        ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}"             "for s in nginx ssh sshd docker fail2ban ufw 3x-ui x-ui warp-svc xray; do
                if systemctl list-unit-files \${s}.service >/dev/null 2>&1; then
                    st=\$(systemctl is-active \${s} 2>/dev/null || echo 'inactive')
                    printf '  %-14s [%s]\n' "\${s}" "\${st}"
                fi
            done" 2>/dev/null || echo "Не удалось получить статус."
        echo ""

        echo "  1. Проверить статус конкретной службы (systemctl status)"
        echo "  2. Перезапустить службу (restart)"
        echo "  3. Остановить службу (stop)"
        echo "  4. Запустить службу (start)"
        echo "  5. Просмотреть журнал службы (journalctl -u)"
        echo "  6. Список всех работающих служб (running services)"
        echo ""
        echo "  0. Назад к выбору сервера"
        print_divider
        read -rp "Выберите действие [0–6]: " act

        case "${act}" in
            1)
                read -rp "Имя службы (например, nginx, ssh, docker): " sname
                if [[ -n "${sname}" ]]; then
                    print_header "СТАТУС: ${sname} (${target})"
                    ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}"                         "systemctl status '${sname}' --no-pager -l" || true
                    press_enter
                fi
                ;;
            2)
                read -rp "Имя службы для перезапуска: " sname
                if [[ -n "${sname}" ]]; then
                    read -rp "Перезапустить '${sname}'? (y/N): " conf_r
                    if [[ "${conf_r}" =~ ^[Yy]$ ]]; then
                        ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}"                             "sudo systemctl restart '${sname}' || systemctl restart '${sname}'" && echo -e "${GREEN}✓ Перезапущено.${NC}" || echo -e "${RED}Ошибка.${NC}"
                        press_enter
                    fi
                fi
                ;;
            3)
                read -rp "Имя службы для остановки: " sname
                if [[ -n "${sname}" ]]; then
                    read -rp "Остановить '${sname}'? (y/N): " conf_s
                    if [[ "${conf_s}" =~ ^[Yy]$ ]]; then
                        ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}"                             "sudo systemctl stop '${sname}' || systemctl stop '${sname}'" && echo -e "${GREEN}✓ Остановлено.${NC}" || echo -e "${RED}Ошибка.${NC}"
                        press_enter
                    fi
                fi
                ;;
            4)
                read -rp "Имя службы для запуска: " sname
                if [[ -n "${sname}" ]]; then
                    ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}"                         "sudo systemctl start '${sname}' || systemctl start '${sname}'" && echo -e "${GREEN}✓ Запущено.${NC}" || echo -e "${RED}Ошибка.${NC}"
                    press_enter
                fi
                ;;
            5)
                read -rp "Имя службы для чтения журнала: " sname
                if [[ -n "${sname}" ]]; then
                    print_header "ЖУРНАЛ: ${sname} (${target})"
                    ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}"                         "journalctl -u '${sname}' -n ${LOG_LINES:-30} --no-pager" || true
                    press_enter
                fi
                ;;
            6)
                print_header "АКТИВНЫЕ СЛУЖБЫ: ${target}"
                ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}"                     "systemctl list-units --type=service --state=running --no-pager | head -n 30" || true
                press_enter
                ;;
            0|[qQ]) return ;;
            *) echo -e "${RED}Неверный ввод.${NC}"; sleep 1 ;;
        esac
    done
}

service_manager_main() {
    while true; do
        clear 2>/dev/null || true
        echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
        echo -e "${BOLD}                SERVICE MANAGER                     ${NC}"
        echo -e "${DIM}         Управление службами systemd на VPS         ${NC}"
        echo -e "${BLUE}════════════════════════════════════════════════════${NC}\n"

        local s_alias
        s_alias=$(prompt_select_server "Выберите сервер для управления службами")
        [[ -z "${s_alias}" ]] && return

        service_manager_server "${s_alias}"
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    service_manager_main "$@"
fi
