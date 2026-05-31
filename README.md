# SmartConnect

**WireGuard → VLESS Tunnel Manager**

**Installer**
```bash
curl -fsSL https://raw.githubusercontent.com/IGrok2/wg-to-vless/main/install.sh | bash
```

Управляет цепочкой: **WireGuard клиент → VLESS прокси → интернет**

---

## Быстрый старт / Quick Start



```bash
# Clone / copy the directory, then:
bash setup.sh install

# Launch
smartconnect
```

---

## Структура / Structure

```
smartconnect/
├── smartconnect          # Main entrypoint
├── setup.sh              # Installer
├── lib/
│   ├── core.sh           # Colors, config, UI helpers
│   ├── installer.sh      # xray / sing-box / v2ray installer
│   ├── subscriptions.sh  # Subscription & node management
│   ├── configs.sh        # JSON config generators + WG menu
│   ├── tunnel.sh         # Connect / disconnect logic
│   └── settings.sh       # Settings, autostart, MOTD, logs
├── locale/
│   ├── en.sh             # English strings
│   └── ru.sh             # Russian strings
└── systemd/
    └── smartconnect@.service  # Systemd unit
```

---

## Меню / Menu

| # | EN | RU |
|---|----|----|
| 1 | Connection Status | Статус подключения |
| 2 | Connect / Disconnect | Подключиться / Отключиться |
| 3 | Manage Subscriptions | Управление подписками |
| 4 | Select Node | Выбор узла |
| 5 | WireGuard Config | Настройка WireGuard |
| 6 | Settings | Настройки |
| 7 | Logs | Логи |
| 8 | Install / Update Core | Установка ядра |

---

## Подписки / Subscriptions

Поддерживаются URL подписок в форматах:
- **base64-encoded** список `vless://...` строк (стандартный формат большинства панелей)
- Прямой список `vless://...` строк (одна на строку)

```
smartconnect → 3 (Manage Subscriptions) → 1 (Add)
  Name: myvpn
  URL:  https://example.com/sub/token
```

Парсируются параметры VLESS URI:
- `uuid`, `host`, `port`
- `security`: none / tls / reality
- `type`: tcp / ws / grpc
- `sni`, `fp` (fingerprint), `pbk`, `sid` (Reality)
- `flow` (xtls-rprx-vision)
- `path` (WebSocket/gRPC)

---

## WireGuard

Импортируй свой `.conf` файл:
```
smartconnect → 5 (WireGuard Config) → 1 (Import file)
  Path: /home/user/wg0.conf
```

Или вставь конфиг вручную через пункт 2.

---

## Установка ядра / Core installation

```
smartconnect → 8 (Install / Update Core)
```

Поддерживаемые ядра:
- **xray-core** (рекомендуется, XTLS Reality)
- **sing-box**
- **v2ray-core**

Автоматически скачивает последний релиз с GitHub под вашу архитектуру (amd64 / arm64 / armv7).

---

## Автозапуск / Autostart

```
smartconnect → 6 (Settings) → 1 (Toggle autostart)
```

Добавляет хук в `~/.bashrc` (или `.zshrc`): при входе в shell сразу открывается SmartConnect.

## MOTD

```
smartconnect → 6 (Settings) → 2 (Toggle MOTD)
```

При входе в терминал показывает статус соединения, активный узел, порты.

---

## CLI режим / CLI mode

```bash
smartconnect connect      # Подключить туннель
smartconnect disconnect   # Отключить
smartconnect status       # Статус
smartconnect update       # Обновить подписки
smartconnect install      # Установить ядро
smartconnect --help
smartconnect --version
```

---

## Systemd сервис / Systemd service

```bash
# Install service
sudo cp systemd/smartconnect@.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable smartconnect@$USER
sudo systemctl start  smartconnect@$USER
sudo systemctl status smartconnect@$USER
```

---

## Язык / Language

По умолчанию: **English**.

Переключить на русский:
```
smartconnect → 6 (Settings) → 3 (Change language) → 2 (Русский)
```

Сделать русский языком по умолчанию:
```bash
echo 'SC_LANG="ru"' >> ~/.smartconnect/config
```

---

## Данные / Data location

```
~/.smartconnect/
├── config              # Settings (lang, core, ports, ...)
├── active_node         # Currently selected node name
├── nodes/              # Parsed .node files
├── subscriptions/      # Subscription metadata
│   └── subs.list       # name|url registry
├── wireguard/          # WG config (chmod 700)
│   └── wg0.conf
├── run/                # PID file, generated core configs
└── logs/               # core.log, system.log
```

---

## Зависимости / Dependencies

Устанавливаются автоматически при первом запуске:

| Tool | Package |
|------|---------|
| `wg`, `wg-quick` | `wireguard-tools` |
| `curl` | `curl` |
| `wget` | `wget` |
| `jq` | `jq` |

VPN ядро устанавливается из меню (пункт 8).
