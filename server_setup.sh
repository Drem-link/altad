#!/bin/bash
set -e

ADMIN_PASS="Passw0rd123"
REALM="TEST.ALT"
DOMAIN="TEST"
SERVER_IP="172.16.1.1"

echo "=== ЗАПУСК НАСТРОЙКИ БИЛЕТА №11 ==="

# 1. Сброс маршрутов для интернета
ip route flush default || true
ip route add default via 10.0.2.2 dev enp0s3 || true

# 2. Установка пакетов
apt-get update
apt-get install -y task-samba-dc dhcp-server bind-utils || apt-get install -y task-samba-dc dhcp-server bind9-utils

# 3. Настройка Samba AD
systemctl stop samba 2>/dev/null || true
rm -rf /etc/samba/smb.conf /var/lib/samba/*
samba-tool domain provision --use-rfc2307 --realm=$REALM --domain=$DOMAIN \
  --server-role=dc --dns-backend=SAMBA_INTERNAL --adminpass="$ADMIN_PASS"

# 4. ЗАПУСК И ОЖИДАНИЕ (тот самый "коммит" базы)
echo "Ожидание инициализации домена..."
systemctl enable --now samba
sleep 15

# 5. Экспорт ключа TSIG (Исправлено: dc1.${REALM})
samba-tool domain exportkeytab /etc/dhcp/dhcp.keytab --principal=dc1.${REALM}
chown root:root /etc/dhcp/dhcp.keytab
chmod 600 /etc/dhcp/dhcp.keytab

# 6. Настройка DHCP (ddns-update-style и резервация)
cat > /etc/dhcp/dhcpd.conf << EOF
ddns-update-style interim;
ignore client-updates;
update-static-leases on;

subnet 172.16.1.0 netmask 255.255.255.0 {
    range 172.16.1.100 172.16.1.200;
    option routers $SERVER_IP;
    option domain-name-servers $SERVER_IP;
    option domain-name "test.alt";
    ddns-domainname "test.alt";
    ddns-rev-domainname "in-addr.arpa.";

    host workstation {
        hardware ethernet 08:00:27:ab:cd:ef;
        fixed-address 172.16.1.99;
    }
}
EOF
echo 'DHCPDARGS="enp0s8"' > /etc/sysconfig/dhcpd
systemctl enable --now dhcpd

# 7. Iptables (Пункт 7 билета)
iptables -F
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT
iptables -A INPUT -p tcp -s 172.16.1.2 --dport 22 -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -s 172.16.1.0/24 -j ACCEPT
iptables -A FORWARD -s 172.16.1.0/24 -j ACCEPT
iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -t nat -A POSTROUTING -o enp0s3 -j MASQUERADE
sysctl -w net.ipv4.ip_forward=1

echo "✅ ВСЁ ГОТОВО!"
