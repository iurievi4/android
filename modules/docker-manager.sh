#!/usr/bin/env bash
# ==============================================================================
# Android VPS Toolkit — Docker Manager (modules/docker-manager.sh)
# Управление контейнерами Docker: статус, логи, перезапуск, статистика, образы
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

docker_manager_server() {
    local target="$1"

    if ! ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}" "command -v docker >/dev/null 2>&1" 2>/dev/null; then
        print_header "DOCKER: ${target}"
        echo -e "${YELLOW}Docker не установлен на сервере ${target}.${NC}"
        press_enter; return
    fi

    while true; do
        clear 2>/dev/null || true
        print_header "DOCKER MANAGER: ${target}" "Управление контейнерами и образами"

        echo -e "${CYAN}Список контейнеров (docker ps -a):${NC}"
        ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}"             "docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null | head -n 20" || echo "Ошибка получения списка."
        echo ""

        echo "  1. Просмотреть логи контейнера"
        echo "  2. Перезапустить контейнер"
        echo "  3. Остановить контейнер"
        echo "  4. Запустить контейнер"
        echo "  5. Статистика ресурсов (docker stats)"
        echo "  6. Список образов (docker images)"
        echo "  7. Очистка неиспользуемых образов (docker system prune)"
        echo ""
        echo "  0. Назад к выбору сервера"
        print_divider
        read -rp "Выберите действие [0–7]: " act

        case "${act}" in
            1)
                read -rp "Имя контейнера: " cname
                if [[ -n "${cname}" ]]; then
                    print_header "ЛОГИ: ${cname} (${target})"
                    ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}"                         "docker logs --tail ${LOG_LINES:-30} '${cname}'" || true
                    press_enter
                fi
                ;;
            2)
                read -rp "Имя контейнера для перезапуска: " cname
                if [[ -n "${cname}" ]]; then
                    ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}"                         "docker restart '${cname}'" && echo -e "${GREEN}✓ Перезапущен.${NC}" || echo -e "${RED}Ошибка.${NC}"
                    press_enter
                fi
                ;;
            3)
                read -rp "Имя контейнера для остановки: " cname
                if [[ -n "${cname}" ]]; then
                    ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}"                         "docker stop '${cname}'" && echo -e "${GREEN}✓ Остановлен.${NC}" || echo -e "${RED}Ошибка.${NC}"
                    press_enter
                fi
                ;;
            4)
                read -rp "Имя контейнера для запуска: " cname
                if [[ -n "${cname}" ]]; then
                    ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}"                         "docker start '${cname}'" && echo -e "${GREEN}✓ Запущен.${NC}" || echo -e "${RED}Ошибка.${NC}"
                    press_enter
                fi
                ;;
            5)
                print_header "DOCKER STATS: ${target}"
                ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}"                     "docker stats --no-stream" || true
                press_enter
                ;;
            6)
                print_header "DOCKER IMAGES: ${target}"
                ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}"                     "docker images" || true
                press_enter
                ;;
            7)
                read -rp "Запустить docker system prune -f? (y/N): " conf_p
                if [[ "${conf_p}" =~ ^[Yy]$ ]]; then
                    ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}"                         "docker system prune -f" || true
                    press_enter
                fi
                ;;
            0|[qQ]) return ;;
            *) echo -e "${RED}Неверный ввод.${NC}"; sleep 1 ;;
        esac
    done
}

docker_manager_main() {
    while true; do
        clear 2>/dev/null || true
        echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
        echo -e "${BOLD}                 DOCKER MANAGER                     ${NC}"
        echo -e "${DIM}      Управление контейнерами на удалённых VPS       ${NC}"
        echo -e "${BLUE}════════════════════════════════════════════════════${NC}\n"

        local s_alias
        s_alias=$(prompt_select_server "Выберите сервер для управления Docker")
        [[ -z "${s_alias}" ]] && return

        docker_manager_server "${s_alias}"
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    docker_manager_main "$@"
fi
