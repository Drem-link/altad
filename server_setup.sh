#!/bin/bash

set -e

ADMIN_PASS="Passw0rd123"

echo "=== НАСТРОЙКА СЕРВЕРА ==="

# 1. Проверка интернета
echo "Проверка интернета..."
ip route del default via 172.16.1.1 dev enp0s8 2>/dev/null || true
ip route add default via 10.0.2.2 dev enp0s3 2>/dev/null || true
ping -c 2 8.8.8.8 || { echo "Нет интернета!"; exit 1; }

# 2. Обновление
apt-get update && apt-get dist-upgrade -y

# 3. Установка Samba
apt-get install -y task-samba-dc

# 4. Создание домена
rm -f /etc/samba/smb.conf
rm -rf /var/lib/samba
samba-tool domain provision \
    --use-rfc2307 \
    --realm=TEST-ALT \
    --domain=TEST \
    --server-role=dc \
    --dns-backend=SAMBA_INTERNAL \
    --adminpass="$ADMIN_PASS"

# 5. Настройка DNS
cp /var/lib/samba/private/krb5.conf /etc/krb5.conf
echo "dns forwarder = 8.8.8.8" >> /etc/samba/smb.conf

# 6. ЗАПУСК САМБЫ (РАБОТАЕТ ЛЮБОЙ ВАРИАНТ)
echo "Запуск Samba..."
systemctl unmask samba-ad-dc 2>/dev/null || true
systemctl enable samba-ad-dc 2>/dev/null || true
systemctl start samba-ad-dc 2>/dev/null || true

systemctl unmask samba 2>/dev/null || true
systemctl enable samba 2>/dev/null || true
systemctl start samba 2>/dev/null || true

sleep 5

# 7. Проверка
if systemctl is-active --quiet samba-ad-dc || systemctl is-active --quiet samba; then
    echo "✅ Samba работает"
else
    echo "❌ ОШИБКА: Samba не запустилась"
    systemctl status samba-ad-dc --no-pager 2>/dev/null || true
    systemctl status samba --no-pager 2>/dev/null || true
    exit 1
fi

# 8. Внутренний интерфейс
ip addr add 172.16.1.1/24 dev enp0s8 2>/dev/null || true

# 9. DHCP
apt-get install -y dhcp-server
cat > /etc/dhcp/dhcpd.conf << 'EOF'
subnet 172.16.1.0 netmask 255.255.255.0 {
    range 172.16.1.100 172.16.1.200;
    option routers 172.16.1.1;
    option domain-name-servers 172.16.1.1;
    option domain-name "test-alt";
    host workstation {
        hardware ethernet 08:00:27:ab:cd:ef;
        fixed-address 172.16.1.99;
    }
}
EOF
echo 'DHCPDARGS="enp0s8"' > /etc/sysconfig/dhcpd
systemctl enable dhcpd
systemctl start dhcpd

# 10. NAT
sysctl -w net.ipv4.ip_forward=1
iptables -t nat -A POSTROUTING -o enp0s3 -j MASQUERADE
iptables -A FORWARD -i enp0s8 -o enp0s3 -j ACCEPT

echo "✅ ГОТОВО!"
