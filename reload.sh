#!/bin/sh
act=$1
if [[ -z $act || $act == "test" ]]
then
	echo  "test"
	#/usr/local/openresty/nginx/sbin/nginx -s reload -c /usr/local/openresty/nginx/conf/nginx.conf
	openresty -s  reload
elif [ $act == "online" ]
then
	echo  "online"
	#/usr/local/openresty/nginx/sbin/nginx -s reload -c /etc/nginx/nginx.conf
	openresty -s  reload
fi