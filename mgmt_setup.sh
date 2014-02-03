#!/bin/bash

# This script installs and configure nginx as load-balancer
# and Monit for monitoring of Docker containers
# at Ubuntu Linux
#

TOOL=$1

function usage {
    cat << EOF
Usage:
$0 [nginx|monit]
EOF
exit 2
}

function install_nginx {
    echo 'Installing Nginx ...'
    echo "deb http://nginx.org/packages/ubuntu $(lsb_release -cs) nginx" > /etc/apt/sources.list.d/nginx.list
    wget -qO- http://nginx.org/keys/nginx_signing.key | apt-key add -
    apt-get update
    apt-get install nginx -y
}

function configure_lb {
    echo Configuring...
    mv /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak
    cp nginx_lb.conf /etc/nginx/nginx.conf
    if [ $? == 0 ]; then
        /etc/init.d/nginx restart
    else
        echo "Warning: Nginx config couldn't be copied. Do it manually and restart service!"
    fi
}

function install_monit {
    echo 'Installing Monit ...'
    apt-get install monit -y
    if [ $? != 0 ]; then
        echo -e "\e[31mERROR: Monit couldn't be installed. Exiting...\e[0m"
        exit 1
    fi
}

function configure_monit {
    mv /etc/monit/monitrc /etc/monit/monitrc.bak
    cp monitrc /etc/monit/monitrc
    chmod 600 /etc/monit/monitrc
    service monit restart
}

########## MAIN ##########

if [ -z $TOOL ]; then
    echo -e "\e[31mERROR: tool to install is not specified.\e[0m"
    usage
fi

case $TOOL in
    nginx)
        install_nginx
        configure_lb
        ;;
    monit)
        install_monit
        configure_monit
        ;;
esac

echo "All is done."
exit 0
