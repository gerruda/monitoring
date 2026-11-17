#!/data/data/com.termux/files/usr/bin/sh
# Ручной подъём всего стека: используется, если Termux:Boot не срабатывает
# (известная проблема MIUI 12 / Android 10, termux/termux-boot#175).
# Установить: cp deploy/termux/up.sh ~/up.sh && chmod +x ~/up.sh
# После перезагрузки: открыть Termux -> ~/up.sh
termux-wake-lock
sshd
sh "$HOME/.termux/boot/monitoring.sh"
