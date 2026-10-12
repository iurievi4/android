#!/usr/bin/env bash
# ==============================================================================
# Android VPS Toolkit — Главный командный пульт (vps-toolkit.sh)
# Полный комплект инструментов для управления VPS и сетью в Termux
# Репозиторий: https://github.com/iurievi4/android
# ==============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "")"
LIB_DIR="${SCRIPT_DIR}/lib"
MODULES_DIR="${SCRIPT_DIR}/modules"

if [[ -f "${LIB_DIR}/common.sh" ]]; then
    # shellcheck source=/dev/null
    source "${LIB_DIR}/common.sh"
else
    BOLD='\033[1m'; DIM='\033[2m'; RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
    SSH_DIR="${HOME}/.ssh"
    CONFIG_FILE="${SSH_DIR}/config"
    get_hosts() { awk '$1 ~ /^[Hh][Oo][Ss][Tt]$/ {for (i=2; i<=NF; i++) if ($i != "*") print $i}' "${CONFIG_FILE}" 2>/dev/null | sort -u; }
fi

# Прямой вызов субмодулей через аргументы командной строки
if [[ $# -gt 0 ]]; then
    case "$1" in
        ssh|ssh-manager|control)   shift; exec "${SCRIPT_DIR}/ssh-manager.sh" "$@" ;;
        monitor|mon)               shift; exec "${MODULES_DIR}/vps-monitor.sh" "$@" ;;
        sftp|files)                shift; exec "${MODULES_DIR}/vps-sftp.sh" "$@" ;;
        sec|security|audit)        shift; exec "${MODULES_DIR}/vps-security.sh" "$@" ;;
        net|netdiag|diag)          shift; exec "${MODULES_DIR}/net-diag.sh" "$@" ;;
        backup|backups)            shift; exec "${MODULES_DIR}/backup-manager.sh" "$@" ;;
        docker)                    shift; exec "${MODULES_DIR}/docker-manager.sh" "$@" ;;
        service|services)          shift; exec "${MODULES_DIR}/service-manager.sh" "$@" ;;
        logs|log)                  shift; exec "${MODULES_DIR}/log-viewer.sh" "$@" ;;
        ports|scan)                shift; exec "${MODULES_DIR}/port-scanner.sh" "$@" ;;
        git|deploy)                shift; exec "${MODULES_DIR}/git-deploy.sh" "$@" ;;
        clean|maint|maintenance)   shift; exec "${MODULES_DIR}/termux-maintenance.sh" "$@" ;;
        keys|key)                  shift; exec "${MODULES_DIR}/ssh-key-manager.sh" "$@" ;;
        quick|cmd)                 shift; exec "${MODULES_DIR}/quick-commands.sh" "$@" ;;
    esac
fi

vps_toolkit_main_menu() {
    while true; do
        clear 2>/dev/null || true
        local hosts=()
        while IFS= read -r h; do [[ -n "$h" ]] && hosts+=("$h"); done < <(get_hosts)
        local total=${#hosts[@]}

        echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
        echo -e "${BOLD}              ANDROID VPS TOOLKIT                   ${NC}"
        echo -e "${DIM}      Мобильный командный пульт администрирования   ${NC}"
        echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
        echo -e "  Настроено серверов: ${BOLD}${total}${NC}\n"

        echo -e "  ${GREEN}1. VPS Control Center (SSH Manager)${NC}"
        echo -e "  ${CYAN}2. VPS Monitor (Сводный онлайн-мониторинг)${NC}"
        echo -e "  ${YELLOW}3. SFTP File Manager (Файловый менеджер)${NC}"
        echo -e "  ${MAGENTA}4. VPS Security Audit (Аудит безопасности)${NC}"
        echo -e "  ${BLUE}5. NetDiag (Сетевая диагностика)${NC}"
        echo -e "  ${YELLOW}6. Backup Manager (Резервные копии)${NC}"
        echo -e "  ${CYAN}7. Docker Manager (Контейнеры)${NC}"
        echo -e "  ${GREEN}8. Service Manager (Службы systemd)${NC}"
        echo -e "  ${BLUE}9. Log Viewer (Журналы и логи)${NC}"
        echo -e " 10. Port Scanner (Сканер портов и сокетов)"
        echo -e " 11. Git Deploy (Обновления из репозиториев)"
        echo -e " 12. Termux Maintenance (Очистка и память)"
        echo -e " 13. SSH Key Manager (Управление ключами)"
        echo -e " 14. Quick Commands (Библиотека быстрых команд)"
        echo ""
        echo -e "  ${RED}0. Выход${NC}"
        echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
        read -rp "Выберите модуль [0–14]: " choice

        case "${choice}" in
            1)
                if [[ -f "${SCRIPT_DIR}/ssh-manager.sh" ]]; then
                    "${SCRIPT_DIR}/ssh-manager.sh"
                elif [[ -f "${PREFIX:-/usr/local}/bin/ssh-manager" ]]; then
                    "${PREFIX:-/usr/local}/bin/ssh-manager"
                fi
                ;;
            2)  [[ -f "${MODULES_DIR}/vps-monitor.sh" ]] && "${MODULES_DIR}/vps-monitor.sh" ;;
            3)  [[ -f "${MODULES_DIR}/vps-sftp.sh" ]] && "${MODULES_DIR}/vps-sftp.sh" ;;
            4)  [[ -f "${MODULES_DIR}/vps-security.sh" ]] && "${MODULES_DIR}/vps-security.sh" ;;
            5)  [[ -f "${MODULES_DIR}/net-diag.sh" ]] && "${MODULES_DIR}/net-diag.sh" ;;
            6)  [[ -f "${MODULES_DIR}/backup-manager.sh" ]] && "${MODULES_DIR}/backup-manager.sh" ;;
            7)  [[ -f "${MODULES_DIR}/docker-manager.sh" ]] && "${MODULES_DIR}/docker-manager.sh" ;;
            8)  [[ -f "${MODULES_DIR}/service-manager.sh" ]] && "${MODULES_DIR}/service-manager.sh" ;;
            9)  [[ -f "${MODULES_DIR}/log-viewer.sh" ]] && "${MODULES_DIR}/log-viewer.sh" ;;
            10) [[ -f "${MODULES_DIR}/port-scanner.sh" ]] && "${MODULES_DIR}/port-scanner.sh" ;;
            11) [[ -f "${MODULES_DIR}/git-deploy.sh" ]] && "${MODULES_DIR}/git-deploy.sh" ;;
            12) [[ -f "${MODULES_DIR}/termux-maintenance.sh" ]] && "${MODULES_DIR}/termux-maintenance.sh" ;;
            13) [[ -f "${MODULES_DIR}/ssh-key-manager.sh" ]] && "${MODULES_DIR}/ssh-key-manager.sh" ;;
            14) [[ -f "${MODULES_DIR}/quick-commands.sh" ]] && "${MODULES_DIR}/quick-commands.sh" ;;
            0|[qQ])
                clear 2>/dev/null || true
                exit 0
                ;;
            *)
                echo -e "${RED}Неверный номер. Введите число от 0 до 14.${NC}"
                sleep 1.2
                ;;
        esac
    done
}

vps_toolkit_main_menu "$@"
