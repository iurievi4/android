#!/usr/bin/env bash
# ==============================================================================
# Android VPS Toolkit — Log Viewer (modules/log-viewer.sh)
# Просмотр системных журналов и логов приложений с фильтрацией
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
    LOG_LINES="35"
    BOLD='\033[1m'; DIM='\033[2m'; RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
    print_header() { clear 2>/dev/null || true; echo -e "${BOLD}=== $1 ===${NC}\n"; }
    print_divider() { echo -e "----------------------------------------"; }
    press_enter() { read -rp "Нажмите Enter..."; }
    prompt_select_server() { echo ""; }
fi

log_viewer_server() {
    local target="$1"

    while true; do
        clear 2>/dev/null || true
        print_header "LOG VIEWER: ${target}" "Просмотр журналов и ошибок"

        echo "  1. Критические ошибки системы (journalctl -p 3 -xb)"
        echo "  2. Попытки авторизации SSH (auth.log / journalctl -u ssh)"
        echo "  3. Журнал ядра и оборудования (dmesg | tail)"
        echo "  4. Логи веб-сервера Nginx (/var/log/nginx/error.log)"
        echo "  5. Логи конкретной systemd службы"
        echo "  6. Логи Docker контейнера"
        echo "  7. Просмотреть произвольный файл лога (/var/log/...)"
        echo ""
        echo "  0. Назад к выбору сервера"
        print_divider
        read -rp "Выберите действие [0–7]: " act

        case "${act}" in
            1)
                print_header "СИСТЕМНЫЕ ОШИБКИ: ${target}"
                ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}"                     "journalctl -p 3 -xb -n ${LOG_LINES:-35} --no-pager" || echo "Записей нет."
                press_enter
                ;;
            2)
                print_header "SSH ЛОГИ: ${target}"
                ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}"                     "grep -i 'failed password' /var/log/auth.log 2>/dev/null | tail -n ${LOG_LINES:-35} || journalctl -u ssh -u sshd -n ${LOG_LINES:-35} --no-pager 2>/dev/null | grep -i 'failed' || echo 'Подозрительных записей нет.'"
                press_enter
                ;;
            3)
                print_header "DMESG: ${target}"
                ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}"                     "dmesg 2>/dev/null | tail -n ${LOG_LINES:-35} || echo 'Нет прав доступа к dmesg.'"
                press_enter
                ;;
            4)
                print_header "NGINX ОШИБКИ: ${target}"
                ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}"                     "tail -n ${LOG_LINES:-35} /var/log/nginx/error.log 2>/dev/null || echo 'Файл /var/log/nginx/error.log не найден.'"
                press_enter
                ;;
            5)
                read -rp "Имя службы: " sname
                if [[ -n "${sname}" ]]; then
                    print_header "ЖУРНАЛ СЛУЖБЫ: ${sname}"
                    ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}"                         "journalctl -u '${sname}' -n ${LOG_LINES:-35} --no-pager" || true
                    press_enter
                fi
                ;;
            6)
                read -rp "Имя контейнера Docker: " cname
                if [[ -n "${cname}" ]]; then
                    print_header "DOCKER ЛОГИ: ${cname}"
                    ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}"                         "docker logs --tail ${LOG_LINES:-35} '${cname}'" || true
                    press_enter
                fi
                ;;
            7)
                read -rp "Путь к лог-файлу (например, /var/log/syslog): " log_f
                if [[ -n "${log_f}" ]]; then
                    print_header "ФАЙЛ: ${log_f}"
                    ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}"                         "tail -n ${LOG_LINES:-35} '${log_f}' 2>/dev/null || echo 'Не удалось прочитать файл.'"
                    press_enter
                fi
                ;;
            0|[qQ]) return ;;
            *) echo -e "${RED}Неверный ввод.${NC}"; sleep 1 ;;
        esac
    done
}

log_viewer_main() {
    while true; do
        clear 2>/dev/null || true
        echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
        echo -e "${BOLD}                   LOG VIEWER                       ${NC}"
        echo -e "${DIM}      Просмотр и фильтрация системных логов         ${NC}"
        echo -e "${BLUE}════════════════════════════════════════════════════${NC}\n"

        local s_alias
        s_alias=$(prompt_select_server "Выберите сервер для просмотра логов")
        [[ -z "${s_alias}" ]] && return

        log_viewer_server "${s_alias}"
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    log_viewer_main "$@"
fi
