#!/usr/bin/env bash
# ==============================================================================
# Android VPS Toolkit — VPS Security Audit (modules/vps-security.sh)
# Экспресс-аудит безопасности: UFW, Fail2ban, SSHD, failed logins, updates
# ==============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "")"
LIB_DIR="${SCRIPT_DIR}/../lib"
if [[ -f "${LIB_DIR}/common.sh" ]]; then
    # shellcheck source=/dev/null
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

sec_audit_server() {
    local target="$1"
    print_header "АУДИТ БЕЗОПАСНОСТИ: ${target}" "Режим: Только проверка (Read-only)"

    echo -e "${CYAN}Сбор данных безопасности с ${target}...${NC}\n"

    local audit_script='
echo "=== 1. ПАРАМЕТРЫ ВХОДА SSH (sshd_config) ==="
grep -E "^(Port|PermitRootLogin|PasswordAuthentication|PubkeyAuthentication)" /etc/ssh/sshd_config 2>/dev/null || echo "Не удалось прочитать sshd_config"

echo -e "\n=== 2. СЕТЕВОЙ ЭКРАН (UFW / IPTABLES) ==="
if command -v ufw >/dev/null 2>&1; then
    sudo ufw status verbose 2>/dev/null || ufw status 2>/dev/null || echo "Требуются права sudo для ufw"
else
    echo "UFW не установлен."
fi

echo -e "\n=== 3. СТАТУС FAIL2BAN ==="
if command -v fail2ban-client >/dev/null 2>&1; then
    sudo fail2ban-client status 2>/dev/null || echo "Fail2ban не запущен или требует sudo"
else
    echo "Fail2ban не установлен."
fi

echo -e "\n=== 4. ОТКРЫТЫЕ ПРОСЛУШИВАЕМЫЕ ПОРТЫ ==="
ss -tulpn 2>/dev/null | grep -E "LISTEN" | head -n 15 || netstat -tulpn 2>/dev/null | head -n 15 || echo "Не удалось получить список портов"

echo -e "\n=== 5. ПОСЛЕДНИЕ НЕУДАЧНЫЕ АВТОРИЗАЦИИ (БРУТФОРС) ==="
grep "Failed password" /var/log/auth.log 2>/dev/null | tail -n 5 || journalctl -u ssh -u sshd -n 5 --no-pager 2>/dev/null | grep -i "failed" || echo "Подозрительных попыток входа не найдено"

echo -e "\n=== 6. ДОСТУПНЫЕ ОБНОВЛЕНИЯ БЕЗОПАСНОСТИ ==="
if command -v apt-get >/dev/null 2>&1; then
    apt list --upgradable 2>/dev/null | grep -i security | head -n 10 || echo "Обновлений безопасности не обнаружено"
fi
'

    ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}" "bash -s" <<< "${audit_script}" 2>/dev/null || {
        echo -e "${RED}Не удалось подключиться к серверу по SSH.${NC}"
    }

    press_enter
}

vps_security_main() {
    while true; do
        clear 2>/dev/null || true
        echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
        echo -e "${BOLD}              VPS SECURITY AUDIT                    ${NC}"
        echo -e "${DIM}   Экспресс-диагностика безопасности серверов       ${NC}"
        echo -e "${BLUE}════════════════════════════════════════════════════${NC}\n"

        echo "  1. Провести полный аудит сервера"
        echo "  2. Проверить попытки подбора паролей (Bruteforce)"
        echo "  3. Проверить статус UFW и открытые порты"
        echo "  4. Проверить статус Fail2ban"
        echo ""
        echo "  0. Назад в главное меню"
        echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
        read -rp "Выберите действие [0–4]: " choice

        case "${choice}" in
            1)
                local s_alias
                s_alias=$(prompt_select_server "Выберите сервер для аудита")
                [[ -n "${s_alias}" ]] && sec_audit_server "${s_alias}"
                ;;
            2)
                local s_alias
                s_alias=$(prompt_select_server "Проверка bruteforce")
                if [[ -n "${s_alias}" ]]; then
                    print_header "НЕУДАЧНЫЕ ВХОДЫ: ${s_alias}"
                    ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${s_alias}" \
                        "grep 'Failed password' /var/log/auth.log 2>/dev/null | tail -n 25 || journalctl -u ssh -u sshd -n 25 --no-pager 2>/dev/null | grep -i 'failed' || echo 'Записей нет.'" || echo "Ошибка."
                    press_enter
                fi
                ;;
            3)
                local s_alias
                s_alias=$(prompt_select_server "Проверка Firewall и портов")
                if [[ -n "${s_alias}" ]]; then
                    print_header "ПОРТЫ И FIREWALL: ${s_alias}"
                    ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${s_alias}" \
                        "echo '=== UFW ==='; sudo ufw status 2>/dev/null || ufw status 2>/dev/null || echo 'UFW недоступен'; echo -e '\n=== LISTEN PORTS ==='; ss -tulpn 2>/dev/null | grep LISTEN || true" || echo "Ошибка."
                    press_enter
                fi
                ;;
            4)
                local s_alias
                s_alias=$(prompt_select_server "Проверка Fail2ban")
                if [[ -n "${s_alias}" ]]; then
                    print_header "FAIL2BAN: ${s_alias}"
                    ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${s_alias}" \
                        "sudo fail2ban-client status 2>/dev/null || echo 'Fail2ban не запущен.'" || echo "Ошибка."
                    press_enter
                fi
                ;;
            0|[qQ]) return ;;
            *) echo -e "${RED}Неверный ввод.${NC}"; sleep 1 ;;
        esac
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    vps_security_main "$@"
fi
