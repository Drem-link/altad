#!/bin/bash

set -e

ADMIN_PASS="Passw0rd123"

echo "=== НАСТРОЙКА СЕРВЕРА ALT LINUX ==="

# 1. Проверка интернета
echo "Проверка интернета..."
ip route del default via 172.16.1.1 dev enp0s8 2>/dev/null || true
ip route add default via 10.0.2.2 dev enp0s3 2>/dev/null || true
ping -c 2 8.8.8.8 || { echo "Нет интернета!"; exit 1; }

# 2. Обновление
apt-get update && apt-get dist-upgrade -y

# 3. Удаление конфликтующих DNS
apt-get remove -y bind dnsmasq systemd-resolved 2>/dev/null || true

# 4. Установка Samba
apt-get install -y task-samba-dc

# 5. Очистка старых конфигов
rm -f /etc/samba/smb.conf
rm -rf /var/lib/samba
mkdir -p /var/lib/samba/sysvol /var/lib/samba/private

# 6. Создание домена
samba-tool domain provision \
    --use-rfc2307 \
    --realm=TEST-ALT \
    --domain=TEST \
    --server-role=dc \
    --dns-backend=SAMBA_INTERNAL \
    --adminpass="$ADMIN_PASS"

# 7. Настройка DNS
cp /var/lib/samba/private/krb5.conf /etc/krb5.conf
echo "dns forwarder = 8.8.8.8" >> /etc/samba/smb.conf

# 8. ЗАПУСК SAMBA (ПРОСТО SAMBA)
systemctl enable samba
systemctl start samba
sleep 3

# 9. Проверка
if systemctl is-active --quiet samba; then
    echo "✅ Samba работает"
else
    echo "❌ Ошибка запуска Samba"
    systemctl status samba --no-pager
    exit 1
fi

# 10. Внутренний интерфейс
ip addr add 172.16.1.1/24 dev enp0s8 2>/dev/null || true
ip link set enp0s8 up

# 11. DHCP
apt-get install -y dhcp-server
cat > /etc/dhcp/dhcpd.conf << 'EOF'
subnet 172.16.1.0 netmask 255.255.255.0 {
    range 172.16.1.100 172.16.1.200;
    option routers 172.16.1.1;
    option domain-name-servers 172.16.1.1;
    option domain-name "test-alt";
    
    default-lease-time 600;
    max-lease-time 7200;
    
    host workstation {
        hardware ethernet 08:00:27:ab:cd:ef;
        fixed-address 172.16.1.99;
    }
}
EOF
echo 'DHCPDARGS="enp0s8"' > /etc/sysconfig/dhcpd
systemctl enable dhcpd
systemctl start dhcpd

# 12. NAT
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
iptables -t nat -A POSTROUTING -o enp0s3 -j MASQUERADE
iptables -A FORWARD -i enp0s8 -o enp0s3 -j ACCEPT
iptables-save > /etc/sysconfig/iptables
systemctl enable iptables
systemctl start iptables

echo "=========================================="
echo "✅ СЕРВЕР НАСТРОЕН!"
echo "IP сервера: 172.16.1.1"
echo "Пароль Administrator: $ADMIN_PASS"
echo "=========================================="
