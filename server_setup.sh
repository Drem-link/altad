#!/bin/bash

# ============================================
# Скрипт установки Samba AD Domain Controller
# Домен: TEST-ALT
# IP сервера: 172.16.1.1
# ============================================

set -e  # Остановка при любой ошибке

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Проверка прав root
if [ "$EUID" -ne 0 ]; then
    log_error "Запусти скрипт от root: sudo bash $0"
    exit 1
fi

# Пароль для администратора
ADMIN_PASS="Passw0rd123"

log_info "Начинаем настройку сервера dc1..."

# 1. Обновление системы
log_info "Обновление системы..."
apt-get update && apt-get dist-upgrade -y

# 2. Настройка сети
log_info "Настройка сети..."
mkdir -p /etc/net/ifaces/enp0s3 /etc/net/ifaces/enp0s8

cat > /etc/net/ifaces/enp0s3/options << EOF
BOOTPROTO=dhcp
TYPE=eth
DISABLED=no
NM_CONTROLLED=no
EOF

cat > /etc/net/ifaces/enp0s8/options << EOF
BOOTPROTO=static
TYPE=eth
DISABLED=no
NM_CONTROLLED=no
EOF

echo "172.16.1.1/24" > /etc/net/ifaces/enp0s8/ipv4
systemctl restart network

# 3. Удаление конфликтующих DNS-серверов
log_info "Удаление конфликтующих DNS-серверов..."
apt-get remove bind dnsmasq systemd-resolved -y 2>/dev/null || true

# 4. Установка Samba AD
log_info "Установка Samba AD..."
apt-get install task-samba-dc -y

# Очистка старых конфигов
rm -f /etc/samba/smb.conf
rm -rf /var/lib/samba

# Создание папок
mkdir -p /var/lib/samba/sysvol /var/lib/samba/private

# Создание домена (неинтерактивно)
log_info "Создание домена TEST-ALT..."
samba-tool domain provision \
    --use-rfc2307 \
    --realm=TEST-ALT \
    --domain=TEST \
    --server-role=dc \
    --dns-backend=SAMBA_INTERNAL \
    --dns-forwarder=8.8.8.8 \
    --adminpass="$ADMIN_PASS" \
    --option="interfaces=lo enp0s8" \
    --option="bind interfaces only=yes"

# Копирование Kerberos конфига
cp /var/lib/samba/private/krb5.conf /etc/krb5.conf

# Запуск Samba
systemctl unmask samba-ad-dc
systemctl enable samba-ad-dc
systemctl start samba-ad-dc

# Проверка
sleep 3
if systemctl is-active --quiet samba-ad-dc; then
    log_info "Samba AD успешно запущена"
else
    log_error "Samba AD не запустилась"
    exit 1
fi

# 5. Настройка DHCP
log_info "Настройка DHCP-сервера..."
apt-get install dhcp-server -y

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

# 6. Настройка iptables
log_info "Настройка iptables и NAT..."
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

# SSH с клиента
iptables -A INPUT -p tcp --dport 22 -s 172.16.1.2 -j ACCEPT

# DNS и DHCP
iptables -A INPUT -p udp --dport 53 -s 172.16.1.0/24 -j ACCEPT
iptables -A INPUT -p udp --dport 67 -s 172.16.1.0/24 -j ACCEPT

# Kerberos
iptables -A INPUT -p tcp --dport 88 -s 172.16.1.0/24 -j ACCEPT
iptables -A INPUT -p udp --dport 88 -s 172.16.1.0/24 -j ACCEPT

# NAT
iptables -t nat -A POSTROUTING -o enp0s3 -j MASQUERADE
iptables -A FORWARD -i enp0s8 -o enp0s3 -j ACCEPT

iptables-save > /etc/sysconfig/iptables
systemctl enable iptables
systemctl start iptables

# 7. Создание пользователя для DHCP DNS обновлений
log_info "Настройка DHCP DNS обновлений..."
samba-tool user create dhcpuser --random-password 2>/dev/null || true
samba-tool user setexpiry dhcpuser --noexpiry
samba-tool group addmembers DnsAdmins dhcpuser 2>/dev/null || true
samba-tool domain exportkeytab /etc/dhcp/dhcpd.keytab --principal=dhcpuser@TEST-ALT
chown dhcpd:dhcpd /etc/dhcp/dhcpd.keytab
chmod 640 /etc/dhcp/dhcpd.keytab
systemctl restart dhcpd

log_info "=========================================="
log_info "Настройка сервера ЗАВЕРШЕНА!"
log_info "IP сервера: 172.16.1.1"
log_info "Пароль Administrator: $ADMIN_PASS"
log_info "=========================================="