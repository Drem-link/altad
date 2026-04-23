#!/bin/bash

ADMIN_PASS="Passw0rd123"
SERVER_IP="172.16.1.1"

echo "=== НАСТРОЙКА КЛИЕНТА ==="

# 1. DNS
echo "Настройка DNS..."
cat > /etc/resolv.conf << EOF
nameserver $SERVER_IP
nameserver 8.8.8.8
search test-alt
EOF

# 2. Пакеты
echo "Установка пакетов..."
apt-get update
apt-get install -y task-auth-ad-sssd krb5-workstation realmd samba-client

# 3. Kerberos
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

# 4. SSSD (заготовка)
mkdir -p /etc/sssd

echo "=========================================="
echo "✅ ПАКЕТЫ УСТАНОВЛЕНЫ, DNS НАСТРОЕН"
echo ""
echo "ТЕПЕРЬ ВРУЧНУЮ (через графику):"
echo "1. Запусти: alterator (или acc)"
echo "2. Выбери: Пользоваторы → Аутентификация"
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
