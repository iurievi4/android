#!/usr/bin/env bash
# ==============================================================================
# Универсальный установщик Android VPS Toolkit (Termux / Linux / Ubuntu / WSL)
# Репозиторий: https://github.com/iurievi4/android
# ==============================================================================

set -euo pipefail

# Автоопределение окружения: Termux vs Linux Root vs Linux User
if [[ -n "${PREFIX:-}" && -d "${PREFIX}" ]]; then
    # Среда Termux (Android)
    BIN_DIR="${PREFIX}/bin"
    OPT_DIR="${PREFIX}/opt/vps-toolkit"
elif [[ $(id -u) -eq 0 ]]; then
    # Linux c правами root (sudo)
    BIN_DIR="/usr/local/bin"
    OPT_DIR="/opt/vps-toolkit"
else
    # Linux обычный пользователь (Ubuntu / Debian / WSL без root)
    BIN_DIR="${HOME}/.local/bin"
    OPT_DIR="${HOME}/.vps-toolkit"
fi

mkdir -p "${BIN_DIR}" "${OPT_DIR}/lib" "${OPT_DIR}/modules"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "")"

echo "Установка Android VPS Toolkit..."
echo "Каталог установки: ${OPT_DIR}"
echo "Бинарные файлы:    ${BIN_DIR}"

if [[ -n "${SCRIPT_DIR}" && -f "${SCRIPT_DIR}/vps-toolkit.sh" ]]; then
    # Локальная установка из папки / архива
    cp -rf "${SCRIPT_DIR}/vps-toolkit.sh" "${OPT_DIR}/"
    cp -rf "${SCRIPT_DIR}/ssh-manager.sh" "${OPT_DIR}/"
    [[ -d "${SCRIPT_DIR}/lib" ]] && cp -rf "${SCRIPT_DIR}/lib/"* "${OPT_DIR}/lib/"
    [[ -d "${SCRIPT_DIR}/modules" ]] && cp -rf "${SCRIPT_DIR}/modules/"* "${OPT_DIR}/modules/"
else
    # Сетевая установка через curl
    GITHUB_USER="${1:-${GITHUB_USER:-"iurievi4"}}"
    REPO_NAME="android"
    BRANCH="main"
    RAW_BASE="https://raw.githubusercontent.com/${GITHUB_USER}/${REPO_NAME}/${BRANCH}/vps-toolkit"
    RAW_BASE_ROOT="https://raw.githubusercontent.com/${GITHUB_USER}/${REPO_NAME}/${BRANCH}"

    echo "Загрузка компонентов из https://github.com/${GITHUB_USER}/${REPO_NAME}..."

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

    for rel_f in "${all_files[@]}"; do
        dest_f="${OPT_DIR}/${rel_f}"
        mkdir -p "$(dirname "${dest_f}")"
        curl -fsSL "${RAW_BASE}/${rel_f}?$(date +%s)" -o "${dest_f}" 2>/dev/null || \
        curl -fsSL "${RAW_BASE_ROOT}/${rel_f}?$(date +%s)" -o "${dest_f}" 2>/dev/null || true
    done
fi

chmod +x "${OPT_DIR}/vps-toolkit.sh" "${OPT_DIR}/ssh-manager.sh" 2>/dev/null || true
chmod +x "${OPT_DIR}/modules/"*.sh "${OPT_DIR}/lib/"*.sh 2>/dev/null || true

# Создание симлинков в BIN_DIR
ln -sf "${OPT_DIR}/vps-toolkit.sh" "${BIN_DIR}/vps-toolkit" 2>/dev/null || cp -f "${OPT_DIR}/vps-toolkit.sh" "${BIN_DIR}/vps-toolkit"
ln -sf "${OPT_DIR}/vps-toolkit.sh" "${BIN_DIR}/vps" 2>/dev/null || cp -f "${OPT_DIR}/vps-toolkit.sh" "${BIN_DIR}/vps"
ln -sf "${OPT_DIR}/ssh-manager.sh" "${BIN_DIR}/ssh-manager" 2>/dev/null || cp -f "${OPT_DIR}/ssh-manager.sh" "${BIN_DIR}/ssh-manager"

hash -r 2>/dev/null || true

# Если установлена в ~/.local/bin, проверяем наличие в PATH
if [[ "${BIN_DIR}" == "${HOME}/.local/bin" && ":$PATH:" != *":${HOME}/.local/bin:"* ]]; then
    export PATH="${HOME}/.local/bin:${PATH}"
    echo 'export PATH="${HOME}/.local/bin:${PATH}"' >> "${HOME}/.bashrc"
fi

echo "===================================================="
echo " Android VPS Toolkit успешно установлен!"
echo " Запуск:"
echo "   vps         (или vps-toolkit)"
echo "   ssh-manager"
echo "===================================================="
