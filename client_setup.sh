#!/bin/bash
set -e

# 1. Настройка интернета (чтобы пакеты скачались)
# Укажи IP своего сервера как шлюз и DNS
ip route flush default || true
ip route add default via 172.16.1.1 dev enp0s3 || true
echo "nameserver 172.16.1.1" > /etc/resolv.conf

# 2. Установка софта
apt-get update
apt-get install -y sssd sssd-ad sssd-krb5 adcli realmd krb5-utils samba-common-tools

# 3. Подготовка к вводу в домен
echo "Passw0rd123" | kinit Administrator@TEST.ALT

# 4. Ввод в домен (Билет №11)
realm join --user=Administrator TEST.ALT << EOF
Passw0rd123
EOF

# 5. Настройка SSSD (чтобы пускало доменных юзеров)
systemctl enable --now sssd

# 6. Настройка автоматического создания домашних папок
control switch system-policy-mkhomedir enabled

echo "=== КЛИЕНТ ВВЕДЕН В ДОМЕН ==="
