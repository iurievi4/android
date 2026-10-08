#!/usr/bin/env bash
# ==============================================================================
# Termux SSH Manager v2.0
# Быстрый и надёжный менеджер SSH для Termux на Android
# Единственный источник истины: ~/.ssh/config (по умолчанию пуст)
# ==============================================================================

set -euo pipefail

SSH_DIR="${HOME}/.ssh"
CONFIG_FILE="${SSH_DIR}/config"
DEFAULT_KEY="${SSH_DIR}/id_ed25519"
MAX_BACKUPS=10

# Цветовая палитра для терминала
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Определение эмодзи флага по коду страны в имени хоста (если применимо)
get_flag() {
    local code
    code="$(echo "$1" | tr '[:upper:]' '[:lower:]')"
    case "${code}" in
        de|germany|ger)      echo "🇩🇪" ;;
        nl|netherlands|ned)  echo "🇳🇱" ;;
        us|usa|unitedstates) echo "🇺🇸" ;;
        gb|uk|britain)       echo "🇬🇧" ;;
        fr|france|fra)       echo "🇫🇷" ;;
        es|spain|esp)        echo "🇪🇸" ;;
        it|italy|ita)        echo "🇮🇹" ;;
        se|sweden|swe)       echo "🇸🇪" ;;
        no|norway|nor)       echo "🇳🇴" ;;
        pl|poland|pol)       echo "🇵🇱" ;;
        ua|ukraine|ukr)      echo "🇺🇦" ;;
        kz|kazakhstan|kaz)   echo "🇰🇿" ;;
        ae|dubai|uae)        echo "🇦🇪" ;;
        sg|singapore|sin)    echo "🇸🇬" ;;
        jp|japan|jpn)        echo "🇯🇵" ;;
        hk|hongkong)         echo "🇭🇰" ;;
        ch|switzerland)      echo "🇨🇭" ;;
        at|austria)          echo "🇦🇹" ;;
        ca|canada)           echo "🇨🇦" ;;
        tr|turkey|tur)       echo "🇹🇷" ;;
        fi|finland|fin)      echo "🇫🇮" ;;
        lv|latvia|lat)       echo "🇱🇻" ;;
        *)                   echo "🌐" ;;
    esac
}

# Инициализация и проверка прав доступа
init_env() {
    if [[ ! -d "${SSH_DIR}" ]]; then
        mkdir -p "${SSH_DIR}"
        chmod 700 "${SSH_DIR}"
    fi
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        touch "${CONFIG_FILE}"
        chmod 600 "${CONFIG_FILE}"
    fi
}

# Резервное копирование с ротацией (хранить до MAX_BACKUPS)
backup_config() {
    if [[ -s "${CONFIG_FILE}" ]]; then
        local timestamp
        timestamp="$(date +%Y-%m-%d-%H%M%S)"
        local bak="${CONFIG_FILE}.backup-${timestamp}"
        cp "${CONFIG_FILE}" "${bak}"
        echo -e "${YELLOW}Резервная копия создана: ${bak}${NC}"

        # Удаление старых бэкапов свыше лимита
        local old_backups=()
        while IFS= read -r f; do
            [[ -n "${f}" ]] && old_backups+=("${f}")
        done < <(ls -t "${CONFIG_FILE}".backup-* 2>/dev/null || true)

        if (( ${#old_backups[@]} > MAX_BACKUPS )); then
            for (( i=MAX_BACKUPS; i<${#old_backups[@]}; i++ )); do
                rm -f "${old_backups[$i]}"
            done
        fi
    fi
}

# Получение списка хостов из ~/.ssh/config
get_hosts() {
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        return
    fi
    grep -iE '^[[:space:]]*Host[[:space:]]+' "${CONFIG_FILE}" \
        | awk '{for(i=2;i<=NF;i++) if($i !~ /[*?]/) print $i}' \
        | sort -u
}

# Удаление хоста из ~/.ssh/config
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

# Поиск локальных ключей
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
# 1. ДОБАВЛЕНИЕ СЕРВЕРА
# ==============================================================================
action_add_host() {
    clear
    echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}               ДОБАВЛЕНИЕ СЕРВЕРА                   ${NC}"
    echo -e "${BLUE}────────────────────────────────────────────────────${NC}"

    read -rp "Имя подключения (например, vps1, server, dev): " host_alias
    host_alias="$(echo "${host_alias}" | xargs)"

    if [[ -z "${host_alias}" ]]; then
        echo -e "${RED}Имя не может быть пустым.${NC}"
        read -rp "Нажмите Enter..."; return
    fi

    if get_hosts | grep -qw "^${host_alias}$"; then
        echo -e "${RED}Хост с именем '${host_alias}' уже существует.${NC}"
        read -rp "Нажмите Enter..."; return
    fi

    read -rp "Hostname / IP: " host_name
    host_name="$(echo "${host_name}" | xargs)"
    if [[ -z "${host_name}" ]]; then
        echo -e "${RED}Hostname/IP не может быть пустым.${NC}"
        read -rp "Нажмите Enter..."; return
    fi

    read -rp "Пользователь [root]: " user_name
    user_name="$(echo "${user_name}" | xargs)"
    user_name="${user_name:-root}"

    read -rp "SSH Port [22]: " port
    port="$(echo "${port}" | xargs)"
    port="${port:-22}"

    echo -e "\nАвторизация:"
    echo "  1) SSH-ключ по умолчанию (${DEFAULT_KEY})"
    echo "  2) Вход по паролю (без использования ключа)"
    echo "  3) Выбрать существующий ключ на телефоне"
    read -rp "> " auth_choice
    auth_choice="${auth_choice:-1}"

    local identity_line=""
    local auth_lines=""

    case "${auth_choice}" in
        1)
            identity_line="    IdentityFile ${DEFAULT_KEY}"
            if [[ ! -f "${DEFAULT_KEY}" ]]; then
                echo -e "${YELLOW}Предупреждение: ключ ${DEFAULT_KEY} пока не создан.${NC}"
            fi
            ;;
        2)
            auth_lines=$'    PubkeyAuthentication no\n    PreferredAuthentications password,keyboard-interactive'
            ;;
        3)
            local keys=()
            while IFS= read -r k; do
                [[ -n "${k}" ]] && keys+=("${k}")
            done < <(get_local_keys)

            if [[ ${#keys[@]} -eq 0 ]]; then
                echo -e "${YELLOW}Ключей не найдено. Будет использован: ${DEFAULT_KEY}${NC}"
                identity_line="    IdentityFile ${DEFAULT_KEY}"
            else
                echo -e "\nВыберите ключ:"
                for i in "${!keys[@]}"; do
                    printf "  %d) %s\n" "$((i+1))" "$(basename "${keys[$i]}")"
                done
                read -rp "Номер ключа: " k_idx
                if [[ "${k_idx}" =~ ^[0-9]+$ ]] && (( k_idx >= 1 && k_idx <= ${#keys[@]} )); then
                    identity_line="    IdentityFile ${keys[$((k_idx-1))]}"
                else
                    identity_line="    IdentityFile ${DEFAULT_KEY}"
                fi
            fi
            ;;
        *)
            echo -e "${RED}Неверный выбор.${NC}"
            read -rp "Нажмите Enter..."; return
            ;;
    esac

    backup_config

    {
        echo ""
        echo "Host ${host_alias}"
        echo "    HostName ${host_name}"
        echo "    User ${user_name}"
        echo "    Port ${port}"
        [[ -n "${identity_line}" ]] && echo "${identity_line}"
        [[ -n "${auth_lines}" ]] && echo "${auth_lines}"
    } >> "${CONFIG_FILE}"

    chmod 600 "${CONFIG_FILE}"
    echo -e "\n${GREEN}✓ Сервер '${host_alias}' добавлен в ~/.ssh/config${NC}"

    read -rp "Проверить подключение сейчас? [Y/n]: " check_now
    check_now="${check_now:-y}"
    if [[ "${check_now}" =~ ^[Yy]$ ]]; then
        echo -e "${CYAN}Тестирование подключения к ${host_alias}...${NC}"
        if ssh -o ConnectTimeout=5 -o BatchMode=yes "${host_alias}" 'exit' 2>/dev/null; then
            echo -e "${GREEN}✓ Соединение успешно установлено!${NC}"
        else
            echo -e "${YELLOW}[!] Порт отвечает или требуется ввод пароля.${NC}"
        fi
        read -rp "Нажмите Enter..."
    fi
}

# ==============================================================================
# 2. РЕДАКТИРОВАНИЕ СЕРВЕРА
# ==============================================================================
action_edit_host() {
    clear
    echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}               ИЗМЕНИТЬ СЕРВЕР                      ${NC}"
    echo -e "${BLUE}────────────────────────────────────────────────────${NC}"

    local hosts=()
    while IFS= read -r h; do
        [[ -n "${h}" ]] && hosts+=("${h}")
    done < <(get_hosts)

    if [[ ${#hosts[@]} -eq 0 ]]; then
        echo -e "${YELLOW}Список серверов пуст.${NC}"
        read -rp "Нажмите Enter..."; return
    fi

    echo "Выберите сервер для редактирования:"
    for i in "${!hosts[@]}"; do
        printf "  %d) %s\n" "$((i+1))" "${hosts[$i]}"
    done
    read -rp "> " sel_idx

    if ! ([[ "${sel_idx}" =~ ^[0-9]+$ ]] && (( sel_idx >= 1 && sel_idx <= ${#hosts[@]} ))); then
        echo -e "${RED}Неверный номер.${NC}"
        read -rp "Нажмите Enter..."; return
    fi

    local target="${hosts[$((sel_idx-1))]}"
    local cur_hn cur_u cur_p cur_key cur_auth_type="key"

    cur_hn=$(ssh -G "${target}" 2>/dev/null | awk '$1=="hostname"{print $2}')
    cur_u=$(ssh -G "${target}" 2>/dev/null | awk '$1=="user"{print $2}')
    cur_p=$(ssh -G "${target}" 2>/dev/null | awk '$1=="port"{print $2}')
    cur_key=$(ssh -G "${target}" 2>/dev/null | awk '$1=="identityfile"{print $2}')
    
    local pubkey_flag
    pubkey_flag=$(ssh -G "${target}" 2>/dev/null | awk '$1=="pubkeyauthentication"{print $2}')
    if [[ "${pubkey_flag}" == "no" ]]; then
        cur_auth_type="password"
    fi

    local new_alias="${target}"
    local new_hn="${cur_hn}"
    local new_u="${cur_u}"
    local new_p="${cur_p}"
    local new_key="${cur_key}"
    local new_auth="${cur_auth_type}"

    while true; do
        clear
        echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
        echo -e "${BOLD}       Редактирование: ${CYAN}${target}${NC}                     "
        echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
        echo "  1) Имя:        ${new_alias}"
        echo "  2) Hostname:   ${new_hn}"
        echo "  3) User:       ${new_u}"
        echo "  4) Port:       ${new_p}"
        if [[ "${new_auth}" == "password" ]]; then
            echo "  5) Auth:       Пароль (без ключа)"
        else
            echo "  5) Auth/Key:   SSH-ключ (${new_key})"
        fi
        echo "  6) Проверить подключение"
        echo ""
        echo "  0) Сохранить изменения"
        echo "  q) Отмена"
        echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
        read -rp "Выберите поле для изменения [0]: " field_choice
        field_choice="${field_choice:-0}"

        case "${field_choice}" in
            1)
                read -rp "Новое имя подключения [${new_alias}]: " val
                [[ -n "${val}" ]] && new_alias="$(echo "${val}" | xargs)"
                ;;
            2)
                read -rp "Новый Hostname/IP [${new_hn}]: " val
                [[ -n "${val}" ]] && new_hn="$(echo "${val}" | xargs)"
                ;;
            3)
                read -rp "Новый User [${new_u}]: " val
                [[ -n "${val}" ]] && new_u="$(echo "${val}" | xargs)"
                ;;
            4)
                read -rp "Новый Port [${new_p}]: " val
                [[ -n "${val}" ]] && new_p="$(echo "${val}" | xargs)"
                ;;
            5)
                echo "1) Вход по SSH-ключу (${DEFAULT_KEY})"
                echo "2) Вход по SSH-ключу (выбрать из списка)"
                echo "3) Вход по паролю"
                read -rp "> " a_sel
                if [[ "${a_sel}" == "1" ]]; then
                    new_auth="key"
                    new_key="${DEFAULT_KEY}"
                elif [[ "${a_sel}" == "2" ]]; then
                    local keys=()
                    while IFS= read -r k; do
                        [[ -n "${k}" ]] && keys+=("${k}")
                    done < <(get_local_keys)
                    for idx in "${!keys[@]}"; do
                        printf "  %d) %s\n" "$((idx+1))" "$(basename "${keys[$idx]}")"
                    done
                    read -rp "Номер: " k_num
                    if [[ "${k_num}" =~ ^[0-9]+$ ]] && (( k_num >= 1 && k_num <= ${#keys[@]} )); then
                        new_auth="key"
                        new_key="${keys[$((k_num-1))]}"
                    fi
                elif [[ "${a_sel}" == "3" ]]; then
                    new_auth="password"
                fi
                ;;
            6)
                echo -e "${CYAN}Тестирование соединения с ${new_hn}:${new_p}...${NC}"
                ssh -o ConnectTimeout=4 -o BatchMode=yes "${target}" 'exit' 2>/dev/null \
                    && echo -e "${GREEN}✓ Доступ по ключу подтверждён.${NC}" \
                    || echo -e "${YELLOW}[!] Порт отвечает или требуется пароль.${NC}"
                read -rp "Нажмите Enter..."
                ;;
            0)
                backup_config
                remove_host_block "${target}"

                local id_line=""
                local pass_lines=""
                if [[ "${new_auth}" == "password" ]]; then
                    pass_lines=$'    PubkeyAuthentication no\n    PreferredAuthentications password,keyboard-interactive'
                else
                    id_line="    IdentityFile ${new_key}"
                fi

                {
                    echo ""
                    echo "Host ${new_alias}"
                    echo "    HostName ${new_hn}"
                    echo "    User ${new_u}"
                    echo "    Port ${new_p}"
                    [[ -n "${id_line}" ]] && echo "${id_line}"
                    [[ -n "${pass_lines}" ]] && echo "${pass_lines}"
                } >> "${CONFIG_FILE}"

                chmod 600 "${CONFIG_FILE}"
                echo -e "${GREEN}✓ Сервер '${new_alias}' сохранён.${NC}"
                read -rp "Нажмите Enter..."
                break
                ;;
            [qQ])
                echo "Редактирование отменено."
                read -rp "Нажмите Enter..."
                break
                ;;
            *)
                ;;
        esac
    done
}

# ==============================================================================
# 3. УДАЛЕНИЕ СЕРВЕРА (С ПОДТВЕРЖДЕНИЕМ ИМЕНИ)
# ==============================================================================
action_delete_host() {
    clear
    echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}               УДАЛИТЬ СЕРВЕР                       ${NC}"
    echo -e "${BLUE}────────────────────────────────────────────────────${NC}"

    local hosts=()
    while IFS= read -r h; do
        [[ -n "${h}" ]] && hosts+=("${h}")
    done < <(get_hosts)

    if [[ ${#hosts[@]} -eq 0 ]]; then
        echo -e "${YELLOW}Список серверов пуст.${NC}"
        read -rp "Нажмите Enter..."; return
    fi

    echo "Выберите сервер для удаления:"
    for i in "${!hosts[@]}"; do
        printf "  %d) %s\n" "$((i+1))" "${hosts[$i]}"
    done
    read -rp "> " del_idx

    if ! ([[ "${del_idx}" =~ ^[0-9]+$ ]] && (( del_idx >= 1 && del_idx <= ${#hosts[@]} ))); then
        echo -e "${RED}Неверный номер.${NC}"
        read -rp "Нажмите Enter..."; return
    fi

    local target="${hosts[$((del_idx-1))]}"
    local u hn p
    hn=$(ssh -G "${target}" 2>/dev/null | awk '$1=="hostname"{print $2}')
    u=$(ssh -G "${target}" 2>/dev/null | awk '$1=="user"{print $2}')
    p=$(ssh -G "${target}" 2>/dev/null | awk '$1=="port"{print $2}')

    echo -e "\n${BOLD}Удаление сервера:${NC}"
    echo -e "  ${CYAN}${target}${NC}"
    echo -e "  ${u}@${hn}:${p}\n"

    echo -e "${YELLOW}Введите точное имя сервера [${target}] для подтверждения:${NC}"
    read -rp "> " typed_name

    if [[ "${typed_name}" != "${target}" ]]; then
        echo -e "${RED}Имя не совпадает. Удаление отменено.${NC}"
        read -rp "Нажмите Enter..."; return
    fi

    read -rp "Удалить сервер '${target}'? [y/N]: " confirm
    if [[ "${confirm}" =~ ^[Yy]$ ]]; then
        backup_config
        remove_host_block "${target}"
        echo -e "${GREEN}✓ Сервер '${target}' успешно удалён.${NC}"
    else
        echo "Удаление отменено."
    fi
    read -rp "Нажмите Enter..."
}

# ==============================================================================
# 4. ПРОВЕРКА ВСЕХ ПОДКЛЮЧЕНИЙ
# ==============================================================================
action_test_all() {
    clear
    echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}               ПРОВЕРКА SSH                         ${NC}"
    echo -e "${BLUE}────────────────────────────────────────────────────${NC}"

    local hosts=()
    while IFS= read -r h; do
        [[ -n "${h}" ]] && hosts+=("${h}")
    done < <(get_hosts)

    if [[ ${#hosts[@]} -eq 0 ]]; then
        echo -e "${YELLOW}Список серверов пуст.${NC}"
        read -rp "Нажмите Enter..."; return
    fi

    local online_count=0
    local total_count=${#hosts[@]}

    for h in "${hosts[@]}"; do
        local hn port flag
        hn=$(ssh -G "$h" 2>/dev/null | awk '$1=="hostname"{print $2}')
        port=$(ssh -G "$h" 2>/dev/null | awk '$1=="port"{print $2}')
        flag=$(get_flag "$h")

        printf "%s %-8s %-22s " "${flag}" "${h}" "${hn}:${port}"

        if ssh -o BatchMode=yes -o ConnectTimeout=4 "${h}" 'exit' 2>/dev/null; then
            echo -e "${GREEN}✓ ONLINE (SSH Key)${NC}"
            ((online_count++))
        else
            if (echo > /dev/tcp/"${hn}"/"${port}") 2>/dev/null; then
                echo -e "${CYAN}✓ ONLINE (Port Open)${NC}"
                ((online_count++))
            else
                echo -e "${RED}✗ OFFLINE${NC}"
            fi
        fi
    done

    echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
    echo -e "${BOLD}${online_count} из ${total_count} серверов доступны${NC}\n"
    read -rp "Нажмите Enter для возврата..."
}

# ==============================================================================
# 5. УПРАВЛЕНИЕ SSH-КЛЮЧАМИ
# ==============================================================================
action_keys_manager() {
    while true; do
        clear
        echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
        echo -e "${BOLD}               SSH KEY MANAGER                      ${NC}"
        echo -e "${BLUE}────────────────────────────────────────────────────${NC}"

        local keys=()
        while IFS= read -r k; do
            [[ -n "${k}" ]] && keys+=("${k}")
        done < <(get_local_keys)

        echo -e "${BOLD}SSH KEYS (${#keys[@]}):${NC}\n"
        if [[ ${#keys[@]} -eq 0 ]]; then
            echo -e "  ${YELLOW}(Локальные ключи в ~/.ssh/ не найдены)${NC}\n"
        else
            for i in "${!keys[@]}"; do
                local k="${keys[$i]}"
                local k_name
                k_name="$(basename "${k}")"
                local fp="-"
                local k_type="KEY"
                if [[ -f "${k}.pub" ]]; then
                    fp=$(ssh-keygen -lf "${k}.pub" 2>/dev/null | awk '{print $2}' || echo "-")
                    k_type=$(ssh-keygen -lf "${k}.pub" 2>/dev/null | awk '{print $4}' || echo "KEY")
                fi
                printf "  %d) ${GREEN}%s${NC}\n     ${DIM}%s | %s${NC}\n     ${CYAN}✓ private + public${NC}\n" \
                    "$((i+1))" "${k_name}" "${k_type}" "${fp}"
            done
            echo ""
        fi

        echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
        echo "  1  Показать публичный ключ (.pub / буфер)"
        echo "  2  Создать новый ключ (ED25519 / RSA)"
        echo "  3  Установить ключ на сервер (ssh-copy-id)"
        echo "  4  Удалить ключ"
        echo "  5  Показать fingerprint (отпечаток)"
        echo "  0  Назад"
        echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
        read -rp "Выберите действие: " act

        case "${act}" in
            1)
                if [[ ${#keys[@]} -eq 0 ]]; then
                    echo "Ключей нет."; sleep 1; continue
                fi
                echo "Выберите ключ:"
                for i in "${!keys[@]}"; do
                    printf "  %d) %s\n" "$((i+1))" "$(basename "${keys[$i]}")"
                done
                read -rp "> " k_sel
                if [[ "${k_sel}" =~ ^[0-9]+$ ]] && (( k_sel >= 1 && k_sel <= ${#keys[@]} )); then
                    local pub_file="${keys[$((k_sel-1))]}.pub"
                    echo -e "\n${BOLD}Публичный ключ (${pub_file}):${NC}\n"
                    cat "${pub_file}"
                    echo ""
                    if command -v termux-clipboard-set >/dev/null 2>&1; then
                        termux-clipboard-set < "${pub_file}"
                        echo -e "${GREEN}✓ Скопировано в буфер обмена Android!${NC}"
                    fi
                fi
                read -rp "Нажмите Enter..."
                ;;
            2)
                echo -e "\n1) ED25519 (рекомендуется)\n2) RSA 4096"
                read -rp "Тип ключа [1]: " t_sel
                local k_type="ed25519"
                local def_name="id_ed25519"
                if [[ "${t_sel}" == "2" ]]; then
                    k_type="rsa"
                    def_name="id_rsa"
                fi
                read -rp "Имя файла [${def_name}]: " k_name
                k_name="${k_name:-${def_name}}"
                local target_path="${SSH_DIR}/${k_name}"
                if [[ -f "${target_path}" ]]; then
                    echo -e "${RED}Ключ ${target_path} уже существует.${NC}"
                    read -rp "Нажмите Enter..."; continue
                fi
                read -rp "Комментарий [termux]: " k_comm
                k_comm="${k_comm:-termux}"
                if [[ "${k_type}" == "rsa" ]]; then
                    ssh-keygen -t rsa -b 4096 -f "${target_path}" -C "${k_comm}"
                else
                    ssh-keygen -t ed25519 -f "${target_path}" -C "${k_comm}"
                fi
                chmod 600 "${target_path}"
                chmod 644 "${target_path}.pub"
                echo -e "${GREEN}✓ Ключ создан: ${target_path}${NC}"
                read -rp "Нажмите Enter..."
                ;;
            3)
                if [[ ${#keys[@]} -eq 0 ]]; then
                    echo "Сначала создайте ключ."; sleep 1; continue
                fi
                echo "Выберите ключ для отправки:"
                for i in "${!keys[@]}"; do
                    printf "  %d) %s\n" "$((i+1))" "$(basename "${keys[$i]}")"
                done
                read -rp "> " k_sel
                if [[ "${k_sel}" =~ ^[0-9]+$ ]] && (( k_sel >= 1 && k_sel <= ${#keys[@]} )); then
                    local sel_pub="${keys[$((k_sel-1))]}.pub"
                    read -rp "Целевой хост (из config или user@host): " target_dest
                    read -rp "Порт [22]: " dest_port
                    dest_port="${dest_port:-22}"
                    echo -e "${CYAN}Выполняется ssh-copy-id...${NC}"
                    ssh-copy-id -i "${sel_pub}" -p "${dest_port}" "${target_dest}" || true
                fi
                read -rp "Нажмите Enter..."
                ;;
            4)
                if [[ ${#keys[@]} -eq 0 ]]; then
                    echo "Ключей нет."; sleep 1; continue
                fi
                echo "Выберите ключ для удаления:"
                for i in "${!keys[@]}"; do
                    printf "  %d) %s\n" "$((i+1))" "$(basename "${keys[$i]}")"
                done
                read -rp "> " k_sel
                if [[ "${k_sel}" =~ ^[0-9]+$ ]] && (( k_sel >= 1 && k_sel <= ${#keys[@]} )); then
                    local to_del="${keys[$((k_sel-1))]}"
                    read -rp "Удалить $(basename "${to_del}") и .pub? [y/N]: " conf
                    if [[ "${conf}" =~ ^[Yy]$ ]]; then
                        rm -f "${to_del}" "${to_del}.pub"
                        echo -e "${GREEN}✓ Ключ удалён.${NC}"
                    fi
                fi
                read -rp "Нажмите Enter..."
                ;;
            5)
                echo "Отпечатки ключей:"
                for k in "${keys[@]}"; do
                    [[ -f "${k}.pub" ]] && ssh-keygen -lf "${k}.pub"
                done
                read -rp "Нажмите Enter..."
                ;;
            0|[qQ])
                break
                ;;
            *)
                ;;
        esac
    done
}

# ==============================================================================
# 6. SSH CONFIG ИСПРАВЛЕНИЕ И ПРОВЕРКА
# ==============================================================================
action_ssh_config_manager() {
    while true; do
        clear
        echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
        echo -e "${BOLD}               SSH CONFIG                           ${NC}"
        echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
        echo "  1  Показать config (${CONFIG_FILE})"
        echo "  2  Проверить синтаксис всех хостов (ssh -G)"
        echo "  3  Сделать резервную копию вручную"
        echo "  4  Исправить права доступа (~/.ssh, config, keys)"
        echo "  0  Назад"
        echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
        read -rp "Выберите действие: " c_act

        case "${c_act}" in
            1)
                echo -e "\n${BOLD}Содержимое ${CONFIG_FILE}:${NC}\n"
                cat "${CONFIG_FILE}"
                echo ""
                read -rp "Нажмите Enter..."
                ;;
            2)
                echo -e "\n${BOLD}Проверка синтаксиса записей:${NC}\n"
                local hosts=()
                while IFS= read -r h; do
                    [[ -n "${h}" ]] && hosts+=("${h}")
                done < <(get_hosts)
                if [[ ${#hosts[@]} -eq 0 ]]; then
                    echo "  Записей пока нет."
                else
                    for h in "${hosts[@]}"; do
                        if ssh -G "$h" >/dev/null 2>&1; then
                            echo -e "  Host [${h}]: ${GREEN}✓ Корректно${NC}"
                        else
                            echo -e "  Host [${h}]: ${RED}✗ Ошибка конфигурации!${NC}"
                        fi
                    done
                fi
                read -rp "Нажмите Enter..."
                ;;
            3)
                backup_config
                read -rp "Нажмите Enter..."
                ;;
            4)
                echo -e "${CYAN}Исправление прав доступа...${NC}"
                chmod 700 "${SSH_DIR}"
                chmod 600 "${CONFIG_FILE}"
                for priv in "${SSH_DIR}"/id_*; do
                    if [[ -f "${priv}" && "${priv}" != *.pub ]]; then
                        chmod 600 "${priv}"
                    fi
                done
                for pub in "${SSH_DIR}"/*.pub; do
                    [[ -f "${pub}" ]] && chmod 644 "${pub}"
                done
                echo -e "${GREEN}✓ Права доступа успешно приведены к стандарту безопасности:${NC}"
                echo "  ~/.ssh         -> 700"
                echo "  ~/.ssh/config  -> 600"
                echo "  Private keys   -> 600"
                echo "  Public keys    -> 644"
                read -rp "Нажмите Enter..."
                ;;
            0|[qQ])
                break
                ;;
            *)
                ;;
        esac
    done
}

# ==============================================================================
# 7. УПРАВЛЕНИЕ РЕЗЕРВНЫМИ КОПИЯМИ
# ==============================================================================
action_backups_manager() {
    while true; do
        clear
        echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
        echo -e "${BOLD}               BACKUPS                              ${NC}"
        echo -e "${BLUE}────────────────────────────────────────────────────${NC}"

        local backups=()
        while IFS= read -r f; do
            [[ -n "${f}" ]] && backups+=("${f}")
        done < <(ls -t "${CONFIG_FILE}".backup-* 2>/dev/null || true)

        if [[ ${#backups[@]} -eq 0 ]]; then
            echo -e "  ${YELLOW}(Резервные копии пока не создавались)${NC}\n"
            echo "  b) Создать бэкап сейчас"
            echo "  0) Назад"
        else
            echo -e "${BOLD}Список последних резервных копий (хранится до ${MAX_BACKUPS}):${NC}\n"
            for i in "${!backups[@]}"; do
                local b_name
                b_name="$(basename "${backups[$i]}")"
                local b_date="${b_name#config.backup-}"
                printf "  %2d) %s  ${DIM}(%s)${NC}\n" "$((i+1))" "${b_date}" "${b_name}"
            done
            echo ""
            echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
            echo "  r  Восстановить из копии"
            echo "  l  Показать содержимое"
            echo "  d  Удалить копию"
            echo "  b  Создать бэкап сейчас"
            echo "  0  Назад"
        fi
        echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
        read -rp "Выберите действие: " b_act

        case "${b_act}" in
            [rR])
                if [[ ${#backups[@]} -eq 0 ]]; then continue; fi
                read -rp "Номер копии для восстановления: " r_idx
                if [[ "${r_idx}" =~ ^[0-9]+$ ]] && (( r_idx >= 1 && r_idx <= ${#backups[@]} )); then
                    local chosen="${backups[$((r_idx-1))]}"
                    backup_config
                    cp -f "${chosen}" "${CONFIG_FILE}"
                    chmod 600 "${CONFIG_FILE}"
                    echo -e "${GREEN}✓ Конфиг восстановлен из ${chosen}${NC}"
                fi
                read -rp "Нажмите Enter..."
                ;;
            [lL])
                if [[ ${#backups[@]} -eq 0 ]]; then continue; fi
                read -rp "Номер копии для просмотра: " l_idx
                if [[ "${l_idx}" =~ ^[0-9]+$ ]] && (( l_idx >= 1 && l_idx <= ${#backups[@]} )); then
                    local chosen="${backups[$((l_idx-1))]}"
                    echo -e "\n${BOLD}Содержимое ${chosen}:${NC}\n"
                    cat "${chosen}"
                    echo ""
                fi
                read -rp "Нажмите Enter..."
                ;;
            [dD])
                if [[ ${#backups[@]} -eq 0 ]]; then continue; fi
                read -rp "Номер копии для удаления: " d_idx
                if [[ "${d_idx}" =~ ^[0-9]+$ ]] && (( d_idx >= 1 && d_idx <= ${#backups[@]} )); then
                    rm -f "${backups[$((d_idx-1))]}"
                    echo -e "${GREEN}✓ Копия удалена.${NC}"
                fi
                read -rp "Нажмите Enter..."
                ;;
            [bB])
                backup_config
                read -rp "Нажмите Enter..."
                ;;
            0|[qQ])
                break
                ;;
            *)
                ;;
        esac
    done
}

# ==============================================================================
# ГЛАВНОЕ МЕНЮ
# ==============================================================================
main_menu() {
    init_env
    while true; do
        clear
        echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
        echo -e "${BOLD}                 TERMUX SSH MANAGER                 ${NC}"
        echo -e "${DIM}          Серверы • SSH • Ключи • Config            ${NC}"
        echo -e "${BLUE}════════════════════════════════════════════════════${NC}"

        local hosts=()
        while IFS= read -r h; do
            [[ -n "${h}" ]] && hosts+=("${h}")
        done < <(get_hosts)

        echo -e "\n${BOLD}  НАСТРОЕННЫЕ СЕРВЕРЫ${NC}\n"

        if [[ ${#hosts[@]} -eq 0 ]]; then
            echo -e "  ${YELLOW}(В ~/.ssh/config нет настроенных серверов)${NC}"
            echo -e "  ${DIM}Нажмите 'A', чтобы добавить первый сервер.${NC}"
        else
            for i in "${!hosts[@]}"; do
                local h="${hosts[$i]}"
                local user_host flag auth_icon
                user_host=$(ssh -G "$h" 2>/dev/null | awk '$1=="user"{u=$2} $1=="hostname"{hn=$2} $1=="port"{p=$2} END{print u"@"hn":"p}')
                flag=$(get_flag "$h")
                
                local pubkey_setting
                pubkey_setting=$(ssh -G "$h" 2>/dev/null | awk '$1=="pubkeyauthentication"{print $2}')
                if [[ "${pubkey_setting}" == "no" ]]; then
                    auth_icon="${YELLOW}🔒 [пароль]${NC}"
                else
                    auth_icon="${GREEN}🔑${NC}"
                fi

                printf "  ${BOLD}%2d)${NC} %s %-8s %-30s %b\n" "$((i+1))" "${flag}" "${h}" "${user_host}" "${auth_icon}"
            done
        fi

        echo -e "\n${BLUE}────────────────────────────────────────────────────${NC}"
        echo -e "  ${GREEN}A${NC}  Добавить сервер"
        echo -e "  ${YELLOW}E${NC}  Изменить сервер"
        echo -e "  ${RED}D${NC}  Удалить сервер"
        echo -e "  ${CYAN}T${NC}  Проверить подключения"
        echo -e "  ${MAGENTA}K${NC}  SSH-ключи"
        echo -e "  ${BLUE}C${NC}  SSH Config"
        echo -e "  ${YELLOW}B${NC}  Резервные копии"
        echo -e "  ${DIM}Q  Выход${NC}"
        echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
        read -rp "Выберите сервер или действие: " choice

        # Проверка: если введено число от 1 до N — МГНОВЕННОЕ подключение
        if [[ "${choice}" =~ ^[0-9]+$ ]]; then
            if (( choice >= 1 && choice <= ${#hosts[@]} )); then
                local chosen_host="${hosts[$((choice-1))]}"
                clear
                echo -e "${GREEN}Подключение к ${chosen_host} (ssh ${chosen_host})...${NC}\n"
                ssh "${chosen_host}" || true
                echo -e "\n${DIM}Сессия закрыта. Нажмите Enter для возврата в меню...${NC}"
                read -rp ""
            else
                echo -e "${RED}Сервер с номером ${choice} не найден.${NC}"
                sleep 1
            fi
            continue
        fi

        case "${choice}" in
            [aA])
                action_add_host
                ;;
            [eE])
                action_edit_host
                ;;
            [dD])
                action_delete_host
                ;;
            [tT])
                action_test_all
                ;;
            [kK])
                action_keys_manager
                ;;
            [cC])
                action_ssh_config_manager
                ;;
            [bB])
                action_backups_manager
                ;;
            [qQ])
                clear
                exit 0
                ;;
            *)
                echo -e "${RED}Неверный выбор.${NC}"
                sleep 1
                ;;
        esac
    done
}

main_menu
