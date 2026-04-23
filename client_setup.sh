#!/bin/bash

Установка пакетов для входа через AD,
apt-get update
apt-get install -y task-auth-ad-sssd

Создание пользователя в домене,
samba-tool user create student --password="Student@2026!" --given-name="Student" --surname="User" --description="Экзаменационный пользователь"
samba-tool user setexpiry student --noexpiry

Проверка,
samba-tool user list
echo ""
echo "=== ПОЛЬЗОВАТЕЛЬ СОЗДАН ==="
echo "Логин: student"
echo "Пароль: Student@2026!"
НОВОЕ

𝐕𝐞𝐬𝐚𝐠𝐨𝐤𝐤 — 6:16пятница, 24 апреля 2026 г. 6:16
#!/bin/bash

# --- ОБЯЗАТЕЛЬНО ПРОВЕРЬ ИМЕНА ИНТЕРФЕЙСОВ ПЕРЕД ЗАПУСКОМ (ip a) ---
IF_INT="enp0s8" 
IF_EXT="enp0s3"
# ------------------------------------------------------------------

Раскрыть (243 строки)
all_server.sh
all_server.sh (10 кб)
10 кб
#!/bin/bash

# =============================================
# СКРИПТ НАСТРОЙКИ КЛИЕНТА (ALT LINUX)
# =============================================

DOMAIN="test.alt"
DOMAIN_UP="TEST.ALT"
WORKGROUP="TEST"
ADMIN_USER="administrator"
ADMIN_PASS="Admin@2026!"

echo "=============================================="
echo "=== 1. ОБНОВЛЕНИЕ СИСТЕМЫ ==="
echo "=============================================="
apt-get update -y
apt-get dist-upgrade -y

echo ""
echo "=============================================="
echo "=== 2. УСТАНОВКА ПАКЕТОВ ==="
echo "=============================================="
apt-get install -y samba-client bind-utils dhcpcd chrony admc

echo ""
echo "=============================================="
echo "=== 3. НАСТРОЙКА DNS ==="
echo "=============================================="
echo "nameserver 172.16.1.1" > /etc/resolv.conf
echo "search $DOMAIN" >> /etc/resolv.conf

echo ""
echo "=============================================="
echo "=== 4. ПОЛУЧЕНИЕ IP ПО DHCP ==="
echo "=============================================="
pkill dhcpcd 2>/dev/null || true
rm -f /var/lib/dhcpcd/*.lease
dhcpcd -4 --noarp

echo ""
echo "=============================================="
echo "=== 5. СИНХРОНИЗАЦИЯ ВРЕМЕНИ ==="
echo "=============================================="
systemctl start chronyd 2>/dev/null || true
chronyc -a makestep

echo ""
echo "=============================================="
echo "=== 6. НАСТРОЙКА HOSTS ==="
echo "=============================================="
IP=$(ip -4 addr show | grep -oP '(?<=inet\s)172\.16\.1\.\d+')
cat > /etc/hosts <<EOF
127.0.0.1       localhost
$IP     $(hostname).$DOMAIN $(hostname)
EOF

echo ""
echo "=============================================="
echo "=== 7. НАСТРОЙКА KERBEROS ==="
echo "=============================================="
cat > /etc/krb5.conf <<EOF
[libdefaults]
    default_realm = $DOMAIN_UP
    dns_lookup_realm = false
    dns_lookup_kdc = true

[realms]
    $DOMAIN_UP = {
        kdc = 172.16.1.1
        admin_server = 172.16.1.1
    }

[domain_realm]
    .$DOMAIN = $DOMAIN_UP
    $DOMAIN = $DOMAIN_UP
EOF

echo ""
echo "=============================================="
echo "=== 8. ОЧИСТКА СТАРЫХ ДАННЫХ SAMBA ==="
echo "=============================================="
systemctl stop winbind smb nmb 2>/dev/null || true
rm -rf /etc/samba/* /var/lib/samba/* /var/cache/samba/*
mkdir -p /var/lib/samba/private /var/cache/samba

echo ""
echo "=============================================="
echo "=== 9. СОЗДАНИЕ SMB.CONF ==="
echo "=============================================="
cat > /etc/samba/smb.conf <<EOF
[global]
   workgroup = $WORKGROUP
   security = ADS
   realm = $DOMAIN_UP
   netbios name = $(hostname | tr '[:lower:]' '[:upper:]')
EOF

echo ""
echo "=============================================="
echo "=== 10. ВВОД В ДОМЕН ==="
... (осталось: 38 строк)

Свернуть (138 строк)
client.sh
client.sh (5 кб)
5 кб
#!/bin/bash

# =============================================
# СКРИПТ ДИАГНОСТИКИ И АВТОИСПРАВЛЕНИЯ
# =============================================

Раскрыть (202 строки)
fix.sh
fix.sh (9 кб)
9 кб
#!/bin/bash

# =============================================
# СКРИПТ ДИАГНОСТИКИ И АВТОИСПРАВЛЕНИЯ КЛИЕНТА
# =============================================

Раскрыть (198 строк)
fix_client.sh
fix_client.sh (7 кб)
7 кб
:man_in_manual_wheelchair_facing_right:
Нажмите, чтобы отреагировать
:flag_ru:
Нажмите, чтобы отреагировать
:point_left:
Нажмите, чтобы отреагировать
Добавить реакцию
Ответить
Переслать
Ещё

Написать @𝐕𝐞𝐬𝐚𝐠𝐨𝐤𝐤
﻿
Отправить GIF
НА ШКОНКЕ
Отец
1
ТРАМВАЙ


#!/bin/bash

# =============================================
# СКРИПТ НАСТРОЙКИ КЛИЕНТА (ALT LINUX)
# =============================================

DOMAIN="test.alt"
DOMAIN_UP="TEST.ALT"
WORKGROUP="TEST"
ADMIN_USER="administrator"
ADMIN_PASS="Admin@2026!"

echo "=============================================="
echo "=== 1. ОБНОВЛЕНИЕ СИСТЕМЫ ==="
echo "=============================================="
apt-get update -y
apt-get dist-upgrade -y

echo ""
echo "=============================================="
echo "=== 2. УСТАНОВКА ПАКЕТОВ ==="
echo "=============================================="
apt-get install -y samba-client bind-utils dhcpcd chrony admc

echo ""
echo "=============================================="
echo "=== 3. НАСТРОЙКА DNS ==="
echo "=============================================="
echo "nameserver 172.16.1.1" > /etc/resolv.conf
echo "search $DOMAIN" >> /etc/resolv.conf

echo ""
echo "=============================================="
echo "=== 4. ПОЛУЧЕНИЕ IP ПО DHCP ==="
echo "=============================================="
pkill dhcpcd 2>/dev/null || true
rm -f /var/lib/dhcpcd/*.lease
dhcpcd -4 --noarp

echo ""
echo "=============================================="
echo "=== 5. СИНХРОНИЗАЦИЯ ВРЕМЕНИ ==="
echo "=============================================="
systemctl start chronyd 2>/dev/null || true
chronyc -a makestep

echo ""
echo "=============================================="
echo "=== 6. НАСТРОЙКА HOSTS ==="
echo "=============================================="
IP=$(ip -4 addr show | grep -oP '(?<=inet\s)172\.16\.1\.\d+')
cat > /etc/hosts <<EOF
127.0.0.1       localhost
$IP     $(hostname).$DOMAIN $(hostname)
EOF

echo ""
echo "=============================================="
echo "=== 7. НАСТРОЙКА KERBEROS ==="
echo "=============================================="
cat > /etc/krb5.conf <<EOF
[libdefaults]
    default_realm = $DOMAIN_UP
    dns_lookup_realm = false
    dns_lookup_kdc = true

[realms]
    $DOMAIN_UP = {
        kdc = 172.16.1.1
        admin_server = 172.16.1.1
    }

[domain_realm]
    .$DOMAIN = $DOMAIN_UP
    $DOMAIN = $DOMAIN_UP
EOF

echo ""
echo "=============================================="
echo "=== 8. ОЧИСТКА СТАРЫХ ДАННЫХ SAMBA ==="
echo "=============================================="
systemctl stop winbind smb nmb 2>/dev/null || true
rm -rf /etc/samba/* /var/lib/samba/* /var/cache/samba/*
mkdir -p /var/lib/samba/private /var/cache/samba

echo ""
echo "=============================================="
echo "=== 9. СОЗДАНИЕ SMB.CONF ==="
echo "=============================================="
cat > /etc/samba/smb.conf <<EOF
[global]
   workgroup = $WORKGROUP
   security = ADS
   realm = $DOMAIN_UP
   netbios name = $(hostname | tr '[:lower:]' '[:upper:]')
EOF

echo ""
echo "=============================================="
echo "=== 10. ВВОД В ДОМЕН ==="
echo "=============================================="
net ads join -U $ADMIN_USER%"$ADMIN_PASS"

echo ""
echo "=============================================="
echo "=== 11. НАСТРОЙКА WINBIND ==="
echo "=============================================="
cat > /etc/samba/smb.conf <<EOF
[global]
   workgroup = $WORKGROUP
   realm = $DOMAIN_UP
   security = ADS
   encrypt passwords = yes
   idmap config * : backend = tdb
   idmap config * : range = 10000-20000
   winbind use default domain = yes
   template shell = /bin/bash
   template homedir = /home/%D/%U
EOF

systemctl enable --now winbind

echo ""
echo "=============================================="
echo "=== 12. ПРОВЕРКА ==="
echo "=============================================="
echo "=== ДОМЕН ===" && net ads info
echo ""
echo "=== ПОЛЬЗОВАТЕЛИ ===" && wbinfo -u
echo ""

echo "=============================================="
echo "=== КЛИЕНТ ГОТОВ! ==="
echo "=============================================="
echo ""
echo "Для запуска ADMC выполни:"
echo "  kinit administrator@TEST.ALT"
echo "  admc"
client.sh
client.sh (5 кб)
5 кб
