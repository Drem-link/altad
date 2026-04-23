#!/bin/bash

set -e

ADMIN_PASS="Passw0rd123"

echo "=== Настройка сервера ==="

# 1. ПРОВЕРКА ИНТЕРНЕТА (не ломаем, а чиним)
echo "Проверка интернета..."

# Проверяем, есть ли шлюз
if ! ip route | grep -q "default"; then
    echo "Нет шлюза по умолчанию. Добавляем..."
    # Находим интерфейс с IP 10.0.2.x (VirtualBox NAT)
    EXT_IF=$(ip -4 addr show | grep -oP 'inet 10\.0\.2\.\d+.*' | awk '{print $NF}' | head -1)
    if [ -n "$EXT_IF" ]; then
        ip route add default via 10.0.2.2 dev $EXT_IF
        echo "default via 10.0.2.2" > /etc/net/ifaces/$EXT_IF/ipv4route
    fi
fi

# Удаляем левый шлюз если есть
ip route del default via 172.16.1.1 dev enp0s8 2>/dev/null || true

# Проверяем интернет
if ! ping -c 2 8.8.8.8 &>/dev/null; then
    echo "НЕТ ИНТЕРНЕТА! Проверь вручную."
    exit 1
fi

echo "Интернет есть. Продолжаем..."

# 2. ОБНОВЛЕНИЕ
apt-get update
apt-get dist-upgrade -y

# 3. УДАЛЕНИЕ КОНФЛИКТУЮЩИХ DNS
apt-get remove bind dnsmasq systemd-resolved -y 2>/dev/null || true

# 4. УСТАНОВКА SAMBA AD
apt-get install task-samba-dc -y

# 5. ОЧИСТКА СТАРЫХ КОНФИГОВ
rm -f /etc/samba/smb.conf
rm -rf /var/lib/samba
mkdir -p /var/lib/samba/sysvol /var/lib/samba/private

# 6. СОЗДАНИЕ ДОМЕНА
samba-tool domain provision \
    --use-rfc2307 \
    --realm=TEST-ALT \
    --domain=TEST \
    --server-role=dc \
    --dns-backend=SAMBA_INTERNAL \
    --adminpass="$ADMIN_PASS"

# 7. НАСТРОЙКА KERBEROS
cp /var/lib/samba/private/krb5.conf /etc/krb5.conf
echo "dns forwarder = 8.8.8.8" >> /etc/samba/smb.conf

# 8. ЗАПУСК SAMBA
systemctl unmask samba-ad-dc
systemctl enable samba-ad-dc
systemctl start samba-ad-dc
sleep 5

# 9. НАСТРОЙКА ВНУТРЕННЕГО ИНТЕРФЕЙСА (не ломаем внешний!)
INT_IF=$(ip -4 addr show | grep -oP 'inet 172\.16\.1\.\d+.*' | awk '{print $NF}' | head -1)
if [ -z "$INT_IF" ]; then
    # Если нет IP 172.16.1.1 - назначаем
    INT_IF=$(ls /sys/class/net/ | grep -v lo | grep -v "$(ip route | grep default | awk '{print $5}' | head -1)" | head -1)
    ip addr add 172.16.1.1/24 dev $INT_IF 2>/dev/null || true
    ip link set $INT_IF up
fi
echo "Внутренний интерфейс: $INT_IF"

# 10. DHCP
apt-get install dhcp-server -y

cat > /etc/dhcp/dhcpd.conf << EOF
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

echo "DHCPDARGS=\"$INT_IF\"" > /etc/sysconfig/dhcpd
systemctl enable dhcpd
systemctl start dhcpd

# 11. IPTABLES (НЕ ТРОГАЕТ НАТ, ТОЛЬКО ДОБАВЛЯЕТ)
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

# Добавляем правила, не сбрасывая существующие
EXT_IF=$(ip route | grep default | awk '{print $5}' | head -1)
iptables -A FORWARD -i $INT_IF -o $EXT_IF -j ACCEPT 2>/dev/null || true
iptables -t nat -A POSTROUTING -o $EXT_IF -j MASQUERADE 2>/dev/null || true

iptables-save > /etc/sysconfig/iptables
systemctl enable iptables
systemctl start iptables

echo "=========================================="
echo "ГОТОВО!"
echo "IP сервера: 172.16.1.1"
echo "Пароль Administrator: $ADMIN_PASS"
echo "=========================================="
