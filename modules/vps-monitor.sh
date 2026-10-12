#!/usr/bin/env bash
# ==============================================================================
# Android VPS Toolkit — VPS Monitor (modules/vps-monitor.sh)
# Сводный мониторинг нескольких серверов на одном экране
# ==============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "")"
LIB_DIR="${SCRIPT_DIR}/../lib"
if [[ -f "${LIB_DIR}/common.sh" ]]; then
    # shellcheck source=/dev/null
    source "${LIB_DIR}/common.sh"
else
    # Fallback локальный
    SSH_DIR="${HOME}/.ssh"
    CONFIG_FILE="${SSH_DIR}/config"
    CONN_TIMEOUT="4"
    BOLD='\033[1m'; DIM='\033[2m'; RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
    print_header() { clear 2>/dev/null || true; echo -e "${BOLD}=== $1 ===${NC}\n"; }
    print_divider() { echo -e "----------------------------------------"; }
    get_hosts() { awk '$1 ~ /^[Hh][Oo][Ss][Tt]$/ {for (i=2; i<=NF; i++) if ($i != "*") print $i}' "${CONFIG_FILE}" 2>/dev/null | sort -u; }
    get_server_flag() { echo "🌐"; }
fi

vps_monitor_main() {
    while true; do
        clear 2>/dev/null || true
        echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
        echo -e "${BOLD}                 VPS MONITOR                        ${NC}"
        echo -e "${DIM}     Сводный мониторинг всех серверов онлайн        ${NC}"
        echo -e "${BLUE}════════════════════════════════════════════════════${NC}\n"

        local hosts=()
        while IFS= read -r h; do [[ -n "$h" ]] && hosts+=("$h"); done < <(get_hosts)
        local total=${#hosts[@]}

        if [[ $total -eq 0 ]]; then
            echo -e "${YELLOW}(В ~/.ssh/config нет настроенных серверов)${NC}\n"
            echo "0. Назад"
            read -rp "> " _
            return
        fi

        echo -e "Опрос ${total} серверов...\n"

        for (( i=0; i<total; i++ )); do
            local h="${hosts[$i]}"
            local flag
            flag=$(get_server_flag "$h")
            local hn
            hn=$(ssh -F "${CONFIG_FILE}" -G "$h" 2>/dev/null | awk '$1=="hostname"{print $2}')
            hn="${hn:-$h}"

            # Замер задержки TCP через /dev/tcp
            local start_t end_t latency_ms="—" is_port_open=0
            local port
            port=$(ssh -F "${CONFIG_FILE}" -G "$h" 2>/dev/null | awk '$1=="port"{print $2}')
            port="${port:-22}"

            start_t=$(date +%s%3N 2>/dev/null || date +%s)
            if (echo > /dev/tcp/"${hn}"/"${port}") 2>/dev/null; then
                end_t=$(date +%s%3N 2>/dev/null || date +%s)
                if [[ $start_t =~ ^[0-9]+$ && $end_t =~ ^[0-9]+$ ]]; then
                    latency_ms="$((end_t - start_t))ms"
                else
                    latency_ms="OK"
                fi
                is_port_open=1
            fi

            if [[ $is_port_open -eq 0 ]]; then
                echo -e " ${BOLD}$((i+1)). ${flag} ${h}${NC} (${hn}:${port})"
                echo -e "    Статус:   ${RED}✗ OFFLINE (порт закрыт / таймаут)${NC}\n"
                continue
            fi

            # Пробуем получить метрики по SSH
            local remote_info
            remote_info=$(ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${h}" "
                uptime_val=\$(uptime -p 2>/dev/null || uptime | awk -F'( |,|up )+' '{print \$4}' || echo '—')
                cpu_load=\$(cat /proc/loadavg 2>/dev/null | awk '{print \$1, \$2, \$3}' || echo '—')
                mem_info=\$(free -m 2>/dev/null | awk 'NR==2{printf \"%d/%dMB (%d%%)\", \$3, \$2, (\$3*100)/\$2}' || echo '—')
                disk_info=\$(df -h / 2>/dev/null | awk 'NR==2{printf \"%s/%s (%s)\", \$3, \$2, \$5}' || echo '—')
                
                # Проверка ключевых служб
                srv_status=\"\"
                command -v docker >/dev/null 2>&1 && srv_status=\"\${srv_status}Docker:ON \" || true
                systemctl is-active --quiet nginx 2>/dev/null && srv_status=\"\${srv_status}Nginx:ON \" || true
                systemctl is-active --quiet 3x-ui 2>/dev/null && srv_status=\"\${srv_status}3x-ui:ON \" || true
                systemctl is-active --quiet warp-svc 2>/dev/null && srv_status=\"\${srv_status}WARP:ON \" || true
                
                echo \"\${uptime_val}|\${cpu_load}|\${mem_info}|\${disk_info}|\${srv_status:-(нет)} \"
            " 2>/dev/null || true)

            if [[ -n "${remote_info}" && "${remote_info}" == *"|"* ]]; then
                IFS='|' read -r r_up r_cpu r_mem r_disk r_srv <<< "${remote_info}"
                echo -e " ${BOLD}$((i+1)). ${flag} ${h}${NC} (${hn}:${port}) — ${GREEN}ONLINE${NC} [${latency_ms}]"
                echo -e "    Uptime:   ${DIM}${r_up}${NC}"
                echo -e "    CPU Load: ${CYAN}${r_cpu}${NC}  |  RAM: ${YELLOW}${r_mem}${NC}"
                echo -e "    Диск /:   ${r_disk}"
                echo -e "    Службы:   ${GREEN}${r_srv}${NC}\n"
            else
                echo -e " ${BOLD}$((i+1)). ${flag} ${h}${NC} (${hn}:${port}) — ${CYAN}PORT OPEN${NC} [${latency_ms}]"
                echo -e "    ${DIM}(SSH аутентификация по ключу не настроена для безагентного опроса)${NC}\n"
            fi
        done

        echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
        echo -e "  ${GREEN}1. Обновить статус (Refresh)${NC}"
        echo -e "  ${RED}0. Назад в главное меню${NC}"
        echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
        read -rp "Выберите действие [0–1]: " act
        case "${act}" in
            1|[rR]) continue ;;
            0|[qQ]) return ;;
            *) echo -e "${RED}Неверный ввод.${NC}"; sleep 1 ;;
        esac
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    vps_monitor_main "$@"
fi
