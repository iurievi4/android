#!/usr/bin/env bash
# ==============================================================================
# TERMUX SSH MANAGER 2.3
# Мобильный SSH-менеджер и пульт управления VPS для Android / Termux
# Репозиторий: https://github.com/iurievi4/android
# Чистый Bash + OpenSSH • Без сторонних агентов на VPS • Источник истины: ~/.ssh/config
# ==============================================================================

# set -euo pipefail (disabled -e to prevent unexpected aborts in interactive TUI)
set -uo pipefail

VERSION="2.3.0"
SSH_DIR="${HOME}/.ssh"
CONFIG_FILE="${SSH_DIR}/config"
KNOWN_HOSTS_FILE="${SSH_DIR}/known_hosts"
DEFAULT_KEY="${SSH_DIR}/id_ed25519"
SETTINGS_FILE="${SSH_DIR}/ssh-manager.conf"
SERVER_IDS_FILE="${SSH_DIR}/server-ids.map"
STATUS_CACHE_FILE="${SSH_DIR}/status-cache.map"
BACKUP_DIR="${SSH_DIR}/backups"
MAX_BACKUPS=10

# Настройки по умолчанию
GH_USER="iurievi4"
DEF_USER="root"
DEF_PORT="1241"
CONN_TIMEOUT="4"
LOG_LINES="30"
USE_COLOR="yes"
OUTPUT_MODE="normal" # normal | compact

# Цветовая палитра
set_colors() {
    if [[ "${USE_COLOR}" == "yes" && -t 1 ]]; then
        RED='\033[0;31m'
        GREEN='\033[0;32m'
        BLUE='\033[0;34m'
        YELLOW='\033[1;33m'
        CYAN='\033[0;36m'
        MAGENTA='\033[0;35m'
        BOLD='\033[1m'
        DIM='\033[2m'
        NC='\033[0m'
    else
        RED=''
        GREEN=''
        BLUE=''
        YELLOW=''
        CYAN=''
        MAGENTA=''
        BOLD=''
        DIM=''
        NC=''
    fi
}

# ==============================================================================
# НАСТРОЙКИ МЕНЕДЖЕРА (Раздел 12 ТЗ)
# ==============================================================================
load_settings() {
    if [[ -f "${SETTINGS_FILE}" ]]; then
        while IFS='=' read -r key val; do
            [[ -z "${key}" || "${key}" =~ ^# ]] && continue
            case "${key}" in
                CONFIG_FILE)  CONFIG_FILE="${val}" ;;
                BACKUP_DIR)   BACKUP_DIR="${val}" ;;
                GH_USER)      GH_USER="${val}" ;;
                DEF_USER)     DEF_USER="${val}" ;;
                DEF_PORT)     DEF_PORT="${val}" ;;
                CONN_TIMEOUT) CONN_TIMEOUT="${val}" ;;
                LOG_LINES)    LOG_LINES="${val}" ;;
                USE_COLOR)    USE_COLOR="${val}" ;;
                OUTPUT_MODE)  OUTPUT_MODE="${val}" ;;
            esac
        done < "${SETTINGS_FILE}"
    fi
    set_colors
}

save_settings() {
    cat <<EOF > "${SETTINGS_FILE}"
# Termux SSH Manager 2.2 Settings
CONFIG_FILE=${CONFIG_FILE}
BACKUP_DIR=${BACKUP_DIR}
GH_USER=${GH_USER}
DEF_USER=${DEF_USER}
DEF_PORT=${DEF_PORT}
CONN_TIMEOUT=${CONN_TIMEOUT}
LOG_LINES=${LOG_LINES}
USE_COLOR=${USE_COLOR}
OUTPUT_MODE=${OUTPUT_MODE}
EOF
    chmod 600 "${SETTINGS_FILE}"
}

# Инициализация окружения
init_env() {
    if [[ ! -d "${SSH_DIR}" ]]; then
        mkdir -p "${SSH_DIR}"
        chmod 700 "${SSH_DIR}"
    fi
    if [[ ! -d "${BACKUP_DIR}" ]]; then
        mkdir -p "${BACKUP_DIR}"
        chmod 700 "${BACKUP_DIR}"
    fi
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        touch "${CONFIG_FILE}"
        chmod 600 "${CONFIG_FILE}"
    fi
    if [[ ! -f "${SERVER_IDS_FILE}" ]]; then
        touch "${SERVER_IDS_FILE}"
        chmod 600 "${SERVER_IDS_FILE}"
    fi
    load_settings
    sync_server_ids
}

# ==============================================================================
# ОПРЕДЕЛЕНИЕ ФЛАГОВ И СИМВОЛОВ СЕРВЕРОВ
# ==============================================================================
get_server_flag() {
    local a
    a=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    case "$a" in
        fi|fi-*|*-fi|fi_*|*_fi|*finland*) echo "🇫🇮" ;;
        lv|lv-*|*-lv|lv_*|*_lv|*latvia*)  echo "🇱🇻" ;;
        pa|pa-*|*-pa|pa_*|*_pa|*panama*)  echo "🌐" ;;
        tr|tr-*|*-tr|tr_*|*_tr|*turkey*)  echo "🇹🇷" ;;
        ru|ru-*|*-ru|ru_*|*_ru|*russia*)  echo "🇷🇺" ;;
        de|de-*|*-de|de_*|*_de|*germany*) echo "🇩🇪" ;;
        us|us-*|*-us|us_*|*_us|*usa*)     echo "🇺🇸" ;;
        nl|nl-*|*-nl|nl_*|*_nl|*netherlands*) echo "🇳🇱" ;;
        fr|fr-*|*-fr|fr_*|*_fr|*france*)  echo "🇫🇷" ;;
        uk|gb|uk-*|*-uk|gb-*|*-gb|*britain*) echo "🇬🇧" ;;
        se|se-*|*-se|se_*|*_se|*sweden*)  echo "🇸🇪" ;;
        sg|sg-*|*-sg|sg_*|*_sg|*singapore*) echo "🇸🇬" ;;
        jp|jp-*|*-jp|jp_*|*_jp|*japan*)   echo "🇯🇵" ;;
        pl|pl-*|*-pl|pl_*|*_pl|*poland*)  echo "🇵🇱" ;;
        kz|kz-*|*-kz|kz_*|*_kz|*kazakhstan*) echo "🇰🇿" ;;
        ee|ee-*|*-ee|ee_*|*_ee|*estonia*) echo "🇪🇪" ;;
        lt|lt-*|*-lt|lt_*|*_lt|*lithuania*) echo "🇱🇹" ;;
        ua|ua-*|*-ua|ua_*|*_ua|*ukraine*) echo "🇺🇦" ;;
        ch|ch-*|*-ch|ch_*|*_ch|*swiss*)   echo "🇨🇭" ;;
        ca|ca-*|*-ca|ca_*|*_ca|*canada*)  echo "🇨🇦" ;;
        *) echo "🌐" ;;
    esac
}

# Заглушки совместимости
sync_server_ids() { :; }
get_id_by_alias() { echo ""; }
get_alias_by_id() { echo "$1"; }
rename_server_id() { :; }
remove_server_id() { :; }

# ==============================================================================
# БАЗОВЫЕ ФУНКЦИИ SSH CONFIG (Источник истины: ~/.ssh/config)
# ==============================================================================

# Извлечение всех Host-алиасов без масок (* и ?)
get_hosts() {
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        return
    fi
    grep -iE '^[[:space:]]*Host[[:space:]]+' "${CONFIG_FILE}" \
        | awk '{for(i=2;i<=NF;i++) if($i !~ /[*?]/) print $i}' \
        | sort -u
}

# Удаление конкретного Host-блока с сохранением остальных
remove_host_block() {
    local target="$1"
    awk -v target="${target}" '
        BEGIN { skip = 0 }
        tolower($1) == "host" {
            skip = 0
            for (i = 2; i <= NF; i++) {
                if ($i == target) {
                    skip = 1
                    break
                }
            }
        }
        !skip { print }
    ' "${CONFIG_FILE}" > "${CONFIG_FILE}.tmp"
    mv "${CONFIG_FILE}.tmp" "${CONFIG_FILE}"
    chmod 600 "${CONFIG_FILE}"
}

# Извлечение полного блока Host со всеми параметрами (4.6 ТЗ)
get_host_raw_block() {
    local target="$1"
    awk -v target="${target}" '
        BEGIN { in_block = 0 }
        tolower($1) == "host" {
            if (in_block) exit
            for (i = 2; i <= NF; i++) {
                if ($i == target) {
                    in_block = 1
                    print $0
                    next
                }
            }
        }
        in_block {
            if (tolower($1) == "host") exit
            print $0
        }
    ' "${CONFIG_FILE}"
}

# Проверка, установлен ли вход по ключу или паролю
get_host_auth_type() {
    local target="$1"
    local pubkey_flag
    pubkey_flag=$(ssh -F "${CONFIG_FILE}" -G "${target}" 2>/dev/null | awk '$1=="pubkeyauthentication"{print $2}')
    if [[ "${pubkey_flag}" == "no" ]]; then
        echo "PWD"
    else
        echo "KEY"
    fi
}

# Получение локальных ключей на телефоне
get_local_keys() {
    local found=()
    for pub in "${SSH_DIR}"/*.pub; do
        [[ -f "${pub}" ]] || continue
        local priv="${pub%.pub}"
        if [[ -f "${priv}" ]]; then
            found+=("${priv}")
        fi
    done
    printf '%s\n' "${found[@]:-}"
}

# ==============================================================================
# РЕЗЕРВНОЕ КОПИРОВАНИЕ С МЕТАДАННЫМИ (Раздел 9 ТЗ)
# ==============================================================================
backup_config() {
    if [[ -s "${CONFIG_FILE}" ]]; then
        local timestamp
        timestamp="$(date +%Y-%m-%d-%H%M%S)"
        local bak="${BACKUP_DIR}/config-${timestamp}.bak"
        local meta="${bak}.meta"

        cp "${CONFIG_FILE}" "${bak}"

        local hosts_in_bak
        hosts_in_bak=$(grep -iE '^[[:space:]]*Host[[:space:]]+' "${bak}" | awk '{for(i=2;i<=NF;i++) if($i !~ /[*?]/) printf "%s ", $i}' | xargs || echo "пусто")
        local count_in_bak
        count_in_bak=$(echo "${hosts_in_bak}" | wc -w)
        local sha_hash
        sha_hash=$(sha256sum "${bak}" 2>/dev/null | awk '{print $1}' || echo "н/д")
        local f_size
        f_size=$(wc -c < "${bak}" | xargs)

        cat <<EOF > "${meta}"
DATE=$(date "+%Y-%m-%d %H:%M:%S")
FILE=$(basename "${bak}")
VERSION=${VERSION}
HOSTS_COUNT=${count_in_bak}
HOSTS_LIST=${hosts_in_bak}
SIZE_BYTES=${f_size}
SHA256=${sha_hash}
SOURCE=${CONFIG_FILE}
EOF
        echo -e "${YELLOW}Резервная копия создана: ${bak}${NC}"

        # Ротация (хранить последние MAX_BACKUPS)
        local old_backups=()
        while IFS= read -r f; do
            [[ -n "${f}" ]] && old_backups+=("${f}")
        done < <(ls -t "${BACKUP_DIR}"/config-*.bak "${BACKUP_DIR}"/config.backup-* 2>/dev/null | grep -v '\.meta$' || true)

        if (( ${#old_backups[@]} > MAX_BACKUPS )); then
            for (( i=MAX_BACKUPS; i<${#old_backups[@]}; i++ )); do
                rm -f "${old_backups[$i]}" "${old_backups[$i]}.meta"
            done
        fi
    fi
}

# ==============================================================================
# ДИАГНОСТИКА ПОДКЛЮЧЕНИЙ (Раздел 5 ТЗ)
# ==============================================================================

# Индивидуальная диагностика сервера (5.1 ТЗ)
diagnose_server() {
    local target="$1"
    local hn port u
    hn=$(ssh -F "${CONFIG_FILE}" -G "${target}" 2>/dev/null | awk '$1=="hostname"{print $2}')
    port=$(ssh -F "${CONFIG_FILE}" -G "${target}" 2>/dev/null | awk '$1=="port"{print $2}')
    u=$(ssh -F "${CONFIG_FILE}" -G "${target}" 2>/dev/null | awk '$1=="user"{print $2}')
    hn="${hn:-${target}}"
    port="${port:-22}"

    echo -e "${BOLD}ДИАГНОСТИКА: ${target}${NC} (${u}@${hn}:${port})\n"

    # 1. DNS check (если не IP)
    local dns_status="OK"
    if [[ ! "${hn}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        if getent hosts "${hn}" >/dev/null 2>&1 || host "${hn}" >/dev/null 2>&1; then
            echo -e "  DNS:               ${GREEN}OK${NC}"
        else
            echo -e "  DNS:               ${RED}FAILED (Имя хоста не разрешается)${NC}"
            dns_status="FAILED"
        fi
    else
        echo -e "  DNS:               ${DIM}Пропущен (прямой IP)${NC}"
    fi

    # 2. TCP порт
    local tcp_status="FAILED"
    if (echo > /dev/tcp/"${hn}"/"${port}") 2>/dev/null; then
        echo -e "  TCP-порт (${port}):     ${GREEN}OK (Порт открыт)${NC}"
        tcp_status="OK"
    else
        echo -e "  TCP-порт (${port}):     ${RED}FAILED (Порт закрыт или тайм-аут)${NC}"
    fi

    # 3. SSH handshake & Host key & Auth
    local err_out
    err_out=$(ssh -F "${CONFIG_FILE}" -v -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}" 'exit' 2>&1 || true)

    local handshake="FAILED"
    local hostkey="UNKNOWN"
    local auth="FAILED"
    local reason=""

    if echo "${err_out}" | grep -qi "SSH2_MSG_KEXINIT sent"; then
        handshake="OK"
    fi

    if echo "${err_out}" | grep -qi "HOST IDENTIFICATION HAS CHANGED"; then
        hostkey="${RED}CHANGED (Ключ сервера изменился!)${NC}"
        reason="Ключ хоста в known_hosts не совпадает с сервером!"
    elif echo "${err_out}" | grep -qi "authenticity of host .* can't be established"; then
        hostkey="${YELLOW}UNKNOWN (Ключ ещё не подтверждён)${NC}"
    elif echo "${err_out}" | grep -qi "Host key: .* OK" || echo "${err_out}" | grep -qi "Host '.*' is known"; then
        hostkey="${GREEN}OK${NC}"
    fi

    if echo "${err_out}" | grep -qi "Authentication succeeded" || ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}" 'exit' >/dev/null 2>&1; then
        auth="${GREEN}OK (Вход выполнен)${NC}"
        reason="Успешная авторизация по ключу."
    elif echo "${err_out}" | grep -qi "Permission denied"; then
        auth="${RED}FAILED${NC}"
        reason="Сервер отклонил ключ или требует пароль."
    elif [[ "${tcp_status}" == "FAILED" ]]; then
        reason="Не удалось установить TCP соединение с портом ${port}."
    fi

    echo -e "  SSH handshake:     ${handshake}"
    echo -e "  Host key:          ${hostkey}"
    echo -e "  Аутентификация:    ${auth}"
    echo ""
    if [[ -n "${reason}" ]]; then
        echo -e "  ${BOLD}Причина:${NC} ${reason}"
    fi
}

# Экспресс-проверка одного сервера (для статуса ONLINE/OFFLINE)
check_server_quick() {
    local target="$1"
    local hn port
    hn=$(ssh -F "${CONFIG_FILE}" -G "${target}" 2>/dev/null | awk '$1=="hostname"{print $2}')
    port=$(ssh -F "${CONFIG_FILE}" -G "${target}" 2>/dev/null | awk '$1=="port"{print $2}')
    hn="${hn:-${target}}"
    port="${port:-22}"

    if ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}" 'exit' >/dev/null 2>&1; then
        echo "ONLINE (KEY)"
        return 0
    fi
    if (echo > /dev/tcp/"${hn}"/"${port}") 2>/dev/null; then
        echo "ONLINE (PORT)"
        return 0
    fi
    echo "OFFLINE"
    return 0
}

# Массовая проверка подключений (5.2 ТЗ)
action_mass_check() {
    clear 2>/dev/null || true
    echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}             МАССОВАЯ ПРОВЕРКА ПОДКЛЮЧЕНИЙ          ${NC}"
    echo -e "${BLUE}────────────────────────────────────────────────────${NC}"

    local hosts=()
    while IFS= read -r h; do [[ -n "$h" ]] && hosts+=("$h"); done < <(get_hosts)
    local total=${#hosts[@]}

    if [[ $total -eq 0 ]]; then
        echo -e "${YELLOW}В конфигурации нет серверов.${NC}"
        read -rp "Нажмите Enter..."; return
    fi

    local online_count=0
    local i=1

    for h in "${hosts[@]}"; do
        local id
        id=$(get_id_by_alias "$h")
        id="${id:-?}"
        local hn port u
        hn=$(ssh -F "${CONFIG_FILE}" -G "$h" 2>/dev/null | awk '$1=="hostname"{print $2}')
        port=$(ssh -F "${CONFIG_FILE}" -G "$h" 2>/dev/null | awk '$1=="port"{print $2}')
        u=$(ssh -F "${CONFIG_FILE}" -G "$h" 2>/dev/null | awk '$1=="user"{print $2}')

        printf "  %d. %-12s (%d/%d)... " "$((i))" "${h}" "$((i))" "${total}"

        local status
        status=$(check_server_quick "$h")

        case "${status}" in
            "ONLINE (KEY)")
                echo -e "${GREEN}✓ ONLINE (Ключ подтверждён)${NC}"
                online_count=$((online_count + 1))
                ;;
            "ONLINE (PORT)")
                echo -e "${CYAN}✓ ONLINE (Порт открыт / Пароль)${NC}"
                online_count=$((online_count + 1))
                ;;
            *)
                echo -e "${RED}✗ OFFLINE (Недоступен)${NC}"
                ;;
        esac
        i=$((i + 1))
    done

    echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
    echo -e "${BOLD}Итог: ${online_count} из ${total} серверов доступны.${NC}\n"
    read -rp "Нажмите Enter для возврата..."
}

# ==============================================================================
# УПРАВЛЕНИЕ СЕРВЕРАМИ (Раздел 4 ТЗ)
# ==============================================================================

# ==============================================================================
# УПРАВЛЕНИЕ СЕРВЕРАМИ (Раздел 4 ТЗ)
# ==============================================================================

# Список серверов для управления (ТЗ 4)
menu_server_management() {
    while true; do
        clear 2>/dev/null || true
        local hosts=()
        while IFS= read -r h; do [[ -n "$h" ]] && hosts+=("$h"); done < <(get_hosts)
        local total=${#hosts[@]}

        echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
        echo -e "${BOLD}              УПРАВЛЕНИЕ СЕРВЕРАМИ                  ${NC}"
        echo -e "${BLUE}════════════════════════════════════════════════════${NC}
"

        if [[ $total -eq 0 ]]; then
            echo -e "  ${YELLOW}(В ~/.ssh/config пока нет серверов)${NC}
"
            echo -e "  1. Добавить сервер"
            echo -e "  0. Назад
"
            echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
            read -rp "Выберите действие [0–1]: " no_srv
            case "${no_srv}" in
                1) action_add_server ;;
                0|[qQ]) return ;;
                *) echo -e "${RED}Неверный ввод.${NC}"; sleep 1.2 ;;
            esac
            continue
        fi

        for (( i=0; i<total; i++ )); do
            local h="${hosts[$i]}"
            local u hn p
            hn=$(ssh -F "${CONFIG_FILE}" -G "$h" 2>/dev/null | awk '$1=="hostname"{print $2}')
            p=$(ssh -F "${CONFIG_FILE}" -G "$h" 2>/dev/null | awk '$1=="port"{print $2}')
            u=$(ssh -F "${CONFIG_FILE}" -G "$h" 2>/dev/null | awk '$1=="user"{print $2}')
            printf "  %d. %s — %s@%s:%s
" "$((i+1))" "${h}" "${u}" "${hn}" "${p}"
        done

        echo ""
        echo "  0. Назад"
        echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
        read -rp "Выберите сервер [0–${total}]: " sel

        if [[ "${sel}" == "0" || "${sel}" == "q" || "${sel}" == "Q" ]]; then
            return
        fi

        if [[ "${sel}" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= total )); then
            local target="${hosts[$((sel-1))]}"
            view_server_card "${target}"
        else
            echo -e "${RED}Неверный номер. Введите число от 0 до ${total}.${NC}"
            sleep 1.2
        fi
    done
}

# 4.3 Карточка сервера (ТЗ 4)
view_server_card() {
    local target="$1"
    while true; do
        if ! get_hosts | grep -qw "^${target}$"; then
            return 0
        fi

        clear 2>/dev/null || true
        local u hn p
        hn=$(ssh -F "${CONFIG_FILE}" -G "${target}" 2>/dev/null | awk '$1=="hostname"{print $2}')
        p=$(ssh -F "${CONFIG_FILE}" -G "${target}" 2>/dev/null | awk '$1=="port"{print $2}')
        u=$(ssh -F "${CONFIG_FILE}" -G "${target}" 2>/dev/null | awk '$1=="user"{print $2}')

        echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
        echo -e "${BOLD}                 СЕРВЕР: ${target}                  ${NC}"
        echo -e "${BLUE}════════════════════════════════════════════════════${NC}
"
        echo -e "  Адрес:         ${hn}"
        echo -e "  Пользователь:  ${u}"
        echo -e "  Порт:          ${p}
"
        echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
        echo "  1. Подключиться"
        echo "  2. Проверить соединение"
        echo "  3. Диагностика SSH"
        echo "  4. Редактировать"
        echo "  5. Создать копию"
        echo "  6. Управление VPS"
        echo "  7. Показать SSH Config"
        echo "  8. Удалить сервер"
        echo ""
        echo "  0. Назад"
        echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
        read -rp "Выберите действие [0–8]: " sc_choice

        case "${sc_choice}" in
            1)
                clear 2>/dev/null || true
                echo -e "${GREEN}Подключение к ${target} (ssh ${target})...${NC}
"
                ssh -F "${CONFIG_FILE}" "${target}" || true
                echo ""
                read -rp "Сессия закрыта. Нажмите Enter..." _
                ;;
            2)
                clear 2>/dev/null || true
                echo -e "
${CYAN}Проверка соединения с ${target}...${NC}"
                local st
                st=$(check_server_quick "${target}")
                case "${st}" in
                    "ONLINE (KEY)") echo -e "${GREEN}✓ ONLINE (Ключ подтверждён)${NC}" ;;
                    "ONLINE (PORT)") echo -e "${CYAN}✓ ONLINE (Порт открыт / Пароль)${NC}" ;;
                    *) echo -e "${RED}✗ OFFLINE (Недоступен)${NC}" ;;
                esac
                echo ""
                read -rp "Нажмите Enter для возврата..." _
                ;;
            3)
                clear 2>/dev/null || true
                diagnose_server "${target}"
                echo ""
                read -rp "Нажмите Enter для возврата..." _
                ;;
            4)
                action_edit_server "${target}"
                ;;
            5)
                action_clone_server "${target}"
                ;;
            6)
                menu_vps_control "${target}"
                ;;
            7)
                clear 2>/dev/null || true
                echo -e "${BOLD}Конфигурация блока Host ${target}:${NC}
"
                get_host_raw_block "${target}"
                echo -e "
${BOLD}Эффективные параметры (ssh -G):${NC}"
                ssh -F "${CONFIG_FILE}" -G "${target}" 2>/dev/null | grep -E '^(hostname|user|port|identityfile|pubkeyauthentication|preferredauthentications|proxyjump|forwardagent|serveraliveinterval)' || true
                echo ""
                read -rp "Нажмите Enter для возврата..." _
                ;;
            8)
                if action_delete_server "${target}"; then
                    return 0
                fi
                ;;
            0|[qQ])
                return 0
                ;;
            *)
                echo -e "${RED}Неверный выбор. Введите цифру [0–8].${NC}"
                sleep 1.2
                ;;
        esac
    done
}

# Диалог выбора сервера только цифрами (ТЗ 1, 6)
prompt_select_server() {
    local title="${1:-Выбор сервера}"
    local hosts=()
    while IFS= read -r h; do [[ -n "$h" ]] && hosts+=("$h"); done < <(get_hosts)
    local total=${#hosts[@]}

    if [[ $total -eq 0 ]]; then
        echo -e "${YELLOW}Список серверов пуст.${NC}" >&2
        read -rp "Нажмите Enter..." >&2
        return 1
    fi

    while true; do
        clear 2>/dev/null || true
        echo -e "${BLUE}═════ ${title} ═════${NC}
" >&2
        for (( i=0; i<total; i++ )); do
            local h="${hosts[$i]}"
            local u hn p
            hn=$(ssh -F "${CONFIG_FILE}" -G "$h" 2>/dev/null | awk '$1=="hostname"{print $2}')
            p=$(ssh -F "${CONFIG_FILE}" -G "$h" 2>/dev/null | awk '$1=="port"{print $2}')
            u=$(ssh -F "${CONFIG_FILE}" -G "$h" 2>/dev/null | awk '$1=="user"{print $2}')
            printf "  %d. %s — %s@%s:%s
" "$((i+1))" "${h}" "${u}" "${hn}" "${p}" >&2
        done
        echo "" >&2
        echo "  0. Назад" >&2
        echo -e "${BLUE}────────────────────────────────────────────────────${NC}" >&2
        read -rp "Выберите сервер [0–${total}]: " sel >&2

        if [[ "${sel}" == "0" || "${sel}" == "q" || "${sel}" == "Q" || -z "${sel}" ]]; then
            return 1
        fi

        if [[ "${sel}" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= total )); then
            echo "${hosts[$((sel-1))]}"
            return 0
        fi

        echo -e "${RED}Неверный номер. Введите число от 0 до ${total}.${NC}" >&2
        sleep 1.2
    done
}


# 4.4 Добавление сервера (Пошаговый мастер)
action_add_server() {
    clear 2>/dev/null || true
    echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}               ДОБАВЛЕНИЕ СЕРВЕРА                   ${NC}"
    echo -e "${BLUE}────────────────────────────────────────────────────${NC}"

    read -rp "1. Имя подключения (алиас, например vps1): " host_alias
    host_alias="$(echo "${host_alias}" | xargs)"

    if [[ -z "${host_alias}" ]]; then
        echo -e "${RED}Ошибка: алиас не может быть пустым.${NC}"
        read -rp "Нажмите Enter..."; return
    fi

    if get_hosts | grep -qw "^${host_alias}$"; then
        echo -e "${RED}Ошибка: сервер с именем '${host_alias}' уже существует.${NC}"
        read -rp "Нажмите Enter..."; return
    fi

    read -rp "2. IP-адрес или доменное имя: " host_name
    host_name="$(echo "${host_name}" | xargs)"
    if [[ -z "${host_name}" ]]; then
        echo -e "${RED}Ошибка: адрес не может быть пустым.${NC}"
        read -rp "Нажмите Enter..."; return
    fi

    read -rp "3. Имя пользователя [${DEF_USER}]: " user_name
    user_name="$(echo "${user_name}" | xargs)"
    user_name="${user_name:-${DEF_USER}}"

    read -rp "4. SSH-порт [${DEF_PORT}]: " port
    port="$(echo "${port}" | xargs)"
    port="${port:-${DEF_PORT}}"

    if ! [[ "${port}" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
        echo -e "${RED}Ошибка: порт должен быть числом от 1 до 65535.${NC}"
        read -rp "Нажмите Enter..."; return
    fi

    echo -e "\n5. Способ аутентификации:"
    echo "   1) SSH-ключ (${DEFAULT_KEY})"
    echo "   2) Пароль (OpenSSH запросит при входе)"
    echo "   3) Выбрать существующий локальный ключ"
    read -rp "Ваш выбор [1]: " a_sel
    a_sel="${a_sel:-1}"

    local identity_line=""
    local auth_lines=""

    case "${a_sel}" in
        1)
            identity_line="    IdentityFile ${DEFAULT_KEY}"
            ;;
        2)
            auth_lines=$'    PubkeyAuthentication no\n    PreferredAuthentications password,keyboard-interactive'
            ;;
        3)
            local keys=()
            while IFS= read -r k; do [[ -n "$k" ]] && keys+=("$k"); done < <(get_local_keys)
            if [[ ${#keys[@]} -eq 0 ]]; then
                echo -e "${YELLOW}Ключей не найдено. Используется: ${DEFAULT_KEY}${NC}"
                identity_line="    IdentityFile ${DEFAULT_KEY}"
            else
                echo -e "\nВыберите ключ:"
                for i in "${!keys[@]}"; do
                    printf "   %d) %s\n" "$((i+1))" "$(basename "${keys[$i]}")"
                done
                read -rp "Номер: " k_num
                if [[ "${k_num}" =~ ^[0-9]+$ ]] && (( k_num >= 1 && k_num <= ${#keys[@]} )); then
                    identity_line="    IdentityFile ${keys[$((k_num-1))]}"
                else
                    identity_line="    IdentityFile ${DEFAULT_KEY}"
                fi
            fi
            ;;
        *)
            echo -e "${RED}Неверный выбор.${NC}"; read -rp "Нажмите Enter..."; return ;;
    esac

    read -rp $'\n6. Дополнительные параметры SSH (необязательно, Enter для пропуска): ' extra_params
    extra_params="$(echo "${extra_params}" | xargs)"

    # Предварительный просмотр конфигурации (9 ТЗ)
    echo -e "\n${BOLD}ПРЕДВАРИТЕЛЬНЫЙ ПРОСМОТР КОНФИГУРАЦИИ:${NC}"
    echo "Host ${host_alias}"
    echo "    HostName ${host_name}"
    echo "    User ${user_name}"
    echo "    Port ${port}"
    [[ -n "${identity_line}" ]] && echo "${identity_line}"
    [[ -n "${auth_lines}" ]] && echo "${auth_lines}"
    [[ -n "${extra_params}" ]] && echo "    ${extra_params}"
    echo ""

    read -rp "Сохранить сервер? [Y/n]: " conf_save
    conf_save="${conf_save:-y}"
    if ! [[ "${conf_save}" =~ ^[Yy]$ ]]; then
        echo "Добавление отменено."
        read -rp "Нажмите Enter..."; return
    fi

    backup_config

    {
        echo ""
        echo "Host ${host_alias}"
        echo "    HostName ${host_name}"
        echo "    User ${user_name}"
        echo "    Port ${port}"
        [[ -n "${identity_line}" ]] && echo "${identity_line}"
        [[ -n "${auth_lines}" ]] && echo "${auth_lines}"
        [[ -n "${extra_params}" ]] && echo "    ${extra_params}"
    } >> "${CONFIG_FILE}"

    chmod 600 "${CONFIG_FILE}"
    sync_server_ids

    local assigned_id
    assigned_id=$(get_id_by_alias "${host_alias}")
    echo -e "
${GREEN}✓ Сервер '${host_alias}' успешно добавлен в ~/.ssh/config.${NC}"
    read -rp "Нажмите Enter..."
}

# 4.5 Редактирование сервера через черновик
action_edit_server() {
    local target="$1"

    # Исходные данные
    local cur_hn cur_u cur_p cur_key cur_auth_type="KEY"
    cur_hn=$(ssh -F "${CONFIG_FILE}" -G "${target}" 2>/dev/null | awk '$1=="hostname"{print $2}')
    cur_u=$(ssh -F "${CONFIG_FILE}" -G "${target}" 2>/dev/null | awk '$1=="user"{print $2}')
    cur_p=$(ssh -F "${CONFIG_FILE}" -G "${target}" 2>/dev/null | awk '$1=="port"{print $2}')
    cur_key=$(ssh -F "${CONFIG_FILE}" -G "${target}" 2>/dev/null | awk '$1=="identityfile"{print $2}')
    cur_auth_type=$(get_host_auth_type "${target}")

    # Черновик (draft)
    local d_alias="${target}"
    local d_hn="${cur_hn}"
    local d_u="${cur_u}"
    local d_p="${cur_p}"
    local d_key="${cur_key}"
    local d_auth="${cur_auth_type}"
    local d_extra=""

    while true; do
        clear 2>/dev/null || true
        echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
        echo -e "${BOLD}РЕДАКТИРОВАНИЕ (черновик): ${CYAN}${target}${NC}"
        echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
        echo "  1) Имя подключения:     ${d_alias}"
        echo "  2) IP / домен:          ${d_hn}"
        echo "  3) Пользователь:        ${d_u}"
        echo "  4) SSH-порт:            ${d_p}"
        echo "  5) Приватный ключ:      ${d_key}"
        echo "  6) Способ аутентификации: ${d_auth}"
        echo "  7) Дополнительные параметры: ${d_extra:-(сохраняются исходные)}"
        echo "  8) Редактировать все поля по очереди"
        echo "  9) Просмотреть итоговую конфигурацию"
        echo " 10) Проверить подключение с текущими параметрами"
        echo " 11) Сохранить изменения в config"
        echo ""
        echo "  0) Отмена / назад"
        echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
        read -rp "Выберите пункт [0-11]: " ed_choice

        case "${ed_choice}" in
            1)
                read -rp "Новое имя подключения [${d_alias}]: " val
                val="$(echo "${val}" | xargs)"
                if [[ -n "${val}" && "${val}" != "${d_alias}" ]]; then
                    if get_hosts | grep -qw "^${val}$"; then
                        echo -e "${RED}Алиас '${val}' уже занят.${NC}"; sleep 1
                    else
                        d_alias="${val}"
                    fi
                fi
                ;;
            2)
                read -rp "Новый IP/домен [${d_hn}]: " val
                [[ -n "${val}" ]] && d_hn="$(echo "${val}" | xargs)"
                ;;
            3)
                read -rp "Новый пользователь [${d_u}]: " val
                [[ -n "${val}" ]] && d_u="$(echo "${val}" | xargs)"
                ;;
            4)
                read -rp "Новый SSH-порт [${d_p}]: " val
                val="$(echo "${val}" | xargs)"
                if [[ -n "${val}" ]] && [[ "${val}" =~ ^[0-9]+$ ]] && (( val >= 1 && val <= 65535 )); then
                    d_p="${val}"
                fi
                ;;
            5)
                echo "1) Использовать ${DEFAULT_KEY}"
                echo "2) Выбрать из имеющихся на телефоне"
                echo "3) Указать путь вручную"
                read -rp "> " k_sel
                if [[ "${k_sel}" == "1" ]]; then
                    d_key="${DEFAULT_KEY}"; d_auth="KEY"
                elif [[ "${k_sel}" == "2" ]]; then
                    local keys=()
                    while IFS= read -r k; do [[ -n "$k" ]] && keys+=("$k"); done < <(get_local_keys)
                    for i in "${!keys[@]}"; do printf "  %d) %s\n" "$((i+1))" "$(basename "${keys[$i]}")"; done
                    read -rp "Номер: " k_n
                    if [[ "${k_n}" =~ ^[0-9]+$ ]] && (( k_n >= 1 && k_n <= ${#keys[@]} )); then
                        d_key="${keys[$((k_n-1))]}"; d_auth="KEY"
                    fi
                elif [[ "${k_sel}" == "3" ]]; then
                    read -rp "Путь к ключу: " val
                    [[ -n "${val}" ]] && d_key="${val}" && d_auth="KEY"
                fi
                ;;
            6)
                echo "1) Вход по SSH-ключу"
                echo "2) Вход по паролю"
                read -rp "> " a_sel
                if [[ "${a_sel}" == "1" ]]; then d_auth="KEY"; fi
                if [[ "${a_sel}" == "2" ]]; then d_auth="PWD"; fi
                ;;
            7)
                read -rp "Дополнительные параметры (Enter для сброса): " d_extra
                ;;
            8)
                read -rp "Имя [${d_alias}]: " val; [[ -n "${val}" ]] && d_alias="$(echo "${val}" | xargs)"
                read -rp "Адрес [${d_hn}]: " val; [[ -n "${val}" ]] && d_hn="$(echo "${val}" | xargs)"
                read -rp "Пользователь [${d_u}]: " val; [[ -n "${val}" ]] && d_u="$(echo "${val}" | xargs)"
                read -rp "Порт [${d_p}]: " val; [[ -n "${val}" ]] && d_p="$(echo "${val}" | xargs)"
                ;;
            9)
                clear 2>/dev/null || true
                echo -e "${BOLD}ИТОГОВАЯ КОНФИГУРАЦИЯ БЛОКА:${NC}\n"
                echo "Host ${d_alias}"
                echo "    HostName ${d_hn}"
                echo "    User ${d_u}"
                echo "    Port ${d_p}"
                if [[ "${d_auth}" == "KEY" ]]; then
                    echo "    IdentityFile ${d_key}"
                else
                    echo "    PubkeyAuthentication no"
                    echo "    PreferredAuthentications password,keyboard-interactive"
                fi
                [[ -n "${d_extra}" ]] && echo "    ${d_extra}"
                echo ""
                read -rp "Нажмите Enter..."
                ;;
            10)
                echo -e "${CYAN}Тестирование подключения к ${d_hn}:${d_p}...${NC}"
                if (echo > /dev/tcp/"${d_hn}"/"${d_p}") 2>/dev/null; then
                    echo -e "${GREEN}✓ Порт ${d_p} отвечает.${NC}"
                else
                    echo -e "${RED}✗ Порт ${d_p} недоступен или тайм-аут.${NC}"
                fi
                read -rp "Нажмите Enter..."
                ;;
            11)
                # Сохранение с извлечением всех сторонних директив (4.6 ТЗ)
                backup_config

                # Извлекаем все неизвестные менеджеру строки из исходного блока
                local preserved_lines
                preserved_lines=$(get_host_raw_block "${target}" | grep -viE '^[[:space:]]*(Host|HostName|User|Port|IdentityFile|PubkeyAuthentication|PreferredAuthentications)[[:space:]]+' || true)

                remove_host_block "${target}"

                {
                    echo ""
                    echo "Host ${d_alias}"
                    echo "    HostName ${d_hn}"
                    echo "    User ${d_u}"
                    echo "    Port ${d_p}"
                    if [[ "${d_auth}" == "KEY" ]]; then
                        echo "    IdentityFile ${d_key}"
                    else
                        echo "    PubkeyAuthentication no"
                        echo "    PreferredAuthentications password,keyboard-interactive"
                    fi
                    [[ -n "${d_extra}" ]] && echo "    ${d_extra}"
                    if [[ -n "${preserved_lines}" ]]; then
                        echo "${preserved_lines}"
                    fi
                } >> "${CONFIG_FILE}"

                chmod 600 "${CONFIG_FILE}"

                # Если имя изменилось, обновляем маппинг с сохранением ID (4.7 ТЗ)
                if [[ "${target}" != "${d_alias}" ]]; then
                    rename_server_id "${target}" "${d_alias}"
                    echo -e "${YELLOW}Предупреждение: алиас '${target}' изменён на '${d_alias}'.${NC}"
                fi
                sync_server_ids
                echo -e "${GREEN}✓ Изменения успешно сохранены в config.${NC}"
                read -rp "Нажмите Enter..."; break ;;
            0|[qQ])
                echo "Редактирование отменено."
                read -rp "Нажмите Enter..."; break ;;
            *) ;;
        esac
    done
}

# 4.8 Клонирование сервера
action_clone_server() {
    local src_host="$1"
    clear 2>/dev/null || true
    echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}               КЛОНИРОВАНИЕ СЕРВЕРА                 ${NC}"
    echo -e "${BLUE}────────────────────────────────────────────────────${NC}"

    local src_hn src_u src_p src_key src_auth
    src_hn=$(ssh -F "${CONFIG_FILE}" -G "${src_host}" 2>/dev/null | awk '$1=="hostname"{print $2}')
    src_u=$(ssh -F "${CONFIG_FILE}" -G "${src_host}" 2>/dev/null | awk '$1=="user"{print $2}')
    src_p=$(ssh -F "${CONFIG_FILE}" -G "${src_host}" 2>/dev/null | awk '$1=="port"{print $2}')
    src_key=$(ssh -F "${CONFIG_FILE}" -G "${src_host}" 2>/dev/null | awk '$1=="identityfile"{print $2}')
    src_auth=$(get_host_auth_type "${src_host}")

    echo -e "Клонирование параметров из: ${BOLD}${src_host}${NC} (${src_u}@${src_hn}:${src_p})\n"

    read -rp "Имя нового подключения: " clone_alias
    clone_alias="$(echo "${clone_alias}" | xargs)"
    if [[ -z "${clone_alias}" ]]; then
        echo -e "${RED}Ошибка: имя не может быть пустым.${NC}"; read -rp "Нажмите Enter..."; return
    fi
    if get_hosts | grep -qw "^${clone_alias}$"; then
        echo -e "${RED}Ошибка: хост '${clone_alias}' уже существует.${NC}"; read -rp "Нажмите Enter..."; return
    fi

    read -rp "Новый адрес / IP [${src_hn}]: " clone_hn
    clone_hn="$(echo "${clone_hn:-${src_hn}}" | xargs)"

    read -rp "Пользователь [${src_u}]: " clone_u
    clone_u="$(echo "${clone_u:-${src_u}}" | xargs)"

    read -rp "SSH-порт [${src_p}]: " clone_p
    clone_p="$(echo "${clone_p:-${src_p}}" | xargs)"

    # Сохраняем дополнительные директивы исходного хоста
    local preserved_lines
    preserved_lines=$(get_host_raw_block "${src_host}" | grep -viE '^[[:space:]]*(Host|HostName|User|Port)[[:space:]]+' || true)

    backup_config

    {
        echo ""
        echo "Host ${clone_alias}"
        echo "    HostName ${clone_hn}"
        echo "    User ${clone_u}"
        echo "    Port ${clone_p}"
        if [[ -n "${preserved_lines}" ]]; then
            echo "${preserved_lines}"
        fi
    } >> "${CONFIG_FILE}"

    chmod 600 "${CONFIG_FILE}"
    sync_server_ids

    local new_id
    new_id=$(get_id_by_alias "${clone_alias}")
    echo -e "
${GREEN}✓ Создан новый сервер ${clone_alias} на основе ${src_host}.${NC}"
    read -rp "Нажмите Enter..."
}

# 4.9 Удаление сервера
action_delete_server() {
    local target="$1"
    clear 2>/dev/null || true
    echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}               УДАЛИТЬ СЕРВЕР                       ${NC}"
    echo -e "${BLUE}────────────────────────────────────────────────────${NC}"

    local id u hn p
    id=$(get_id_by_alias "${target}")
    hn=$(ssh -F "${CONFIG_FILE}" -G "${target}" 2>/dev/null | awk '$1=="hostname"{print $2}')
    u=$(ssh -F "${CONFIG_FILE}" -G "${target}" 2>/dev/null | awk '$1=="user"{print $2}')
    p=$(ssh -F "${CONFIG_FILE}" -G "${target}" 2>/dev/null | awk '$1=="port"{print $2}')

    echo -e "Вы собираетесь удалить сервер:"
    echo -e "  ${BOLD}${target}${NC}"
    echo -e "  Адрес: ${u}@${hn}:${p}\n"

    echo -e "${YELLOW}Для подтверждения введите имя подключения [${target}]:${NC}"
    read -rp "> " confirm_name

    if [[ "${confirm_name}" != "${target}" ]]; then
        echo -e "${RED}Имя не совпадает. Удаление отменено.${NC}"
        read -rp "Нажмите Enter..."; return 1
    fi

    read -rp "Удалить сервер '${target}'? [y/N]: " conf_del
    if [[ "${conf_del}" =~ ^[Yy]$ ]]; then
        backup_config
        remove_host_block "${target}"
        remove_server_id "${target}"
        echo -e "${GREEN}✓ Сервер '${target}' успешно удалён из ~/.ssh/config.${NC}"
        read -rp "Нажмите Enter..."; return 0
    else
        echo "Удаление отменено."
        read -rp "Нажмите Enter..."; return 1
    fi
}

# 4.8 Поиск серверов
action_search_servers() {
    clear 2>/dev/null || true
    echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}                 ПОИСК СЕРВЕРОВ                     ${NC}"
    echo -e "${BLUE}────────────────────────────────────────────────────${NC}"

    read -rp "Поисковый запрос (алиас, IP или пользователь): " q
    q="$(echo "${q}" | tr '[:upper:]' '[:lower:]')"

    local hosts=()
    while IFS= read -r h; do [[ -n "$h" ]] && hosts+=("$h"); done < <(get_hosts)

    echo -e "\n${BOLD}Результаты поиска:${NC}"
    local count=0
    for h in "${hosts[@]}"; do
        local id u hn p
        id=$(get_id_by_alias "$h")
        u=$(ssh -F "${CONFIG_FILE}" -G "$h" 2>/dev/null | awk '$1=="user"{print $2}')
        hn=$(ssh -F "${CONFIG_FILE}" -G "$h" 2>/dev/null | awk '$1=="hostname"{print $2}')
        p=$(ssh -F "${CONFIG_FILE}" -G "$h" 2>/dev/null | awk '$1=="port"{print $2}')
        local full_line="${id} ${h} ${u} ${hn} ${p}"
        if echo "${full_line}" | tr '[:upper:]' '[:lower:]' | grep -q "${q}"; then
            printf "  [%s] %-12s %s@%s:%s\n" "${id}" "${h}" "${u}" "${hn}" "${p}"
            count=$((count + 1))
        fi
    done

    [[ $count -eq 0 ]] && echo -e "  ${YELLOW}Ничего не найдено.${NC}"
    echo ""
    read -rp "Нажмите Enter..."
}

# ==============================================================================
# SSH-КЛЮЧИ (Раздел 6 ТЗ)
# ==============================================================================
menu_ssh_keys() {
    while true; do
        clear 2>/dev/null || true
        echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
        echo -e "${BOLD}                    SSH-КЛЮЧИ                       ${NC}"
        echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
        echo "  1) Список локальных ключей"
        echo "  2) Создать новый ключ"
        echo "  3) Проверить ключевую пару"
        echo "  4) Показать публичный ключ"
        echo "  5) Fingerprint"
        echo "  6) Установить ключ на VPS (ssh-copy-id / manual)"
        echo "  7) Проверить вход по ключу"
        echo "  8) GitHub: получить публичные ключи"
        echo "  9) Сравнить ключи с GitHub"
        echo " 10) Удалить локальный ключ"
        echo ""
        echo "  0) Назад"
        echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
        read -rp "Выберите действие [0-10]: " k_choice

        case "${k_choice}" in
            1) keys_list_local ;;
            2) keys_create_new ;;
            3) keys_verify_pair ;;
            4) keys_show_pub ;;
            5) keys_show_fingerprints ;;
            6) keys_deploy_to_vps ;;
            7) keys_test_login ;;
            8) keys_github_fetch ;;
            9) keys_github_compare ;;
            10) keys_delete_local ;;
            0|[qQ]) break ;;
            *) echo -e "${RED}Неверный выбор.${NC}"; sleep 1 ;;
        esac
    done
}

# 6.2 Список локальных ключей
keys_list_local() {
    clear 2>/dev/null || true
    echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}               ЛОКАЛЬНЫЕ SSH-КЛЮЧИ                  ${NC}"
    echo -e "${BLUE}────────────────────────────────────────────────────${NC}"

    local pub_files=()
    while IFS= read -r f; do [[ -n "$f" ]] && pub_files+=("$f"); done < <(ls "${SSH_DIR}"/*.pub 2>/dev/null || true)

    if [[ ${#pub_files[@]} -eq 0 ]]; then
        echo -e "${YELLOW}Ключи в ~/.ssh/ не найдены.${NC}"
    else
        for pub in "${pub_files[@]}"; do
            local priv="${pub%.pub}"
            local k_name
            k_name="$(basename "${priv}")"
            local fp k_type
            fp=$(ssh-keygen -lf "${pub}" 2>/dev/null | awk '{print $2}' || echo "-")
            k_type=$(ssh-keygen -lf "${pub}" 2>/dev/null | awk '{print $4}' || echo "KEY")
            
            echo -e "${BOLD}• ${k_name}${NC} [${k_type}]"
            echo -e "  Отпечаток: ${CYAN}${fp}${NC}"
            if [[ -f "${priv}" ]]; then
                echo -e "  Статус:    ${GREEN}✓ Приватный + Публичный файлы есть${NC}"
            else
                echo -e "  Статус:    ${YELLOW}⚠ Только публичный (.pub) файл, приватного нет!${NC}"
            fi
            echo ""
        done
    fi
    read -rp "Нажмите Enter..."
}

# 6.3 Создание ключа
keys_create_new() {
    clear 2>/dev/null || true
    echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}               СОЗДАНИЕ SSH-КЛЮЧА                   ${NC}"
    echo -e "${BLUE}────────────────────────────────────────────────────${NC}"

    echo "1) ED25519 (современный, быстрый, безопасный — рекомендуется)"
    echo "2) RSA 4096 (для совместимости со старыми системами)"
    echo "0) Отмена"
    read -rp "Выберите тип [1]: " t_sel
    t_sel="${t_sel:-1}"
    [[ "${t_sel}" == "0" ]] && return

    local k_type="ed25519"
    local def_name="id_ed25519"
    if [[ "${t_sel}" == "2" ]]; then
        k_type="rsa"
        def_name="id_rsa"
    fi

    read -rp "Имя файла [${def_name}]: " k_name
    k_name="${k_name:-${def_name}}"
    local target_path="${SSH_DIR}/${k_name}"

    # 6.4 Защита от перезаписи
    if [[ -f "${target_path}" ]]; then
        echo -e "\n${YELLOW}Предупреждение: файл ${target_path} уже существует!${NC}"
        echo "1) Задать другое имя"
        echo "2) Создать бэкап и заменить существующий"
        echo "0) Отмена"
        read -rp "> " ow_sel
        if [[ "${ow_sel}" == "1" ]]; then
            read -rp "Новое имя файла: " k_name
            target_path="${SSH_DIR}/${k_name}"
        elif [[ "${ow_sel}" == "2" ]]; then
            cp "${target_path}" "${target_path}.bak_$(date +%s)"
            [[ -f "${target_path}.pub" ]] && cp "${target_path}.pub" "${target_path}.pub.bak_$(date +%s)"
        else
            return
        fi
    fi

    read -rp "Комментарий (например, email или termux): " k_comm
    k_comm="${k_comm:-termux}"

    echo -e "${CYAN}Генерация ключа ${k_type}...${NC}"
    if [[ "${k_type}" == "rsa" ]]; then
        ssh-keygen -t rsa -b 4096 -f "${target_path}" -C "${k_comm}"
    else
        ssh-keygen -t ed25519 -f "${target_path}" -C "${k_comm}"
    fi

    chmod 600 "${target_path}"
    chmod 644 "${target_path}.pub"

    echo -e "\n${GREEN}✓ Ключ успешно создан:${NC} ${target_path}"
    echo -e "Fingerprint: $(ssh-keygen -lf "${target_path}.pub" | awk '{print $2}')"
    read -rp "Нажмите Enter..."
}

# 6.5 Проверка ключевой пары
keys_verify_pair() {
    clear 2>/dev/null || true
    echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}       ПРОВЕРКА КЛЮЧЕВОЙ ПАРЫ (priv ↔ pub)          ${NC}"
    echo -e "${BLUE}────────────────────────────────────────────────────${NC}"

    read -rp "Имя файла ключа [id_ed25519]: " k_name
    k_name="${k_name:-id_ed25519}"
    local priv="${SSH_DIR}/${k_name}"
    local pub="${SSH_DIR}/${k_name}.pub"

    local has_priv=0
    local has_pub=0
    [[ -f "${priv}" ]] && has_priv=1
    [[ -f "${pub}" ]] && has_pub=1

    if [[ $has_priv -eq 0 && $has_pub -eq 0 ]]; then
        echo -e "${RED}Файлы ключа '${k_name}' не найдены в ~/.ssh/${NC}"
        read -rp "Нажмите Enter..."; return
    fi

    [[ $has_priv -eq 1 ]] && echo -e "  Приватный файл: ${GREEN}✓ Найден${NC} (${priv})" || echo -e "  Приватный файл: ${RED}✗ Отсутствует${NC}"
    
    if [[ $has_pub -eq 1 ]]; then
        echo -e "  Публичный файл:  ${GREEN}✓ Найден${NC} (${pub})"
    else
        echo -e "  Публичный файл:  ${YELLOW}⚠ Отсутствует${NC}"
        if [[ $has_priv -eq 1 ]]; then
            read -rp "Восстановить .pub из приватного ключа? [Y/n]: " do_rec
            if [[ "${do_rec:-y}" =~ ^[Yy]$ ]]; then
                ssh-keygen -y -f "${priv}" > "${pub}"
                chmod 644 "${pub}"
                echo -e "  ${GREEN}✓ Публичный ключ восстановлен!${NC}"
                has_pub=1
            fi
        fi
    fi

    if [[ $has_priv -eq 1 && $has_pub -eq 1 ]]; then
        local fp_pub fp_priv
        fp_pub=$(ssh-keygen -lf "${pub}" 2>/dev/null | awk '{print $2}')
        fp_priv=$(ssh-keygen -y -f "${priv}" 2>/dev/null | ssh-keygen -lf - 2>/dev/null | awk '{print $2}' || true)
        echo ""
        if [[ -n "${fp_pub}" && "${fp_pub}" == "${fp_priv}" ]]; then
            echo -e "${GREEN}✓ КЛЮЧИ ПОЛНОСТЬЮ СОВПАДАЮТ!${NC}"
            echo -e "Fingerprint: ${BOLD}${fp_pub}${NC}"
            echo -e "Полноценная рабочая пара готова к работе."
        else
            echo -e "${RED}⚠ ВНИМАНИЕ: КЛЮЧИ НЕ СОВПАДАЮТ!${NC}"
            echo -e "Публичный файл не соответствует приватному ключу."
        fi
    fi
    echo ""
    read -rp "Нажмите Enter..."
}

# 6.4 Показать публичный ключ
keys_show_pub() {
    clear 2>/dev/null || true
    echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}               ПУБЛИЧНЫЙ КЛЮЧ (.pub)                ${NC}"
    echo -e "${BLUE}────────────────────────────────────────────────────${NC}"

    local pub_files=()
    while IFS= read -r f; do [[ -n "$f" ]] && pub_files+=("$f"); done < <(ls "${SSH_DIR}"/*.pub 2>/dev/null || true)

    if [[ ${#pub_files[@]} -eq 0 ]]; then
        echo -e "${YELLOW}Публичные ключи не найдены.${NC}"
        read -rp "Нажмите Enter..."; return
    fi

    for i in "${!pub_files[@]}"; do
        printf "  %d) %s\n" "$((i+1))" "$(basename "${pub_files[$i]}")"
    done
    read -rp "Выберите ключ: " sel
    if [[ "${sel}" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#pub_files[@]} )); then
        local chosen="${pub_files[$((sel-1))]}"
        echo -e "\n${BOLD}${chosen}:${NC}\n"
        cat "${chosen}"
        echo ""
        if command -v termux-clipboard-set >/dev/null 2>&1; then
            termux-clipboard-set < "${chosen}"
            echo -e "${GREEN}✓ Скопировано в буфер обмена Android!${NC}"
        fi
    fi
    read -rp "Нажмите Enter..."
}

keys_show_fingerprints() {
    clear 2>/dev/null || true
    echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}               ОТПЕЧАТКИ (FINGERPRINTS)             ${NC}"
    echo -e "${BLUE}────────────────────────────────────────────────────${NC}"

    local pub_files=()
    while IFS= read -r f; do [[ -n "$f" ]] && pub_files+=("$f"); done < <(ls "${SSH_DIR}"/*.pub 2>/dev/null || true)

    for pub in "${pub_files[@]}"; do
        local fp
        fp=$(ssh-keygen -lf "${pub}" 2>/dev/null || echo "Некорректный ключ")
        echo -e "${BOLD}$(basename "${pub}")${NC}:"
        echo -e "  ${CYAN}${fp}${NC}\n"
    done
    read -rp "Нажмите Enter..."
}

# 6.6 Установка ключа на VPS
keys_deploy_to_vps() {
    clear 2>/dev/null || true
    echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}       УСТАНОВКА КЛЮЧА НА VPS                       ${NC}"
    echo -e "${BLUE}────────────────────────────────────────────────────${NC}"

    local pub_files=()
    while IFS= read -r f; do [[ -n "$f" ]] && pub_files+=("$f"); done < <(ls "${SSH_DIR}"/*.pub 2>/dev/null || true)

    if [[ ${#pub_files[@]} -eq 0 ]]; then
        echo -e "${YELLOW}Сначала создайте или загрузите SSH-ключ.${NC}"
        read -rp "Нажмите Enter..."; return
    fi

    echo "Выберите публичный ключ для установки:"
    for i in "${!pub_files[@]}"; do
        printf "  %d) %s\n" "$((i+1))" "$(basename "${pub_files[$i]}")"
    done
    read -rp "> " k_sel
    [[ "${k_sel}" =~ ^[0-9]+$ ]] && (( k_sel >= 1 && k_sel <= ${#pub_files[@]} )) || return
    local chosen_pub="${pub_files[$((k_sel-1))]}"

    local s_alias
    s_alias=$(prompt_select_server "Выберите сервер для установки ключа")
    [[ -z "${s_alias}" ]] && return

    echo -e "\n${CYAN}Установка ${chosen_pub} на ${s_alias}...${NC}"

    # Попытка через ssh-copy-id, а если нет — ручной fallback
    if command -v ssh-copy-id >/dev/null 2>&1; then
        ssh-copy-id -i "${chosen_pub}" "${s_alias}" || {
            echo -e "${YELLOW}Попытка ручной установки через SSH pipe...${NC}"
            cat "${chosen_pub}" | ssh -F "${CONFIG_FILE}" "${s_alias}" "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
        }
    else
        cat "${chosen_pub}" | ssh -F "${CONFIG_FILE}" "${s_alias}" "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
    fi

    echo -e "${GREEN}✓ Процесс завершён. Проверка входа по ключу...${NC}"
    if ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${s_alias}" 'exit' 2>/dev/null; then
        echo -e "${GREEN}✓ Вход по ключу подтверждён!${NC}"
    else
        echo -e "${YELLOW}⚠ Сервер пока не принимает ключ без пароля.${NC}"
    fi
    read -rp "Нажмите Enter..."
}

keys_test_login() {
    local s_alias
    s_alias=$(prompt_select_server "Проверка входа по ключу")
    [[ -z "${s_alias}" ]] && return

    echo -e "\n${CYAN}Проверка входа на ${s_alias}...${NC}"
    if ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${s_alias}" 'exit' 2>/dev/null; then
        echo -e "${GREEN}✓ Авторизация по ключу успешна!${NC}"
    else
        echo -e "${RED}✗ Вход по ключу не удался (ключ отклонён или требуется пароль).${NC}"
    fi
    read -rp "Нажмите Enter..."
}

keys_github_fetch() {
    clear 2>/dev/null || true
    echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}       ПОЛУЧИТЬ ПУБЛИЧНЫЕ КЛЮЧИ С GITHUB            ${NC}"
    echo -e "${BLUE}────────────────────────────────────────────────────${NC}"

    read -rp "Логин GitHub [${GH_USER}]: " u_gh
    u_gh="${u_gh:-${GH_USER}}"

    echo -e "${CYAN}Запрос https://github.com/${u_gh}.keys...${NC}"
    local raw
    if ! raw=$(curl -fsSL --connect-timeout "${CONN_TIMEOUT}" "https://github.com/${u_gh}.keys"); then
        echo -e "${RED}Не удалось загрузить ключи.${NC}"
        read -rp "Нажмите Enter..."; return
    fi

    if [[ -z "${raw}" ]]; then
        echo -e "${YELLOW}Ключи в профиле отсутствуют.${NC}"
        read -rp "Нажмите Enter..."; return
    fi

    local lines=()
    while IFS= read -r l; do [[ -n "$l" ]] && lines+=("$l"); done <<< "${raw}"

    echo -e "\nНайдено ключей: ${#lines[@]}"
    for i in "${!lines[@]}"; do
        local fp
        fp=$(echo "${lines[$i]}" | ssh-keygen -lf - 2>/dev/null || echo "-")
        printf "  %d) %s\n" "$((i+1))" "${fp}"
    done

    read -rp "Сохранить ключ в ~/.ssh? Введите номер [1] или 0 для отмены: " c_idx
    c_idx="${c_idx:-1}"
    [[ "${c_idx}" == "0" ]] && return

    if [[ "${c_idx}" =~ ^[0-9]+$ ]] && (( c_idx >= 1 && c_idx <= ${#lines[@]} )); then
        local chosen_key="${lines[$((c_idx-1))]}"
        read -rp "Имя файла [github_${u_gh}.pub]: " save_name
        save_name="${save_name:-github_${u_gh}.pub}"
        [[ "${save_name}" != *.pub ]] && save_name="${save_name}.pub"
        echo "${chosen_key}" > "${SSH_DIR}/${save_name}"
        chmod 644 "${SSH_DIR}/${save_name}"
        echo -e "${GREEN}✓ Публичный ключ сохранён в ~/.ssh/${save_name}${NC}"
    fi
    read -rp "Нажмите Enter..."
}

keys_github_compare() {
    clear 2>/dev/null || true
    echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}       СРАВНИТЬ КЛЮЧИ С GITHUB                      ${NC}"
    echo -e "${BLUE}────────────────────────────────────────────────────${NC}"

    read -rp "Логин GitHub [${GH_USER}]: " u_gh
    u_gh="${u_gh:-${GH_USER}}"

    local raw
    if ! raw=$(curl -fsSL --connect-timeout "${CONN_TIMEOUT}" "https://github.com/${u_gh}.keys" 2>/dev/null); then
        echo -e "${RED}Ошибка загрузки ключей с GitHub.${NC}"
        read -rp "Нажмите Enter..."; return
    fi

    local pub_files=()
    while IFS= read -r f; do [[ -n "$f" ]] && pub_files+=("$f"); done < <(ls "${SSH_DIR}"/*.pub 2>/dev/null || true)

    echo -e "\n${BOLD}Сравнение локальных ключей с профилем GitHub (${u_gh}):${NC}\n"
    for pub in "${pub_files[@]}"; do
        local l_fp
        l_fp=$(ssh-keygen -lf "${pub}" 2>/dev/null | awk '{print $2}')
        local matched=0
        while IFS= read -r gh_l; do
            [[ -z "$gh_l" ]] && continue
            local g_fp
            g_fp=$(echo "$gh_l" | ssh-keygen -lf - 2>/dev/null | awk '{print $2}')
            if [[ "$l_fp" == "$g_fp" ]]; then matched=1; break; fi
        done <<< "${raw}"

        if [[ $matched -eq 1 ]]; then
            echo -e "• $(basename "$pub"): ${GREEN}✓ СОВПАДАЕТ с GitHub${NC} (${l_fp})"
        else
            echo -e "• $(basename "$pub"): ${YELLOW}⚠ НЕТ на GitHub${NC} (${l_fp})"
        fi
    done
    echo ""
    read -rp "Нажмите Enter..."
}

keys_delete_local() {
    clear 2>/dev/null || true
    echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}               УДАЛИТЬ ЛОКАЛЬНЫЙ КЛЮЧ               ${NC}"
    echo -e "${BLUE}────────────────────────────────────────────────────${NC}"

    local pub_files=()
    while IFS= read -r f; do [[ -n "$f" ]] && pub_files+=("$f"); done < <(ls "${SSH_DIR}"/*.pub 2>/dev/null || true)

    if [[ ${#pub_files[@]} -eq 0 ]]; then
        echo -e "${YELLOW}Ключей нет.${NC}"; read -rp "Нажмите Enter..."; return
    fi

    for i in "${!pub_files[@]}"; do
        printf "  %d) %s\n" "$((i+1))" "$(basename "${pub_files[$i]%.pub}")"
    done
    echo "  0) Отмена"
    read -rp "Выберите ключ: " sel
    if [[ "${sel}" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#pub_files[@]} )); then
        local priv="${pub_files[$((sel-1))]%.pub}"
        local pub="${priv}.pub"
        read -rp "Точно удалить ключ $(basename "${priv}") и его .pub? [y/N]: " conf
        if [[ "${conf}" =~ ^[Yy]$ ]]; then
            rm -f "${priv}" "${pub}"
            echo -e "${GREEN}✓ Ключ удалён.${NC}"
        fi
    fi
    read -rp "Нажмите Enter..."
}

# ==============================================================================
# SSH CONFIG (Раздел 7 ТЗ)
# ==============================================================================
menu_ssh_config() {
    while true; do
        clear 2>/dev/null || true
        echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
        echo -e "${BOLD}                 SSH CONFIG                         ${NC}"
        echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
        echo "  1) Просмотреть полный конфиг"
        echo "  2) Конфигурация выбранного сервера"
        echo "  3) Проверить конфигурацию"
        echo "  4) Эффективные параметры SSH (ssh -F "${CONFIG_FILE}" -G)"
        echo "  5) Проверить пути к ключам"
        echo "  6) Проверить права доступа"
        echo "  7) Исправить права доступа (700 / 600 / 644)"
        echo "  8) Резервная копия"
        echo "  9) Восстановить конфигурацию"
        echo " 10) Просмотреть Include"
        echo ""
        echo "  0) Назад"
        echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
        read -rp "Выберите действие [0-10]: " c_act

        case "${c_act}" in
            1)
                clear 2>/dev/null || true
                echo -e "${BOLD}Файл ${CONFIG_FILE}:${NC}\n"
                cat "${CONFIG_FILE}"
                echo ""
                read -rp "Нажмите Enter..."
                ;;
            2)
                local s_alias
                s_alias=$(prompt_select_server "Просмотр блока Host")
                if [[ -n "${s_alias}" ]]; then
                    clear 2>/dev/null || true
                    echo -e "${BOLD}Конфигурация ${s_alias}:${NC}\n"
                    get_host_raw_block "${s_alias}"
                    echo ""
                    read -rp "Нажмите Enter..."
                fi
                ;;
            3)
                clear 2>/dev/null || true
                echo -e "${BOLD}Проверка записей SSH Config:${NC}\n"
                local hosts=()
                while IFS= read -r h; do [[ -n "$h" ]] && hosts+=("$h"); done < <(get_hosts)
                for h in "${hosts[@]}"; do
                    if ssh -F "${CONFIG_FILE}" -G "$h" >/dev/null 2>&1; then
                        echo -e "  Host [${h}]: ${GREEN}✓ Синтаксис корректен${NC}"
                    else
                        echo -e "  Host [${h}]: ${RED}✗ Ошибка разбора OpenSSH!${NC}"
                    fi
                done
                echo ""
                read -rp "Нажмите Enter..."
                ;;
            4)
                local s_alias
                s_alias=$(prompt_select_server "Эффективные параметры (ssh -F "${CONFIG_FILE}" -G)")
                if [[ -n "${s_alias}" ]]; then
                    clear 2>/dev/null || true
                    echo -e "${BOLD}Эффективные параметры для ${s_alias}:${NC}\n"
                    ssh -F "${CONFIG_FILE}" -G "${s_alias}" 2>/dev/null | grep -E '^(hostname|user|port|identityfile|pubkeyauthentication|preferredauthentications|proxyjump|forwardagent|serveraliveinterval)' || ssh -F "${CONFIG_FILE}" -G "${s_alias}"
                    echo ""
                    read -rp "Нажмите Enter..."
                fi
                ;;
            5)
                clear 2>/dev/null || true
                echo -e "${BOLD}Проверка путей к ключам в config:${NC}\n"
                local hosts=()
                while IFS= read -r h; do [[ -n "$h" ]] && hosts+=("$h"); done < <(get_hosts)
                for h in "${hosts[@]}"; do
                    local id_file
                    id_file=$(ssh -F "${CONFIG_FILE}" -G "$h" 2>/dev/null | awk '$1=="identityfile"{print $2}')
                    if [[ -n "${id_file}" ]]; then
                        local exp_path="${id_file/#\~/$HOME}"
                        if [[ -f "${exp_path}" ]]; then
                            echo -e "  ${h}: ${GREEN}✓ Ключ найден (${id_file})${NC}"
                        else
                            echo -e "  ${h}: ${RED}✗ Ключ НЕ найден (${id_file})${NC}"
                        fi
                    fi
                done
                echo ""
                read -rp "Нажмите Enter..."
                ;;
            6)
                clear 2>/dev/null || true
                echo -e "${BOLD}Аудит прав доступа к SSH файлам:${NC}\n"
                ls -ld "${SSH_DIR}"
                ls -l "${CONFIG_FILE}"
                ls -l "${SSH_DIR}"/id_* 2>/dev/null || true
                ls -l "${KNOWN_HOSTS_FILE}" 2>/dev/null || true
                echo ""
                read -rp "Нажмите Enter..."
                ;;
            7)
                clear 2>/dev/null || true
                echo -e "${CYAN}Приведение прав к стандартам безопасности:${NC}"
                echo "  ~/.ssh         -> 700"
                echo "  ~/.ssh/config  -> 600"
                echo "  Приватные      -> 600"
                echo "  Публичные      -> 644"
                chmod 700 "${SSH_DIR}"
                chmod 600 "${CONFIG_FILE}"
                for priv in "${SSH_DIR}"/id_*; do
                    [[ -f "$priv" && "$priv" != *.pub ]] && chmod 600 "$priv"
                done
                for pub in "${SSH_DIR}"/*.pub; do
                    [[ -f "$pub" ]] && chmod 644 "$pub"
                done
                [[ -f "${KNOWN_HOSTS_FILE}" ]] && chmod 600 "${KNOWN_HOSTS_FILE}"
                echo -e "\n${GREEN}✓ Права доступа успешно исправлены.${NC}"
                read -rp "Нажмите Enter..."
                ;;
            8)
                backup_config
                read -rp "Нажмите Enter..."
                ;;
            9)
                menu_backups
                ;;
            10)
                clear 2>/dev/null || true
                echo -e "${BOLD}Директивы Include в ${CONFIG_FILE}:${NC}\n"
                grep -iE '^[[:space:]]*Include[[:space:]]+' "${CONFIG_FILE}" || echo "Директивы Include отсутствуют."
                echo ""
                read -rp "Нажмите Enter..."
                ;;
            0|[qQ]) break ;;
            *) echo -e "${RED}Неверный выбор.${NC}"; sleep 1 ;;
        esac
    done
}

# ==============================================================================
# KNOWN_HOSTS (Раздел 8 ТЗ)
# ==============================================================================
menu_known_hosts() {
    while true; do
        clear 2>/dev/null || true
        echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
        echo -e "${BOLD}                 KNOWN_HOSTS                        ${NC}"
        echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
        echo "  1) Просмотр записей"
        echo "  2) Поиск записи по имени или адресу"
        echo "  3) Удалить отпечаток хоста (ssh-keygen -R)"
        echo "  4) Удалить отпечаток хоста с нестандартным портом"
        echo "  5) Очистить весь файл known_hosts"
        echo ""
        echo "  0) Назад"
        echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
        read -rp "Выберите действие [0-5]: " kh_act

        case "${kh_act}" in
            1)
                clear 2>/dev/null || true
                echo -e "${BOLD}Записи ${KNOWN_HOSTS_FILE}:${NC}\n"
                if [[ -s "${KNOWN_HOSTS_FILE}" ]]; then
                    awk '{print NR")", $1, "["$2"]"}' "${KNOWN_HOSTS_FILE}" | head -n 35
                else
                    echo "Файл пуст или отсутствует."
                fi
                echo ""
                read -rp "Нажмите Enter..."
                ;;
            2)
                read -rp "Поисковый запрос: " q_kh
                q_kh="$(echo "${q_kh}" | xargs)"
                if [[ -n "${q_kh}" && -f "${KNOWN_HOSTS_FILE}" ]]; then
                    echo -e "\n${BOLD}Результаты:${NC}"
                    grep -n "${q_kh}" "${KNOWN_HOSTS_FILE}" || echo "Не найдено."
                fi
                read -rp "Нажмите Enter..."
                ;;
            3)
                read -rp "IP или имя хоста для удаления из known_hosts: " rm_host
                rm_host="$(echo "${rm_host}" | xargs)"
                if [[ -n "${rm_host}" ]]; then
                    ssh-keygen -R "${rm_host}" 2>/dev/null || true
                    echo -e "${GREEN}✓ Отпечаток хоста '${rm_host}' удалён.${NC}"
                fi
                read -rp "Нажмите Enter..."
                ;;
            4)
                read -rp "Хост (IP или имя): " rm_h
                read -rp "Порт: " rm_p
                if [[ -n "${rm_h}" && -n "${rm_p}" ]]; then
                    ssh-keygen -R "[${rm_h}]:${rm_p}" 2>/dev/null || true
                    echo -e "${GREEN}✓ Отпечаток '[${rm_h}]:${rm_p}' удалён.${NC}"
                fi
                read -rp "Нажмите Enter..."
                ;;
            5)
                read -rp "Вы действительно хотите очистить known_hosts? [y/N]: " conf_kh
                if [[ "${conf_kh}" =~ ^[Yy]$ ]]; then
                    > "${KNOWN_HOSTS_FILE}"
                    echo -e "${GREEN}✓ Файл known_hosts очищен.${NC}"
                fi
                read -rp "Нажмите Enter..."
                ;;
            0|[qQ]) break ;;
            *) echo -e "${RED}Неверный выбор.${NC}"; sleep 1 ;;
        esac
    done
}

# ==============================================================================
# УДАЛЁННОЕ УПРАВЛЕНИЕ VPS (Раздел 10 ТЗ)
# ==============================================================================
menu_vps_control() {
    local target="$1"
    while true; do
        clear 2>/dev/null || true
        local id u hn p
        id=$(get_id_by_alias "${target}")
        hn=$(ssh -F "${CONFIG_FILE}" -G "${target}" 2>/dev/null | awk '$1=="hostname"{print $2}')
        p=$(ssh -F "${CONFIG_FILE}" -G "${target}" 2>/dev/null | awk '$1=="port"{print $2}')
        u=$(ssh -F "${CONFIG_FILE}" -G "${target}" 2>/dev/null | awk '$1=="user"{print $2}')

        echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
        echo -e "${BOLD}       УПРАВЛЕНИЕ VPS: ${CYAN}${target}${NC} ${DIM}(${u}@${hn}:${p})${NC}"
        echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
        echo "  1) Информация о сервере"
        echo "  2) Мониторинг ресурсов"
        echo "  3) Службы systemd"
        echo "  4) Docker"
        echo "  5) Системные журналы"
        echo "  6) Диски и файловая система"
        echo "  7) Сеть и порты"
        echo "  8) Firewall и Fail2ban"
        echo "  9) Обновления Linux"
        echo " 10) Резервное копирование конфигураций"
        echo " 11) Терминал SSH"
        echo ""
        echo "  0) Назад"
        echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
        read -rp "Выберите действие [0-11]: " vps_act

        case "${vps_act}" in
            1) vps_info "${target}" ;;
            2) vps_monitoring "${target}" ;;
            3) vps_systemd "${target}" ;;
            4) vps_docker "${target}" ;;
            5) vps_logs "${target}" ;;
            6) vps_disks "${target}" ;;
            7) vps_network "${target}" ;;
            8) vps_firewall "${target}" ;;
            9) vps_updates "${target}" ;;
            10) vps_backup_configs "${target}" ;;
            11)
                clear 2>/dev/null || true
                echo -e "${GREEN}Открытие интерактивного сеанса SSH к ${target}...${NC}\n"
                ssh -F "${CONFIG_FILE}" "${target}" || true
                echo -e "\n${DIM}Сессия закрыта. Нажмите Enter...${NC}"
                read -rp ""
                ;;
            0|[qQ]) break ;;
            *) echo -e "${RED}Неверный выбор.${NC}"; sleep 1 ;;
        esac
    done
}

# 10.2 Информация о сервере
vps_info() {
    local target="$1"
    clear 2>/dev/null || true
    echo -e "${BOLD}Информация о сервере ${target}:${NC}\n"
    local cmd='
echo "• Hostname:      $(hostname 2>/dev/null || echo N/A)"
echo "• Дистрибутив:   $(grep -oP "(?<=^PRETTY_NAME=).*" /etc/os-release 2>/dev/null | tr -d "\"" || uname -s)"
echo "• Ядро:          $(uname -r 2>/dev/null || uname -v)"
echo "• Архитектура:   $(uname -m 2>/dev/null || echo N/A)"
echo "• Uptime:        $(uptime -p 2>/dev/null || uptime)"
echo "• Время сервера: $(date "+%Y-%m-%d %H:%M:%S %Z")"
echo "• Процессор:     $(nproc 2>/dev/null || echo 1) cores ($(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo N/A))"
echo "• Память (RAM):  $(free -h 2>/dev/null | awk "/^Mem:/ {print \$3 \" / \" \$2}" || echo N/A)"
echo "• Диск (/):      $(df -h / 2>/dev/null | awk "NR==2 {print \$3 \" / \" \$2 \" (\" \$5 \")\"}" || echo N/A)"
'
    ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}" "bash -s" <<< "${cmd}" 2>/dev/null || echo "Не удалось получить информацию по SSH."
    echo ""
    read -rp "Нажмите Enter..."
}

# 10.3 Мониторинг ресурсов
vps_monitoring() {
    local target="$1"
    clear 2>/dev/null || true
    echo -e "${BOLD}Мониторинг ресурсов ${target}:${NC}\n"
    local cmd='
echo "=== ЗАГРУЗКА (LOAD AVERAGE) ==="
cat /proc/loadavg 2>/dev/null | awk "{print \"1 мин: \" \$1 \" | 5 мин: \" \$2 \" | 15 мин: \" \$3}" || uptime
echo ""
echo "=== ПАМЯТЬ И SWAP ==="
free -h 2>/dev/null || free -m
echo ""
echo "=== ИСПОЛЬЗОВАНИЕ ДИСКОВ ==="
df -h -x tmpfs -x devtmpfs -x overlay 2>/dev/null || df -h
echo ""
echo "=== ТОП-5 ПРОЦЕССОВ ПО CPU ==="
ps aux --sort=-%cpu 2>/dev/null | head -n 6 | awk "{printf \"%-8s %-6s %-5s %-5s %s\n\", \$1, \$2, \$3, \$4, \$11}"
echo ""
echo "=== ТОП-5 ПРОЦЕССОВ ПО ПАМЯТИ ==="
ps aux --sort=-%mem 2>/dev/null | head -n 6 | awk "{printf \"%-8s %-6s %-5s %-5s %s\n\", \$1, \$2, \$3, \$4, \$11}"
'
    ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}" "bash -s" <<< "${cmd}" 2>/dev/null || echo "Ошибка мониторинга."
    echo ""
    read -rp "Нажмите Enter..."
}

# 10.4 systemd
vps_systemd() {
    local target="$1"
    while true; do
        clear 2>/dev/null || true
        echo -e "${BOLD}Управление службами systemd на ${target}:${NC}\n"
        echo "  1) Активные службы (running)"
        echo "  2) Поиск службы по имени и статус"
        echo "  3) Перезапуск службы"
        echo "  4) Остановка службы (с защитой SSH)"
        echo "  5) Запуск службы"
        echo "  6) Журнал службы"
        echo "  0) Назад"
        echo ""
        read -rp "Выберите действие: " s_act
        case "${s_act}" in
            1)
                clear 2>/dev/null || true
                ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}" \
                    "systemctl list-units --type=service --state=running --no-pager --no-legend 2>/dev/null | awk '{print \$1, \"[\"\$3\"]\", \$4}' | head -n 35" || echo "Не удалось получить службы."
                read -rp "Нажмите Enter..." ;;
            2)
                read -rp "Имя службы: " s_n
                [[ -n "$s_n" ]] && ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}" "systemctl status ${s_n} --no-pager -l" || true
                read -rp "Нажмите Enter..." ;;
            3)
                read -rp "Служба для перезапуска: " s_n
                if [[ -n "$s_n" ]]; then
                    [[ "$s_n" == "ssh"* ]] && echo -e "${YELLOW}Предупреждение: перезапуск SSH!${NC}"
                    read -rp "Подтвердите перезапуск ${s_n}? [y/N]: " conf_r
                    [[ "${conf_r}" =~ ^[Yy]$ ]] && ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}" "sudo systemctl restart ${s_n} || systemctl restart ${s_n}" && echo -e "${GREEN}✓ Перезапущено.${NC}"
                fi
                read -rp "Нажмите Enter..." ;;
            4)
                read -rp "Служба для остановки: " s_n
                if [[ -n "$s_n" ]]; then
                    if [[ "$s_n" == "ssh"* || "$s_n" == *"network"* || "$s_n" == "ufw" ]]; then
                        echo -e "${RED}Остановка ${s_n} приведёт к потере доступа к серверу!${NC}"
                        read -rp "Введите 'YES' для подтверждения: " cf_f
                        [[ "${cf_f}" != "YES" ]] && continue
                    fi
                    ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}" "sudo systemctl stop ${s_n} || systemctl stop ${s_n}" && echo -e "${GREEN}✓ Остановлено.${NC}"
                fi
                read -rp "Нажмите Enter..." ;;
            5)
                read -rp "Служба для запуска: " s_n
                [[ -n "$s_n" ]] && ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}" "sudo systemctl start ${s_n} || systemctl start ${s_n}" && echo -e "${GREEN}✓ Запущено.${NC}"
                read -rp "Нажмите Enter..." ;;
            6)
                read -rp "Имя службы: " s_n
                [[ -n "$s_n" ]] && ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}" "journalctl -u ${s_n} -n ${LOG_LINES} --no-pager" || true
                read -rp "Нажмите Enter..." ;;
            0|[qQ]) break ;;
            *) ;;
        esac
    done
}

# 10.5 Docker
vps_docker() {
    local target="$1"
    clear 2>/dev/null || true
    echo -e "${DIM}Проверка Docker на сервере...${NC}"
    if ! ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}" "command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1"; then
        echo -e "\n${YELLOW}Docker не установлен или у текущего пользователя нет прав на docker.sock.${NC}\n"
        read -rp "Нажмите Enter для возврата..."; return
    fi

    while true; do
        clear 2>/dev/null || true
        echo -e "${BOLD}Docker на сервере ${target}:${NC}\n"
        echo "  1) Список всех контейнеров (docker ps -a)"
        echo "  2) Логи контейнера"
        echo "  3) Перезапуск контейнера"
        echo "  4) Остановка контейнера"
        echo "  5) Запуск контейнера"
        echo "  6) Статистика ресурсов (docker stats)"
        echo "  7) Список образов (docker images)"
        echo "  0) Назад"
        echo ""
        read -rp "Выберите действие: " doc_act
        case "${doc_act}" in
            1)
                clear 2>/dev/null || true
                ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}" \
                    "docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}\t{{.Ports}}'" || echo "Ошибка."
                read -rp "Нажмите Enter..." ;;
            2)
                read -rp "Имя контейнера: " c_n
                [[ -n "$c_n" ]] && ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}" "docker logs --tail ${LOG_LINES} ${c_n}" || true
                read -rp "Нажмите Enter..." ;;
            3)
                read -rp "Имя контейнера: " c_n
                [[ -n "$c_n" ]] && ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}" "docker restart ${c_n}" && echo -e "${GREEN}✓ Перезапущен.${NC}"
                read -rp "Нажмите Enter..." ;;
            4)
                read -rp "Имя контейнера: " c_n
                [[ -n "$c_n" ]] && ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}" "docker stop ${c_n}" && echo -e "${GREEN}✓ Остановлен.${NC}"
                read -rp "Нажмите Enter..." ;;
            5)
                read -rp "Имя контейнера: " c_n
                [[ -n "$c_n" ]] && ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}" "docker start ${c_n}" && echo -e "${GREEN}✓ Запущен.${NC}"
                read -rp "Нажмите Enter..." ;;
            6)
                clear 2>/dev/null || true
                ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}" "docker stats --no-stream" || true
                read -rp "Нажмите Enter..." ;;
            7)
                clear 2>/dev/null || true
                ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}" "docker images" || true
                read -rp "Нажмите Enter..." ;;
            0|[qQ]) break ;;
            *) ;;
        esac
    done
}

# 10.6 Системные журналы
vps_logs() {
    local target="$1"
    clear 2>/dev/null || true
    echo -e "${BOLD}Журналы сервера ${target}:${NC}\n"
    echo "  1) Системные ошибки (journalctl -p 3 -xb)"
    echo "  2) Ошибки авторизации SSH"
    echo "  3) Журнал ядра (dmesg)"
    echo "  0) Назад"
    read -rp "> " l_sel
    case "${l_sel}" in
        1)
            clear 2>/dev/null || true
            ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}" "journalctl -p 3 -xb -n ${LOG_LINES} --no-pager" || echo "Записей нет."
            read -rp "Нажмите Enter..." ;;
        2)
            clear 2>/dev/null || true
            ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}" "grep -i 'failed password' /var/log/auth.log 2>/dev/null | tail -n ${LOG_LINES} || journalctl -u ssh -u sshd -n ${LOG_LINES} --no-pager 2>/dev/null | grep -i 'failed' || echo 'Записей нет.'"
            read -rp "Нажмите Enter..." ;;
        3)
            clear 2>/dev/null || true
            ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}" "dmesg 2>/dev/null | tail -n ${LOG_LINES} || echo 'Нет доступа к dmesg.'"
            read -rp "Нажмите Enter..." ;;
        0|[qQ]) return ;;
    esac
}

# 10.7 Диски
vps_disks() {
    local target="$1"
    clear 2>/dev/null || true
    echo -e "${BOLD}Дисковая подсистема ${target}:${NC}\n"
    local cmd='
echo "=== РАЗДЕЛЫ ДИСКОВ (df -h) ==="
df -h -x tmpfs -x devtmpfs 2>/dev/null || df -h
echo ""
echo "=== СВОБОДНЫЕ INODE (df -i) ==="
df -i -x tmpfs -x devtmpfs 2>/dev/null || df -i
echo ""
if command -v lsblk >/dev/null 2>&1; then
    echo "=== БЛОЧНЫЕ УСТРОЙСТВА (lsblk) ==="
    lsblk 2>/dev/null
fi
'
    ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}" "bash -s" <<< "${cmd}" 2>/dev/null || echo "Ошибка."
    read -rp "Нажмите Enter..."
}

# 10.7 Сеть и порты
vps_network() {
    local target="$1"
    clear 2>/dev/null || true
    echo -e "${BOLD}Сеть и порты на ${target}:${NC}\n"
    local cmd='
echo "=== ПРОСЛУШИВАЕМЫЕ ПОРТЫ ==="
if command -v ss >/dev/null 2>&1; then
    ss -tulpn 2>/dev/null | head -n 25
elif command -v netstat >/dev/null 2>&1; then
    netstat -tulpn 2>/dev/null | head -n 25
fi
echo ""
echo "=== ИНТЕРФЕЙСЫ И АДРЕСА ==="
ip -br a 2>/dev/null || ifconfig 2>/dev/null | head -n 15
echo ""
echo "=== ВНЕШНИЙ IP ==="
curl -s --connect-timeout 3 https://api.ipify.org 2>/dev/null || echo "N/A"
'
    ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}" "bash -s" <<< "${cmd}" 2>/dev/null || echo "Ошибка."
    read -rp "Нажмите Enter..."
}

# 10.8 Firewall & Fail2ban
vps_firewall() {
    local target="$1"
    clear 2>/dev/null || true
    echo -e "${BOLD}Firewall и защита на ${target}:${NC}\n"
    local cmd='
echo "=== UFW FIREWALL ==="
sudo ufw status verbose 2>/dev/null || ufw status 2>/dev/null || echo "UFW не установлен или нет прав."
echo ""
echo "=== FAIL2BAN ==="
sudo fail2ban-client status 2>/dev/null || echo "Fail2ban не запущен или не установлен."
'
    ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}" "bash -s" <<< "${cmd}" 2>/dev/null || echo "Ошибка."
    read -rp "Нажмите Enter..."
}

# 10.9 Обновления
vps_updates() {
    local target="$1"
    clear 2>/dev/null || true
    echo -e "${BOLD}Обновления пакетов на ${target}:${NC}\n"
    echo "  1) Проверить наличие обновлений (apt update)"
    echo "  2) Показать список обновляемых пакетов"
    echo "  3) Установить обновления (apt upgrade)"
    echo "  4) Очистить кэш пакетов (apt clean & autoremove)"
    echo "  0) Назад"
    read -rp "> " u_sel
    case "${u_sel}" in
        1)
            ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}" "sudo apt-get update || apt-get update" || true
            read -rp "Нажмите Enter..." ;;
        2)
            ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}" "apt list --upgradable 2>/dev/null | head -n 40" || true
            read -rp "Нажмите Enter..." ;;
        3)
            read -rp "Запустить apt upgrade? [y/N]: " cf
            if [[ "${cf}" =~ ^[Yy]$ ]]; then
                ssh -F "${CONFIG_FILE}" -t "${target}" "sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y" || true
            fi
            read -rp "Нажмите Enter..." ;;
        4)
            ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}" "sudo apt-get autoremove -y && sudo apt-get clean" && echo -e "${GREEN}✓ Очищено.${NC}" || true
            read -rp "Нажмите Enter..." ;;
        0|[qQ]) return ;;
    esac
}

# 10.10 Резервные копии конфигураций на сервере
vps_backup_configs() {
    local target="$1"
    clear 2>/dev/null || true
    echo -e "${BOLD}Резервные копии конфигов на ${target}:${NC}\n"
    echo "  1) Сделать бэкап sshd_config и authorized_keys на сервере"
    echo "  2) Показать список серверных бэкапов (~/.ssh/backups)"
    echo "  0) Назад"
    read -rp "> " bk_sel
    case "${bk_sel}" in
        1)
            local cmd='
mkdir -p ~/.ssh/backups
ts=$(date +%Y%m%d_%H%M%S)
[[ -f ~/.ssh/authorized_keys ]] && cp ~/.ssh/authorized_keys ~/.ssh/backups/authorized_keys.bak_$ts
[[ -f /etc/ssh/sshd_config ]] && sudo cp /etc/ssh/sshd_config ~/.ssh/backups/sshd_config.bak_$ts 2>/dev/null
echo "✓ Копия сохранена в ~/.ssh/backups/*_$ts"
'
            ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}" "bash -s" <<< "${cmd}" 2>/dev/null || echo "Ошибка."
            read -rp "Нажмите Enter..." ;;
        2)
            ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}" "ls -lh ~/.ssh/backups 2>/dev/null || echo 'Папка пуста.'"
            read -rp "Нажмите Enter..." ;;
        0|[qQ]) return ;;
    esac
}

# ==============================================================================
# НАСТРОЙКИ МЕНЕДЖЕРА (Раздел 12 ТЗ)
# ==============================================================================
menu_settings() {
    while true; do
        clear 2>/dev/null || true
        echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
        echo -e "${BOLD}                 НАСТРОЙКИ                          ${NC}"
        echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
        echo "  1) Путь к SSH Config:         ${CONFIG_FILE}"
        echo "  2) Путь к резервным копиям:   ${BACKUP_DIR}"
        echo "  3) SSH-порт по умолчанию:     ${DEF_PORT}"
        echo "  4) Тайм-аут подключения:      ${CONN_TIMEOUT} сек"
        echo "  5) Цветной интерфейс:         ${USE_COLOR}"
        echo "  6) Режим вывода:              ${OUTPUT_MODE}"
        echo "  7) Проверить зависимости (openssh, curl, etc.)"
        echo "  8) Информация о версии"
        echo "  9) Сброс настроек менеджера"
        echo ""
        echo "  0) Назад"
        echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
        read -rp "Выберите пункт [0-9]: " st_sel

        case "${st_sel}" in
            1)
                read -rp "Новый путь к SSH Config [${CONFIG_FILE}]: " val
                [[ -n "$val" ]] && CONFIG_FILE="$val" && save_settings ;;
            2)
                read -rp "Новый путь к резервным копиям [${BACKUP_DIR}]: " val
                [[ -n "$val" ]] && BACKUP_DIR="$val" && mkdir -p "$BACKUP_DIR" && save_settings ;;
            3)
                read -rp "SSH-порт по умолчанию [${DEF_PORT}]: " val
                [[ -n "$val" ]] && DEF_PORT="$val" && save_settings ;;
            4)
                read -rp "Тайм-аут подключения в секундах [${CONN_TIMEOUT}]: " val
                [[ -n "$val" ]] && CONN_TIMEOUT="$val" && save_settings ;;
            5)
                [[ "${USE_COLOR}" == "yes" ]] && USE_COLOR="no" || USE_COLOR="yes"
                save_settings; set_colors ;;
            6)
                [[ "${OUTPUT_MODE}" == "normal" ]] && OUTPUT_MODE="compact" || OUTPUT_MODE="normal"
                save_settings ;;
            7)
                clear 2>/dev/null || true
                echo -e "${BOLD}Проверка необходимых компонентов:${NC}\n"
                for cmd in ssh ssh-keygen scp curl awk grep sed; do
                    if command -v "$cmd" >/dev/null 2>&1; then
                        echo -e "  $cmd: ${GREEN}✓ Установлен${NC}"
                    else
                        echo -e "  $cmd: ${RED}✗ Отсутствует! (Установите через pkg install $cmd)${NC}"
                    fi
                done
                read -rp "Нажмите Enter..." ;;
            8)
                clear 2>/dev/null || true
                echo -e "${BOLD}TERMUX SSH MANAGER${NC}"
                echo "Версия:      ${VERSION}"
                echo "Платформа:   Android / Termux"
                echo "Репозиторий: https://github.com/iurievi4/android"
                read -rp "Нажмите Enter..." ;;
            9)
                echo -e "${YELLOW}Сброс вернёт настройки менеджера к значениям по умолчанию.${NC}"
                echo -e "${DIM}SSH Config, серверы и ключи затронуты НЕ будут.${NC}"
                read -rp "Сбросить настройки? [y/N]: " conf_rst
                if [[ "${conf_rst}" =~ ^[Yy]$ ]]; then
                    rm -f "${SETTINGS_FILE}"
                    load_settings
                    echo -e "${GREEN}✓ Настройки сброшены.${NC}"
                fi
                read -rp "Нажмите Enter..." ;;
            0|[qQ]) break ;;
            *) echo -e "${RED}Неверный выбор.${NC}"; sleep 1 ;;
        esac
    done
}

# ==============================================================================
# ЭКРАН ВЫБОРА СЕРВЕРА ДЛЯ ПОДКЛЮЧЕНИЯ (Пункт 1 Главного меню)
# ==============================================================================
# ==============================================================================
# ЭКРАН ПОДКЛЮЧЕНИЯ И ГЛАВНОЕ МЕНЮ (ТЗ 2 и 3)
# ==============================================================================

# Экран подключения к VPS (ТЗ 2)
menu_connect_server() {
    while true; do
        clear 2>/dev/null || true
        local hosts=()
        while IFS= read -r h; do [[ -n "$h" ]] && hosts+=("$h"); done < <(get_hosts)
        local total=${#hosts[@]}

        echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
        echo -e "${BOLD}              ПОДКЛЮЧЕНИЕ К VPS                     ${NC}"
        echo -e "${BLUE}════════════════════════════════════════════════════${NC}
"

        if [[ $total -eq 0 ]]; then
            echo -e "  ${YELLOW}(В ~/.ssh/config пока нет серверов)${NC}
"
            echo -e "  1. Добавить сервер"
            echo -e "  0. Назад
"
            echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
            read -rp "Выберите действие [0–1]: " no_srv
            case "${no_srv}" in
                1) action_add_server ;;
                0|[qQ]) return ;;
                *) echo -e "${RED}Неверный ввод.${NC}"; sleep 1.2 ;;
            esac
            continue
        fi

        for (( i=0; i<total; i++ )); do
            local h="${hosts[$i]}"
            local flag
            flag=$(get_server_flag "$h")
            local u hn p
            hn=$(ssh -F "${CONFIG_FILE}" -G "$h" 2>/dev/null | awk '$1=="hostname"{print $2}')
            p=$(ssh -F "${CONFIG_FILE}" -G "$h" 2>/dev/null | awk '$1=="port"{print $2}')
            u=$(ssh -F "${CONFIG_FILE}" -G "$h" 2>/dev/null | awk '$1=="user"{print $2}')

            echo -e "  ${BOLD}$((i+1)). ${flag} ${h}${NC}"
            echo -e "     ${DIM}${u}@${hn}:${p}${NC}
"
        done

        echo "  0. Назад"
        echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
        read -rp "Выберите сервер [0–${total}]: " sel

        if [[ "${sel}" == "0" || "${sel}" == "q" || "${sel}" == "Q" ]]; then
            return
        fi

        if [[ "${sel}" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= total )); then
            local target="${hosts[$((sel-1))]}"
            clear 2>/dev/null || true
            echo -e "${GREEN}Подключение к ${target} (ssh ${target})...${NC}
"
            ssh -F "${CONFIG_FILE}" "${target}" || true
            echo ""
            read -rp "Сессия завершена. Нажмите Enter для возврата..." _
        else
            echo -e "${RED}Неверный номер. Введите число от 0 до ${total}.${NC}"
            sleep 1.2
        fi
    done
}

# Главное меню (ТЗ 3)
# ==============================================================================
# МЕНЮ РЕЗЕРВНОГО КОПИРОВАНИЯ И ЗАШИФРОВАННОГО СЕЙФА
# ==============================================================================
print_header() {
    local title="$1"
    clear 2>/dev/null || true
    echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}                 ${title}${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════${NC}\n"
}
print_divider() {
    echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
}
press_enter() {
    local prompt="${1:-Нажмите Enter для возврата...}"
    echo ""
    read -rp "${prompt}" _
}

backup_manager_create_local() {
    print_header "ЛОКАЛЬНЫЙ БЭКАП CONFIG"
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        echo -e "${YELLOW}Файл конфигурации ~/.ssh/config не найден.${NC}"
        press_enter; return
    fi

    mkdir -p "${BACKUP_DIR}"
    chmod 700 "${BACKUP_DIR}" 2>/dev/null || true

    local ts bname bfile mfile
    ts=$(date +"%Y-%m-%d-%H%M%S")
    bname="config-${ts}.bak"
    bfile="${BACKUP_DIR}/${bname}"
    mfile="${BACKUP_DIR}/${bname}.meta"

    cp "${CONFIG_FILE}" "${bfile}"
    chmod 600 "${bfile}"

    local sha size hosts_list host_cnt
    sha=$(sha256sum "${bfile}" 2>/dev/null | awk '{print $1}' || echo "no-sha256")
    size=$(wc -c < "${bfile}" 2>/dev/null || echo "0")
    hosts_list=$(get_hosts | tr '\n' ',' | sed 's/,$//')
    host_cnt=$(get_hosts | wc -l)

    cat << META > "${mfile}"
CREATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
BACKUP_FILE=${bname}
SOURCE_FILE=${CONFIG_FILE}
FILE_SIZE_BYTES=${size}
SHA256=${sha}
HOST_COUNT=${host_cnt}
HOST_ALIASES=${hosts_list}
MANAGER_VERSION=vps-toolkit-1.0
META
    chmod 600 "${mfile}"

    echo -e "${GREEN}✓ Резервная копия создана:${NC}"
    echo -e "  Файл:   ${BOLD}${bfile}${NC}"
    echo -e "  Размер: ${size} байт"
    echo -e "  SHA256: ${DIM}${sha}${NC}"
    echo -e "  Хостов: ${host_cnt} (${hosts_list:-нет})"
    press_enter
}

# 2. Список локальных копий
backup_manager_list_local() {
    print_header "СПИСОК ЛОКАЛЬНЫХ БЭКАПОВ CONFIG"
    mkdir -p "${BACKUP_DIR}"
    local b_files=()
    while IFS= read -r f; do [[ -n "$f" ]] && b_files+=("$f"); done < <(find "${BACKUP_DIR}" -maxdepth 1 \( -name "config-*.bak" -o -name "config.backup-*" \) ! -name "*.meta" 2>/dev/null | sort -r)

    if [[ ${#b_files[@]} -eq 0 ]]; then
        echo -e "${YELLOW}Локальных копий пока нет.${NC}"
        press_enter; return
    fi

    echo -e "Найдено копий: ${#b_files[@]}\n"
    for (( i=0; i<${#b_files[@]}; i++ )); do
        local bf="${b_files[$i]}"
        local mf="${bf}.meta"
        local bname=$(basename "${bf}")
        local dt="—" sz="—" hc="—"
        if [[ -f "${mf}" ]]; then
            dt=$(grep "^CREATED_AT=" "${mf}" 2>/dev/null | cut -d= -f2 || echo "—")
            sz=$(grep "^FILE_SIZE_BYTES=" "${mf}" 2>/dev/null | cut -d= -f2 || echo "—")
            hc=$(grep "^HOST_COUNT=" "${mf}" 2>/dev/null | cut -d= -f2 || echo "—")
        fi
        printf "  %2d. %-32s [%s байт | хостов: %s]\n" "$((i+1))" "${bname}" "${sz}" "${hc}"
    done
    press_enter
}

# 3. Восстановление локального config
backup_manager_restore_local() {
    print_header "ВОССТАНОВЛЕНИЕ CONFIG ИЗ ЛОКАЛЬНОЙ КОПИИ"
    local b_files=()
    while IFS= read -r f; do [[ -n "$f" ]] && b_files+=("$f"); done < <(find "${BACKUP_DIR}" -maxdepth 1 \( -name "config-*.bak" -o -name "config.backup-*" \) ! -name "*.meta" 2>/dev/null | sort -r)

    if [[ ${#b_files[@]} -eq 0 ]]; then
        echo -e "${YELLOW}Нет доступных копий для восстановления.${NC}"
        press_enter; return
    fi

    for (( i=0; i<${#b_files[@]}; i++ )); do
        printf "  %d. %s\n" "$((i+1))" "$(basename "${b_files[$i]}")"
    done
    echo ""
    echo "  0. Отмена"
    print_divider
    read -rp "Выберите номер: " b_idx

    [[ "${b_idx}" == "0" || -z "${b_idx}" ]] && return
    if [[ ! "${b_idx}" =~ ^[0-9]+$ ]] || (( b_idx < 1 || b_idx > ${#b_files[@]} )); then
        echo -e "${RED}Неверный номер.${NC}"; sleep 1; return
    fi

    local chosen="${b_files[$((b_idx-1))]}"
    read -rp "Заменить текущий ~/.ssh/config копией $(basename "${chosen}")? (y/N): " confirm_res
    if [[ "${confirm_res}" =~ ^[Yy]$ ]]; then
        cp "${CONFIG_FILE}" "${CONFIG_FILE}.pre-restore-$(date +%s)" 2>/dev/null || true
        cp -f "${chosen}" "${CONFIG_FILE}"
        chmod 600 "${CONFIG_FILE}"
        echo -e "${GREEN}✓ Конфигурация успешно восстановлена.${NC}"
    fi
    press_enter
}

# Определение каталога Загрузок Android
get_android_downloads_path() {
    if [[ -d "${HOME}/storage/shared/Download" ]]; then
        echo "${HOME}/storage/shared/Download"
    elif [[ -d "/storage/emulated/0/Download" && -w "/storage/emulated/0/Download" ]]; then
        echo "/storage/emulated/0/Download"
    elif [[ -d "/sdcard/Download" && -w "/sdcard/Download" ]]; then
        echo "/sdcard/Download"
    else
        echo "${HOME}/downloads"
    fi
}

# 4. ЗАШИФРОВАННЫЙ ЭКСПОРТ (Config + Ключи) в память телефона
backup_vault_export() {
    print_header "ЭКСПОРТ ЗАШИФРОВАННОГО АРХИВА" "Конфигурация серверов + Приватные ключи (AES-256)"

    # Собираем список файлов в ~/.ssh
    local files_to_pack=()
    for f in "${SSH_DIR}"/*; do
        [[ -f "$f" ]] || continue
        local b=$(basename "$f")
        case "$b" in
            *.backup*|*.bak*|*.tmp|*.old) continue ;;
            config|known_hosts|id_*|*.key|*.pub|*.conf|*.list)
                files_to_pack+=("$b")
                ;;
        esac
    done

    if [[ ${#files_to_pack[@]} -eq 0 ]]; then
        echo -e "${YELLOW}В ~/.ssh/ не найдено файлов для архивации.${NC}"
        press_enter; return
    fi

    echo -e "Файлы, включаемые в защищённый сейф:"
    for f in "${files_to_pack[@]}"; do
        echo -e "  • ${BOLD}${f}${NC}"
    done
    echo ""

    # Запрос пароля со скрытым вводом
    echo -e "${CYAN}Введите пароль для шифрования архива (AES-256):${NC}"
    read -s -rp "Пароль: " pass1
    echo ""
    read -s -rp "Подтвердите пароль: " pass2
    echo ""

    if [[ -z "${pass1}" ]]; then
        echo -e "${RED}Пароль не может быть пустым. Отмена.${NC}"
        press_enter; return 1
    fi

    if [[ "${pass1}" != "${pass2}" ]]; then
        echo -e "${RED}Пароли не совпадают! Экспорт отменён.${NC}"
        press_enter; return 1
    fi

    # Проверка доступа к памяти Android
    local dest_dir
    dest_dir=$(get_android_downloads_path)
    if [[ "${dest_dir}" == *"/downloads" && ! -d "${HOME}/storage/shared" ]]; then
        if command -v termux-setup-storage >/dev/null 2>&1; then
            echo -e "${YELLOW}Запрос доступа к памяти телефона Android...${NC}"
            termux-setup-storage 2>/dev/null || true
            sleep 1
            dest_dir=$(get_android_downloads_path)
        fi
    fi

    mkdir -p "${dest_dir}"
    local out_name="vps-vault-$(date +%Y%m%d-%H%M%S).enc"
    local out_file="${dest_dir}/${out_name}"

    echo -e "
${CYAN}Шифрование данных (AES-256-CBC, PBKDF2)...${NC}"
    if tar -czf - -C "${SSH_DIR}" "${files_to_pack[@]}" | openssl enc -aes-256-cbc -salt -pbkdf2 -iter 100000 -pass pass:"${pass1}" -out "${out_file}"; then
        echo -e "
${GREEN}════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}✓ СЕЙФ УСПЕШНО СОЗДАН И ВЫГРУЖЕН В ПАМЯТЬ ТЕЛЕФОНА!${NC}"
        echo -e "${GREEN}════════════════════════════════════════════════════${NC}"
        echo -e "  Файл:   ${BOLD}${out_file}${NC}"
        echo -e "  Размер: $(wc -c < "${out_file}") байт"
        echo -e "  Шифр:   AES-256-CBC (100 000 итераций PBKDF2)"
        echo -e "
${YELLOW}Как использовать:${NC}"
        echo "1. Файл сохранён в папке «Загрузки» телефона."
        echo "2. Вы можете сохранить его на Google Диск или отправить в Избранное Telegram."
        echo "3. В новом Termux выберите «Импорт и расшифровка», введите этот пароль — и все серверы с ключами сразу восстановятся."
    else
        echo -e "
${RED}✗ Ошибка при создании архива.${NC}"
    fi
    press_enter
}

# 5. ИМПОРТ И РАСШИФРОВКА АРХИВА в новый Termux
backup_vault_import() {
    print_header "ИМПОРТ И РАСШИФРОВКА СЕЙФА" "Восстановление серверов и ключей в Termux"

    # Поиск доступных .enc файлов в памяти
    local search_dirs=(
        "${HOME}/storage/shared/Download"
        "/storage/emulated/0/Download"
        "/sdcard/Download"
        "${HOME}/downloads"
        "${HOME}"
    )
    local found_enc=()
    for d in "${search_dirs[@]}"; do
        [[ -d "$d" ]] || continue
        while IFS= read -r f; do
            [[ -n "$f" && -f "$f" ]] && found_enc+=("$f")
        done < <(find "$d" -maxdepth 2 -name "*.enc" 2>/dev/null | sort -u)
    done

    local chosen_enc=""
    if [[ ${#found_enc[@]} -gt 0 ]]; then
        echo -e "Найдены зашифрованные архивы в памяти телефона:
"
        for (( i=0; i<${#found_enc[@]}; i++ )); do
            printf "  %d. %s
" "$((i+1))" "${found_enc[$i]}"
        done
        echo ""
        echo "  M. Указать путь к файлу вручную"
        echo "  0. Отмена"
        print_divider
        read -rp "Выберите файл [1-${#found_enc[@]}]: " f_choice

        case "${f_choice}" in
            0|[qQ]) return ;;
            [Mm])
                read -rp "Полный путь к файлу .enc: " manual_p
                [[ -f "${manual_p}" ]] && chosen_enc="${manual_p}"
                ;;
            *)
                if [[ "${f_choice}" =~ ^[0-9]+$ ]] && (( f_choice >= 1 && f_choice <= ${#found_enc[@]} )); then
                    chosen_enc="${found_enc[$((f_choice-1))]}"
                fi
                ;;
        esac
    else
        echo -e "${YELLOW}Архивы *.enc в стандартных папках не обнаружены.${NC}"
        read -rp "Введите путь к .enc файлу вручную (или 0 для отмены): " manual_p
        [[ "${manual_p}" == "0" || -z "${manual_p}" ]] && return
        if [[ -f "${manual_p}" ]]; then
            chosen_enc="${manual_p}"
        else
            echo -e "${RED}Файл '${manual_p}' не найден.${NC}"
            press_enter; return
        fi
    fi

    if [[ -z "${chosen_enc}" ]]; then
        echo -e "${RED}Файл не выбран.${NC}"; press_enter; return
    fi

    echo -e "
Выбран файл: ${BOLD}${chosen_enc}${NC}"
    read -s -rp "Введите пароль для расшифровки: " pass_dec
    echo ""

    # Пробуем расшифровать во временную папку для проверки пароля
    local tmp_dir
    tmp_dir=$(mktemp -d 2>/dev/null || mktemp -d -t 'vps-vault-XXXXXX')
    echo -e "${CYAN}Проверка пароля и расшифровка...${NC}"

    if ! openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 -pass pass:"${pass_dec}" -in "${chosen_enc}" 2>/dev/null | tar -xzf - -C "${tmp_dir}" 2>/dev/null; then
        echo -e "
${RED}✗ Ошибка: неверный пароль или архив повреждён!${NC}"
        rm -rf "${tmp_dir}"
        press_enter; return 1
    fi

    echo -e "${GREEN}✓ Пароль верный! Извлечены файлы:${NC}"
    for f in "${tmp_dir}"/*; do
        echo -e "  • $(basename "$f")"
    done
    echo ""

    read -rp "Установить эти серверы и ключи в текущий Termux (~/.ssh)? (y/N): " conf_inst
    if [[ ! "${conf_inst}" =~ ^[Yy]$ ]]; then
        echo "Отмена."
        rm -rf "${tmp_dir}"
        press_enter; return
    fi

    # Создаём резервную копию текущего ~/.ssh
    if [[ -d "${SSH_DIR}" ]]; then
        mkdir -p "${BACKUP_DIR}"
        tar -czf "${BACKUP_DIR}/pre-import-$(date +%s).tar.gz" -C "${SSH_DIR}" . 2>/dev/null || true
    fi

    # Копируем извлеченные файлы
    mkdir -p "${SSH_DIR}"
    cp -rf "${tmp_dir}"/* "${SSH_DIR}/"
    rm -rf "${tmp_dir}"

    # Выставляем строгие права доступа OpenSSH
    chmod 700 "${SSH_DIR}"
    chmod 600 "${SSH_DIR}/config" 2>/dev/null || true
    chmod 600 "${SSH_DIR}/known_hosts" 2>/dev/null || true
    for priv in "${SSH_DIR}"/id_* "${SSH_DIR}"/*.key; do
        [[ -f "$priv" && "$priv" != *.pub ]] && chmod 600 "$priv"
    done
    for pub in "${SSH_DIR}"/*.pub; do
        [[ -f "$pub" ]] && chmod 644 "$pub"
    done
    for conf in "${SSH_DIR}"/*.conf "${SSH_DIR}"/*.list; do
        [[ -f "$conf" ]] && chmod 600 "$conf"
    done

    echo -e "
${GREEN}════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}✓ ВСЕ СЕРВЕРЫ И КЛЮЧИ УСПЕШНО УСТАНОВЛЕНЫ В TERMUX!${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════${NC}"
    echo "• Настройки хостов (~/.ssh/config): восстановлены (права 600)"
    echo "• Приватные ключи: восстановлены (права 600)"
    echo "• Публичные ключи: восстановлены (права 644)"
    echo "• Все подключения сразу готовы к работе через меню."
    press_enter
}

menu_backups() {
    while true; do
        clear 2>/dev/null || true
        echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
        echo -e "${BOLD}                 BACKUP MANAGER                     ${NC}"
        echo -e "${DIM}      Резервные копии и защищённый сейф ключей      ${NC}"
        echo -e "${BLUE}════════════════════════════════════════════════════${NC}\n"

        echo "  1. Быстрый локальный бэкап config (~/.ssh/backups/)"
        echo "  2. Список локальных бэкапов config"
        echo "  3. Восстановить config из локальной копии"
        echo -e "  ${BLUE}──────────────────────────────────────────────────${NC}"
        echo -e "  ${GREEN}4. 🔒 Экспорт ЗАШИФРОВАННОГО архива (Config + Ключи) в память телефона${NC}"
        echo -e "  ${CYAN}5. 🔓 Импорт и расшифровка архива из памяти телефона в новый Termux${NC}"
        echo -e "  ${BLUE}──────────────────────────────────────────────────${NC}"
        echo "  6. Очистить старые локальные бэкапы config"
        echo ""
        echo "  0. Назад в главное меню"
        echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
        read -rp "Выберите действие [0–6]: " choice

        case "${choice}" in
            1) backup_manager_create_local ;;
            2) backup_manager_list_local ;;
            3) backup_manager_restore_local ;;
            4) backup_vault_export ;;
            5) backup_vault_import ;;
            6)
                print_header "РОТАЦИЯ ЛОКАЛЬНЫХ БЭКАПОВ"
                find "${BACKUP_DIR}" \( -name "config-*.bak" -o -name "config.backup-*" \) -mtime +14 -delete 2>/dev/null || true
                echo -e "${GREEN}✓ Ротация выполнена.${NC}"
                press_enter
                ;;
            0|[qQ]) return ;;
            *) echo -e "${RED}Неверный ввод.${NC}"; sleep 1 ;;
        esac
    done
}

main_menu() {
    init_env

    while true; do
        clear 2>/dev/null || true
        local hosts=()
        while IFS= read -r h; do [[ -n "$h" ]] && hosts+=("$h"); done < <(get_hosts)
        local total=${#hosts[@]}

        echo -e "${CYAN}╔═══════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${NC}  ${BOLD} ____ ____  _   _   __  __                    ${NC}${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${BOLD}/ ___/ ___|| | | | |  \/  | __ _ _ __         ${NC}${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${BOLD}\___ \___ \| |_| | | |\/| |/ _\` | '_ \        ${NC}${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${BOLD} ___) |__) |  _  | | |  | | (_| | | | |       ${NC}${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${BOLD}|____/____/|_| |_| |_|  |_|\__,_|_| |_|       ${NC}${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}            ${GREEN}${BOLD}SSH MANAGER v2.3${NC}                    ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}       ${DIM}VPS Control Center for Termux${NC}            ${CYAN}║${NC}"
        echo -e "${CYAN}╚═══════════════════════════════════════════════╝${NC}"
        echo -e "  Подключено серверов: ${GREEN}${BOLD}${total}${NC}\n"

        echo -e "  ${GREEN}1. Подключиться к серверу${NC}"
        echo -e "  ${GREEN}2. Добавить сервер${NC}"
        echo -e "  ${CYAN}3. Управление серверами${NC}"
        echo -e "  ${YELLOW}4. Проверить подключения${NC}"
        echo -e "  ${MAGENTA}5. SSH-ключи${NC}"
        echo -e "  ${BLUE}6. SSH Config${NC}"
        echo -e "  ${YELLOW}7. Резервные копии${NC}"
        echo -e "  ${DIM}8. Настройки${NC}"
        echo ""
        echo -e "  ${RED}0. Выход${NC}"
        echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
        read -rp "Выберите действие [0–8]: " choice

        case "${choice}" in
            1) menu_connect_server ;;
            2) action_add_server ;;
            3) menu_server_management ;;
            4) action_mass_check ;;
            5) menu_ssh_keys ;;
            6) menu_ssh_config ;;
            7) menu_backups ;;
            8) menu_settings ;;
            0|[qQ])
                clear 2>/dev/null || true
                exit 0
                ;;
            *)
                echo -e "${RED}Неверный выбор: "${choice}". Введите цифру [0–8].${NC}"
                sleep 1.2
                ;;
        esac
    done
}

main_menu "$@"
