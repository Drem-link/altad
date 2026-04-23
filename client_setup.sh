#!/bin/bash

set -e

echo "=== НАСТРОЙКА КЛИЕНТА ДЛЯ ВХОДА В ДОМЕН ==="

# 1. Запрос интерфейса и пароля
echo "Список доступных интерфейсов:"
ip -br link | grep -v LOOPBACK
echo ""
read -p "Введи имя сетевого интерфейса клиента (обычно enp0s3 или eth0): " CLIENT_IF
read -p "Введи пароль администратора домена (по умолчанию Passw0rd123): " USER_PASS
ADMIN_PASS="${USER_PASS:-Passw0rd123}"
SERVER_IP="172.16.1.1"

echo ""
echo "Интерфейс клиента: $CLIENT_IF"
echo "Пароль администратора: $ADMIN_PASS"
read -p "Всё верно? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Отменено."
    exit 1
fi

# 2. Настройка сети (DHCP)
echo "Настройка сети через DHCP..."
mkdir -p /etc/net/ifaces/$CLIENT_IF
cat > /etc/net/ifaces/$CLIENT_IF/options << EOF
BOOTPROTO=dhcp
TYPE=eth
DISABLED=no
NM_CONTROLLED=no
EOF

rm -f /etc/net/ifaces/$CLIENT_IF/ipv4
rm -f /etc/net/ifaces/$CLIENT_IF/ipv4route
systemctl restart network
sleep 5

# 3. Настройка DNS
echo "Настройка DNS..."
cat > /etc/resolv.conf << EOF
nameserver $SERVER_IP
nameserver 8.8.8.8
search test-alt
EOF

# 4. Установка пакетов
echo "Установка пакетов..."
apt-get update
apt-get install -y task-auth-ad-sssd krb5-workstation realmd samba-client

# 5. Настройка Kerberos
echo "Настройка Kerberos..."
cat > /etc/krb5.conf << EOF
[libdefaults]
    default_realm = TEST-ALT
    dns_lookup_realm = false
    dns_lookup_kdc = true

[realms]
    TEST-ALT = {
        kdc = $SERVER_IP
        admin_server = $SERVER_IP
    }
EOF

# 6. Настройка SSSD (заготовка, чтобы потом через графику)
mkdir -p /etc/sssd

echo "=========================================="
echo "✅ ПАКЕТЫ УСТАНОВЛЕНЫ, DNS НАСТРОЕН"
echo ""
echo "ТЕПЕРЬ ВРУЧНУЮ (через графику):"
echo "1. Запусти: alterator (или acc)"
echo "2. Выбери: Пользователи → Аутентификация"
echo "3. Выбери: Active Directory or ALT Domain"
echo "4. Введи:"
echo "   Домен: TEST-ALT"
echo "   Контроллер: $SERVER_IP"
echo "   Пользователь: administrator"
echo "   Пароль: $ADMIN_PASS"
echo "5. Нажми Применить и перезагрузись"
echo ""
echo "После перезагрузки войди как: TEST\\administrator"
echo "Пароль: $ADMIN_PASS"
echo "=========================================="
