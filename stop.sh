#!/bin/sh
#wcd
act=$1
if [[ -z $act || $act == "test" ]]
then
	echo  "test"
	openresty -s stop
	#/usr/local/openresty/nginx/sbin/nginx -s stop -c /usr/local/openresty/nginx/conf/nginx.conf
elif [ $act == "online" ]
then
	echo  "online"
	openresty -s stop
	#/usr/local/openresty/nginx/sbin/nginx -s stop -c /etc/nginx/nginx.conf
fi
