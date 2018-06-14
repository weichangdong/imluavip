###################################################################
# File Name: del_img_video.sh
# Author: wcd
du  -hs /data/v3-p2papi/app2/resource/
find  /data/v3-p2papi/app2/resource/ -type f -mtime +15 -exec rm -fv {} \;
du  -hs /data/v3-p2papi/app2/resource/