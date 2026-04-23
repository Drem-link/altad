#!/bin/bash

ADMIN_PASS="Passw0rd123"
SERVER_IP="172.16.1.1"

# 1. DNS (рабочий)
echo "nameserver $SERVER_IP" > /etc/resolv.conf
echo "nameserver 8.8.8.8" >> /etc/resolv.conf

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

echo "✅ ПАКЕТЫ УСТАНОВЛЕНЫ"
echo "Теперь через alterator войди в домен TEST-ALT"
