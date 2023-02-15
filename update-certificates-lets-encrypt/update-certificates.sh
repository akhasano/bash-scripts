#!/bin/bash
export ALB_ID=BK8FPYPszTzc6s1RdFvFnv3Y
export SECURITYGROUP_ID=s5jQWrywX5M6n9E9h9sJVsH3
export ROUTER_ID=Z6TS8WeRdHohSGXbsGLNiPsk
export CERTIFICATE_ID=YhJQI7uE7to1t4p1usxD0F8g
export EMAIL=some_email@email.com
export WEBROOT=/usr/share/nginx/html
export CERTIFICATE_NAME=certificatename
export YC="/home/$USER/.local/bin/yc"

log_print() {
        dt=`date '+%Y-%m-%d %H:%M'`
        printf "%s %s\n" "$dt $1"
}

log_print "Устанавливаем нужный софт (jq,yc)"
sudo apt update && sudo apt install jq -y -qq
mkdir /home/$USER/.local/bin/ -p
curl -k https://nexus.internal.local/repository/binary-private/third-party-apps/yc -o $YC
sudo chmod +x $YC
export PATH="$HOME/.local/bin/:$PATH"
# curl -sSL https://storage.yandexcloud.net/yandexcloud-yc/install.sh | bash

log_print "Данные сертификата до обновления"
$YC certificate-manager certificate get --id="${CERTIFICATE_ID}" --format=json | jq

log_print "Удаляем redirect listener"
$YC application-load-balancer load-balancer remove-listener --id "${ALB_ID}" --listener-name=redirect  > /dev/null 2>&1

log_print "Создаём новый листенер на порту 80"
$YC application-load-balancer load-balancer add-http-listener --listener-name=http80 --http-router-id="${ROUTER_ID}" --external-ipv4-endpoint port=80 --id "${ALB_ID}"  > /dev/null 2>&1

log_print "Ставим python, pip, python-venv"
sudo apt update  > /dev/null 2>&1 && sudo apt install python3 python3-venv python3-pip -y  > /dev/null 2>&1
log_print "Создаём виртуальное окружение и инсталлируем certbot"
python3 -m venv /home/$USER/le && . /home/$USER/le/bin/activate && yes | pip install certbot --quiet  --exists-action i

log_print "Подготавливаем папки для генерации сертификатов"
mkdir /home/$USER/le/config /home/$USER/le/workdir /home/$USER/le/logs -p && sudo chmod o=rwx "${WEBROOT}" -R

log_print "Отключаем группы безопасности"
$YC application-load-balancer load-balancer update "${ALB_ID}" --security-group-id ""  > /dev/null 2>&1

if [[ $1 == "DRY-RUN" ]]; then
    log_print "Запущены в режиме DRY-RUN. Проверка возможности."
    log_print "Запускаем dry-run генерации сертификатов"
    certbot certonly -n --cert-name "${CERTIFICATE_NAME}" --preferred-challenges=http --webroot --webroot-path "${WEBROOT}" --agree-tos -m "${EMAIL}" $(for i in $(cat domains.txt); do printf "\055d %s " $i; done) --key-type rsa --rsa-key-size 2048 --config-dir /home/$USER/le/config --work-dir /home/$USER/le/workdir --logs-dir /home/$USER/le/logs --dry-run

    log_print "Показываем строку выполнения для dry-run режима"
    echo $YC certificate-manager certificate update --id "${CERTIFICATE_ID}" --chain /home/$USER/le/config/live/"${CERTIFICATE_NAME}"/fullchain.pem --key=/home/$USER/le/config/live/"${CERTIFICATE_NAME}"/privkey.pem
else
    log_print "Запуск в прод. режиме. Будут выписаны новый сертификат"
    log_print "Запускаем генерации сертификатов"
    certbot certonly -n --cert-name "${CERTIFICATE_NAME}" --preferred-challenges=http --webroot --webroot-path "${WEBROOT}" --agree-tos -m "${EMAIL}" $(for i in $(cat domains.txt); do printf "\055d %s " $i; done) --key-type rsa --rsa-key-size 2048 --config-dir /home/$USER/le/config --work-dir /home/$USER/le/workdir --logs-dir /home/$USER/le/logs

    log_print "Обновляем сертификат"
    $YC certificate-manager certificate update --id "${CERTIFICATE_ID}" --chain /home/${USER}/le/config/live/${CERTIFICATE_NAME}/fullchain.pem --key=/home/$USER/le/config/live/${CERTIFICATE_NAME}/privkey.pem
fi

log_print "Включаем группы безопасности"
$YC application-load-balancer load-balancer update "${ALB_ID}" --security-group-id "${SECURITYGROUP_ID}"  > /dev/null 2>&1

log_print "Удаляем listener http80"
$YC application-load-balancer load-balancer remove-listener --id "${ALB_ID}" --listener-name=http80  > /dev/null 2>&1

log_print "Создаем listener redirect"
$YC application-load-balancer load-balancer add-http-listener --listener-name=redirect  --redirect-to-https --external-ipv4-endpoint port=80  --id "${ALB_ID}"  > /dev/null 2>&1

log_print "Данные сертификата после обновления"
$YC certificate-manager certificate get --id="${CERTIFICATE_ID}" --format=json | jq