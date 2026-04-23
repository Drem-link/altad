#!/bin/bash

set -e

ADMIN_PASS="Passw0rd123"
SERVER_IP="172.16.1.1"

echo "=== НАСТРОЙКА КЛИЕНТА ==="

# 1. НАСТРОЙКА СЕТИ (DHCP)
echo "Настройка сети..."
mkdir -p /etc/net/ifaces/enp0s3
cat > /etc/net/ifaces/enp0s3/options << 'EOF'
BOOTPROTO=dhcp
TYPE=eth
DISABLED=no
NM_CONTROLLED=no
EOF

rm -f /etc/net/ifaces/enp0s3/ipv4
rm -f /etc/net/ifaces/enp0s3/ipv4route
systemctl restart network
sleep 5

# 2. УСТАНОВКА ВСЕХ ЕБАНЫХ ПАКЕТОВ
echo "Установка пакетов..."
apt-get update
apt-get install -y \
    task-auth-ad-sssd \
    task-auth-ad \
    samba-client \
    samba-common \
    samba-common-tools \
    krb5-workstation \
    krb5-client \
    realmd \
    oddjob \
    oddjob-mkhomedir \
    sssd \
    sssd-ad \
    sssd-tools \
    adcli \
    policycoreutils-python-utils \
    libnss-sss \
    libpam-sss

# 3. ВКЛЮЧАЕМ ДОМЕННЫЙ ЛОГИН
echo "Включение доменной аутентификации..."
authselect select sssd with-mkhomedir --force

# 4. НАСТРОЙКА KERBEROS
echo "Настройка Kerberos..."
cat > /etc/krb5.conf << EOF
[libdefaults]
    default_realm = TEST-ALT
    dns_lookup_realm = false
    dns_lookup_kdc = true
    ticket_lifetime = 24h
    renew_lifetime = 7d

[realms]
    TEST-ALT = {
        kdc = $SERVER_IP
        admin_server = $SERVER_IP
    }
EOF

# 5. НАСТРОЙКА SSSD
echo "Настройка SSSD..."
cat > /etc/sssd/sssd.conf << EOF
[sssd]
    domains = TEST-ALT
    config_file_version = 2
    services = nss, pam

[domain/TEST-ALT]
    default_shell = /bin/bash
    krb5_store_password_if_offline = True
    cache_credentials = True
    krb5_realm = TEST-ALT
    realmd_tags = manages-system joined-with-adcli
    id_provider = ad
    auth_provider = ad
    access_provider = ad
    chpass_provider = ad
    ad_domain = TEST-ALT
    ad_server = $SERVER_IP
    ad_hostname = $(hostname)
    ldap_id_mapping = True
    fallback_homedir = /home/%u
    default_shell = /bin/bash
EOF

chmod 600 /etc/sssd/sssd.conf

# 6. ПОЛУЧЕНИЕ БИЛЕТА KERBEROS
echo "Получение Kerberos билета..."
echo "$ADMIN_PASS" | kinit administrator@TEST-ALT 2>/dev/null || echo "Kerberos ошибка"

# 7. ВВОД В ДОМЕН ЧЕРЕЗ adcli (НАДЁЖНО)
echo "Ввод в домен через adcli..."
echo "$ADMIN_PASS" | adcli join TEST-ALT -H $(hostname) -U administrator 2>/dev/null || echo "adcli не сработал, пробуем net ads"

# 8. ВВОД В ДОМЕН ЧЕРЕЗ net ads (ЗАПАСНОЙ)
echo "Ввод в домен через net ads..."
echo "$ADMIN_PASS" | net ads join -U Administrator -S $SERVER_IP 2>/dev/null || echo "net ads не сработал"

# 9. ЗАПУСК SSSD
echo "Запуск SSSD..."
systemctl enable sssd
systemctl start sssd

# 10. НАСТРОЙКА PAM ДЛЯ ДОМЕННЫХ ПОЛЬЗОВАТЕЛЕЙ
echo "Настройка PAM..."
cat > /etc/pam.d/system-auth << 'EOF'
auth        required      pam_env.so
auth        sufficient    pam_unix.so nullok try_first_pass
auth        requisite     pam_succeed_if.so uid >= 1000 quiet_success
auth        sufficient    pam_sss.so use_first_pass
auth        required      pam_deny.so

account     required      pam_unix.so
account     sufficient    pam_localuser.so
account     sufficient    pam_succeed_if.so uid < 1000 quiet
account     required      pam_permit.so
account     required      pam_sss.so

password    requisite     pam_pwquality.so try_first_pass local_users_only
password    sufficient    pam_unix.so sha512 shadow nullok try_first_pass use_authtok
password    sufficient    pam_sss.so use_authtok
password    required      pam_deny.so

session     optional      pam_keyinit.so revoke
session     required      pam_limits.so
session     optional      pam_mkhomedir.so
session     optional      pam_oddjob_mkhomedir.so umask=0077
session     required      pam_unix.so
session     optional      pam_sss.so
EOF

echo "=========================================="
echo "НАСТРОЙКА КЛИЕНТА ЗАВЕРШЕНА!"
echo "Перезагрузи: reboot"
echo "Вход: administrator / $ADMIN_PASS"
echo "Или: TEST-ALT\\administrator"
echo "=========================================="
