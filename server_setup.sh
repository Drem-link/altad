#!/bin/bash
set -e

ADMIN_PASS="Passw0rd123"
DOMAIN_NAME="test.alt"
REALM="TEST.ALT"
SERVER_IP="172.16.1.1"

echo "=== ВЫПОЛНЕНИЕ ЭКЗАМЕНАЦИОННОГО БИЛЕТА №11 ==="

# 1. Исправление интернета (для загрузки пакетов)
ip route flush default || true
ip route add default via 10.0.2.2 dev enp0s3 || true

# 2. Установка необходимых пакетов
apt-get update
apt-get install -y task-samba-dc dhcp-server bind9-utils

# 3. Развертывание Samba AD (dc1.test.alt)
systemctl stop samba 2>/dev/null || true
rm -rf /etc/samba/smb.conf /var/lib/samba/*
samba-tool domain provision --use-rfc2307 --realm=$REALM --domain=TEST \
  --server-role=dc --dns-backend=SAMBA_INTERNAL --adminpass="$ADMIN_PASS"

# 4. Генерация ключа TSIG для DHCP (требование билета)
# Создаем keytab для обновлений DNS
samba-tool domain exportkeytab /etc/dhcp/dhcp.keytab --principal=dc1$@$REALM
chown root:root /etc/dhcp/dhcp.keytab
chmod 600 /etc/dhcp/dhcp.keytab

# 5. Настройка DHCP с DDNS (секция dhcpd.conf)
cat > /etc/dhcp/dhcpd.conf << EOF
ddns-update-style interim;
ignore client-updates;
update-static-leases on;

subnet 172.16.1.0 netmask 255.255.255.0 {
    range 172.16.1.100 172.16.1.200;
    option routers $SERVER_IP;
    option domain-name-servers $SERVER_IP;
    option domain-name "$DOMAIN_NAME";
    ddns-domainname "$DOMAIN_NAME";
    ddns-rev-domainname "in-addr.arpa.";

    # Резервирование для рабочей станции (Пункт 8 билета)
    host workstation {
        hardware ethernet 08:00:27:ab:cd:ef;
        fixed-address 172.16.1.99;
    }
}
EOF

echo 'DHCPDARGS="enp0s8"' > /etc/sysconfig/dhcpd

# 6. Межсетевой экран (iptables) - Пункт 7 билета
iptables -F
iptables -X
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# Разрешаем SSH только для администратора (172.16.1.2)
iptables -A INPUT -p tcp -s 172.16.1.2 --dport 22 -j ACCEPT
# Разрешаем Loopback и установленные соединения
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
# Разрешаем трафик из локалки
iptables -A INPUT -s 172.16.1.0/24 -j ACCEPT
iptables -A FORWARD -s 172.16.1.0/24 -j ACCEPT
iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

# NAT (Маскарадинг) на внешнем интерфейсе
iptables -t nat -A POSTROUTING -o enp0s3 -j MASQUERADE
sysctl -w net.ipv4.ip_forward=1

# 7. Финальный запуск сервисов
systemctl enable --now samba dhcpd

echo "✅ Билет №11 выполнен. Проверьте kinit и фиксированный IP 172.16.1.99."
