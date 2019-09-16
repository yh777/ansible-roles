#!/bin/bash

kernel_num=$(sudo awk -F\' '$1=="menuentry " {print i++ " : " $2}' /etc/grub2.cfg | grep 'CentOS Linux (5' | awk '{print $1}')
sed -i s/GRUB_DEFAULT=.*/GRUB_DEFAULT=$kernel_num/ /etc/default/grub
