#!/bin/bash
set -e

ADMIN_PASS="Passw0rd123"

echo "=== ФИКС НАСТРОЙКИ СЕРВЕРА ==="

# 1. Жесткий фикс интернета [cite: 1, 2]
echo "Настройка маршрутов..."
# Удаляем ВООБЩЕ все дефолты и ставим один рабочий 
ip route flush default || true
ip route add default via 10.0.2.2 dev enp0s3 || { echo "Ошибка шлюза!"; exit 1; } [cite: 3]
ping -c 2 8.8.8.8 || { echo "Интернета всё еще нет!"; exit 1; } [cite: 3]

# 2. Обновление и установка 
apt-get update && apt-get install -y task-samba-dc dhcp-server

# 3. Очистка перед provision 
systemctl stop samba smb nmb 2>/dev/null || true
rm -f /etc/samba/smb.conf
rm -rf /var/lib/samba/* rm -rf /var/cache/samba/*

# 4. Создание домена 
samba-tool domain provision \
    --use-rfc2307 \
    --realm=TEST.ALT \
    --domain=TEST \
    --server-role=dc \
    --dns-backend=SAMBA_INTERNAL \
    --adminpass="$ADMIN_PASS"

# 5. DNS Фикс (вставляем в Global) 
cp /var/lib/samba/private/krb5.conf /etc/krb5.conf
sed -i '/\[global\]/a \    dns forwarder = 8.8.8.8' /etc/samba/smb.conf

# 6. ЗАПУСК (Для Альта используем сервис samba) [cite: 5, 6]
echo "Запуск Samba..."
systemctl unmask samba
systemctl enable --now samba

# 7. Настройка внутреннего интерфейса (статикой) [cite: 9]
# Чтобы не отвалилось, вешаем адрес явно
ip addr flush dev enp0s8 || true
ip addr add 172.16.1.1/24 dev enp0s8

# 8. DHCP (Конфиг без ошибок в синтаксисе) [cite: 10, 11]
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

# 9. NAT [cite: 11]
sysctl -w net.ipv4.ip_forward=1
iptables -F
iptables -t nat -F
iptables -t nat -A POSTROUTING -o enp0s3 -j MASQUERADE
iptables -A FORWARD -i enp0s8 -o enp0s3 -j ACCEPT

echo "✅ ТЕПЕРЬ ДОЛЖНО ВЗЛЕТЕТЬ!"
