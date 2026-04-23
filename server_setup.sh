#!/bin/bash

set -e

ADMIN_PASS="Passw0rd123"

echo "=== НАСТРОЙКА СЕРВЕРА ==="

# 1. ПРОВЕРКА ИНТЕРНЕТА
echo "Проверка интернета..."
if ! ping -c 2 8.8.8.8 &>/dev/null; then
    # Удаляем левый шлюз
    ip route del default via 172.16.1.1 dev enp0s8 2>/dev/null || true
    # Добавляем правильный шлюз для VirtualBox NAT
    ip route add default via 10.0.2.2 dev enp0s3 2>/dev/null || true
fi

ping -c 2 8.8.8.8 || { echo "Нет интернета! Проверь сеть."; exit 1; }

# 2. ОБНОВЛЕНИЕ
echo "Обновление системы..."
apt-get update && apt-get dist-upgrade -y

# 3. УДАЛЕНИЕ КОНФЛИКТУЮЩИХ СЛУЖБ
echo "Удаление конфликтующих DNS..."
apt-get remove -y bind dnsmasq systemd-resolved 2>/dev/null || true

# 4. УСТАНОВКА SAMBA
echo "Установка Samba..."
apt-get install -y task-samba-dc

# 5. ОЧИСТКА СТАРЫХ КОНФИГОВ
echo "Очистка старых конфигов..."
rm -f /etc/samba/smb.conf
rm -rf /var/lib/samba
mkdir -p /var/lib/samba/sysvol /var/lib/samba/private

# 6. СОЗДАНИЕ ДОМЕНА
echo "Создание домена TEST-ALT..."
samba-tool domain provision \
    --use-rfc2307 \
    --realm=TEST-ALT \
    --domain=TEST \
    --server-role=dc \
    --dns-backend=SAMBA_INTERNAL \
    --adminpass="$ADMIN_PASS"

# 7. НАСТРОЙКА DNS FORWARDER
echo "Настройка DNS forwarder..."
cp /var/lib/samba/private/krb5.conf /etc/krb5.conf
echo "dns forwarder = 8.8.8.8" >> /etc/samba/smb.conf

# 8. ЗАПУСК SAMBA (ПРАВИЛЬНОЕ ИМЯ СЛУЖБЫ - samba)
echo "Запуск Samba..."
systemctl unmask samba
systemctl enable samba
systemctl start samba
sleep 3

# 9. НАСТРОЙКА ВНУТРЕННЕГО ИНТЕРФЕЙСА
echo "Настройка внутреннего интерфейса..."
if ! ip addr show | grep -q "172.16.1.1"; then
    ip addr add 172.16.1.1/24 dev enp0s8 2>/dev/null || true
    ip link set enp0s8 up
fi

# 10. НАСТРОЙКА DHCP
echo "Настройка DHCP..."
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

# 11. НАСТРОЙКА IPTABLES И NAT
echo "Настройка iptables и NAT..."
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

# Очистка только FORWARD и NAT, чтобы не сбросить SSH
iptables -F FORWARD 2>/dev/null || true
iptables -t nat -F 2>/dev/null || true

# Правила
iptables -P INPUT DROP 2>/dev/null || true
iptables -P FORWARD DROP 2>/dev/null || true
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -s 172.16.1.2 -j ACCEPT
iptables -A INPUT -p udp --dport 53 -s 172.16.1.0/24 -j ACCEPT
iptables -A INPUT -p udp --dport 67 -s 172.16.1.0/24 -j ACCEPT

# NAT и FORWARD
iptables -t nat -A POSTROUTING -o enp0s3 -j MASQUERADE
iptables -A FORWARD -i enp0s8 -o enp0s3 -j ACCEPT
iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

iptables-save > /etc/sysconfig/iptables
systemctl enable iptables
systemctl start iptables

# 12. ДОБАВЛЕНИЕ ПОЛЬЗОВАТЕЛЯ ДЛЯ DHCP DNS ОБНОВЛЕНИЙ
echo "Настройка обновлений DNS..."
samba-tool user create dhcpuser --random-password 2>/dev/null || true
samba-tool user setexpiry dhcpuser --noexpiry 2>/dev/null || true
samba-tool group addmembers DnsAdmins dhcpuser 2>/dev/null || true
samba-tool domain exportkeytab /etc/dhcp/dhcpd.keytab --principal=dhcpuser@TEST-ALT 2>/dev/null || true
chown dhcpd:dhcpd /etc/dhcp/dhcpd.keytab 2>/dev/null || true
systemctl restart dhcpd

echo "=========================================="
echo "ГОТОВО! ВСЕ НАСТРОЕНО!"
echo "IP сервера: 172.16.1.1"
echo "Пароль Administrator: $ADMIN_PASS"
echo "=========================================="
