#!/usr/bin/env bash
# ==============================================================================
# Android VPS Toolkit — Общая библиотека функций (lib/common.sh)
# Чистый Bash • Совместимо с Android/Termux без root • Единый источник: ~/.ssh/config
# ==============================================================================

set -uo pipefail

TOOLKIT_VERSION="1.0.0"
SSH_DIR="${HOME}/.ssh"
CONFIG_FILE="${SSH_DIR}/config"
KNOWN_HOSTS_FILE="${SSH_DIR}/known_hosts"
SETTINGS_FILE="${SSH_DIR}/vps-toolkit.conf"
BACKUP_DIR="${SSH_DIR}/backups"

# Настройки по умолчанию
CONN_TIMEOUT="4"
USE_COLOR="yes"
LOG_LINES="30"

# Загрузка пользовательских настроек если есть
if [[ -f "${SETTINGS_FILE}" ]]; then
    # shellcheck source=/dev/null
    source "${SETTINGS_FILE}" 2>/dev/null || true
fi

# Настройка цветов
if [[ "${USE_COLOR}" == "yes" && -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    MAGENTA='\033[0;35m'
    BOLD='\033[1m'
    DIM='\033[2m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    MAGENTA=''
    BOLD=''
    DIM=''
    NC=''
fi

# Инициализация окружения
init_common_env() {
    mkdir -p "${SSH_DIR}" "${BACKUP_DIR}"
    chmod 700 "${SSH_DIR}" 2>/dev/null || true
    chmod 700 "${BACKUP_DIR}" 2>/dev/null || true
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        touch "${CONFIG_FILE}"
        chmod 600 "${CONFIG_FILE}" 2>/dev/null || true
    fi
}

# Красивый заголовок
print_header() {
    local title="$1"
    local subtitle="${2:-}"
    clear 2>/dev/null || true
    echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
    printf "${BOLD}%*s${NC}\n" $(( (52 + ${#title}) / 2 )) "${title}"
    if [[ -n "${subtitle}" ]]; then
        printf "${DIM}%*s${NC}\n" $(( (52 + ${#subtitle}) / 2 )) "${subtitle}"
    fi
    echo -e "${BLUE}════════════════════════════════════════════════════${NC}\n"
}

# Разделитель
print_divider() {
    echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
}

# Ожидание нажатия Enter
press_enter() {
    local prompt="${1:-Нажмите Enter для продолжения...}"
    echo ""
    read -rp "${prompt}" _
}

# Получение списка хостов из ~/.ssh/config (исключая wildcard *)
get_hosts() {
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        return 0
    fi
    awk '
        $1 ~ /^[Hh][Oo][Ss][Tt]$/ {
            for (i=2; i<=NF; i++) {
                if ($i != "*" && $i !~ /[*?]/) print $i
            }
        }
    ' "${CONFIG_FILE}" | sort -u
}

# Получение флага страны по алиасу сервера
get_server_flag() {
    local a
    a=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    case "$a" in
        fi|fi-*|*-fi|fi_*|*_fi|*finland*) echo "🇫🇮" ;;
        lv|lv-*|*-lv|lv_*|*_lv|*latvia*)  echo "🇱🇻" ;;
        pa|pa-*|*-pa|pa_*|*_pa|*panama*)  echo "🇵🇦" ;;
        tr|tr-*|*-tr|tr_*|*_tr|*turkey*)  echo "🇹🇷" ;;
        ru|ru-*|*-ru|ru_*|*_ru|*russia*)  echo "🇷🇺" ;;
        de|de-*|*-de|de_*|*_de|*germany*) echo "🇩🇪" ;;
        us|us-*|*-us|us_*|*_us|*usa*)     echo "🇺🇸" ;;
        nl|nl-*|*-nl|nl_*|*_nl|*netherlands*|*holland*) echo "🇳🇱" ;;
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

# Получение параметров хоста через ssh -G
get_host_param() {
    local host="$1"
    local param="$2"
    ssh -F "${CONFIG_FILE}" -G "${host}" 2>/dev/null | awk -v p="${param}" '$1==p {print $2; exit}'
}

# Выполнение команды на удалённом сервере
ssh_exec() {
    local host="$1"
    local cmd="$2"
    ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${host}" "${cmd}"
}

# Быстрая проверка доступности сервера
check_server_quick() {
    local target="$1"
    local hn port
    hn=$(get_host_param "${target}" "hostname")
    port=$(get_host_param "${target}" "port")
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

# Диалог выбора сервера только цифрами
prompt_select_server() {
    local title="${1:-Выбор сервера}"
    local hosts=()
    while IFS= read -r h; do [[ -n "$h" ]] && hosts+=("$h"); done < <(get_hosts)
    local total=${#hosts[@]}

    if [[ $total -eq 0 ]]; then
        echo -e "${YELLOW}Список серверов пуст (в ~/.ssh/config нет хостов).${NC}" >&2
        read -rp "Нажмите Enter..." >&2
        return 1
    fi

    while true; do
        clear 2>/dev/null || true
        print_header "${title}" "Выберите сервер для операции" >&2
        for (( i=0; i<total; i++ )); do
            local h="${hosts[$i]}"
            local flag
            flag=$(get_server_flag "$h")
            local u hn p
            hn=$(get_host_param "$h" "hostname")
            p=$(get_host_param "$h" "port")
            u=$(get_host_param "$h" "user")
            printf "  ${BOLD}%d.${NC} %s %-12s ${DIM}%s@%s:%s${NC}\n" "$((i+1))" "${flag}" "${h}" "${u}" "${hn}" "${p}" >&2
        done
        echo "" >&2
        echo "  0. Назад" >&2
        print_divider >&2
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
