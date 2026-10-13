#!/usr/bin/env bash
# ==============================================================================
# Android VPS Toolkit — Termux Maintenance (modules/termux-maintenance.sh)
# Обслуживание среды Termux: очистка кэша, обновление, проверка памяти и хранилища
# ==============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "")"
LIB_DIR="${SCRIPT_DIR}/../lib"
if [[ -f "${LIB_DIR}/common.sh" ]]; then
    # shellcheck source=/dev/null
    source "${LIB_DIR}/common.sh"
else
    BOLD='\033[1m'; DIM='\033[2m'; RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
    print_header() { clear 2>/dev/null || true; echo -e "${BOLD}=== $1 ===${NC}\n"; }
    print_divider() { echo -e "----------------------------------------"; }
    press_enter() { read -rp "Нажмите Enter..."; }
fi

termux_maintenance_main() {
    while true; do
        clear 2>/dev/null || true
        echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
        echo -e "${BOLD}             TERMUX MAINTENANCE                     ${NC}"
        echo -e "${DIM}      Обслуживание и оптимизация окружения          ${NC}"
        echo -e "${BLUE}════════════════════════════════════════════════════${NC}\n"

        echo "  1. Проверка свободного места (диск Termux и телефон)"
        echo "  2. Очистить кэш пакетов apt / pkg (pkg clean)"
        echo "  3. Удалить ненужные зависимости (apt autoremove)"
        echo "  4. Обновить репозитории и пакеты Termux (pkg update)"
        echo "  5. Проверить доступ к памяти телефона (termux-setup-storage)"
        echo "  6. Проверить установленные утилиты (curl, openssh, git, etc.)"
        echo ""
        echo "  0. Назад в главное меню"
        echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
        read -rp "Выберите действие [0–6]: " choice

        case "${choice}" in
            1)
                print_header "СВОБОДНОЕ МЕСТО"
                df -h "${PREFIX}" "${HOME}" || df -h
                press_enter
                ;;
            2)
                print_header "ОЧИСТКА КЭША"
                apt-get clean 2>/dev/null || pkg clean 2>/dev/null || true
                rm -rf "${PREFIX}/var/cache/apt/archives/*.deb" 2>/dev/null || true
                echo -e "${GREEN}✓ Кэш пакетов очищен.${NC}"
                press_enter
                ;;
            3)
                print_header "УДАЛЕНИЕ ЛИШНИХ ЗАВИСИМОСТЕЙ"
                apt-get autoremove -y 2>/dev/null || true
                echo -e "${GREEN}✓ Готово.${NC}"
                press_enter
                ;;
            4)
                print_header "ОБНОВЛЕНИЕ ПАКЕТОВ"
                pkg update -y && pkg upgrade -y
                press_enter
                ;;
            5)
                print_header "ДОСТУП К ПАМЯТИ"
                termux-setup-storage 2>/dev/null || true
                echo -e "${GREEN}✓ Запрос на доступ к хранилищу отправлен в Android.${NC}"
                press_enter
                ;;
            6)
                print_header "ПРОВЕРКА УТИЛИТ"
                for tool in ssh scp sftp curl git openssl tar awk sed; do
                    if command -v "${tool}" >/dev/null 2>&1; then
                        echo -e "  [${GREEN}OK${NC}]   ${tool}"
                    else
                        echo -e "  [${RED}MISS${NC}] ${tool} (не установлен)"
                    fi
                done
                press_enter
                ;;
            0|[qQ])
                return
                ;;
            *)
                echo -e "${RED}Неверный ввод.${NC}"; sleep 1
                ;;
        esac
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    termux_maintenance_main "$@"
fi
