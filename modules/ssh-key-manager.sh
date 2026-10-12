#!/usr/bin/env bash
# ==============================================================================
# Android VPS Toolkit — SSH Key Manager (modules/ssh-key-manager.sh)
# Управление локальными ключами: генерация, экспорт .pub, отпечатки, ssh-copy-id
# ==============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "")"
LIB_DIR="${SCRIPT_DIR}/../lib"
if [[ -f "${LIB_DIR}/common.sh" ]]; then
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

ssh_key_manager_list() {
    print_header "ЛОКАЛЬНЫЕ SSH-КЛЮЧИ"
    local pub_files=()
    while IFS= read -r f; do [[ -n "$f" ]] && pub_files+=("$f"); done < <(find "${SSH_DIR}" -maxdepth 1 -name "*.pub" 2>/dev/null | sort)

    if [[ ${#pub_files[@]} -eq 0 ]]; then
        echo -e "${YELLOW}Ключей в ~/.ssh/ не найдено.${NC}"
        press_enter; return
    fi

    for (( i=0; i<${#pub_files[@]}; i++ )); do
        local pub="${pub_files[$i]}"
        local priv="${pub%.pub}"
        local bname=$(basename "${priv}")
        local fp="—"
        fp=$(ssh-keygen -lf "${pub}" 2>/dev/null || echo "Некорректный ключ")
        local priv_status="${GREEN}найден${NC}"
        [[ ! -f "${priv}" ]] && priv_status="${RED}ОТСУТСТВУЕТ${NC}"

        echo -e " ${BOLD}$((i+1)). ${bname}${NC} [Приватный: ${priv_status}]"
        echo -e "    Отпечаток: ${DIM}${fp}${NC}\n"
    done
    press_enter
}

ssh_key_manager_generate() {
    print_header "ГЕНЕРАЦИЯ SSH-КЛЮЧА"
    echo "  1. ED25519 (Рекомендуется, быстрый и надёжный)"
    echo "  2. RSA 4096 (Классический)"
    echo "  0. Отмена"
    print_divider
    read -rp "Выберите алгоритм [0–2]: " a_choice

    local k_type="ed25519" k_bits=""
    case "${a_choice}" in
        1) k_type="ed25519" ;;
        2) k_type="rsa"; k_bits="-b 4096" ;;
        0|[qQ]) return ;;
        *) return ;;
    esac

    read -rp "Имя файла ключа [id_${k_type}]: " k_name
    k_name="${k_name:-id_${k_type}}"
    local full_path="${SSH_DIR}/${k_name}"

    if [[ -f "${full_path}" ]]; then
        echo -e "${RED}Ошибка: файл ${full_path} уже существует! Защита от перезаписи.${NC}"
        press_enter; return
    fi

    read -rp "Комментарий к ключу (email или имя): " k_comment
    k_comment="${k_comment:-termux-$(date +%Y%m%d)}"

    echo -e "\n${CYAN}Генерация ключа ${k_type}...${NC}"
    ssh-keygen -t "${k_type}" ${k_bits} -C "${k_comment}" -f "${full_path}" -N ""

    chmod 600 "${full_path}"
    chmod 644 "${full_path}.pub"

    echo -e "\n${GREEN}✓ Ключевая пара успешно создана:${NC}"
    echo "  Приватный: ${full_path}"
    echo "  Публичный: ${full_path}.pub"
    press_enter
}

ssh_key_manager_export_pub() {
    print_header "ПУБЛИЧНЫЙ КЛЮЧ (.pub)"
    local pub_files=()
    while IFS= read -r f; do [[ -n "$f" ]] && pub_files+=("$f"); done < <(find "${SSH_DIR}" -maxdepth 1 -name "*.pub" 2>/dev/null | sort)

    if [[ ${#pub_files[@]} -eq 0 ]]; then
        echo -e "${YELLOW}Ключей не найдено.${NC}"; press_enter; return
    fi

    for (( i=0; i<${#pub_files[@]}; i++ )); do
        printf "  %d. %s\n" "$((i+1))" "$(basename "${pub_files[$i]}")"
    done
    echo ""
    echo "  0. Назад"
    print_divider
    read -rp "Выберите ключ: " sel

    [[ "${sel}" == "0" || -z "${sel}" ]] && return
    if [[ "${sel}" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#pub_files[@]} )); then
        local chosen="${pub_files[$((sel-1))]}"
        clear 2>/dev/null || true
        print_header "СОДЕРЖИМОЕ: $(basename "${chosen}")"
        cat "${chosen}"
        echo ""

        if command -v termux-clipboard-set >/dev/null 2>&1; then
            termux-clipboard-set < "${chosen}"
            echo -e "${GREEN}✓ Ключ скопирован в буфер обмена Android!${NC}"
        else
            echo -e "${DIM}(Для копирования в буфер установите termux-api)${NC}"
        fi
        press_enter
    fi
}

ssh_key_manager_install_on_vps() {
    print_header "УСТАНОВКА КЛЮЧА НА VPS (ssh-copy-id)"
    local pub_files=()
    while IFS= read -r f; do [[ -n "$f" ]] && pub_files+=("$f"); done < <(find "${SSH_DIR}" -maxdepth 1 -name "*.pub" 2>/dev/null | sort)

    if [[ ${#pub_files[@]} -eq 0 ]]; then
        echo -e "${YELLOW}Нет публичных ключей для отправки.${NC}"; press_enter; return
    fi

    for (( i=0; i<${#pub_files[@]}; i++ )); do
        printf "  %d. %s\n" "$((i+1))" "$(basename "${pub_files[$i]}")"
    done
    read -rp "Выберите ключ [1-${#pub_files[@]}]: " k_sel
    [[ ! "${k_sel}" =~ ^[0-9]+$ ]] || (( k_sel < 1 || k_sel > ${#pub_files[@]} )) && return
    local chosen_pub="${pub_files[$((k_sel-1))]}"

    local s_alias
    s_alias=$(prompt_select_server "Выберите сервер назначения")
    [[ -z "${s_alias}" ]] && return

    echo -e "\n${CYAN}Отправка ${chosen_pub} на ${s_alias}...${NC}"
    if command -v ssh-copy-id >/dev/null 2>&1; then
        ssh-copy-id -F "${CONFIG_FILE}" -i "${chosen_pub}" "${s_alias}" || true
    else
        cat "${chosen_pub}" | ssh -F "${CONFIG_FILE}" "${s_alias}" \
            "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
    fi
    echo -e "\n${GREEN}✓ Ключ добавлен на сервер.${NC}"
    press_enter
}

ssh_key_manager_main() {
    while true; do
        clear 2>/dev/null || true
        echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
        echo -e "${BOLD}               SSH KEY MANAGER                      ${NC}"
        echo -e "${DIM}      Управление SSH-ключами на телефоне            ${NC}"
        echo -e "${BLUE}════════════════════════════════════════════════════${NC}\n"

        echo "  1. Просмотреть список установленных ключей"
        echo "  2. Сгенерировать новый ключ (ED25519 / RSA)"
        echo "  3. Показать публичный ключ (.pub) и скопировать"
        echo "  4. Установить публичный ключ на VPS (ssh-copy-id)"
        echo "  5. Загрузить публичные ключи с GitHub"
        echo ""
        echo "  0. Назад в главное меню"
        print_divider
        read -rp "Выберите действие [0–5]: " choice

        case "${choice}" in
            1) ssh_key_manager_list ;;
            2) ssh_key_manager_generate ;;
            3) ssh_key_manager_export_pub ;;
            4) ssh_key_manager_install_on_vps ;;
            5)
                read -rp "GitHub логин: " gh_u
                if [[ -n "${gh_u}" ]]; then
                    echo -e "\n${CYAN}Загрузка https://github.com/${gh_u}.keys...${NC}\n"
                    curl -s "https://github.com/${gh_u}.keys" || echo "Ошибка загрузки."
                    press_enter
                fi
                ;;
            0|[qQ]) return ;;
            *) echo -e "${RED}Неверный ввод.${NC}"; sleep 1 ;;
        esac
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    ssh_key_manager_main "$@"
fi
