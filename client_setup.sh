#!/bin/bash

# ============================================
# Скрипт ввода клиента в домен TEST-ALT
# ============================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Проверка прав root
if [ "$EUID" -ne 0 ]; then
    log_error "Запусти скрипт от root: sudo bash $0"
    exit 1
fi

ADMIN_PASS="Passw0rd123"
SERVER_IP="172.16.1.1"
DOMAIN="TEST-ALT"

log_info "Начинаем настройку клиента..."

# 1. Обновление
log_info "Обновление системы..."
apt-get update && apt-get dist-upgrade -y

# 2. Настройка сети (DHCP)
log_info "Настройка сети..."
mkdir -p /etc/net/ifaces/enp0s3
cat > /etc/net/ifaces/enp0s3/options << EOF
BOOTPROTO=dhcp
TYPE=eth
DISABLED=no
NM_CONTROLLED=no
EOF

systemctl restart network

# 3. Установка пакетов
log_info "Установка пакетов для домена..."
apt-get install task-auth-ad-sssd samba-client krb5-workstation realmd -y

# 4. Настройка Kerberos
log_info "Настройка Kerberos..."
cat > /etc/krb5.conf << EOF
[libdefaults]
    default_realm = $DOMAIN
    dns_lookup_realm = false
    dns_lookup_kdc = true

[realms]
    $DOMAIN = {
        kdc = $SERVER_IP
        admin_server = $SERVER_IP
    }
EOF

# 5. Проверка Kerberos
log_info "Проверка Kerberos..."
echo "$ADMIN_PASS" | kinit administrator@$DOMAIN 2>/dev/null || {
    log_error "Kerberos не работает. Проверь доступность сервера."
    exit 1
}
klist

# 6. Создание Samba конфига
log_info "Настройка Samba..."
mkdir -p /etc/samba /var/lib/samba/private /var/log/samba

cat > /etc/samba/smb.conf << EOF
[global]
   workgroup = TEST
   realm = $DOMAIN
   security = ads
   server role = standalone
   log file = /var/log/samba/%m.log
   max log size = 50
   winbind use default domain = yes
   winbind enum users = yes
EOF

chmod 0700 /var/lib/samba /var/lib/samba/private 2>/dev/null || true

# 7. Ввод в домен
log_info "Ввод в домен $DOMAIN..."
echo "$ADMIN_PASS" | net ads join -U Administrator -S $SERVER_IP 2>/dev/null || {
    log_error "Не удалось войти в домен"
    exit 1
}

# 8. Автоматическая настройка через alterator (acc)
log_info "Настройка аутентификации..."
cat > /tmp/ad_auth.exp << 'EOF'
#!/usr/bin/expect
set timeout 30
spawn acc
sleep 2
send -- "\t\t"
send -- "\t\t"
send -- "\r"
sleep 1
send -- "\r"
sleep 2
send -- "\r"
sleep 1
send -- "TEST-ALT\r"
send -- "172.16.1.1\r"
send -- "administrator\r"
send -- "Passw0rd123\r"
sleep 2
send -- "\t\r"
sleep 5
send -- "\r"
expect eof
EOF

chmod +x /tmp/ad_auth.exp
/tmp/ad_auth.exp 2>/dev/null || log_warn "Автонастройка не удалась, настрой вручную: acc → Аутентификация"

rm -f /tmp/ad_auth.exp

log_info "=========================================="
log_info "Настройка клиента ЗАВЕРШЕНА!"
log_info "Перезагрузи клиент: reboot"
log_info "После перезагрузки войди как: administrator  Пароль: $ADMIN_PASS"
log_info "Или: TEST\\administrator"
log_info "=========================================="
