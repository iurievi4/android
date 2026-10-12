#!/usr/bin/env bash
# ==============================================================================
# Установщик Android VPS Toolkit для Termux
# Репозиторий: https://github.com/iurievi4/android
# ==============================================================================

set -euo pipefail

BIN_DIR="${PREFIX:-/usr/local}/bin"
OPT_DIR="${PREFIX:-/data/data/com.termux/files/usr}/opt/vps-toolkit"
[[ ! -d "${PREFIX:-}" ]] && OPT_DIR="${HOME}/.vps-toolkit"

mkdir -p "${BIN_DIR}" "${OPT_DIR}/lib" "${OPT_DIR}/modules"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "")"

echo "Установка Android VPS Toolkit..."

if [[ -n "${SCRIPT_DIR}" && -f "${SCRIPT_DIR}/vps-toolkit.sh" ]]; then
    # Локальная установка из архива или папки
    cp -rf "${SCRIPT_DIR}/vps-toolkit.sh" "${OPT_DIR}/"
    cp -rf "${SCRIPT_DIR}/ssh-manager.sh" "${OPT_DIR}/"
    cp -rf "${SCRIPT_DIR}/lib/"* "${OPT_DIR}/lib/"
    cp -rf "${SCRIPT_DIR}/modules/"* "${OPT_DIR}/modules/"
else
    # Сетевая загрузка
    GITHUB_USER="${1:-${GITHUB_USER:-"iurievi4"}}"
    REPO_NAME="android"
    BRANCH="main"
    RAW_BASE="https://raw.githubusercontent.com/${GITHUB_USER}/${REPO_NAME}/${BRANCH}"

    echo "Загрузка компонентов из репозитория ${GITHUB_USER}/${REPO_NAME}..."
    curl -fsSL "${RAW_BASE}/vps-toolkit.sh" -o "${OPT_DIR}/vps-toolkit.sh"
    curl -fsSL "${RAW_BASE}/ssh-manager.sh" -o "${OPT_DIR}/ssh-manager.sh"
    curl -fsSL "${RAW_BASE}/lib/common.sh" -o "${OPT_DIR}/lib/common.sh"
    curl -fsSL "${RAW_BASE}/modules/vps-monitor.sh" -o "${OPT_DIR}/modules/vps-monitor.sh"
    curl -fsSL "${RAW_BASE}/modules/net-diag.sh" -o "${OPT_DIR}/modules/net-diag.sh"
    curl -fsSL "${RAW_BASE}/modules/vps-security.sh" -o "${OPT_DIR}/modules/vps-security.sh"
    curl -fsSL "${RAW_BASE}/modules/vps-sftp.sh" -o "${OPT_DIR}/modules/vps-sftp.sh"
    curl -fsSL "${RAW_BASE}/modules/termux-maintenance.sh" -o "${OPT_DIR}/modules/termux-maintenance.sh"
fi

chmod +x "${OPT_DIR}/vps-toolkit.sh" "${OPT_DIR}/ssh-manager.sh" "${OPT_DIR}/modules/"*.sh "${OPT_DIR}/lib/"*.sh

# Создание симлинков в $PREFIX/bin для быстрого доступа
ln -sf "${OPT_DIR}/vps-toolkit.sh" "${BIN_DIR}/vps-toolkit"
ln -sf "${OPT_DIR}/vps-toolkit.sh" "${BIN_DIR}/vps"
ln -sf "${OPT_DIR}/ssh-manager.sh" "${BIN_DIR}/ssh-manager"
ln -sf "${OPT_DIR}/modules/net-diag.sh" "${BIN_DIR}/netdiag"
ln -sf "${OPT_DIR}/modules/vps-monitor.sh" "${BIN_DIR}/vps-monitor"

hash -r 2>/dev/null || true

echo "===================================================="
echo " Android VPS Toolkit успешно установлен!"
echo " Каталог файлов: ${OPT_DIR}"
echo ""
echo " Команды запуска:"
echo "   vps          — Главный пульт управления Toolkit"
echo "   vps-toolkit  — Главный пульт управления Toolkit"
echo "   ssh-manager  — Менеджер SSH-подключений и серверов"
echo "   netdiag      — Быстрая сетевая диагностика"
echo "   vps-monitor  — Мониторинг серверов онлайн"
echo "===================================================="
