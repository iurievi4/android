#!/usr/bin/env bash
# ==============================================================================
# Android VPS Toolkit — Backup Manager (modules/backup-manager.sh)
# Резервные копии: локальные бэкапы config и зашифрованный сейф (Config + Ключи)
# ==============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "")"
LIB_DIR="${SCRIPT_DIR}/../lib"
if [[ -f "${LIB_DIR}/common.sh" ]]; then
    source "${LIB_DIR}/common.sh"
else
    SSH_DIR="${HOME}/.ssh"
    CONFIG_FILE="${SSH_DIR}/config"
    BACKUP_DIR="${SSH_DIR}/backups"
    BOLD='\033[1m'; DIM='\033[2m'; RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
    print_header() { clear 2>/dev/null || true; echo -e "${BOLD}=== $1 ===${NC}\n"; }
    print_divider() { echo -e "----------------------------------------"; }
    press_enter() { read -rp "Нажмите Enter..."; }
    get_hosts() { awk '$1 ~ /^[Hh][Oo][Ss][Tt]$/ {for (i=2; i<=NF; i++) if ($i != "*") print $i}' "${CONFIG_FILE}" 2>/dev/null | sort -u; }
fi

# 1. Быстрый локальный бэкап только config
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

backup_manager_main() {
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

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    backup_manager_main "$@"
fi
