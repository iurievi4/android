#!/usr/bin/env bash
# ==============================================================================
# Android VPS Toolkit — Git Deploy (modules/git-deploy.sh)
# Управление Git-репозиториями на сервере: pull, статус, бэкап, лог
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

git_deploy_server() {
    local target="$1"
    read -rp "Путь к Git-проекту на сервере (например, /opt/my-project или ~/app): " repo_path
    if [[ -z "${repo_path}" ]]; then return; fi

    while true; do
        clear 2>/dev/null || true
        print_header "GIT DEPLOY: ${target}" "Каталог: ${repo_path}"

        echo "  1. Проверить статус репозитория (git status)"
        echo "  2. Просмотреть последние 5 коммитов (git log)"
        echo "  3. Загрузить обновления (git pull) со страховочным бэкапом"
        echo "  4. Просмотреть незакоммиченные изменения (git diff)"
        echo "  5. Откатить локальные изменения (git restore / reset)"
        echo ""
        echo "  0. Назад к выбору сервера"
        print_divider
        read -rp "Выберите действие [0–5]: " act

        case "${act}" in
            1)
                print_header "GIT STATUS: ${repo_path}"
                ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}"                     "cd '${repo_path}' 2>/dev/null && git status || echo 'Ошибка: каталог не найден или не является git репозиторием.'"
                press_enter
                ;;
            2)
                print_header "ПОСЛЕДНИЕ КОММИТЫ: ${repo_path}"
                ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}"                     "cd '${repo_path}' 2>/dev/null && git log -n 5 --oneline --decorate || true"
                press_enter
                ;;
            3)
                print_header "PULL ОБНОВЛЕНИЙ: ${repo_path}"
                read -rp "Создать страховочный tar.gz архив перед обновлением? (Y/n): " do_bk
                if [[ ! "${do_bk}" =~ ^[Nn]$ ]]; then
                    ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}"                         "tar -czf '${repo_path}.pre-deploy-\$(date +%s).tar.gz' -C '${repo_path}' . 2>/dev/null" || echo "Не удалось создать бэкап."
                fi
                echo -e "\n${CYAN}Выполнение git pull...${NC}"
                ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}"                     "cd '${repo_path}' 2>/dev/null && git pull" || echo -e "${RED}Ошибка pull.${NC}"
                press_enter
                ;;
            4)
                print_header "GIT DIFF: ${repo_path}"
                ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}"                     "cd '${repo_path}' 2>/dev/null && git diff" || true
                press_enter
                ;;
            5)
                read -rp "Откатить все незакоммиченные изменения в ${repo_path}? (y/N): " conf_rst
                if [[ "${conf_rst}" =~ ^[Yy]$ ]]; then
                    ssh -F "${CONFIG_FILE}" -o BatchMode=yes -o ConnectTimeout="${CONN_TIMEOUT}" "${target}"                         "cd '${repo_path}' 2>/dev/null && git reset --hard HEAD" && echo -e "${GREEN}✓ Изменения сброшены.${NC}" || echo "Ошибка."
                    press_enter
                fi
                ;;
            0|[qQ]) return ;;
            *) echo -e "${RED}Неверный ввод.${NC}"; sleep 1 ;;
        esac
    done
}

git_deploy_main() {
    while true; do
        clear 2>/dev/null || true
        echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
        echo -e "${BOLD}                  GIT DEPLOY                        ${NC}"
        echo -e "${DIM}      Обновление проектов на удалённых серверах     ${NC}"
        echo -e "${BLUE}════════════════════════════════════════════════════${NC}\n"

        local s_alias
        s_alias=$(prompt_select_server "Выберите сервер для развёртывания Git")
        [[ -z "${s_alias}" ]] && return

        git_deploy_server "${s_alias}"
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    git_deploy_main "$@"
fi
