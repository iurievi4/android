#!/usr/bin/env bash
# ==============================================================================
# Termux SSH Manager
# Управление SSH-серверами (~/.ssh/config) и SSH-ключами в Termux на Android
# ==============================================================================

set -euo pipefail

SSH_DIR="${HOME}/.ssh"
CONFIG_FILE="${SSH_DIR}/config"
DEFAULT_KEY="${SSH_DIR}/id_ed25519"

# Цветовая палитра
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Инициализация каталогов и прав доступа
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

backup_config() {
    if [[ -s "${CONFIG_FILE}" ]]; then
        local bak="${CONFIG_FILE}.bak_$(date +%Y%m%d_%H%M%S)"
        cp "${CONFIG_FILE}" "${bak}"
        echo -e "${YELLOW}Резервная копия создана: ${bak}${NC}"
    fi
}

print_header() {
    clear
    echo -e "${BLUE}====================================================${NC}"
    echo -e "${BOLD}               TERMUX SSH MANAGER                   ${NC}"
    echo -e "${DIM}      Управление серверами, конфигом и SSH-ключами   ${NC}"
    echo -e "${BLUE}====================================================${NC}"
}

# ==============================================================================
# Функции управления SSH-ключами
# ==============================================================================

# Поиск всех доступных локальных приватных ключей
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

# Меню управления ключами
keys_menu() {
    while true; do
        print_header
        echo -e "${BOLD}--- Управление локальными SSH-ключами ---${NC}\n"

        local keys=()
        while IFS= read -r k; do
            [[ -n "${k}" ]] && keys+=("${k}")
        done < <(get_local_keys)

        if [[ ${#keys[@]} -eq 0 ]]; then
            echo -e "  ${YELLOW}(SSH-ключи в ~/.ssh/ не найдены)${NC}\n"
        else
            echo -e "${BOLD}Найденные ключи на устройстве:${NC}"
            for i in "${!keys[@]}"; do
                local k="${keys[$i]}"
                local k_name
                k_name="$(basename "${k}")"
                local k_fingerprint="-"
                if command -v ssh-keygen >/dev/null 2>&1; then
                    k_fingerprint=$(ssh-keygen -lf "${k}.pub" 2>/dev/null | awk '{print $2, $4}' || echo "-")
                fi
                printf "  ${GREEN}%2d)${NC} %-16s ${DIM}%s${NC}\n" "$((i+1))" "${k_name}" "${k_fingerprint}"
            done
            echo ""
        fi

        echo -e "${BOLD}Действия:${NC}"
        echo -e "  ${GREEN}1)${NC} Сгенерировать новый SSH-ключ (ed25519 / rsa)"
        echo -e "  ${CYAN}2)${NC} Показать публичный ключ (для GitHub или VPS)"
        echo -e "  ${YELLOW}3)${NC} Скопировать ключ на сервер (ssh-copy-id)"
        echo -e "  ${RED}4)${NC} Удалить ключ с устройства"
        echo -e "  ${DIM}0) Назад в главное меню${NC}"
        echo ""
        read -rp "Выберите действие: " k_act

        case "${k_act}" in
            1)
                create_ssh_key
                ;;
            2)
                show_public_key
                ;;
            3)
                deploy_key_to_server
                ;;
            4)
                delete_ssh_key
                ;;
            0)
                break
                ;;
            *)
                ;;
        esac
    done
}

# Генерация нового ключа
create_ssh_key() {
    echo -e "\n${BOLD}--- Генерация нового SSH-ключа ---${NC}"
    echo "1) ED25519 (современный, быстрый и безопасный — рекомендуется)"
    echo "2) RSA 4096 (для старых систем)"
    read -rp "Выберите тип ключа [1]: " t_choice
    t_choice="${t_choice:-1}"

    local key_type="ed25519"
    local default_name="id_ed25519"
    if [[ "${t_choice}" == "2" ]]; then
        key_type="rsa"
        default_name="id_rsa"
    fi

    read -rp "Имя файла ключа [${default_name}]: " key_name
    key_name="${key_name:-${default_name}}"
    local target_key="${SSH_DIR}/${key_name}"

    if [[ -f "${target_key}" ]]; then
        echo -e "${RED}Ошибка: ключ ${target_key} уже существует.${NC}"
        read -rp "Нажмите Enter..."; return
    fi

    read -rp "Комментарий к ключу (например, email или termux-phone): " comment
    comment="${comment:-termux-$(date +%Y%m%d)}"

    echo -e "${CYAN}Генерация ключа ${key_type}... (при запросе passphrase можно нажать Enter для входа без пароля)${NC}"
    if [[ "${key_type}" == "rsa" ]]; then
        ssh-keygen -t rsa -b 4096 -f "${target_key}" -C "${comment}"
    else
        ssh-keygen -t ed25519 -f "${target_key}" -C "${comment}"
    fi

    chmod 600 "${target_key}"
    chmod 644 "${target_key}.pub"

    echo -e "\n${GREEN}[OK] Ключ успешно создан:${NC} ${target_key}"
    echo -e "${BOLD}Публичный ключ:${NC}"
    cat "${target_key}.pub"

    # Если установлен termux-api, копируем в буфер
    if command -v termux-clipboard-set >/dev/null 2>&1; then
        termux-clipboard-set < "${target_key}.pub"
        echo -e "${CYAN}(Публичный ключ скопирован в буфер обмена Android)${NC}"
    fi

    read -rp "Нажмите Enter..."
}

# Просмотр публичного ключа
show_public_key() {
    local keys=()
    while IFS= read -r k; do
        [[ -n "${k}" ]] && keys+=("${k}")
    done < <(get_local_keys)

    if [[ ${#keys[@]} -eq 0 ]]; then
        echo -e "${RED}Нет доступных ключей.${NC}"
        read -rp "Нажмите Enter..."; return
    fi

    echo -e "\n${BOLD}Выберите ключ для просмотра публичной части (.pub):${NC}"
    for i in "${!keys[@]}"; do
        printf "  %d) %s\n" "$((i+1))" "$(basename "${keys[$i]}")"
    done
    read -rp "Номер ключа: " idx

    if [[ "${idx}" =~ ^[0-9]+$ ]] && (( idx >= 1 && idx <= ${#keys[@]} )); then
        local chosen="${keys[$((idx-1))]}"
        local pub_file="${chosen}.pub"
        if [[ -f "${pub_file}" ]]; then
            echo -e "\n${BOLD}Публичный ключ (${pub_file}):${NC}\n"
            echo -e "${CYAN}$(cat "${pub_file}")${NC}\n"
            if command -v termux-clipboard-set >/dev/null 2>&1; then
                termux-clipboard-set < "${pub_file}"
                echo -e "${GREEN}✓ Скопировано в буфер обмена Android!${NC}"
            else
                echo -e "${DIM}(Подсказка: установите пакет termux-api для автокопирования в буфер обмена)${NC}"
            fi
        else
            echo -e "${RED}Файл публичного ключа ${pub_file} не найден.${NC}"
        fi
    else
        echo -e "${RED}Неверный номер.${NC}"
    fi
    read -rp "Нажмите Enter..."
}

# Копирование ключа на сервер (ssh-copy-id)
deploy_key_to_server() {
    local keys=()
    while IFS= read -r k; do
        [[ -n "${k}" ]] && keys+=("${k}")
    done < <(get_local_keys)

    if [[ ${#keys[@]} -eq 0 ]]; then
        echo -e "${RED}Сначала сгенерируйте SSH-ключ.${NC}"
        read -rp "Нажмите Enter..."; return
    fi

    echo -e "\n${BOLD}Выберите ключ для отправки на сервер:${NC}"
    for i in "${!keys[@]}"; do
        printf "  %d) %s\n" "$((i+1))" "$(basename "${keys[$i]}")"
    done
    read -rp "Номер ключа [1]: " k_idx
    k_idx="${k_idx:-1}"

    if ! ([[ "${k_idx}" =~ ^[0-9]+$ ]] && (( k_idx >= 1 && k_idx <= ${#keys[@]} ))); then
        echo -e "${RED}Неверный выбор.${NC}"
        read -rp "Нажмите Enter..."; return
    fi
    local selected_key="${keys[$((k_idx-1))]}"

    echo -e "\nКуда скопировать ключ?"
    echo "1) На сервер из существующего списка config (tr, fi, lv, pa...)"
    echo "2) Указать произвольный хост вручную (user@host -p port)"
    read -rp "Ваш выбор [1]: " d_mode
    d_mode="${d_mode:-1}"

    if [[ "${d_mode}" == "1" ]]; then
        local hosts=()
        while IFS= read -r h; do
            [[ -n "${h}" ]] && hosts+=("${h}")
        done < <(get_hosts)

        if [[ ${#hosts[@]} -eq 0 ]]; then
            echo -e "${RED}Список серверов пуст.${NC}"
            read -rp "Нажмите Enter..."; return
        fi

        echo -e "\nВыберите сервер:"
        for i in "${!hosts[@]}"; do
            printf "  %d) %s\n" "$((i+1))" "${hosts[$i]}"
        done
        read -rp "Номер сервера: " h_idx
        if [[ "${h_idx}" =~ ^[0-9]+$ ]] && (( h_idx >= 1 && h_idx <= ${#hosts[@]} )); then
            local target_host="${hosts[$((h_idx-1))]}"
            echo -e "${CYAN}Копирование ключа на ${target_host}...${NC}"
            ssh-copy-id -i "${selected_key}.pub" "${target_host}" || true
        else
            echo -e "${RED}Неверный номер.${NC}"
        fi
    else
        read -rp "Сервер (например, root@155.103.71.33): " remote_dest
        read -rp "Порт [22]: " remote_port
        remote_port="${remote_port:-22}"
        echo -e "${CYAN}Копирование ключа на ${remote_dest}:${remote_port}...${NC}"
        ssh-copy-id -i "${selected_key}.pub" -p "${remote_port}" "${remote_dest}" || true
    fi

    read -rp "Нажмите Enter..."
}

# Удаление SSH-ключа
delete_ssh_key() {
    local keys=()
    while IFS= read -r k; do
        [[ -n "${k}" ]] && keys+=("${k}")
    done < <(get_local_keys)

    if [[ ${#keys[@]} -eq 0 ]]; then
        echo -e "${RED}Нет ключей для удаления.${NC}"
        read -rp "Нажмите Enter..."; return
    fi

    echo -e "\n${BOLD}Выберите ключ для удаления:${NC}"
    for i in "${!keys[@]}"; do
        printf "  %d) %s\n" "$((i+1))" "$(basename "${keys[$i]}")"
    done
    read -rp "Номер ключа: " idx

    if [[ "${idx}" =~ ^[0-9]+$ ]] && (( idx >= 1 && idx <= ${#keys[@]} )); then
        local chosen="${keys[$((idx-1))]}"
        echo -e "${RED}Вы действительно хотите удалить ключ $(basename "${chosen}") и его .pub файл? (y/N)${NC}"
        read -rp "> " conf
        if [[ "${conf}" =~ ^[Yy]$ ]]; then
            rm -f "${chosen}" "${chosen}.pub"
            echo -e "${GREEN}Ключ удалён.${NC}"
        else
            echo "Удаление отменено."
        fi
    else
        echo -e "${RED}Неверный номер.${NC}"
    fi
    read -rp "Нажмите Enter..."
}

# ==============================================================================
# Функции управления серверами (~/.ssh/config)
# ==============================================================================

get_hosts() {
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        return
    fi
    grep -iE '^[[:space:]]*Host[[:space:]]+' "${CONFIG_FILE}" \
        | awk '{for(i=2;i<=NF;i++) if($i !~ /[*?]/) print $i}' \
        | sort -u
}

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

test_connection() {
    local host="$1"
    echo -e "\n${CYAN}Проверка соединения с [${host}]...${NC}"
    
    if ssh -o ConnectTimeout=4 -o BatchMode=yes "${host}" 'exit' 2>/dev/null; then
        echo -e "${GREEN}[OK] Подключение по SSH-ключу успешно выполнено!${NC}"
        read -rp "Нажмите Enter для продолжения..."
        return
    fi

    local hn port
    hn=$(ssh -G "${host}" 2>/dev/null | awk '$1=="hostname"{print $2}')
    port=$(ssh -G "${host}" 2>/dev/null | awk '$1=="port"{print $2}')

    if (echo > /dev/tcp/"${hn}"/"${port}") 2>/dev/null; then
        echo -e "${YELLOW}[!] Сетевой порт ${port} на ${hn} открыт и отвечает.${NC}"
        echo -e "${DIM}(Требуется пароль или сервер не принял текущий ключ)${NC}"
    else
        echo -e "${RED}[FAIL] Порт ${port} на ${hn} недоступен или превышен таймаут.${NC}"
    fi
    read -rp "Нажмите Enter для продолжения..."
}

# Добавление нового сервера
add_host() {
    echo -e "\n${BOLD}--- Добавление нового сервера ---${NC}"
    read -rp "Псевдоним хоста (например, tr, fi, vps1): " host_alias
    host_alias="$(echo "${host_alias}" | xargs)"

    if [[ -z "${host_alias}" ]]; then
        echo -e "${RED}Ошибка: имя хоста не может быть пустым.${NC}"
        read -rp "Нажмите Enter..."; return
    fi

    if get_hosts | grep -qw "^${host_alias}$"; then
        echo -e "${RED}Ошибка: хост с именем '${host_alias}' уже существует.${NC}"
        read -rp "Нажмите Enter..."; return
    fi

    read -rp "IP-адрес или домен (HostName): " host_name
    host_name="$(echo "${host_name}" | xargs)"
    if [[ -z "${host_name}" ]]; then
        echo -e "${RED}Ошибка: HostName не может быть пустым.${NC}"
        read -rp "Нажмите Enter..."; return
    fi

    read -rp "Имя пользователя [root]: " user_name
    user_name="$(echo "${user_name}" | xargs)"
    user_name="${user_name:-root}"

    read -rp "SSH-порт [22]: " port
    port="$(echo "${port}" | xargs)"
    port="${port:-22}"

    echo -e "\n${BOLD}Выберите способ авторизации:${NC}"
    echo "  1) Выбрать SSH-ключ из установленных на телефоне"
    echo "  2) Указать путь к ключу вручную"
    echo "  3) Вход только по паролю (отключить проверку ключей)"
    read -rp "Ваш выбор [1]: " auth_choice
    auth_choice="${auth_choice:-1}"

    local identity_line=""
    local auth_lines=""

    case "${auth_choice}" in
        1)
            local local_keys=()
            while IFS= read -r k; do
                [[ -n "${k}" ]] && local_keys+=("${k}")
            done < <(get_local_keys)

            if [[ ${#local_keys[@]} -gt 0 ]]; then
                echo -e "\nДоступные ключи:"
                for i in "${!local_keys[@]}"; do
                    printf "    %d) %s\n" "$((i+1))" "$(basename "${local_keys[$i]}")"
                done
                read -rp "Выберите номер ключа [1]: " chosen_k_idx
                chosen_k_idx="${chosen_k_idx:-1}"
                if [[ "${chosen_k_idx}" =~ ^[0-9]+$ ]] && (( chosen_k_idx >= 1 && chosen_k_idx <= ${#local_keys[@]} )); then
                    identity_line="    IdentityFile ${local_keys[$((chosen_k_idx-1))]}"
                else
                    identity_line="    IdentityFile ${DEFAULT_KEY}"
                fi
            else
                identity_line="    IdentityFile ${DEFAULT_KEY}"
                echo -e "${YELLOW}Ключей не найдено, установлен по умолчанию: ${DEFAULT_KEY}${NC}"
            fi
            ;;
        2)
            read -rp "Путь к файлу приватного ключа: " custom_key
            identity_line="    IdentityFile ${custom_key}"
            ;;
        3)
            auth_lines=$'    PubkeyAuthentication no\n    PreferredAuthentications password,keyboard-interactive'
            ;;
        *)
            echo -e "${RED}Неверный выбор авторизации.${NC}"
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
    echo -e "${GREEN}Сервер '${host_alias}' успешно добавлен в ${CONFIG_FILE}.${NC}"
    read -rp "Нажмите Enter..."
}

# Редактирование параметров существующего сервера
edit_host() {
    local target="$1"
    local cur_hn cur_u cur_p
    cur_hn=$(ssh -G "${target}" 2>/dev/null | awk '$1=="hostname"{print $2}')
    cur_u=$(ssh -G "${target}" 2>/dev/null | awk '$1=="user"{print $2}')
    cur_p=$(ssh -G "${target}" 2>/dev/null | awk '$1=="port"{print $2}')

    echo -e "\n${BOLD}Редактирование сервера [${target}]:${NC}"
    echo -e "${DIM}(Оставьте поле пустым, чтобы сохранить текущее значение)${NC}\n"

    read -rp "IP или HostName [${cur_hn}]: " new_hn
    new_hn="${new_hn:-${cur_hn}}"

    read -rp "User [${cur_u}]: " new_u
    new_u="${new_u:-${cur_u}}"

    read -rp "Port [${cur_p}]: " new_p
    new_p="${new_p:-${cur_p}}"

    echo -e "\nСпособ авторизации:"
    echo "  1) Выбрать SSH-ключ из имеющихся на устройстве"
    echo "  2) Указать путь к ключу вручную"
    echo "  3) Пароль (отключить ключ)"
    echo "  4) Не менять параметры авторизации"
    read -rp "Ваш выбор [4]: " a_choice
    a_choice="${a_choice:-4}"

    local identity_line=""
    local auth_lines=""

    case "${a_choice}" in
        1)
            local local_keys=()
            while IFS= read -r k; do
                [[ -n "${k}" ]] && local_keys+=("${k}")
            done < <(get_local_keys)
            if [[ ${#local_keys[@]} -gt 0 ]]; then
                for i in "${!local_keys[@]}"; do
                    printf "    %d) %s\n" "$((i+1))" "$(basename "${local_keys[$i]}")"
                done
                read -rp "Номер ключа: " chosen_k_idx
                if [[ "${chosen_k_idx}" =~ ^[0-9]+$ ]] && (( chosen_k_idx >= 1 && chosen_k_idx <= ${#local_keys[@]} )); then
                    identity_line="    IdentityFile ${local_keys[$((chosen_k_idx-1))]}"
                fi
            else
                identity_line="    IdentityFile ${DEFAULT_KEY}"
            fi
            ;;
        2)
            read -rp "Путь к файлу ключа: " custom_key
            identity_line="    IdentityFile ${custom_key}"
            ;;
        3)
            auth_lines=$'    PubkeyAuthentication no\n    PreferredAuthentications password,keyboard-interactive'
            ;;
        4)
            local raw_block
            raw_block=$(awk -v target="${target}" '
                BEGIN { in_host=0 }
                tolower($1)=="host" {
                    in_host=0
                    for(i=2; i<=NF; i++) {
                        if($i==target) { in_host=1; break }
                    }
                    next
                }
                in_host && tolower($1)=="host" { in_host=0 }
                in_host { print }
            ' "${CONFIG_FILE}")
            identity_line=$(echo "${raw_block}" | grep -iE '^[[:space:]]*IdentityFile' || true)
            auth_lines=$(echo "${raw_block}" | grep -iE '^[[:space:]]*(PubkeyAuthentication|PreferredAuthentications)' || true)
            ;;
        *)
            echo -e "${RED}Неверный выбор.${NC}"
            read -rp "Нажмите Enter..."; return
            ;;
    esac

    backup_config
    remove_host_block "${target}"

    {
        echo ""
        echo "Host ${target}"
        echo "    HostName ${new_hn}"
        echo "    User ${new_u}"
        echo "    Port ${new_p}"
        [[ -n "${identity_line}" ]] && echo "${identity_line}"
        [[ -n "${auth_lines}" ]] && echo "${auth_lines}"
    } >> "${CONFIG_FILE}"

    chmod 600 "${CONFIG_FILE}"
    echo -e "${GREEN}Сервер '${target}' успешно обновлён.${NC}"
    read -rp "Нажмите Enter..."
}

# Удаление хоста
delete_host() {
    local target="$1"
    echo -e "\n${RED}Внимание! Вы собираетесь удалить хост [${target}].${NC}"
    read -rp "Подтвердить удаление? (y/N): " confirm
    if [[ "${confirm}" =~ ^[Yy]$ ]]; then
        backup_config
        remove_host_block "${target}"
        echo -e "${GREEN}Хост '${target}' удалён из конфигурации.${NC}"
    else
        echo "Удаление отменено."
    fi
    read -rp "Нажмите Enter..."
}

# Меню для выбранного сервера
manage_host_menu() {
    local target="$1"
    while true; do
        print_header
        echo -e "${BOLD}Выбран сервер: ${CYAN}${target}${NC}\n"

        echo -e "${BOLD}Текущие параметры:${NC}"
        ssh -G "${target}" 2>/dev/null | grep -E '^(hostname|user|port|identityfile|pubkeyauthentication) ' | sed 's/^/  /' || true
        echo ""
        echo -e "  ${GREEN}1)${NC} Подключиться (ssh ${target})"
        echo -e "  ${CYAN}2)${NC} Проверить соединение (ping / port check)"
        echo -e "  ${YELLOW}3)${NC} Редактировать параметры"
        echo -e "  ${RED}4)${NC} Удалить сервер"
        echo -e "  ${DIM}0) Назад в главное меню${NC}"
        echo ""
        read -rp "Выберите действие [1]: " sub_choice
        sub_choice="${sub_choice:-1}"

        case "${sub_choice}" in
            1)
                clear
                echo -e "${GREEN}Подключение к ${target}...${NC}\n"
                ssh "${target}" || true
                echo -e "\n${DIM}Сессия закрыта.${NC}"
                read -rp "Нажмите Enter для возврата..."
                ;;
            2)
                test_connection "${target}"
                ;;
            3)
                edit_host "${target}"
                ;;
            4)
                delete_host "${target}"
                break
                ;;
            0)
                break
                ;;
            *)
                ;;
        esac
    done
}

# Главное меню приложения
main_menu() {
    init_env
    while true; do
        print_header
        local hosts=()
        while IFS= read -r h; do
            [[ -n "${h}" ]] && hosts+=("${h}")
        done < <(get_hosts)

        echo -e "${BOLD}Настроенные серверы:${NC}"
        if [[ ${#hosts[@]} -eq 0 ]]; then
            echo -e "  ${YELLOW}(серверов пока нет. Нажмите 'a' для добавления)${NC}"
        else
            for i in "${!hosts[@]}"; do
                local h="${hosts[$i]}"
                local user_host auth_tag
                user_host=$(ssh -G "$h" 2>/dev/null | awk '$1=="user"{u=$2} $1=="hostname"{hn=$2} $1=="port"{p=$2} END{print u"@"hn":"p}')
                
                local pubkey_setting
                pubkey_setting=$(ssh -G "$h" 2>/dev/null | awk '$1=="pubkeyauthentication"{print $2}')
                if [[ "${pubkey_setting}" == "no" ]]; then
                    auth_tag="${YELLOW}[пароль]${NC}"
                else
                    auth_tag="${GREEN}[ключ]${NC}"
                fi

                printf "  ${GREEN}%2d)${NC} %-10s %-32s %b\n" "$((i+1))" "$h" "$user_host" "$auth_tag"
            done
        fi

        echo ""
        echo -e "${BOLD}Действия:${NC}"
        echo -e "  ${GREEN}a)${NC} Добавить новый сервер"
        echo -e "  ${MAGENTA}k)${NC} Управление SSH-ключами на телефоне (создать / удалить / скопировать)"
        echo -e "  ${CYAN}b)${NC} Показать резервные копии конфига"
        echo -e "  ${RED}q)${NC} Выход"
        echo ""
        read -rp "Введите номер сервера или действие: " choice

        case "${choice}" in
            [aA])
                add_host
                ;;
            [kK])
                keys_menu
                ;;
            [bB])
                echo -e "\n${BOLD}Список бэкапов в ${SSH_DIR}:${NC}"
                ls -lh "${SSH_DIR}"/config.bak_* 2>/dev/null || echo "Резервных копий пока нет."
                read -rp "Нажмите Enter..."
                ;;
            [qQ])
                clear
                exit 0
                ;;
            *)
                if [[ "${choice}" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#hosts[@]} )); then
                    manage_host_menu "${hosts[$((choice-1))]}"
                else
                    echo -e "${RED}Неверный ввод.${NC}"
                    sleep 1
                fi
                ;;
        esac
    done
}

main_menu
