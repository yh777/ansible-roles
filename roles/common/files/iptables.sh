#!/bin/bash

######### ENV ####################
# env_start
export LANG=C
export LC_ALL=C
export PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
# env_over


### kernel modules ##############
modules="ip_conntrack_ftp ip_conntrack_irc"
for mod in $modules
do
    testmod=`lsmod | grep "${mod}"`
    if [ "$testmod" == "" ]; then
        modprobe $mod
    fi
done

###### filter table ################

###### INPUT chains ######
iptables -P INPUT ACCEPT
iptables -P OUTPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -F
iptables -F -t nat
iptables -X
iptables -X -t nat
iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -p icmp -m icmp --icmp-type any -m limit --limit 100/s -j ACCEPT

### zabbix ###
#iptables -A INPUT -s 123.57.185.94 -p tcp --dport 10050 -j ACCEPT

# MySQL

#WEB
#iptables -A INPUT -p tcp --dport 80 -j ACCEPT
#iptables -A INPUT -p tcp --dport 443 -j ACCEPT

#SSHD
iptables -A INPUT -p tcp --dport 37212 -j ACCEPT

# Trust
iptables -A INPUT -s 172.16.130.164 -j ACCEPT
iptables -A INPUT -s 172.16.44.145 -j ACCEPT
iptables -A INPUT -s 172.16.44.146 -j ACCEPT
iptables -A INPUT -s 172.16.44.147 -j ACCEPT
iptables -A INPUT -s 172.16.44.149 -j ACCEPT
iptables -A INPUT -s 172.16.44.148 -j ACCEPT

iptables -A FORWARD -o docker0 -m state --state RELATED,ESTABLISHED -j ACCEPT    # 已经建立连接的包
iptables -A FORWARD -o docker_gwbridge -m state --state RELATED,ESTABLISHED -j ACCEPT

iptables -A FORWARD -i docker0 ! -o docker0 -j ACCEPT           # 容器访问外网
iptables -A FORWARD -i docker_gwbridge ! -o docker_gwbridge -j ACCEPT

iptables -A FORWARD -i docker0 -o docker0 -j ACCEPT             # 容器互访
iptables -A FORWARD -i docker_gwbridge -o docker_gwbridge -j ACCEPT

iptables -t nat -A POSTROUTING -o eth0 -s 192.168.0.0/16 -j MASQUERADE    # 容器访问外网SNAT

### global ###
iptables -A INPUT -j REJECT --reject-with icmp-host-prohibited



