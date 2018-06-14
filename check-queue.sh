re=$(ps  axf|grep  queue.lua|grep  v3)
day=`date  "+%Y-%m-%d %H:%M:%S"`
if [ "$re" = "" ]
then
        echo  "$day error"
        #source /etc/profile.d/wcd.sh && 
        nohup  lua /data/v3-p2papi/app2/cmd/queue.lua 1>>/data/v3-p2papi/log/queue.log 2>&1 &
fi