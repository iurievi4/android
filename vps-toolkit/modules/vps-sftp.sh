#!/usr/bin/env bash
# ==============================================================================
# Android VPS Toolkit — SFTP File Manager (modules/vps-sftp.sh)
# Просмотр файлов, скачивание, загрузка, просмотр логов и редактирование конфигов
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

sftp_browse_server() {
    local target="$1"
    local cur_path="/etc"

    while true; do
        clear 2>/dev/null || true
        print_header "SFTP: ${target}" "Текущий каталог: ${cur_path}"

        echo -e "${CYAN}Содержимое каталога:${NC}"
        ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}" \
            "ls -la --color=never '${cur_path}' 2>/dev/null | head -n 25 || echo 'Нет доступа к каталогу.'"
        echo ""

        echo "  1. Перейти в другой каталог"
        echo "  2. Просмотреть текстовый файл / лог"
        echo "  3. Скачать файл на телефон (~/downloads/)"
        echo "  4. Загрузить локальный файл на сервер"
        echo "  5. Открыть интерактивную сессию SFTP"
        echo ""
        echo "  0. Назад к выбору серверов"
        print_divider
        read -rp "Выберите действие [0–5]: " action

        case "${action}" in
            1)
                read -rp "Введите путь (например, /opt, /var/log, /root): " new_p
                [[ -n "${new_p}" ]] && cur_path="${new_p}"
                ;;
            2)
                read -rp "Имя файла в ${cur_path} (или полный путь): " fname
                if [[ -n "${fname}" ]]; then
                    [[ "${fname}" != /* ]] && fname="${cur_path}/${fname}"
                    clear 2>/dev/null || true
                    print_header "ПРОСМОТР: ${fname}"
                    ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}" \
                        "head -n 50 '${fname}' 2>/dev/null || cat '${fname}' 2>/dev/null || echo 'Не удалось прочитать файл.'"
                    press_enter
                fi
                ;;
            3)
                read -rp "Путь к удалённому файлу для скачивания: " r_file
                if [[ -n "${r_file}" ]]; then
                    [[ "${r_file}" != /* ]] && r_file="${cur_path}/${r_file}"
                    local dl_dir="${HOME}/downloads"
                    mkdir -p "${dl_dir}"
                    echo -e "\n${CYAN}Скачивание в ${dl_dir}...${NC}"
                    if scp -F "${CONFIG_FILE}" "${target}:${r_file}" "${dl_dir}/"; then
                        echo -e "${GREEN}✓ Файл успешно сохранён в ${dl_dir}/$(basename "${r_file}")${NC}"
                    else
                        echo -e "${RED}✗ Ошибка при скачивании файла.${NC}"
                    fi
                    press_enter
                fi
                ;;
            4)
                read -rp "Путь к локальному файлу на телефоне: " l_file
                read -rp "Путь назначения на VPS [${cur_path}]: " r_dest
                r_dest="${r_dest:-${cur_path}}"
                if [[ -n "${l_file}" && -f "${l_file}" ]]; then
                    echo -e "\n${CYAN}Загрузка ${l_file} на ${target}:${r_dest}...${NC}"
                    if scp -F "${CONFIG_FILE}" "${l_file}" "${target}:${r_dest}"; then
                        echo -e "${GREEN}✓ Файл успешно загружен на VPS.${NC}"
                    else
                        echo -e "${RED}✗ Ошибка при загрузке файла.${NC}"
                    fi
                else
                    echo -e "${RED}Локальный файл не найден.${NC}"
                fi
                press_enter
                ;;
            5)
                clear 2>/dev/null || true
                echo -e "${GREEN}Запуск консоли SFTP для ${target}...${NC}\n"
                sftp -F "${CONFIG_FILE}" "${target}" || true
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

vps_sftp_main() {
    while true; do
        clear 2>/dev/null || true
        echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
        echo -e "${BOLD}              SFTP FILE MANAGER                     ${NC}"
        echo -e "${DIM}     Управление файлами и логами на серверах        ${NC}"
        echo -e "${BLUE}════════════════════════════════════════════════════${NC}\n"

        local s_alias
        s_alias=$(prompt_select_server "Выберите сервер для работы с файлами")
        if [[ -z "${s_alias}" ]]; then
            return
        fi

        sftp_browse_server "${s_alias}"
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    vps_sftp_main "$@"
fi
