#!/bin/sh
#wcd
act=$1
if [[ -z $act || $act == "test" ]]
then
	echo  "test"
	#/usr/local/openresty/nginx/sbin/nginx -c /usr/local/openresty/nginx/conf/nginx.conf
	openresty
elif [ $act == "online" ]
then
	echo  "online"
	openresty
	#/usr/local/openresty/nginx/sbin/nginx -c /etc/nginx/nginx.conf
fi
