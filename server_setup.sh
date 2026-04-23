#!/bin/bash

# ============================================
# Скрипт установки Samba AD Domain Controller
# Автоопределение интерфейсов
# ============================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

if [ "$EUID" -ne 0 ]; then
    log_error "Запусти скрипт от root: sudo bash $0"
    exit 1
fi

ADMIN_PASS="Passw0rd123"

# ============================================
# Автоопределение интерфейсов
# ============================================
log_info "Определение сетевых интерфейсов..."

# Внешний интерфейс (смотрит в интернет)
# Ищем интерфейс с дефолтным маршрутом или с IP в сети 10.0.2.0/24 (VirtualBox NAT)
EXT_IF=$(ip route | grep default | awk '{print $5}' | head -1)
if [ -z "$EXT_IF" ]; then
    # Если нет дефолтного маршрута, ищем интерфейс с IP 10.0.2.x
    EXT_IF=$(ip -4 addr show | grep -oP 'inet 10\.0\.2\.\d+.*' | awk '{print $NF}' | head -1)
fi

# Внутренний интерфейс (локальная сеть)
# Ищем интерфейс с IP в сети 172.16.1.0/24 или любой другой интерфейс, кроме внешнего
INT_IF=$(ip -4 addr show | grep -oP 'inet 172\.16\.1\.\d+.*' | awk '{print $NF}' | head -1)

if [ -z "$INT_IF" ]; then
    # Если нет IP 172.16.1.x, выбираем первый интерфейс, не являющийся внешним и lo
    for iface in $(ls /sys/class/net/ | grep -v lo); do
        if [ "$iface" != "$EXT_IF" ]; then
            INT_IF="$iface"
            break
        fi
    done
fi

if [ -z "$EXT_IF" ] || [ -z "$INT_IF" ]; then
    log_error "Не удалось определить интерфейсы. Укажи вручную:"
    log_error "Внешний интерфейс (интернет): $EXT_IF"
    log_error "Внутренний интерфейс (локальная сеть): $INT_IF"
    exit 1
fi

log_info "Внешний интерфейс (интернет): $EXT_IF"
log_info "Внутренний интерфейс (локальная сеть): $INT_IF"

# Шлюз для VirtualBox NAT (обычно 10.0.2.2)
GATEWAY="10.0.2.2"

# ============================================
# Настройка сети
# ============================================
log_info "Настройка сети..."

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
sleep 5

# Убеждаемся, что есть шлюз через внешний интерфейс
if ! ip route | grep -q "default via $GATEWAY"; then
    log_info "Добавляем шлюз по умолчанию через $EXT_IF..."
    ip route add default via $GATEWAY dev $EXT_IF 2>/dev/null || true
    echo "default via $GATEWAY" > /etc/net/ifaces/$EXT_IF/ipv4route
    systemctl restart network
fi

# Проверка интернета
if ! ping -c 2 8.8.8.8 &>/dev/null; then
    log_warn "Интернет не работает! Проверь подключение."
    log_warn "Возможно, шлюз отличается от $GATEWAY"
    log_warn "Найди правильный шлюз командой: ip route | grep default"
fi

# ============================================
# Удаление конфликтующих DNS-серверов
# ============================================
log_info "Удаление конфликтующих DNS-серверов..."
apt-get remove bind dnsmasq systemd-resolved -y 2>/dev/null || true

# ============================================
# Установка Samba AD
# ============================================
log_info "Установка Samba AD..."
apt-get update && apt-get dist-upgrade -y
apt-get install task-samba-dc -y

rm -f /etc/samba/smb.conf
rm -rf /var/lib/samba
mkdir -p /var/lib/samba/sysvol /var/lib/samba/private

log_info "Создание домена TEST-ALT..."
samba-tool domain provision \
    --use-rfc2307 \
    --realm=TEST-ALT \
    --domain=TEST \
    --server-role=dc \
    --dns-backend=SAMBA_INTERNAL \
    --adminpass="$ADMIN_PASS" \
    --option="interfaces=lo $INT_IF" \
    --option="bind interfaces only=yes"

cp /var/lib/samba/private/krb5.conf /etc/krb5.conf
echo "dns forwarder = 8.8.8.8" >> /etc/samba/smb.conf

systemctl unmask samba-ad-dc
systemctl enable samba-ad-dc
systemctl start samba-ad-dc
sleep 5

if ! systemctl is-active --quiet samba-ad-dc; then
    log_error "Samba AD не запустилась"
    systemctl status samba-ad-dc --no-pager
    exit 1
fi

# ============================================
# Настройка DHCP
# ============================================
log_info "Настройка DHCP-сервера..."
apt-get install dhcp-server -y

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

# ============================================
# Настройка iptables
# ============================================
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

iptables -A INPUT -p tcp --dport 22 -s 172.16.1.2 -j ACCEPT
iptables -A INPUT -p udp --dport 53 -s 172.16.1.0/24 -j ACCEPT
iptables -A INPUT -p udp --dport 67 -s 172.16.1.0/24 -j ACCEPT
iptables -A INPUT -p tcp --dport 88 -s 172.16.1.0/24 -j ACCEPT
iptables -A INPUT -p udp --dport 88 -s 172.16.1.0/24 -j ACCEPT

iptables -t nat -A POSTROUTING -o $EXT_IF -j MASQUERADE
iptables -A FORWARD -i $INT_IF -o $EXT_IF -j ACCEPT

iptables-save > /etc/sysconfig/iptables
systemctl enable iptables
systemctl start iptables

# ============================================
# Пользователь для DHCP DNS обновлений
# ============================================
log_info "Настройка DHCP DNS обновлений..."
samba-tool user create dhcpuser --random-password 2>/dev/null || true
samba-tool user setexpiry dhcpuser --noexpiry 2>/dev/null || true
samba-tool group addmembers DnsAdmins dhcpuser 2>/dev/null || true
samba-tool domain exportkeytab /etc/dhcp/dhcpd.keytab --principal=dhcpuser@TEST-ALT 2>/dev/null || true
chown dhcpd:dhcpd /etc/dhcp/dhcpd.keytab 2>/dev/null || true
chmod 640 /etc/dhcp/dhcpd.keytab 2>/dev/null || true
systemctl restart dhcpd

# ============================================
# Финальный вывод
# ============================================
log_info "=========================================="
log_info "Настройка сервера ЗАВЕРШЕНА!"
log_info "Внешний интерфейс: $EXT_IF | Внутренний: $INT_IF"
log_info "IP сервера: 172.16.1.1"
log_info "Пароль Administrator: $ADMIN_PASS"
log_info "=========================================="
