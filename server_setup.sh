#!/bin/bash

ADMIN_PASS="Passw0rd123"

echo "=== НАСТРОЙКА СЕРВЕРА ==="

# 1. Чистка порта 53
fuser -k 53/tcp 53/udp 2>/dev/null
systemctl stop bind dnsmasq systemd-resolved 2>/dev/null
apt-get remove -y bind dnsmasq systemd-resolved 2>/dev/null

# 2. Обновление и установка Samba
apt-get update && apt-get dist-upgrade -y
apt-get install -y task-samba-dc

# 3. Чистый создание домена
rm -f /etc/samba/smb.conf
rm -rf /var/lib/samba
mkdir -p /var/lib/samba/sysvol /var/lib/samba/private

samba-tool domain provision \
    --use-rfc2307 \
    --realm=TEST-ALT \
    --domain=TEST \
    --server-role=dc \
    --dns-backend=SAMBA_INTERNAL \
    --adminpass="$ADMIN_PASS"

# 4. Настройка DNS и запуск
cp /var/lib/samba/private/krb5.conf /etc/krb5.conf
echo "dns forwarder = 8.8.8.8" >> /etc/samba/smb.conf

systemctl unmask samba
systemctl enable samba
systemctl start samba

# 5. DHCP (если нужен)
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

# 6. NAT (только если нет)
sysctl -w net.ipv4.ip_forward=1
iptables -t nat -A POSTROUTING -o enp0s3 -j MASQUERADE
iptables -A FORWARD -i enp0s8 -o enp0s3 -j ACCEPT
iptables-save > /etc/sysconfig/iptables

echo "✅ ГОТОВО"
