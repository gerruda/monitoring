# Постоянный SSH-туннель с Windows к телефону

Телефон держит Prometheus (`127.0.0.1:9091`) и Grafana (`127.0.0.1:3000`) на
своём loopback. Чтобы смотреть их с Windows, нужен локальный форвард:

```
Windows 127.0.0.1:3000  ──SSH──▶  телефон 127.0.0.1:3000   (Grafana)
Windows 127.0.0.1:9091  ──SSH──▶  телефон 127.0.0.1:9091   (Prometheus)
```

Скрипт `phone-tunnel.ps1` держит туннель и переподключает его при обрыве.

## 1. Ключ Windows → телефон (один раз)

Туннель запускается без человека, поэтому нужен вход по ключу, а не пароль.

```powershell
# если ключа ещё нет
ssh-keygen -t ed25519 -C "windows@home" -f "$env:USERPROFILE\.ssh\id_ed25519"

# добавить публичный ключ на телефон (спросит пароль Termux один раз)
type "$env:USERPROFILE\.ssh\id_ed25519.pub" | ssh -p 8022 u0_aXXX@10.0.1.123 "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"

# проверка без пароля
ssh -p 8022 -o BatchMode=yes u0_aXXX@10.0.1.123 "echo OK"
```

## 2. Запуск скрипта

Скопируй `phone-tunnel.ps1` в `C:\scripts\` и поправь значения по умолчанию
(`$PhoneHost`, `$PhoneUser` — логин из `whoami` в Termux).

```powershell
New-Item -ItemType Directory -Force C:\scripts | Out-Null
Copy-Item .\phone-tunnel.ps1 C:\scripts\ -Force

# пробный запуск (Ctrl+C для остановки)
powershell -NoProfile -ExecutionPolicy Bypass -File C:\scripts\phone-tunnel.ps1
```

Проверка в другом окне:

```powershell
Get-NetTCPConnection -LocalPort 3000, 9091 -State Listen | Format-Table LocalAddress, LocalPort
Invoke-WebRequest http://127.0.0.1:3000/api/health -UseBasicParsing
```

Grafana: <http://127.0.0.1:3000>, Prometheus: <http://127.0.0.1:9091>.

## 3. Автозапуск при входе в Windows

Планировщик заданий, задача от текущего пользователя, без окна:

```powershell
schtasks /Create /F /TN "Phone SSH Tunnel" /SC ONLOGON /RL LIMITED /TR "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\scripts\phone-tunnel.ps1"
schtasks /Run /TN "Phone SSH Tunnel"
Get-ScheduledTask -TaskName "Phone SSH Tunnel" | Get-ScheduledTaskInfo
```

Остановить / удалить:

```powershell
schtasks /End /TN "Phone SSH Tunnel"
schtasks /Delete /TN "Phone SSH Tunnel" /F
```

Если нужен запуск до входа пользователя — `/SC ONSTART` + задача от SYSTEM
(нужны права администратора; ключ должен лежать у SYSTEM, проще оставить ONLOGON).

## Траблшутинг

| Симптом | Причина / что делать |
|---|---|
| `bind: Address already in use` в логе, туннель перезапускается | порт 3000/9091 занят локально: `Get-NetTCPConnection -LocalPort 3000 -State Listen`; закрой местную Grafana/Prometheus или смени `-L` |
| `Permission denied (publickey)` | не добавлен ключ: повтори шаг 1, проверь `~/.ssh/authorized_keys` на телефоне |
| `Connection refused` | sshd на телефоне не запущен / телефон в другом Wi-Fi: `sshd` в Termux, проверь IP |
| туннель есть, но Grafana 502/пусто | на телефоне не запущена Grafana: `curl -fsS http://127.0.0.1:3000/api/health` в Termux |
| IP телефона меняется | закрепи адрес в DHCP роутера (reservation по MAC) или пропиши актуальный в `$PhoneHost` |
| после сна Windows туннель не поднялся | задача ONLOGON запускается при входе; для выхода из сна добавь триггер «при пробуждении» в Планировщике |
