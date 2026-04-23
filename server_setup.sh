#!/bin/bash
set -e

# Переменные из билета
ADMIN_PASS="Passw0rd123"
REALM="TEST.ALT"
DOMAIN="TEST"
SERVER_IP="172.16.1.1"

echo "=== ВЫПОЛНЕНИЕ ЭКЗАМЕНАЦИОННОГО БИЛЕТА №11 ==="

# 1. Жесткий фикс интернета (через enp0s3)
ip route flush default || true
ip route add default via 10.0.2.2 dev enp0s3 || true
echo "nameserver 8.8.8.8" > /etc/resolv.conf

# 2. Установка пакетов (бинд и самба)
apt-get update
apt-get install -y task-samba-dc dhcp-server bind-utils || apt-get install -y task-samba-dc dhcp-server bind9-utils

# 3. Чистка и развертывание AD
systemctl stop samba 2>/dev/null || true
rm -rf /etc/samba/smb.conf /var/lib/samba/* /var/cache/samba/*

samba-tool domain provision \
  --use-rfc2307 \
  --realm=$REALM \
  --domain=$DOMAIN \
  --server-role=dc \
  --dns-backend=SAMBA_INTERNAL \
  --adminpass="$ADMIN_PASS"

# 4. Настройка Kerberos и старт
cp /var/lib/samba/private/krb5.conf /etc/krb5.conf
systemctl unmask samba
systemctl enable --now samba

echo "Ждем инициализации базы данных..."
sleep 15

# 5. Экспорт ключа TSIG для DDNS (Пункт 6 билета)
# Важно: используем dc.test.alt (имя хоста на скринах - dc)
samba-tool domain exportkeytab /etc/dhcp/dhcp.keytab --principal=dc\$@$REALM || \
samba-tool domain exportkeytab /etc/dhcp/dhcp.keytab --principal=Administrator@$REALM

chown root:root /etc/dhcp/dhcp.keytab
chmod 600 /etc/dhcp/dhcp.keytab

# 6. Конфиг DHCP (DDNS + Резервирование)
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

    # Пункт 8 билета: Фиксация IP для workstation
    host workstation {
        hardware ethernet 08:00:27:ab:cd:ef;
        fixed-address 172.16.1.99;
    }
}
EOF

echo 'DHCPDARGS="enp0s8"' > /etc/sysconfig/dhcpd
systemctl enable --now dhcpd

# 7. IPTABLES (Пункт 7 билета - БЕЗОПАСНОСТЬ)
iptables -F
iptables -X
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# Разрешаем SSH только для админа (172.16.1.2)
iptables -A INPUT -p tcp -s 172.16.1.2 --dport 22 -j ACCEPT
# Разрешаем локалку, петлю и установленные связи
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -s 172.16.1.0/24 -j ACCEPT
iptables -A FORWARD -s 172.16.1.0/24 -j ACCEPT
iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

# NAT и Forwarding
iptables -t nat -A POSTROUTING -o enp0s3 -j MASQUERADE
sysctl -w net.ipv4.ip_forward=1

echo "✅ БИЛЕТ №11 ГОТОВ!"
