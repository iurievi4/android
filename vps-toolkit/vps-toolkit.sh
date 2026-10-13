#!/usr/bin/env bash
# ==============================================================================
# Android VPS Toolkit — Главный командный пульт (vps-toolkit.sh)
# Автономный лаунчер с автоматической докачкой модулей из GitHub на лету
# Репозиторий: https://github.com/iurievi4/android
# ==============================================================================

set -uo pipefail

GITHUB_USER="iurievi4"
REPO_NAME="android"
BRANCH="main"
RAW_BASE="https://raw.githubusercontent.com/${GITHUB_USER}/${REPO_NAME}/${BRANCH}/vps-toolkit"
RAW_BASE_ROOT="https://raw.githubusercontent.com/${GITHUB_USER}/${REPO_NAME}/${BRANCH}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "")"

# Определение базовой рабочей директории компонентов
if [[ -d "${SCRIPT_DIR}/modules" && -f "${SCRIPT_DIR}/lib/common.sh" ]]; then
    # Локальный репозиторий / распакованная папка
    BASE_DIR="${SCRIPT_DIR}"
elif [[ -d "${PREFIX:-/data/data/com.termux/files/usr}/opt/vps-toolkit" ]]; then
    BASE_DIR="${PREFIX:-/data/data/com.termux/files/usr}/opt/vps-toolkit"
else
    # Одиночный скрипт (скачан в $PREFIX/bin или домашнюю папку)
    BASE_DIR="${HOME}/.vps-toolkit"
fi

LIB_DIR="${BASE_DIR}/lib"
MODULES_DIR="${BASE_DIR}/modules"

mkdir -p "${LIB_DIR}" "${MODULES_DIR}"

# Цветовая палитра (базовая, если библиотека ещё не загружена)
BOLD='\033[1m'; DIM='\033[2m'; RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; NC='\033[0m'
SSH_DIR="${HOME}/.ssh"
CONFIG_FILE="${SSH_DIR}/config"

# Функция гарантированной загрузки компонента из GitHub
ensure_component() {
    local rel_path="$1"
    local full_path="${BASE_DIR}/${rel_path}"

    if [[ ! -f "${full_path}" ]]; then
        echo -e "\n${CYAN}Компонент '${rel_path}' не найден локально.${NC}"
        echo -e "${YELLOW}Загрузка из GitHub (${GITHUB_USER}/${REPO_NAME})...${NC}"
        mkdir -p "$(dirname "${full_path}")"

        local url1="${RAW_BASE}/${rel_path}?$(date +%s)"
        local url2="${RAW_BASE_ROOT}/${rel_path}?$(date +%s)"
        if curl -fsSL -H "Cache-Control: no-cache" "${url1}" -o "${full_path}" 2>/dev/null || \
           curl -fsSL -H "Cache-Control: no-cache" "${url2}" -o "${full_path}" 2>/dev/null; then
            chmod +x "${full_path}" 2>/dev/null || true
            echo -e "${GREEN}✓ ${rel_path} успешно загружен.${NC}\n"
            sleep 0.5
        else
            echo -e "${RED}✗ Не удалось скачать ${rel_path} с GitHub.${NC}"
            echo -e "${DIM}Проверьте подключение к интернету или репозиторий.${NC}"
            read -rp "Нажмите Enter для продолжения..." _
            return 1
        fi
    fi
    chmod +x "${full_path}" 2>/dev/null || true
    return 0
}

# Подключение общей библиотеки (с автодокачкой при отсутствии)
if [[ ! -f "${LIB_DIR}/common.sh" ]]; then
    ensure_component "lib/common.sh" >/dev/null 2>&1 || true
fi
if [[ -f "${LIB_DIR}/common.sh" ]]; then
    # shellcheck source=/dev/null
    source "${LIB_DIR}/common.sh"
else
    get_hosts() { awk '$1 ~ /^[Hh][Oo][Ss][Tt]$/ {for (i=2; i<=NF; i++) if ($i != "*") print $i}' "${CONFIG_FILE}" 2>/dev/null | sort -u; }
fi

# Пакетная загрузка / обновление всех модулей
download_all_modules() {
    clear 2>/dev/null || true
    echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}       СИНХРОНИЗАЦИЯ ВСЕХ МОДУЛЕЙ ИЗ GITHUB         ${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════${NC}\n"
    echo -e "Репозиторий:  ${CYAN}https://github.com/${GITHUB_USER}/${REPO_NAME}${NC}"
    echo -e "Куда ставить: ${BASE_DIR}\n"

    local all_components=(
        "lib/common.sh"
        "ssh-manager.sh"
        "modules/vps-monitor.sh"
        "modules/vps-sftp.sh"
        "modules/vps-security.sh"
        "modules/net-diag.sh"
        "modules/backup-manager.sh"
        "modules/docker-manager.sh"
        "modules/service-manager.sh"
        "modules/log-viewer.sh"
        "modules/port-scanner.sh"
        "modules/git-deploy.sh"
        "modules/termux-maintenance.sh"
        "modules/ssh-key-manager.sh"
        "modules/quick-commands.sh"
    )

    local success_count=0
    local total=${#all_components[@]}

    for (( i=0; i<total; i++ )); do
        local comp="${all_components[$i]}"
        printf " [%2d/%d] Загрузка %-30s ... " "$((i+1))" "${total}" "${comp}"
        local full_p="${BASE_DIR}/${comp}"
        mkdir -p "$(dirname "${full_p}")"
        local url1="${RAW_BASE}/${comp}?$(date +%s)"
        local url2="${RAW_BASE_ROOT}/${comp}?$(date +%s)"
        if curl -fsSL -H "Cache-Control: no-cache" "${url1}" -o "${full_p}" 2>/dev/null || \
           curl -fsSL -H "Cache-Control: no-cache" "${url2}" -o "${full_p}" 2>/dev/null; then
            chmod +x "${full_p}"
            echo -e "${GREEN}✓ OK${NC}"
            success_count=$((success_count + 1))
        else
            echo -e "${RED}✗ ОШИБКА${NC}"
        fi
    done

    echo -e "\n${BLUE}────────────────────────────────────────────────────${NC}"
    echo -e "${BOLD}Итог: загружено ${success_count} из ${total} компонентов.${NC}"
    read -rp "Нажмите Enter для возврата в меню..." _
}

# Проверка первого запуска: если модулей нет вообще, предлагаем скачать все сразу
check_first_run() {
    local existing
    existing=$(find "${MODULES_DIR}" -name "*.sh" 2>/dev/null | wc -l)
    if [[ $existing -eq 0 && ! -f "${BASE_DIR}/ssh-manager.sh" ]]; then
        clear 2>/dev/null || true
        echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
        echo -e "${BOLD}       ДОБРО ПОЖАЛОВАТЬ В ANDROID VPS TOOLKIT       ${NC}"
        echo -e "${BLUE}════════════════════════════════════════════════════${NC}\n"
        echo -e "Обнаружен первый запуск одиночного скрипта."
        echo -e "Модули будут сохранены в: ${CYAN}${BASE_DIR}${NC}\n"
        read -rp "Загрузить все 14 модулей из GitHub сейчас? (Y/n): " first_q
        if [[ ! "${first_q}" =~ ^[Nn]$ ]]; then
            download_all_modules
        fi
    fi
}

# Прямой вызов субмодулей через аргументы командной строки
if [[ $# -gt 0 ]]; then
    case "$1" in
        ssh|ssh-manager|control)   shift; ensure_component "ssh-manager.sh" && exec "${BASE_DIR}/ssh-manager.sh" "$@" ;;
        monitor|mon)               shift; ensure_component "modules/vps-monitor.sh" && exec "${MODULES_DIR}/vps-monitor.sh" "$@" ;;
        sftp|files)                shift; ensure_component "modules/vps-sftp.sh" && exec "${MODULES_DIR}/vps-sftp.sh" "$@" ;;
        sec|security|audit)        shift; ensure_component "modules/vps-security.sh" && exec "${MODULES_DIR}/vps-security.sh" "$@" ;;
        net|netdiag|diag)          shift; ensure_component "modules/net-diag.sh" && exec "${MODULES_DIR}/net-diag.sh" "$@" ;;
        backup|backups)            shift; ensure_component "modules/backup-manager.sh" && exec "${MODULES_DIR}/backup-manager.sh" "$@" ;;
        docker)                    shift; ensure_component "modules/docker-manager.sh" && exec "${MODULES_DIR}/docker-manager.sh" "$@" ;;
        service|services)          shift; ensure_component "modules/service-manager.sh" && exec "${MODULES_DIR}/service-manager.sh" "$@" ;;
        logs|log)                  shift; ensure_component "modules/log-viewer.sh" && exec "${MODULES_DIR}/log-viewer.sh" "$@" ;;
        ports|scan)                shift; ensure_component "modules/port-scanner.sh" && exec "${MODULES_DIR}/port-scanner.sh" "$@" ;;
        git|deploy)                shift; ensure_component "modules/git-deploy.sh" && exec "${MODULES_DIR}/git-deploy.sh" "$@" ;;
        clean|maint|maintenance)   shift; ensure_component "modules/termux-maintenance.sh" && exec "${MODULES_DIR}/termux-maintenance.sh" "$@" ;;
        keys|key)                  shift; ensure_component "modules/ssh-key-manager.sh" && exec "${MODULES_DIR}/ssh-key-manager.sh" "$@" ;;
        quick|cmd)                 shift; ensure_component "modules/quick-commands.sh" && exec "${MODULES_DIR}/quick-commands.sh" "$@" ;;
        update|sync)               shift; download_all_modules; exit 0 ;;
    esac
fi

check_first_run

vps_toolkit_main_menu() {
    while true; do
        clear 2>/dev/null || true
        local hosts=()
        while IFS= read -r h; do [[ -n "$h" ]] && hosts+=("$h"); done < <(get_hosts)
        local total=${#hosts[@]}

        echo -e "${CYAN}╔═══════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${NC}   ${BOLD}_   _ ____  ____    _____ ___   ___ _       ${NC}${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${BOLD}| | | |  _ \/ ___|  |_   _/ _ \ / _ \ |      ${NC}${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${BOLD}| | | | |_) \___ \    | || | | | | | | |      ${NC}${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${BOLD} \ \_/ /  __/ ___) |   | || |_| | |_| | |      ${NC}${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${BOLD}  \___/|_|   |____/    |_| \___/ \___/|_|      ${NC}${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}        ${GREEN}${BOLD}ANDROID VPS TOOLKIT v1.2${NC}               ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}     ${DIM}Pocket Admin Console for Termux${NC}           ${CYAN}║${NC}"
        echo -e "${CYAN}╚═══════════════════════════════════════════════╝${NC}"
        echo -e "  Подключено серверов: ${GREEN}${BOLD}${total}${NC}  •  Termux Android"
        echo -e "${BLUE}─────────────────────────────────────────────────${NC}\n"

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
        echo -e " 15. ${CYAN}Синхронизировать / обновить все модули из GitHub${NC}"
        echo ""
        echo -e "  ${RED}0. Выход${NC}"
        echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
        read -rp "Выберите модуль [0–15]: " choice

        case "${choice}" in
            1)  ensure_component "ssh-manager.sh" && "${BASE_DIR}/ssh-manager.sh" ;;
            2)  ensure_component "modules/vps-monitor.sh" && "${MODULES_DIR}/vps-monitor.sh" ;;
            3)  ensure_component "modules/vps-sftp.sh" && "${MODULES_DIR}/vps-sftp.sh" ;;
            4)  ensure_component "modules/vps-security.sh" && "${MODULES_DIR}/vps-security.sh" ;;
            5)  ensure_component "modules/net-diag.sh" && "${MODULES_DIR}/net-diag.sh" ;;
            6)  ensure_component "modules/backup-manager.sh" && "${MODULES_DIR}/backup-manager.sh" ;;
            7)  ensure_component "modules/docker-manager.sh" && "${MODULES_DIR}/docker-manager.sh" ;;
            8)  ensure_component "modules/service-manager.sh" && "${MODULES_DIR}/service-manager.sh" ;;
            9)  ensure_component "modules/log-viewer.sh" && "${MODULES_DIR}/log-viewer.sh" ;;
            10) ensure_component "modules/port-scanner.sh" && "${MODULES_DIR}/port-scanner.sh" ;;
            11) ensure_component "modules/git-deploy.sh" && "${MODULES_DIR}/git-deploy.sh" ;;
            12) ensure_component "modules/termux-maintenance.sh" && "${MODULES_DIR}/termux-maintenance.sh" ;;
            13) ensure_component "modules/ssh-key-manager.sh" && "${MODULES_DIR}/ssh-key-manager.sh" ;;
            14) ensure_component "modules/quick-commands.sh" && "${MODULES_DIR}/quick-commands.sh" ;;
            15) download_all_modules ;;
            0|[qQ])
                clear 2>/dev/null || true
                exit 0
                ;;
            *)
                echo -e "${RED}Неверный номер. Введите число от 0 до 15.${NC}"
                sleep 1.2
                ;;
        esac
    done
}

vps_toolkit_main_menu "$@"
