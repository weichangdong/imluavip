local html_router = {}
local redis = require("app2.lib.redis")
local config = require("app2.config.config")
local my_redis = redis:new()
local ngx = ngx
local md5 = ngx.md5
local exit = ngx.exit
local utils = require("app2.lib.utils")
local json = require("cjson.safe")
local table_object  = json.encode_empty_table_as_object
local pairs = pairs

html_router.letsgo_get_html = function(req, res, next)
    local id = req.params.id
    local tmp_data = my_redis:hget(config.redis_key.moments_prefix_hash_key .. id,"data")
    if utils.is_redis_null(tmp_data) then
        ngx.print("Sorry, It doesn't exist or is deleted")
        exit(200)
    end
    local mm_data = json.decode(tmp_data)
    --1:img-list 2:video
    local add_type = mm_data.add_type
    local price = mm_data.price
    local base_url = mm_data.base_url
    local position = mm_data.position
    local desc = mm_data.desc
    local uid = mm_data.uid
    local base_info_tmp = my_redis:hget(config.redis_key.user_prefix .. uid, "base_info")
    if utils.is_redis_null(base_info_tmp) then
        ngx.print('Sorry, It doesn\'t exist or is deleted')
        exit(200)
    end
    local base_info = json.decode(base_info_tmp) 
    local username = base_info.username
    local ok_username
    if utils.utf8len(username) > 15 then
        ok_username = string.sub(username,1,15).."..."
    else
        ok_username = username
    end
    local avatar = base_info.avatar
    local hot_num = my_redis:hget(config.redis_key.moments_prefix_hash_key .. id,"hot")
    local urls
    local video_cover,video_url
    local img_video_list=""
    local ok_img_video_list
    local down_load_url = "https://play.google.com/store/apps/details?id=com.hot.girl.sexy.video.youporn.Xvideos.Tube8.porn.pornhub.paramount"
    local data_value = 0
    if price > 0 then
        if add_type == 1 then
            urls = mm_data.img_urls
            img_video_list = base_url..urls[1]
            --图片蒙层 付费
            ok_img_video_list='<div class="flexslider" style="height:800px;margin-top:0px;margin-left:50px;float: left;position:relative;" ><div class="suo"><img src="https://wcd.cloudfront.net/html/lock.png"></div><img src="'..img_video_list..'" style="height:800px;opacity: 0.2;width:800px;"/></div>'
        else
            video_url = base_url..mm_data.video_url
            video_cover = base_url..mm_data.video_cover
            --视频播放付费
		    ok_img_video_list = '<div class="flexslider" style="height:800px;margin-top:0px;margin-left:25px;float: left;position:relative;text-align:center" ><div class="suo"><img src="https://wcd.cloudfront.net/html/app.png"></div><div class="play"><img src="https://wcd.cloudfront.net/html/play.png" style="width:200px;height:200px"></div><img src="'..video_cover..'" style="width:850px;height:800px;opacity: 0.2;margin-left:-10px"/></div>'
        end
    else
        if add_type == 1 then
            urls = mm_data.img_urls
            for _,img_name in pairs(urls) do
                img_video_list = img_video_list..'<li><img src="'..base_url..img_name..'" style="height:800px"/></li>'
            end
            --图片轮播 免费
            ok_img_video_list = '<div  class="flexslider" style="height:800px" id="wcd"><ul class="slides">'..img_video_list..'</ul></div>'
        else
            --视频播放 免费
            video_url = base_url..mm_data.video_url
            video_cover = base_url..mm_data.video_cover
            ok_img_video_list = '<div  class="flexslider" id="wcd" ><ul class="slides"><video id="media" src="'..video_url..'" poster="'..video_cover..'" controls width="100%" width= 100%; height=800px; object-fit: fill></video></ul></div>'
        end
    end

    local html = [[
<!DOCTYPE html>
<html>
	<head>
<meta charset="utf-8" />
<link rel="stylesheet" type="text/css" href="https://wcd.cloudfront.net/html/flexslider.css" />
<script type="text/javascript" src="https://wcd.cloudfront.net/html/jquery.js"></script>
<script type="text/javascript" src="https://wcd.cloudfront.net/html/jquery.flexslider-min.js"></script>
		<title>Paramount</title>
	</head>
	<body>
		<div id="background">
		<div id="page_one" style="height:1250px">
		    <div id="click">
			<div id="header_one" >
				<div id="headone_image"style="border-radius:50%;" >
					<img src="]]..avatar..[[" style="width:150px;height:150px;border-radius:50%;"/>
                </div>
                
                <div id="biaoti" style="width:75%;">
				<div id="nicheng"><p style="margin-top:2px;font-size:65px;">]]
                ..ok_username..
                [[</p></div>
					<p style="margin-top:40px;color:lightgray;color: #989898;font-size: 40px;">]]
                    ..position..
                    [[</p>
					<hr style="margin-top:-10px;color:rgba(0,0,0,0.08);width:700px"/>
				</div>				
			</div>
			<div id="text" style="padding-left:20px;width:850px;">
            ]]
            ..desc..
            [[
			</div>
            ]]
            ..ok_img_video_list.. 
			[[</div>
			<div id="foot" style="height:100px;">
		
				<div id="comment" class="foot_comment" >
					<div style="float: left;"><img src="https://wcd.cloudfront.net/html/ic_chat_black_24px.svg" style="width:60px;height:60px;"/></div>
					<div class="foot_text" style="color:#777777;letter-spacing: 0.33px;font-size: 50px;margin-top:3px;margin-left:30px;">476</div>
				</div>
				<div id="like" class="foot_comment" >
					<div style="float: left;"><img src="https://wcd.cloudfront.net/html/hot.svg"  style="width:60px;height:60px;"/></div>
					<div class="foot_text" style="color:#777777;letter-spacing: 0.33px;font-size: 50px;margin-top:5px;margin-left:30px;">]]..hot_num..[[</div>
				</div>
			</div>
		</div>
       
        <div id="foot_alert" style="background-color: #4C4C4C;height:130px">
        	<div style="float:left;margin-left:50px;margin-top:20px;"><img src="https://wcd.cloudfront.net/html/app.png" style="width:80px;height:80px;"></div>
        	<div id="download_text" style="margin-left:50px;margin-top:10px;">Download Paramount</div>
        	<a href="]]..down_load_url..[[">
        	<div id="download_button" style="margin-left:750px;float:left;height:70px;margin-top:-75px;background:#21C6B2;
border-radius: 2px;text-align: center;line-height:70px;font-size: 30px;">
            <strong>DOWNLOAD</strong>
        	</div></a>
        </div>
        </div>
         <div id="alert_download" style="display:none;width:700px;height:600px;position:absolute;z-index: 999;border-radius: 2px;background: #FAFAFA;margin-left:130px;box-shadow: -10 -10 5px 0 ">
        	<div id="touxiang" style="margin-top:-100px;text-align: center;border-radius:50%;"><img src="]]..avatar..[[" style="width:250px;height:250px;border-radius:50%;"></div>
			<p class="downtext" style="color: #F5A623;">Do you want to </p>
			<p class="downtext" style="color: #F5A623;">konw more about me?</p>
			<p class="downtext" style="color: #989898;line-height: 48px;">Download paramount now!</p>
           
			<div style="width:650px;height:120px;background-color:  #21C6B2;margin:0 auto;border-radius: 2px;">
				<a href="]]..down_load_url..[["><p style="text-align: center;color: white;line-height: 120px;font-size:50px;">DOWNLOAD</p></a>
			</div>
		</div>
        <script type="text/javascript">
            $(function() {
                $(".flexslider").flexslider({
                    slideshowSpeed: 3000, //展示时间间隔ms
                    animationSpeed: 300, //滚动时间ms
                    touch: true
                });
            });
var myBtn  = document.getElementById('page_one');
var Background=document.getElementById('page_one');
var myDiv = document.getElementById('alert_download');
var back = document.getElementById('background');
myBtn.onclick = function(e){
    var val = myDiv.style.display;
    var v_id = $(e.target).attr('id');
    if(val == 'none' && v_id != "media"){
        myDiv.style.display = 'block'; 
        Background.style.opacity='0.6'
        back.style.backgroundColor="darkgray"
    }else{
        myDiv.style.display = 'none';
        Background.style.opacity='1'
        back.style.backgroundColor="white"
    }
}

</script>
</body>
</html>]]
    res:html(html)
end
return html_router