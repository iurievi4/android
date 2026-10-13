# Android Tools & VPS Toolkit 📱 ⚡ 🛠️

![Bash](https://img.shields.io/badge/Language-Bash-4EAA25?logo=gnu-bash&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Termux%20%7C%20Android-green?logo=android&logoColor=white)
![SSH](https://img.shields.io/badge/Client-OpenSSH-informational?logo=ssh)
![License](https://img.shields.io/badge/License-MIT-blue)

Набор инструментов и скриптов для превращения смартфона на Android в полноценную карманную консоль системного администратора в среде Termux без root.

Основной проект репозитория находится в директории **[`vps-toolkit/`](vps-toolkit/)**.

---

## ⚡ Быстрая установка (в одну команду)

Откройте Termux на телефоне и выполните:

```bash
pkg update && pkg install curl -y && curl -fsSL -H "Cache-Control: no-cache" "https://raw.githubusercontent.com/iurievi4/android/main/vps-toolkit/install.sh?$(date +%s)" | bash
```

> **Вам не нужно вручную устанавливать `openssh` или другие утилиты!**  
> В установщик встроен интерактивный мастер (Pre-Flight Check): он сам проверит наличие `openssh`, `openssl`, `tar`, `termux-api`, предложит установить недостающие пакеты в один клик и настроит доступ к памяти Android (`termux-setup-storage`).

---

## 🚀 Команды быстрого запуска

После установки доступны команды:

- **`vps`** (или **`vps-toolkit`**) — Единый главный командный пульт (14 модулей).
- **`ssh-manager`** — VPS Control Center (управление серверами, подключение, ключи, config).
- **`vps-monitor`** — Сводный онлайн-мониторинг серверов (CPU, RAM, диск, службы).
- **`netdiag`** — Сетевая диагностика (Ping, DNS, TCP-порты, SSL, SOCKS5).

---

## 📂 Структура репозитория

```text
android/
├── README.md               # Корневое описание репозитория
└── vps-toolkit/            # Основной пакет инструментов VPS Toolkit
    ├── README.md           # Полная подробная документация по всем 14 модулям
    ├── MANUAL_TERMUX.md    # Пошаговое руководство по настройке Termux с нуля
    ├── vps-toolkit.sh      # Главный командный пульт (лаунчер)
    ├── ssh-manager.sh      # Флагман: VPS Control Center & SSH Manager
    ├── install.sh          # Интерактивный установщик с автопроверкой пакетов
    ├── lib/
    │   └── common.sh       # Общая библиотека функций и оформления
    └── modules/            # 13 специализированных модулей:
        ├── vps-monitor.sh        # Сводный онлайн-мониторинг
        ├── vps-sftp.sh           # SFTP файловый менеджер (/etc, скачивание)
        ├── vps-security.sh       # Аудит безопасности (UFW, Fail2ban, bruteforce)
        ├── net-diag.sh           # Сетевая диагностика NetDiag
        ├── backup-manager.sh     # Менеджер бэкапов и зашифрованный сейф
        ├── docker-manager.sh     # Управление контейнерами Docker
        ├── service-manager.sh    # Управление службами systemd
        ├── log-viewer.sh         # Просмотр и фильтрация логов
        ├── port-scanner.sh       # Сканер портов и сокетов
        ├── git-deploy.sh         # Развёртывание и pull Git-проектов
        ├── termux-maintenance.sh # Очистка и оптимизация Termux
        ├── ssh-key-manager.sh    # Управление ключами ED25519/RSA
        └── quick-commands.sh     # Библиотека быстрых команд
```

---

## 📖 Полная документация

Подробное описание работы каждого из 14 модулей, руководство по созданию зашифрованного сейфа с ключами и мануал по настройке Termux смотрите в файле:  
👉 **[vps-toolkit/README.md](vps-toolkit/README.md)**

---

## 🔒 Безопасность данных

- **Никаких зашитых серверов**: в репозитории нет личных IP-адресов, паролей или ключей.
- **Единый источник истины**: конфигурация берётся строго из локального `~/.ssh/config`.
- **Защита `.gitignore`**: исключает попадание любых бэкапов, ключей и конфигураций в Git.

## 📄 Лицензия

Проект распространяется под открытой лицензией [MIT](LICENSE).
