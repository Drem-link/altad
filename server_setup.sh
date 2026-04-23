#!/bin/bash

set -e

ADMIN_PASS="Passw0rd123"

echo "=== ИТОГОВАЯ НАСТРОЙКА СЕРВЕРА (ALT LINUX) ==="

# 1. Жесткая настройка интернета
echo "Проверка интернета..."
ip route flush default || true
ip route add default via 10.0.2.2 dev enp0s3 || { echo "Ошибка: проверьте адаптер NAT"; exit 1; }
ping -c 2 8.8.8.8 || { echo "Нет связи с интернетом!"; exit 1; }

# 2. Обновление и установка пакетов
apt-get update && apt-get install -y task-samba-dc dhcp-server

# 3. Полная очистка Samba перед настройкой
systemctl stop samba 2>/dev/null || true
rm -f /etc/samba/smb.conf
rm -rf /var/lib/samba/*
rm -rf /var/cache/samba/*

# 4. Создание домена
samba-tool domain provision \
    --use-rfc2307 \
    --realm=TEST.ALT \
    --domain=TEST \
    --server-role=dc \
    --dns-backend=SAMBA_INTERNAL \
    --adminpass="$ADMIN_PASS"

# 5. Настройка DNS и Kerberos
cp /var/lib/samba/private/krb5.conf /etc/krb5.conf
sed -i '/\[global\]/a \    dns forwarder = 8.8.8.8' /etc/samba/smb.conf

# 6. Запуск Samba (в Альте это один сервис)
echo "Запуск контроллера домена..."
systemctl unmask samba
systemctl enable --now samba

# 7. Настройка внутреннего интерфейса
echo "Настройка сети enp0s8..."
ip addr flush dev enp0s8 || true
ip addr add 172.16.1.1/24 dev enp0s8

# 8. Настройка DHCP
cat > /etc/dhcp/dhcpd.conf << EOF
subnet 172.16.1.0 netmask 255.255.255.0 {
    range 172.16.1.100 172.16.1.200;
    option routers 172.16.1.1;
    option domain-name-servers 172.16.1.1;
    option domain-name "test.alt";
}
EOF
echo 'DHCPDARGS="enp0s8"' > /etc/sysconfig/dhcpd
systemctl enable --now dhcpd

# 9. Настройка NAT (интернет для клиентов)
sysctl -w net.ipv4.ip_forward=1
iptables -F
iptables -t nat -F
iptables -t nat -A POSTROUTING -o enp0s3 -j MASQUERADE
iptables -A FORWARD -i enp0s8 -o enp0s3 -j ACCEPT

echo "✅ ГОТОВО! Контроллер домена и DHCP запущены."
