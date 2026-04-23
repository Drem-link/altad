#!/bin/bash

set -e

echo "=== НАСТРОЙКА СЕРВЕРА Samba AD ==="

# 1. Запрос интерфейсов у пользователя
echo "Список доступных интерфейсов:"
ip -br link | grep -v LOOPBACK
echo ""
read -p "Введи имя ВНЕШНЕГО интерфейса (смотрит в интернет, обычно enp0s3 или eth0): " EXT_IF
read -p "Введи имя ВНУТРЕННЕГО интерфейса (локальная сеть, обычно enp0s8 или eth1): " INT_IF
read -p "Введи пароль администратора домена (оставь пустым для Passw0rd123): " USER_PASS
ADMIN_PASS="${USER_PASS:-Passw0rd123}"

echo ""
echo "Внешний интерфейс: $EXT_IF"
echo "Внутренний интерфейс: $INT_IF"
echo "Пароль администратора: $ADMIN_PASS"
read -p "Всё верно? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Отменено."
    exit 1
fi

# 2. Настройка сети
echo "Настройка сети..."
mkdir -p /etc/net/ifaces/$EXT_IF /etc/net/ifaces/$INT_IF

cat > /etc/net/ifaces/$EXT_IF/options << EOF
BOOTPROTO=dhcp
TYPE=eth
DISABLED=no
NM_CONTROLLED=no
EOF

cat > /etc/net/ifaces/$INT_IF/options << EOF
BOOTPROTO=static
TYPE=eth
DISABLED=no
NM_CONTROLLED=no
EOF

echo "172.16.1.1/24" > /etc/net/ifaces/$INT_IF/ipv4
rm -f /etc/net/ifaces/$INT_IF/ipv4route
systemctl restart network
sleep 3

# 3. Чистка порта 53 и конфликтов
echo "Чистка порта 53 и конфликтующих служб..."
fuser -k 53/tcp 53/udp 2>/dev/null || true
systemctl stop bind dnsmasq systemd-resolved named 2>/dev/null || true
systemctl disable bind dnsmasq systemd-resolved named 2>/dev/null || true
apt-get remove -y bind dnsmasq systemd-resolved 2>/dev/null || true

# 4. Обновление и установка Samba
echo "Обновление и установка Samba..."
apt-get update && apt-get dist-upgrade -y
apt-get install -y task-samba-dc

# 5. Очистка старых конфигов
rm -f /etc/samba/smb.conf
rm -rf /var/lib/samba
mkdir -p /var/lib/samba/sysvol /var/lib/samba/private

# 6. Создание домена
echo "Создание домена TEST-ALT..."
samba-tool domain provision \
    --use-rfc2307 \
    --realm=TEST-ALT \
    --domain=TEST \
    --server-role=dc \
    --dns-backend=SAMBA_INTERNAL \
    --adminpass="$ADMIN_PASS" \
    --option="interfaces=lo $INT_IF" \
    --option="bind interfaces only=yes"

# 7. Настройка DNS forwarder
cp /var/lib/samba/private/krb5.conf /etc/krb5.conf
echo "dns forwarder = 8.8.8.8" >> /etc/samba/smb.conf

# 8. Запуск Samba
systemctl unmask samba
systemctl enable samba
systemctl start samba
sleep 5

if systemctl is-active --quiet samba; then
    echo "✅ Samba работает"
else
    echo "❌ Samba не запустилась, смотри логи: journalctl -u samba -n 20"
    exit 1
fi

# 9. DHCP
echo "Настройка DHCP..."
apt-get install -y dhcp-server

cat > /etc/dhcp/dhcpd.conf << EOF
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

echo "DHCPDARGS=\"$INT_IF\"" > /etc/sysconfig/dhcpd
systemctl enable dhcpd
systemctl start dhcpd

# 10. NAT и iptables
echo "Настройка NAT и iptables..."
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

iptables -t nat -A POSTROUTING -o $EXT_IF -j MASQUERADE
iptables -A FORWARD -i $INT_IF -o $EXT_IF -j ACCEPT
iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

iptables-save > /etc/sysconfig/iptables
systemctl enable iptables
systemctl start iptables

echo "=========================================="
echo "✅ СЕРВЕР НАСТРОЕН!"
echo "Домен: TEST-ALT"
echo "IP сервера: 172.16.1.1"
echo "Пароль Administrator: $ADMIN_PASS"
echo "=========================================="
