#!/bin/bash

set -e

ADMIN_PASS="Passw0rd123"
SERVER_IP="172.16.1.1"

echo "=== НАСТРОЙКА КЛИЕНТА ==="

# 1. НАСТРОЙКА СЕТИ (DHCP)
echo "Настройка сети..."
mkdir -p /etc/net/ifaces/enp0s3
cat > /etc/net/ifaces/enp0s3/options << 'EOF'
BOOTPROTO=dhcp
TYPE=eth
DISABLED=no
NM_CONTROLLED=no
EOF

rm -f /etc/net/ifaces/enp0s3/ipv4
rm -f /etc/net/ifaces/enp0s3/ipv4route
systemctl restart network
sleep 5

# 2. УСТАНОВКА ПАКЕТОВ
echo "Установка пакетов..."
apt-get update
apt-get install -y task-auth-ad-sssd samba-client krb5-workstation realmd

# 3. НАСТРОЙКА KERBEROS
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

# 4. ПОЛУЧЕНИЕ БИЛЕТА
echo "Получение Kerberos билета..."
echo "$ADMIN_PASS" | kinit administrator@TEST-ALT 2>/dev/null || echo "Kerberos ошибка, но продолжаем..."

# 5. НАСТРОЙКА SAMBA
echo "Настройка Samba..."
mkdir -p /etc/samba /var/lib/samba/private /var/log/samba
cat > /etc/samba/smb.conf << EOF
[global]
   workgroup = TEST
   realm = TEST-ALT
   security = ads
   server role = standalone
   log file = /var/log/samba/%m.log
   max log size = 50
   winbind use default domain = yes
EOF

# 6. ВВОД В ДОМЕН
echo "Ввод в домен..."
echo "$ADMIN_PASS" | net ads join -U Administrator -S $SERVER_IP 2>/dev/null || echo "Попробуй ввести в домен вручную: net ads join -U Administrator -S 172.16.1.1"

echo "=========================================="
echo "КЛИЕНТ НАСТРОЕН!"
echo "Перезагрузи: reboot"
echo "Вход: administrator / $ADMIN_PASS"
echo "=========================================="
