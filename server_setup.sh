#!/bin/bash

echo "=== НАСТРОЙКА СЕРВЕРА Samba AD ==="
echo ""

# 1. ЗАПРАШИВАЕМ ИНТЕРФЕЙСЫ
echo "Доступные интерфейсы:"
ip -br link | grep -v LOOPBACK
echo ""
read -p "Введи имя ВНЕШНЕГО интерфейса (интернет, NAT): " EXT_IF
read -p "Введи имя ВНУТРЕННЕГО интерфейса (локальная сеть): " INT_IF

# 2. ЗАПРАШИВАЕМ MAC ДЛЯ РЕЗЕРВИРОВАНИЯ
echo ""
echo "Доступные MAC-адреса клиентов можно посмотреть командой: arp -n"
read -p "Введи MAC-адрес клиента для резервирования IP 172.16.1.99 (например, 08:00:27:ab:cd:ef): " CLIENT_MAC

# 3. ПАРОЛЬ
read -sp "Введи пароль администратора домена (Enter = Passw0rd123): " USER_PASS
echo ""
ADMIN_PASS="${USER_PASS:-Passw0rd123}"

echo ""
echo "=========================================="
echo "Внешний интерфейс: $EXT_IF"
echo "Внутренний интерфейс: $INT_IF"
echo "MAC клиента для резервирования: $CLIENT_MAC"
echo "Пароль администратора: $ADMIN_PASS"
echo "=========================================="
read -p "Всё верно? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Отменено."
    exit 1
fi

# 4. Чистка порта 53
echo "Очистка порта 53..."
fuser -k 53/tcp 53/udp 2>/dev/null
systemctl stop bind dnsmasq systemd-resolved 2>/dev/null
apt-get remove -y bind dnsmasq systemd-resolved 2>/dev/null

# 5. Обновление и установка Samba
echo "Обновление и установка Samba..."
apt-get update && apt-get dist-upgrade -y
apt-get install -y task-samba-dc

# 6. Создание домена
echo "Создание домена TEST-ALT..."
rm -f /etc/samba/smb.conf
rm -rf /var/lib/samba
mkdir -p /var/lib/samba/sysvol /var/lib/samba/private

samba-tool domain provision \
    --use-rfc2307 \
    --realm=TEST-ALT \
    --domain=TEST \
    --server-role=dc \
    --dns-backend=SAMBA_INTERNAL \
    --adminpass="$ADMIN_PASS" \
    --option="interfaces=lo $INT_IF" \
    --option="bind interfaces only=yes"

# 7. Настройка DNS
cp /var/lib/samba/private/krb5.conf /etc/krb5.conf
echo "dns forwarder = 8.8.8.8" >> /etc/samba/smb.conf

# 8. Запуск Samba
systemctl unmask samba
systemctl enable samba
systemctl start samba
sleep 5

# 9. Настройка DHCP с DDNS
echo "Настройка DHCP-сервера..."
apt-get install -y dhcp-server

# Создание ключа TSIG
samba-tool user create dhcpuser --random-password 2>/dev/null || true
samba-tool user setexpiry dhcpuser --noexpiry 2>/dev/null || true
samba-tool group addmembers DnsAdmins dhcpuser 2>/dev/null || true
samba-tool domain exportkeytab /etc/dhcp/dhcpd.keytab --principal=dhcpuser@TEST-ALT 2>/dev/null || true
chown dhcpd:dhcpd /etc/dhcp/dhcpd.keytab 2>/dev/null || true
chmod 640 /etc/dhcp/dhcpd.keytab

# Конфиг DHCP с подставленными значениями
cat > /etc/dhcp/dhcpd.conf << EOF
ddns-update-style interim;
ddns-updates on;
ddns-domainname "test-alt";
ddns-rev-domainname "in-addr.arpa";

zone test-alt. {
    primary 127.0.0.1;
    key dhcpuser;
}

zone 1.16.172.in-addr.arpa. {
    primary 127.0.0.1;
    key dhcpuser;
}

subnet 172.16.1.0 netmask 255.255.255.0 {
    range 172.16.1.100 172.16.1.200;
    option routers 172.16.1.1;
    option domain-name-servers 172.16.1.1;
    option domain-name "test-alt";
    
    default-lease-time 600;
    max-lease-time 7200;
    
    ddns-updates on;
    ddns-domainname "test-alt.";
    ddns-rev-domainname "in-addr.arpa.";
    
    allow client-updates;
    update-static-leases on;
    
    host workstation {
        hardware ethernet $CLIENT_MAC;
        fixed-address 172.16.1.99;
        ddns-hostname "workstation";
    }
}
EOF

echo "DHCPDARGS=\"$INT_IF\"" > /etc/sysconfig/dhcpd
systemctl enable dhcpd
systemctl restart dhcpd

# 10. Права на запись DNS-зоны
samba-tool group addmembers DnsAdmins administrator 2>/dev/null || true
samba-tool group addmembers DnsUpdateProxy dhcpuser 2>/dev/null || true

# 11. NAT и iptables
echo "Настройка iptables и NAT..."
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

iptables -F
iptables -t nat -F
iptables -X

iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

iptables -A INPUT -p tcp --dport 22 -s 172.16.1.2 -j ACCEPT
iptables -A INPUT -p udp --dport 53 -s 172.16.1.0/24 -j ACCEPT
iptables -A INPUT -p udp --dport 67 -s 172.16.1.0/24 -j ACCEPT

iptables -t nat -A POSTROUTING -o $EXT_IF -j MASQUERADE
iptables -A FORWARD -i $INT_IF -o $EXT_IF -j ACCEPT

iptables-save > /etc/sysconfig/iptables
systemctl enable iptables
systemctl start iptables

echo "=========================================="
echo "✅ НАСТРОЙКА ЗАВЕРШЕНА"
echo "Домен: TEST-ALT"
echo "IP сервера: 172.16.1.1"
echo "Пароль Administrator: $ADMIN_PASS"
echo "Резервирование для MAC: $CLIENT_MAC -> 172.16.1.99"
echo "=========================================="
