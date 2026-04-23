#!/bin/bash

echo "=== УСТАНОВКА ПАКЕТОВ ДЛЯ ДОМЕНА ==="

apt-get update
apt-get install -y \
    task-auth-ad-sssd \
    krb5-workstation \
    realmd \
    samba-client \
    adcli \
    sssd \
    sssd-tools

echo "=== ПАКЕТЫ УСТАНОВЛЕНЫ ==="
echo "Дальше вводи в домен командой:"
echo "realm join --user=administrator TEST-ALT"
