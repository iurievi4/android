#!/usr/bin/env bash
# ==============================================================================
# Android VPS Toolkit — Backup Manager (modules/backup-manager.sh)
# Резервные копии конфигураций, метаданные .meta, проверка целостности и откат
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

backup_manager_create() {
    print_header "СОЗДАНИЕ РЕЗЕРВНОЙ КОПИИ"
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        echo -e "${YELLOW}Файл конфигурации ~/.ssh/config не найден.${NC}"
        press_enter; return
    fi

    mkdir -p "${BACKUP_DIR}"
    chmod 700 "${BACKUP_DIR}" 2>/dev/null || true

    local ts bname bfile mfile
    ts=$(date +"%Y-%m-%d-%H%M%S")
    bname="config.backup-${ts}"
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

    echo -e "${GREEN}✓ Резервная копия успешно создана:${NC}"
    echo -e "  Файл:   ${BOLD}${bfile}${NC}"
    echo -e "  Размер: ${size} байт"
    echo -e "  SHA256: ${DIM}${sha}${NC}"
    echo -e "  Хостов: ${host_cnt} (${hosts_list:-нет})"
    press_enter
}

backup_manager_list() {
    print_header "СПИСОК РЕЗЕРВНЫХ КОПИЙ"
    mkdir -p "${BACKUP_DIR}"
    local b_files=()
    while IFS= read -r f; do [[ -n "$f" ]] && b_files+=("$f"); done < <(find "${BACKUP_DIR}" -maxdepth 1 -name "config.backup-*" ! -name "*.meta" 2>/dev/null | sort -r)

    if [[ ${#b_files[@]} -eq 0 ]]; then
        echo -e "${YELLOW}Резервных копий пока нет.${NC}"
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

backup_manager_restore() {
    print_header "ВОССТАНОВЛЕНИЕ КОНФИГУРАЦИИ"
    local b_files=()
    while IFS= read -r f; do [[ -n "$f" ]] && b_files+=("$f"); done < <(find "${BACKUP_DIR}" -maxdepth 1 -name "config.backup-*" ! -name "*.meta" 2>/dev/null | sort -r)

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
    read -rp "Выберите номер для восстановления: " b_idx

    [[ "${b_idx}" == "0" || -z "${b_idx}" ]] && return
    if [[ ! "${b_idx}" =~ ^[0-9]+$ ]] || (( b_idx < 1 || b_idx > ${#b_files[@]} )); then
        echo -e "${RED}Неверный номер.${NC}"; sleep 1; return
    fi

    local chosen="${b_files[$((b_idx-1))]}"
    local mfile="${chosen}.meta"

    if [[ -f "${mfile}" ]]; then
        local expected_sha current_sha
        expected_sha=$(grep "^SHA256=" "${mfile}" 2>/dev/null | cut -d= -f2 || true)
        current_sha=$(sha256sum "${chosen}" 2>/dev/null | awk '{print $1}' || true)
        if [[ -n "${expected_sha}" && "${expected_sha}" != "${current_sha}" ]]; then
            echo -e "${RED}ВНИМАНИЕ! Контрольная сумма не совпадает.${NC}"
            read -rp "Всё равно восстановить? (y/N): " force_res
            [[ ! "${force_res}" =~ ^[Yy]$ ]] && return
        fi
    fi

    read -rp "Заменить текущий ~/.ssh/config выбранной копией? (y/N): " confirm_res
    if [[ "${confirm_res}" =~ ^[Yy]$ ]]; then
        cp "${CONFIG_FILE}" "${CONFIG_FILE}.pre-restore-$(date +%s)" 2>/dev/null || true
        cp -f "${chosen}" "${CONFIG_FILE}"
        chmod 600 "${CONFIG_FILE}"
        echo -e "${GREEN}✓ Конфигурация успешно восстановлена из $(basename "${chosen}").${NC}"
    else
        echo "Восстановление отменено."
    fi
    press_enter
}

backup_manager_main() {
    while true; do
        clear 2>/dev/null || true
        echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
        echo -e "${BOLD}                 BACKUP MANAGER                     ${NC}"
        echo -e "${DIM}      Резервные копии конфигураций SSH и метаданные ${NC}"
        echo -e "${BLUE}════════════════════════════════════════════════════${NC}\n"

        echo "  1. Создать резервную копию сейчас"
        echo "  2. Просмотреть список существующих бэкапов"
        echo "  3. Восстановить конфигурацию из копии"
        echo "  4. Очистить старые бэкапы (старше 14 дней)"
        echo ""
        echo "  0. Назад в главное меню"
        echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
        read -rp "Выберите действие [0–4]: " choice

        case "${choice}" in
            1) backup_manager_create ;;
            2) backup_manager_list ;;
            3) backup_manager_restore ;;
            4)
                print_header "РОТАЦИЯ БЭКАПОВ"
                find "${BACKUP_DIR}" -name "config.backup-*" -mtime +14 -delete 2>/dev/null || true
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
