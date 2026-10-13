#!/usr/bin/env bash
# ==============================================================================
# Android VPS Toolkit — Интерактивный установщик с проверкой окружения
# Автопроверка зависимостей • Доступ к памяти • Автопоиск и восстановление бэкапов
# Репозиторий: https://github.com/iurievi4/android
# ==============================================================================

set -uo pipefail

# Цветовая палитра
if [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'
    CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; MAGENTA=''; BOLD=''; DIM=''; NC=''
fi

# Определение типа окружения: Termux vs Linux
IS_TERMUX=0
if [[ -n "${PREFIX:-}" && -d "${PREFIX}" ]]; then
    IS_TERMUX=1
    BIN_DIR="${PREFIX}/bin"
    OPT_DIR="${PREFIX}/opt/vps-toolkit"
elif [[ $(id -u) -eq 0 ]]; then
    BIN_DIR="/usr/local/bin"
    OPT_DIR="/opt/vps-toolkit"
else
    BIN_DIR="${HOME}/.local/bin"
    OPT_DIR="${HOME}/.vps-toolkit"
fi

clear 2>/dev/null || true
echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}       УСТАНОВКА ANDROID VPS TOOLKIT               ${NC}"
echo -e "${DIM}  Мобильный пульт администрирования Linux VPS и SSH  ${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════${NC}\n"

# ------------------------------------------------------------------------------
# 1. ПРОВЕРКА И УСТАНОВКА ЗАВИСИМОСТЕЙ (PRE-FLIGHT CHECK)
# ------------------------------------------------------------------------------
echo -e "${BOLD}Шаг 1/4. Проверка необходимых приложений и утилит:${NC}\n"

missing_core=()
missing_optional=()

# Проверка curl
if command -v curl >/dev/null 2>&1; then
    echo -e "  [${GREEN}✓${NC}] curl           ${DIM}(найден: $(curl --version 2>/dev/null | head -n1 | awk '{print $2}' || echo 'OK'))${NC}"
else
    echo -e "  [${RED}✗${NC}] curl           ${RED}НЕ НАЙДЕН (обязательно для загрузки)${NC}"
    missing_core+=("curl")
fi

# Проверка openssh / ssh
if command -v ssh >/dev/null 2>&1; then
    echo -e "  [${GREEN}✓${NC}] openssh (ssh)  ${DIM}(найден: $(ssh -V 2>&1 | awk '{print $1}' || echo 'OK'))${NC}"
else
    echo -e "  [${RED}✗${NC}] openssh (ssh)  ${RED}НЕ НАЙДЕН (обязательно для подключения)${NC}"
    missing_core+=("openssh")
fi

# Проверка openssl
if command -v openssl >/dev/null 2>&1; then
    echo -e "  [${GREEN}✓${NC}] openssl        ${DIM}(найден: шифрование AES-256 готово)${NC}"
else
    echo -e "  [${YELLOW}!${NC}] openssl        ${YELLOW}НЕ НАЙДЕН (нужен для защищённых бэкапов)${NC}"
    missing_core+=("openssl")
fi

# Проверка tar
if command -v tar >/dev/null 2>&1; then
    echo -e "  [${GREEN}✓${NC}] tar            ${DIM}(найден)${NC}"
else
    echo -e "  [${RED}✗${NC}] tar            ${RED}НЕ НАЙДЕН (нужен для архивов)${NC}"
    missing_core+=("tar")
fi

# Проверка опциональных утилит
if [[ $IS_TERMUX -eq 1 ]]; then
    if command -v termux-clipboard-set >/dev/null 2>&1; then
        echo -e "  [${GREEN}✓${NC}] termux-api     ${DIM}(найден: буфер обмена Android активен)${NC}"
    else
        echo -e "  [${DIM}–${NC}] termux-api     ${DIM}(опционально: копирование ключей в буфер)${NC}"
        missing_optional+=("termux-api")
    fi
fi

if command -v traceroute >/dev/null 2>&1; then
    echo -e "  [${GREEN}✓${NC}] traceroute     ${DIM}(найден: трассировка NetDiag)${NC}"
else
    echo -e "  [${DIM}–${NC}] traceroute     ${DIM}(опционально: нужен для трассировки сети)${NC}"
    missing_optional+=("traceroute")
fi

echo -e "\n${BLUE}────────────────────────────────────────────────────${NC}"

# Автоматическая доустановка недостающих пакетов
all_to_install=("${missing_core[@]}" "${missing_optional[@]}")

if [[ ${#all_to_install[@]} -gt 0 ]]; then
    echo -e "${YELLOW}Обнаружены отсутствующие пакеты: ${BOLD}${all_to_install[*]}${NC}"
    
    if [[ $IS_TERMUX -eq 1 ]]; then
        echo -e "В Termux они могут быть установлены автоматически через пакетный менеджер pkg."
        read -rp "Установить недостающие пакеты сейчас? [Y/n]: " ans_pkg
        ans_pkg="${ans_pkg:-Y}"
        if [[ "${ans_pkg}" =~ ^[YyДд]$ ]]; then
            echo -e "\n${CYAN}-> Обновление репозиториев Termux (pkg update)...${NC}"
            pkg update -y || apt-get update -y || true
            echo -e "\n${CYAN}-> Установка ${all_to_install[*]}...${NC}"
            pkg install -y "${all_to_install[@]}" || apt-get install -y "${all_to_install[@]}" || true
            echo -e "${GREEN}✓ Пакеты установлены.${NC}\n"
        fi
    else
        # Linux (Ubuntu / Debian)
        if [[ ${#missing_core[@]} -gt 0 ]]; then
            echo -e "${YELLOW}Для работы требуются: ${missing_core[*]}.${NC}"
            read -rp "Попытаться установить через apt? [Y/n]: " ans_apt
            ans_apt="${ans_apt:-Y}"
            if [[ "${ans_apt}" =~ ^[Yy]$ ]]; then
                sudo_prefix=""
                [[ $(id -u) -ne 0 ]] && sudo_prefix="sudo"
                $sudo_prefix apt-get update -y && $sudo_prefix apt-get install -y "${all_to_install[@]}" || true
            fi
        fi
    fi
else
    echo -e "${GREEN}✓ Все необходимые системные утилиты установлены и готовы к работе.${NC}\n"
fi

# ------------------------------------------------------------------------------
# 2. ПРОВЕРКА ДОСТУПА К ПАМЯТИ ТЕЛЕФОНА (ДЛЯ TERMUX)
# ------------------------------------------------------------------------------
if [[ $IS_TERMUX -eq 1 ]]; then
    echo -e "${BOLD}Шаг 2/4. Доступ к памяти телефона Android:${NC}"
    if [[ -d "${HOME}/storage/shared" ]]; then
        echo -e "  [${GREEN}✓${NC}] Доступ к памяти телефона уже предоставлен (${HOME}/storage/shared).\n"
    else
        echo -e "  [${YELLOW}!${NC}] Доступ к памяти телефона ещё не настроен."
        echo -e "      (Необходим для сохранения и восстановления бэкапов из папки «Загрузки»)."
        read -rp "Запросить доступ к памяти (termux-setup-storage)? [Y/n]: " ans_st
        ans_st="${ans_st:-Y}"
        if [[ "${ans_st}" =~ ^[YyДд]$ ]]; then
            echo -e "\n${CYAN}-> Запрос системного разрешения Android...${NC}"
            echo -e "${YELLOW}Внимание: нажмите «Разрешить» в появившемся окне Android!${NC}"
            termux-setup-storage 2>/dev/null || true
            sleep 1.5
            echo -e "${GREEN}✓ Запрос отправлен.${NC}\n"
        fi
    fi
else
    echo -e "${BOLD}Шаг 2/4. Настройка путей установки Linux:${NC}"
    echo -e "  Каталог программы: ${CYAN}${OPT_DIR}${NC}"
    echo -e "  Исполняемые файлы: ${CYAN}${BIN_DIR}${NC}\n"
fi

# ------------------------------------------------------------------------------
# 3. ПРОВЕРКА ПАПКИ БЭКАПОВ НА ТЕЛЕФОНЕ И ПРЕДЛОЖЕНИЕ ВОССТАНОВЛЕНИЯ
# ------------------------------------------------------------------------------
echo -e "${BOLD}Шаг 3/4. Проверка папки для бэкапов на телефоне:${NC}"

BACKUP_SEARCH_DIR=""
if [[ $IS_TERMUX -eq 1 ]]; then
    if [[ -d "${HOME}/storage/shared/Download" ]]; then
        BACKUP_SEARCH_DIR="${HOME}/storage/shared/Download"
    elif [[ -d "/storage/emulated/0/Download" && -r "/storage/emulated/0/Download" ]]; then
        BACKUP_SEARCH_DIR="/storage/emulated/0/Download"
    elif [[ -d "/sdcard/Download" && -r "/sdcard/Download" ]]; then
        BACKUP_SEARCH_DIR="/sdcard/Download"
    fi
else
    BACKUP_SEARCH_DIR="${HOME}/Downloads"
    [[ ! -d "${BACKUP_SEARCH_DIR}" ]] && BACKUP_SEARCH_DIR="${HOME}"
fi

echo -e "  Папка бэкапов:  ${CYAN}${BACKUP_SEARCH_DIR:-${HOME}/storage/shared/Download}${NC}"
echo -e "  Права доступа:  ${DIM}Только к этой папке для импорта/экспорта бэкапов${NC}"
echo -e "  Поддерживаемые расширения файлов:"
echo -e "    • ${BOLD}*.enc${NC}            — Зашифрованный сейф (Серверы + Приватные ключи)"
echo -e "    • ${BOLD}*.bak${NC} (config-*.bak) — Простая копия (Только файл настроек серверов)\n"

# Функция определения типа бэкапа
detect_b_type() {
    local f="$1"
    local head_bytes
    head_bytes=$(head -c 8 "$f" 2>/dev/null || true)
    if [[ "${head_bytes}" == "Salted__" || "$f" == *.enc ]]; then
        echo "ENC"
    elif grep -qE "^[[:space:]]*Host[[:space:]]+" "$f" 2>/dev/null; then
        echo "PLAIN"
    else
        echo "UNKNOWN"
    fi
}

found_backups=()
if [[ -n "${BACKUP_SEARCH_DIR}" && -d "${BACKUP_SEARCH_DIR}" ]]; then
    while IFS= read -r bf; do
        [[ -n "$bf" && -f "$bf" ]] && found_backups+=("$bf")
    done < <(find "${BACKUP_SEARCH_DIR}" -maxdepth 2 \( -name "*.enc" -o -name "*.bak" -o -name "config.backup-*" -o -name "vps-vault-*" \) 2>/dev/null | sort -u)
fi

if [[ ${#found_backups[@]} -gt 0 ]]; then
    echo -e "${YELLOW}Обнаружены существующие резервные копии в папке Загрузок:${NC}\n"
    for (( b_i=0; b_i<${#found_backups[@]}; b_i++ )); do
        b_file="${found_backups[$b_i]}"
        b_type=$(detect_b_type "${b_file}")
        b_size=$(wc -c < "${b_file}" 2>/dev/null || echo "0")
        
        if [[ "${b_type}" == "ENC" ]]; then
            type_label="${MAGENTA}[ЗАШИФРОВАН: AES-256 + Ключи]${NC}"
        elif [[ "${b_type}" == "PLAIN" ]]; then
            type_label="${CYAN}[НЕ ЗАШИФРОВАН: Только config]${NC}"
        else
            type_label="${DIM}[Неизвестный формат]${NC}"
        fi
        
        printf "  %2d. %-32s %b ${DIM}(%s Б)${NC}\n" "$((b_i+1))" "$(basename "${b_file}")" "${type_label}" "${b_size}"
    done
    echo ""
    read -rp "Восстановить серверы и ключи из найденного бэкапа сейчас? [Y/n]: " ans_rest
    ans_rest="${ans_rest:-Y}"
    
    if [[ "${ans_rest}" =~ ^[YyДд]$ ]]; then
        chosen_b=""
        if [[ ${#found_backups[@]} -eq 1 ]]; then
            chosen_b="${found_backups[0]}"
        else
            read -rp "Выберите номер файла [1-${#found_backups[@]}]: " b_num
            if [[ "${b_num}" =~ ^[0-9]+$ ]] && (( b_num >= 1 && b_num <= ${#found_backups[@]} )); then
                chosen_b="${found_backups[$((b_num-1))]}"
            fi
        fi

        if [[ -n "${chosen_b}" && -f "${chosen_b}" ]]; then
            b_type=$(detect_b_type "${chosen_b}")
            mkdir -p "${HOME}/.ssh"
            chmod 700 "${HOME}/.ssh"

            if [[ "${b_type}" == "ENC" ]]; then
                echo -e "\n${CYAN}Файл зашифрован (AES-256). Введите пароль для расшифровки:${NC}"
                read -s -rp "Пароль: " pass_dec
                echo ""

                tmp_dec=$(mktemp -d 2>/dev/null || mktemp -d -t 'vps-dec-XXXXXX')
                if openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 -pass pass:"${pass_dec}" -in "${chosen_b}" 2>/dev/null | tar -xzf - -C "${tmp_dec}" 2>/dev/null; then
                    cp -rf "${tmp_dec}"/* "${HOME}/.ssh/"
                    rm -rf "${tmp_dec}"

                    # Автоматическая установка правильных прав доступа Linux
                    chmod 700 "${HOME}/.ssh"
                    chmod 600 "${HOME}/.ssh/config" 2>/dev/null || true
                    chmod 600 "${HOME}/.ssh/known_hosts" 2>/dev/null || true
                    for priv in "${HOME}/.ssh"/id_* "${HOME}/.ssh"/*.key; do
                        [[ -f "$priv" && "$priv" != *.pub ]] && chmod 600 "$priv"
                    done
                    for pub in "${HOME}/.ssh"/*.pub; do
                        [[ -f "$pub" ]] && chmod 644 "$pub"
                    done
                    echo -e "${GREEN}✓ Серверы и приватные ключи успешно расшифрованы и установлены в ~/.ssh!${NC}\n"
                else
                    echo -e "${RED}✗ Ошибка: неверный пароль или повреждённый файл. Пропуск восстановления.${NC}\n"
                    rm -rf "${tmp_dec}"
                fi
            elif [[ "${b_type}" == "PLAIN" ]]; then
                cp -f "${chosen_b}" "${HOME}/.ssh/config"
                chmod 600 "${HOME}/.ssh/config"
                echo -e "${GREEN}✓ Файл config успешно скопирован в ~/.ssh/config!${NC}\n"
            fi
        fi
    else
        echo -e "${DIM}Пропуск восстановления. Будет настроено чистое окружение.${NC}\n"
    fi
else
    echo -e "  [i] Бэкапов в папке Загрузок не найдено. Создаётся чистое окружение.\n"
fi

# ------------------------------------------------------------------------------
# 4. ЗАГРУЗКА И РАЗВЁРТЫВАНИЕ КОМПОНЕНТОВ
# ------------------------------------------------------------------------------
echo -e "${BOLD}Шаг 4/4. Развёртывание компонентов VPS Toolkit:${NC}\n"

mkdir -p "${BIN_DIR}" "${OPT_DIR}/lib" "${OPT_DIR}/modules"

SCRIPT_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "")"
fi

if [[ -n "${SCRIPT_DIR}" && -f "${SCRIPT_DIR}/vps-toolkit.sh" ]]; then
    # Локальная установка
    echo -e "Копирование компонентов из локальной папки..."
    cp -rf "${SCRIPT_DIR}/vps-toolkit.sh" "${OPT_DIR}/"
    cp -rf "${SCRIPT_DIR}/ssh-manager.sh" "${OPT_DIR}/"
    [[ -d "${SCRIPT_DIR}/lib" ]] && cp -rf "${SCRIPT_DIR}/lib/"* "${OPT_DIR}/lib/"
    [[ -d "${SCRIPT_DIR}/modules" ]] && cp -rf "${SCRIPT_DIR}/modules/"* "${OPT_DIR}/modules/"
    echo -e "${GREEN}✓ Локальные компоненты скопированы.${NC}"
else
    # Сетевая установка через curl
    GITHUB_USER="${1:-${GITHUB_USER:-"iurievi4"}}"
    REPO_NAME="android"
    BRANCH="main"
    RAW_BASE="https://raw.githubusercontent.com/${GITHUB_USER}/${REPO_NAME}/${BRANCH}/vps-toolkit"
    RAW_BASE_ROOT="https://raw.githubusercontent.com/${GITHUB_USER}/${REPO_NAME}/${BRANCH}"

    echo -e "Загрузка компонентов из репозитория ${CYAN}${GITHUB_USER}/${REPO_NAME}${NC}...\n"

    all_files=(
        "vps-toolkit.sh"
        "ssh-manager.sh"
        "lib/common.sh"
        "modules/vps-monitor.sh"
        "modules/vps-sftp.sh"
        "modules/vps-security.sh"
        "modules/net-diag.sh"
        "modules/backup-manager.sh"
        "modules/docker-manager.sh"
        "modules/service-manager.sh"
        "modules/log-viewer.sh"
        "modules/port-scanner.sh"
        "modules/git-deploy.sh"
        "modules/termux-maintenance.sh"
        "modules/ssh-key-manager.sh"
        "modules/quick-commands.sh"
    )

    total_f=${#all_files[@]}
    success_cnt=0

    for (( i=0; i<total_f; i++ )); do
        rel_f="${all_files[$i]}"
        dest_f="${OPT_DIR}/${rel_f}"
        mkdir -p "$(dirname "${dest_f}")"
        printf "  [%2d/%d] %-30s ... " "$((i+1))" "${total_f}" "${rel_f}"

        url1="${RAW_BASE}/${rel_f}?$(date +%s)"
        url2="${RAW_BASE_ROOT}/${rel_f}?$(date +%s)"
        if curl -fsSL -H "Cache-Control: no-cache" "${url1}" -o "${dest_f}" 2>/dev/null || \
           curl -fsSL -H "Cache-Control: no-cache" "${url2}" -o "${dest_f}" 2>/dev/null; then
            chmod +x "${dest_f}" 2>/dev/null || true
            echo -e "${GREEN}OK${NC}"
            success_cnt=$((success_cnt + 1))
        else
            echo -e "${RED}ОШИБКА${NC}"
        fi
    done
fi

chmod +x "${OPT_DIR}/vps-toolkit.sh" "${OPT_DIR}/ssh-manager.sh" 2>/dev/null || true
chmod +x "${OPT_DIR}/modules/"*.sh "${OPT_DIR}/lib/"*.sh 2>/dev/null || true

# Создание симлинков в BIN_DIR
ln -sf "${OPT_DIR}/vps-toolkit.sh" "${BIN_DIR}/vps-toolkit" 2>/dev/null || cp -f "${OPT_DIR}/vps-toolkit.sh" "${BIN_DIR}/vps-toolkit" 2>/dev/null || true
ln -sf "${OPT_DIR}/vps-toolkit.sh" "${BIN_DIR}/vps" 2>/dev/null || cp -f "${OPT_DIR}/vps-toolkit.sh" "${BIN_DIR}/vps" 2>/dev/null || true
ln -sf "${OPT_DIR}/ssh-manager.sh" "${BIN_DIR}/ssh-manager" 2>/dev/null || cp -f "${OPT_DIR}/ssh-manager.sh" "${BIN_DIR}/ssh-manager" 2>/dev/null || true
ln -sf "${OPT_DIR}/modules/vps-monitor.sh" "${BIN_DIR}/vps-monitor" 2>/dev/null || true
ln -sf "${OPT_DIR}/modules/net-diag.sh" "${BIN_DIR}/netdiag" 2>/dev/null || true

hash -r 2>/dev/null || true

# Проверка PATH для Ubuntu/Linux (~/.local/bin)
if [[ "${BIN_DIR}" == "${HOME}/.local/bin" && ":$PATH:" != *":${HOME}/.local/bin:"* ]]; then
    export PATH="${HOME}/.local/bin:${PATH}"
    if [[ -f "${HOME}/.bashrc" ]] && ! grep -q '\.local/bin' "${HOME}/.bashrc"; then
        echo 'export PATH="${HOME}/.local/bin:${PATH}"' >> "${HOME}/.bashrc"
    fi
fi

echo -e "\n${BLUE}════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}      УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА! 🎉               ${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
echo -e "  Каталог модулей:  ${CYAN}${OPT_DIR}${NC}"
echo -e "  Путь к командам:  ${CYAN}${BIN_DIR}${NC}\n"
echo -e "  ${BOLD}Команды для запуска:${NC}"
echo -e "    ${GREEN}vps${NC}          — Главный пульт (меню со всеми 14 модулями)"
echo -e "    ${GREEN}ssh-manager${NC}  — VPS Control Center (управление серверами)"
echo -e "    ${CYAN}vps-monitor${NC}  — Сводный онлайн-мониторинг всех VPS"
echo -e "    ${CYAN}netdiag${NC}      — Сетевая диагностика (Ping, DNS, TCP, SSL)"
echo -e "${BLUE}════════════════════════════════════════════════════${NC}\n"
