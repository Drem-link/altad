#!/bin/bash

ADMIN_PASS="Passw0rd123"
SERVER_IP="172.16.1.1"

echo "=== НАСТРОЙКА КЛИЕНТА ==="

# 1. DNS (без выебона)
cat > /etc/resolv.conf << EOF
nameserver $SERVER_IP
nameserver 8.8.8.8
search test-alt
EOF

# 2. Пакеты
apt-get update
apt-get install -y task-auth-ad-sssd krb5-workstation realmd

# 3. Kerberos
cat > /etc/krb5.conf << EOF
[libdefaults]
    default_realm = TEST-ALT
    dns_lookup_realm = false
    dns_lookup_kdc = true

[realms]
    TEST-ALT = {
        kdc = $SERVER_IP
    }
EOF

# 4. Вход в домен
echo "Введи пароль: $ADMIN_PASS"
realm join --user=administrator TEST-ALT

# 5. Автосоздание домашней папки
pam-auth-update --enable mkhomedir

echo "=========================================="
echo "ГОТОВО. Перезагрузи: reboot"
echo "Вход: TEST\\administrator пароль: $ADMIN_PASS"
echo "=========================================="
