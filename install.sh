#!/usr/bin/env bash
# ==============================================================================
# Установщик Termux SSH Manager
# Поддерживает как локальный запуск (./install.sh),
# так и установку одной командой через curl:
# curl -fsSL https://raw.githubusercontent.com/<USER>/termux-ssh-manager/main/install.sh | bash
# ==============================================================================

set -euo pipefail

# Укажите ваш логин GitHub по умолчанию (или передавайте аргументом скрипта)
GITHUB_USER="${1:-${GITHUB_USER:-"YOUR_USERNAME"}}"
REPO_NAME="termux-ssh-manager"
BRANCH="main"

BIN_DIR="${PREFIX:-/usr/local}/bin"
INSTALL_PATH="${BIN_DIR}/ssh-manager"

mkdir -p "${BIN_DIR}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "")"

if [[ -n "${SCRIPT_DIR}" && -f "${SCRIPT_DIR}/ssh-manager.sh" ]]; then
    echo "Установка из локальных файлов..."
    cp -f "${SCRIPT_DIR}/ssh-manager.sh" "${INSTALL_PATH}"
else
    echo "Загрузка ssh-manager.sh из репозитория ${GITHUB_USER}/${REPO_NAME}..."
    RAW_URL="https://raw.githubusercontent.com/${GITHUB_USER}/${REPO_NAME}/${BRANCH}/ssh-manager.sh"
    curl -fsSL "${RAW_URL}" -o "${INSTALL_PATH}"
fi

chmod +x "${INSTALL_PATH}"

echo "===================================================="
echo " Termux SSH Manager успешно установлен!"
echo " Путь: ${INSTALL_PATH}"
echo " Команда для запуска: ssh-manager"
echo "===================================================="
