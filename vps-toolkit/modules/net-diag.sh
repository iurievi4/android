#!/usr/bin/env bash
# ==============================================================================
# Android VPS Toolkit — NetDiag (modules/net-diag.sh)
# Сетевая диагностика: Ping, Traceroute, DNS, TCP, SSL/HTTPS, внешний IP, SOCKS5
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
fi

netdiag_ping() {
    print_header "PING ТЕСТ" "Проверка задержки и потерь пакетов"
    read -rp "Введите хост или IP (по умолчанию 1.1.1.1): " target
    target="${target:-1.1.1.1}"
    echo -e "\n${CYAN}Отправка 4 пакетов на ${target}...${NC}\n"
    ping -c 4 "${target}" || echo -e "${RED}Ошибка ping.${NC}"
    press_enter
}

netdiag_traceroute() {
    print_header "ТРАССИРОВКА МАРШРУТА" "Определение узлов на пути к серверу"
    read -rp "Введите хост или IP: " target
    if [[ -z "${target}" ]]; then return; fi
    echo -e "\n${CYAN}Трассировка к ${target}...${NC}\n"
    if command -v traceroute >/dev/null 2>&1; then
        traceroute -m 20 "${target}" || true
    elif command -v tracepath >/dev/null 2>&1; then
        tracepath "${target}" || true
    else
        echo -e "${YELLOW}Утилита traceroute не установлена.${NC}"
        echo "Установите её командой: pkg install traceroute -y"
    fi
    press_enter
}

netdiag_dns() {
    print_header "DNS ЗАПРОСЫ" "Проверка разрешения доменных имён"
    read -rp "Введите домен (например, google.com): " domain
    if [[ -z "${domain}" ]]; then return; fi
    echo -e "\n${CYAN}Запрос записей для ${domain}...${NC}\n"
    if command -v dig >/dev/null 2>&1; then
        echo -e "${BOLD}A-записи (Cloudflare DNS 1.1.1.1):${NC}"
        dig +short A "${domain}" @1.1.1.1 || true
        echo -e "\n${BOLD}A-записи (Google DNS 8.8.8.8):${NC}"
        dig +short A "${domain}" @8.8.8.8 || true
    elif command -v nslookup >/dev/null 2>&1; then
        nslookup "${domain}" || true
    elif command -v getent >/dev/null 2>&1; then
        getent hosts "${domain}" || true
    else
        curl -s "https://cloudflare-dns.com/dns-query?name=${domain}&type=A" -H "accept: application/dns-json" | grep -oE '"data":"[0-9.]+"' || echo "Не удалось выполнить запрос."
    fi
    press_enter
}

netdiag_tcp_port() {
    print_header "ПРОВЕРКА TCP-ПОРТА" "Доступность конкретного сервиса"
    read -rp "Хост или IP: " host_val
    read -rp "Порт (например: 22, 443, 1241): " port_val
    if [[ -z "${host_val}" || -z "${port_val}" ]]; then return; fi

    echo -e "\n${CYAN}Проверка ${host_val}:${port_val}...${NC}"
    if (timeout 4 bash -c "echo > /dev/tcp/${host_val}/${port_val}") 2>/dev/null; then
        echo -e "${GREEN}✓ Порт ${port_val} ОТКРЫТ и принимает соединения.${NC}"
    else
        echo -e "${RED}✗ Порт ${port_val} ЗАКРЫТ, заблокирован или таймаут.${NC}"
    fi
    press_enter
}

netdiag_ssl_http() {
    print_header "HTTP/HTTPS & SSL ТЕСТ" "Проверка ответа сайта и сертификата"
    read -rp "URL или домен (например, https://example.com): " url_val
    [[ "${url_val}" != http* ]] && url_val="https://${url_val}"
    echo -e "\n${CYAN}Запрос к ${url_val}...${NC}\n"
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code} | Время: %{time_total}s | SSL handshake: %{time_appconnect}s\n" --connect-timeout 5 "${url_val}" || echo "Ошибка соединения")
    echo -e "Результат: ${BOLD}${http_code}${NC}\n"

    # Извлечение срока действия SSL через openssl если установлен
    local domain
    domain=$(echo "${url_val}" | sed -e 's|^[^/]*//||' -e 's|/.*$||' -e 's|:.*$||')
    if command -v openssl >/dev/null 2>&1; then
        echo -e "${BOLD}Сертификат SSL:${NC}"
        echo | openssl s_client -servername "${domain}" -connect "${domain}:443" 2>/dev/null | openssl x509 -noout -dates -issuer 2>/dev/null || echo "Не удалось получить SSL детали."
    fi
    press_enter
}

netdiag_my_ip() {
    print_header "ОПРЕДЕЛЕНИЕ ВНЕШНЕГО IP" "Текущий выход в сеть смартфона"
    echo -e "${CYAN}Определение IP через разные каналы...${NC}\n"
    local ip4 ip6 geo
    ip4=$(curl -4 -s --connect-timeout 4 https://api.ipify.org 2>/dev/null || echo "Не доступен")
    ip6=$(curl -6 -s --connect-timeout 4 https://api64.ipify.org 2>/dev/null || echo "Не доступен")
    geo=$(curl -s --connect-timeout 4 "https://ipapi.co/${ip4}/country_name/" 2>/dev/null || echo "—")

    echo -e "IPv4:    ${BOLD}${GREEN}${ip4}${NC}"
    echo -e "Страна:  ${YELLOW}${geo}${NC}"
    echo -e "IPv6:    ${DIM}${ip6}${NC}"
    press_enter
}

netdiag_socks5() {
    print_header "ПРОВЕРКА SOCKS5 ПРОКСИ" "Диагностика NaïveProxy / Xray / WARP"
    read -rp "Адрес SOCKS5 (по умолчанию 127.0.0.1): " proxy_host
    proxy_host="${proxy_host:-127.0.0.1}"
    read -rp "Порт SOCKS5 (по умолчанию 10808): " proxy_port
    proxy_port="${proxy_port:-10808}"

    echo -e "\n${CYAN}Тест подключения через socks5h://${proxy_host}:${proxy_port}...${NC}\n"
    local proxy_out
    proxy_out=$(curl -s -x "socks5h://${proxy_host}:${proxy_port}" --connect-timeout 5 https://api.ipify.org 2>/dev/null || true)

    if [[ -n "${proxy_out}" ]]; then
        echo -e "${GREEN}✓ Прокси РАБОТАЕТ!${NC}"
        echo -e "Исходящий IP через прокси: ${BOLD}${CYAN}${proxy_out}${NC}"
    else
        echo -e "${RED}✗ Не удалось подключиться через прокси.${NC}"
        echo -e "${DIM}Проверьте, запущена ли служба (Xray, WARP, v2ray) на порту ${proxy_port}.${NC}"
    fi
    press_enter
}

netdiag_main() {
    while true; do
        clear 2>/dev/null || true
        echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
        echo -e "${BOLD}                 NETDIAG — СЕТЬ                     ${NC}"
        echo -e "${DIM}      Диагностика сети, серверов и прокси           ${NC}"
        echo -e "${BLUE}════════════════════════════════════════════════════${NC}\n"

        echo "  1. Проверка Ping"
        echo "  2. Трассировка маршрута (Traceroute)"
        echo "  3. Проверка DNS"
        echo "  4. Проверка TCP-порта"
        echo "  5. Проверка HTTP/HTTPS и SSL-сертификата"
        echo "  6. Мой внешний IP и геолокация"
        echo "  7. Проверка SOCKS5-прокси (WARP, Xray, Naïve)"
        echo ""
        echo "  0. Назад в главное меню"
        echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
        read -rp "Выберите действие [0–7]: " choice

        case "${choice}" in
            1) netdiag_ping ;;
            2) netdiag_traceroute ;;
            3) netdiag_dns ;;
            4) netdiag_tcp_port ;;
            5) netdiag_ssl_http ;;
            6) netdiag_my_ip ;;
            7) netdiag_socks5 ;;
            0|[qQ]) return ;;
            *) echo -e "${RED}Неверный ввод.${NC}"; sleep 1 ;;
        esac
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    netdiag_main "$@"
fi
