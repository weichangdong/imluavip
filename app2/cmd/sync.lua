package.path = package.path .. ";/data/v3-p2papi/?.lua;/usr/local/luarocks/share/lua/5.1/?.lua;;"
package.cpath = package.cpath .. ";/usr/local/luarocks/lib/lua/5.1/?.so;;"
local my_redis = require("app2.lib.cmd_redis")
local config = require("app2.config.config")
local json = require("cjson.safe")
local luasql = require "luasql.mysql"
local curl = require("luacurl")
local socket = require('socket')
local mysql_con = luasql.mysql()
local table_object  = json.encode_empty_table_as_object

local tinsert = table.insert
local tconcat = table.concat
local tsort = table.sort
local tonumber = tonumber
local match = string.match
local ssub = string.sub
local sfind = string.find
local sformat = string.format
local pairs = pairs
local ipairs = ipairs
local io = io
local string = string
local os = os
local ioopen = io.open

local function sleep(n)
    local n = n or 0.1
    socket.select(nil, nil, n)
end

local function conn_redis()
        return my_redis.connect(config.redis_config['write']['HOST'],config.redis_config['write']['PORT'])
end

local connect_db = function()
         conn = mysql_con:connect(config.mysql.connect_config['database'],config.mysql.connect_config['user'],config.mysql.connect_config['password'],config.mysql.connect_config['host'],config.mysql.connect_config['port'])
         if not conn then
           print("connect mysql error")
           return
        end
         conn:execute "SET NAMES UTF8"
         return conn
end

local close_db = function(conn)
    conn:close()
end

local function now_date()
        return os.date("%Y-%m-%d %H:%M:%S")
end

local function now_time()
        return os.time()
end

local re,redis_client = pcall(conn_redis)
if not re then
        print(now_date() .." redis error\n")
        os.exit()
end

local function fans_insert_data(uid1, uid2, createtime)
    local conn = connect_db()
    local sql = sformat([[
      INSERT INTO user_fans(`uid1`,`uid2`,`createtime`)
      VALUES ('%s', '%s','%s')]], uid1, uid2, createtime)
    conn:execute(sql)
    local lastinsert_id = conn:getlastautoid()
    close_db(conn)
end

local function moments_pay_log_insert(uid1, uid2, mm_id, price, log_time)
    local conn = connect_db()
    local sql = sformat([[
      INSERT INTO moments_pay_log(`uid1`,`uid2`,`mm_id`,`price`,`log_time`)
      VALUES ('%s', '%s','%s', '%s', '%s')]], uid1, uid2, mm_id, price, log_time)
    conn:execute(sql)
    close_db(conn)
end

local function moments_report_insert(uid, mm_id, report_type, log_time)
    local conn = connect_db()
    local sql = sformat([[
      INSERT INTO moments_report_log(`uid`,`mm_id`,`type`,`log_time`)
      VALUES ('%s', '%s','%s','%s')]], uid, mm_id, report_type, log_time)
    conn:execute(sql)
    close_db(conn)
end

local function fans_delete_data(uid1, uid2)
    local conn = connect_db()
    local sql = sformat([[
      DELETE FROM user_fans WHERE uid1=%s and uid2=%s limit 1]], uid1, uid2)
    conn:execute(sql)
    close_db(conn)
end

local function delete_moments_info(myuid, mm_id)
    local conn = connect_db()
    local sql = sformat([[
      DELETE FROM moments_data WHERE id=%s and uid=%s limit 1]], mm_id, myuid)
    conn:execute(sql)
    close_db(conn)
end

local function delete_moments_grade_info(mm_id)
    local conn = connect_db()
    local sql = sformat([[
      DELETE FROM user_grade_mms WHERE mm_id=%s]], mm_id)
    conn:execute(sql)
    close_db(conn)
end

local function delete_moments_tags_info(mm_id)
    local conn = connect_db()
    local sql = sformat([[
      DELETE FROM moments_tags_data WHERE mm_id=%s]], mm_id)
    conn:execute(sql)
    close_db(conn)
end

local function fans_ifollow_num_data(uid)
    local conn = connect_db()
    local sql = sformat([[
      select count(1) as num FROM user_fans WHERE uid2=%s]], uid)
    local cur = conn:execute(sql)
    local row = cur:fetch({},"a")
    cur:close()
    close_db(conn)
    return row['num']
end

local function fans_followme_num_data(uid)
    local conn = connect_db()
    local sql = sformat([[select count(1) as num FROM user_fans WHERE uid1=%s]], uid)
    local cur = conn:execute(sql)
    local row = cur:fetch({},"a")
    cur:close()
    close_db(conn)
    return row['num']
end

local function update_video_cover(myuid, cover_id)
    local conn = connect_db()
    local sql = sformat([[
      update user_video set iscover=0 where uid=%s limit 5]], myuid)
    conn:execute(sql)

    local sql = sformat([[
      update user_video set iscover=1 where uid=%s and id=%s limit 1]], myuid, cover_id)
    conn:execute(sql)
    close_db(conn)
end

local function change_video_cover(myuid, cover_id)
    local conn = connect_db()
    local sql = sformat([[
      update user_video set iscover=1 where uid=%s and id=%s limit 1]], myuid, cover_id)
    conn:execute(sql)
    close_db(conn)
end

local function change_video_compress(myuid, id, compress_url,compress_cover)
    local conn = connect_db()
    local sql = sformat([[
      update user_video set compress_video='%s',compress_cover='%s' where uid=%s and id=%s limit 1]], compress_url,compress_cover,myuid,id)
    conn:execute(sql)
    close_db(conn)
end

local select_video_info = function(myuid, cover_id)
    local conn = connect_db()
    local sql = sformat([[
      select video,cover,compress_video,vinfo from  user_video  where id=%s and uid=%s limit 1]], cover_id, myuid)
    local cur = conn:execute(sql)
    if not cur then
        return nil,nil
    end
    local row = cur:fetch({},"a")
    cur:close()
    close_db(conn)
    if row then
        return row['video'],row['cover'],row['compress_video'],row['vinfo']
    end
    return nil,nil
end

local select_moments_special = function(mm_id)
    local conn = connect_db()
    local sql = sformat([[
    select msid  from moments_special_data  where  mdid=%s]], mm_id)
    local cur = conn:execute(sql)
    if not cur then
        return {}
    end
    local row = cur:fetch({},"a")
    if not row then
        return {}
    end
    local re = {}
    while row do
        tinsert(re,row["msid"])
        row = cur:fetch(row,"a")
    end
    cur:close()
    close_db(conn)
    return re
end

local select_moments_info = function(myuid, mm_id)
    local conn = connect_db()
    local sql = sformat([[
      select * from  moments_data  where id=%s and uid=%s and use_cdn=1 limit 1]], mm_id, myuid)
    local cur = conn:execute(sql)
    if not cur then
        return nil,nil,nil
    end
    local row = cur:fetch({},"a")
    cur:close()
    close_db(conn)
    if row then
        return row['type'],row['one2one'],{
            video_url = row['video_url'],
            video_cover = row['video_cover'],
            img1 = row['img1'],
            img2 = row['img2'],
            img3 = row['img3'],
            img4 = row['img4'],
            img5 = row['img5'],
            img6 = row['img6'],
            img7 = row['img7'],
            img8 = row['img8'],
            img9 = row['img9'],
        }
    end
    return nil,nil,nil
end

local function delete_video_cover(myuid, id)
    local conn = connect_db()
    local sql = sformat([[
      DELETE FROM user_video WHERE id=%s and uid=%s limit 1]], id, myuid)
    conn:execute(sql)
    close_db(conn)
end

local  function deal_fans_act(myuid,data)
    local act_type = data['act_type']
    local all_ok_uids = data['all_ok_uids']
    if act_type == 1 then --myuid 关注别人
        local now_time = data['now_time']
        if now_time then
            for _,uid in pairs(all_ok_uids) do
                fans_insert_data(uid, myuid, now_time)
            end
        end
        
    else --myuid 取消关注别人
        for _,uid in pairs(all_ok_uids) do
            fans_delete_data(uid, myuid)
        end
    end
    -- check the ifollow tonumber
    local ifollow_cache_num = redis_client:hget(config.redis_key.user_prefix .. myuid, "ifollow")
    local ifollow_db_num = fans_ifollow_num_data(myuid)
    if ifollow_cache_num - ifollow_db_num > 1 then
        print("I follow Error uid:".. myuid .." "..now_date() .." cache_num:"..ifollow_cache_num.." db_num:"..ifollow_db_num.."\n")
    end
    
    local followme_cache_num = redis_client:hget(config.redis_key.user_prefix .. myuid, "followme")
    local followme_db_num = fans_followme_num_data(myuid)
    if followme_cache_num - followme_db_num > 1 then
        print("Follow me Error uid:".. myuid  .." "..now_date() .." cache_num:"..followme_cache_num.." db_num:"..followme_db_num.."\n")
     end
end

local function deal_set_cover(myuid, data)
    update_video_cover(myuid,data['cover_id'])
end

local function get_del_path(del)
    local last_pos = sfind(del, "/[^/]*$")
    local del_path = ssub(del, last_pos+1)
    return del_path
end

local function get_path_without_suffix(new_name)
    local pos = sfind(new_name,".",1,true)
    local okok = ssub(new_name,1,pos - 1)
    return okok
end

local function deal_del_video(myuid, data)
    local del_video,del_img,compress_video = select_video_info(myuid,data['del_id'])
    if not del_video then
        return
    end
    delete_video_cover(myuid,data['del_id'])
    if data['change_id'] > 0 then
        change_video_cover(myuid,data['change_id'])
    end
    local del_video_path = get_del_path(del_video)
    if del_video_path then
        local cmd1 = config.upload.aws_s3_cmd_rm .. config.upload.aws_s3_dir .. del_video_path
        os.execute(cmd1)
    end
    local del_img_path = get_del_path(del_img)
    if del_img_path then
        local cmd2 = config.upload.aws_s3_cmd_rm .. config.upload.aws_s3_dir .. del_img_path
        os.execute(cmd2)
    end
    if compress_video ~= "" then 
        local del_compress_video_path = get_del_path(compress_video)
        if del_compress_video_path then
            local cmd3 = config.upload.aws_s3_cmd_rm .. config.upload.aws_s3_dir_compress .. del_compress_video_path
            os.execute(cmd3)
        end
    end
end

local function deal_update_name(myuid, data)
    local conn = connect_db()
    local sql = sformat([[
      update user set `username`=%s where id=%s limit 1]], data['name'], myuid)
    conn:execute(sql)
    --print(sql)
    close_db(conn)
end

local function deal_update_brief(myuid, data)
    local conn = connect_db()
    local sql = sformat([[
      update user set `brief`='%s' where id=%s limit 1]], data['brief'], myuid)
    conn:execute(sql)
    close_db(conn)
end

local function update_user_avatar(myuid, url)
    local conn = connect_db()
    local sql = sformat([[
      update user set `avatar`='%s' where id=%s limit 1]], url, myuid)
    conn:execute(sql)
    close_db(conn)
end

local function update_moments_isgood(id, status)
    local conn = connect_db()
    local is_isgood = redis_client:zscore(config.redis_key.moments_isgood_zset_key, id)
    if status == 1  and is_isgood then
        local sql = sformat([[
        update moments_data set `isgood`=1 where id=%s limit 1]], id)
        conn:execute(sql)
        close_db(conn)
    elseif status == 0  and  not is_isgood then
        local sql = sformat([[
        update moments_data set `isgood`=0 where id=%s limit 1]], id)
        conn:execute(sql)
        close_db(conn)
    end
end

local function down_raw_video(url)
    local result = {}
    local c = curl.new()
    c:setopt(curl.OPT_URL, url)
    c:setopt(curl.OPT_WRITEDATA, result)
    c:setopt(curl.OPT_WRITEFUNCTION, function(tab, buffer)
        tinsert(tab, buffer)
        return #buffer
    end)
    local ok = c:perform()
    return ok, tconcat(result)
end

local function file_exists(path)
  local file = ioopen(path, "rb")
  if file then 
    file:close()
    return true
  end
  return false
end

local function deal_compress_video(myuid, data)
    local check_exist = redis_client:hexists(config.redis_key.video_prefix .. myuid, data['video_id'])
    if not check_exist then
        print("deal_compress_video uid:"..myuid .. " id:"..data['video_id'] .. " not  exists")
        return
    end
    local raw_video_url,cover_url,need_compress,vinfo = select_video_info(myuid,data['video_id'])
    if not raw_video_url or need_compress ~="" then
        print("deal_compress_video uid:"..myuid .. " id:"..data['video_id'] .. " info  error")
        return
    end
    --[[
    --use linux wget replace lua code
    local ok, content = down_raw_video(raw_video_url)
    local file_link = ioopen(raw_file_name, "w+b")
    if file_link then
        file_link:write(content)
        file_link:close()
    end
    --]]
    local raw_video_name = get_del_path(raw_video_url)

    local new_name = "aws_"..raw_video_name
    local new_cover_name = get_path_without_suffix(new_name) .. ".jpg"
    local raw_file_name = config.upload.compress_video_raw_dir..raw_video_name
    local new_file_name = config.upload.compress_video_ok_dir .. new_name
    local new_cover_file_name = config.upload.compress_video_ok_dir .. new_cover_name
    local down_cmd = "wget -q -O '"..raw_file_name.."' '".. raw_video_url .."'"
    os.execute(down_cmd)
    if not file_exists(raw_file_name) then
        os.execute(down_cmd)
    end
    if not file_exists(raw_file_name) then
        print("compress_video down file error "..down_cmd)
        return
    end
    local compress_cmd = config.ffmpeg_cmd.." -y -v error -i "..raw_file_name.." -strict -2 -vcodec libx264 -preset ultrafast -crf 30 -acodec aac -ar 44100 -ac 2 -b:a 96k "..new_file_name
    os.execute(compress_cmd)
    if not file_exists(new_file_name) then 
        os.execute(compress_cmd) 
    end
    if not file_exists(new_file_name) then 
        print(now_date() .." compress_video error raw:"..raw_video_url .." uid:"..myuid.."   id:"..data['video_id'].." cmd:"..compress_cmd)
        return
    end

    -- get the compress video cover
    --[[暂时不需要
    local get_cover_cmd = config.ffmpeg_cmd.." -y -v error -i "..new_file_name.."  -vframes 1 -q:v 2  -f mjpeg "..new_cover_file_name
    os.execute(get_cover_cmd)
    if not file_exists(new_cover_file_name) then
        os.execute(get_cover_cmd)
    end
    if not file_exists(new_cover_file_name) then
        print(now_date() .." compress_video get cover error uid:"..myuid.."   id:"..data['video_id'].." cmd:"..get_cover_cmd)
        return
    end

    local get_width_height = config.ffprobe_cmd.." -v quiet -print_format json -show_streams " .. new_cover_file_name
    local t = io.popen(get_width_height)
    local a = t:read("*all")
    local ffprobe_cover_info = json.decode(a)
    local width = ffprobe_cover_info.streams[1].width or 540 
    local height = ffprobe_cover_info.streams[1].height or 960
    local compress_vinfo = {
        width = width,
        height = height,
    }
    local upload_cover_cmd = config.upload.aws_s3_cmd .. new_cover_file_name.. config.upload.aws_s3_dir_compress .. new_cover_name .." 1>/dev/null 2>&1 >>/dev/null"
    os.execute(upload_cover_cmd)
    local ok_compress_cover_url = config.upload.resource_url_compress .. new_cover_name
    --]]
    local ok_compress_cover_url = ""
    local upload_video_cmd = config.upload.aws_s3_cmd .. new_file_name.. config.upload.aws_s3_dir_compress .. new_name .." 1>/dev/null 2>&1 >>/dev/null"
    os.execute(upload_video_cmd)
    local ok_compress_url = config.upload.resource_url_compress .. new_name
    local check_cmd = "curl -sI " .. ok_compress_url
    local t = io.popen(check_cmd)
    local a = t:read("*line")
    local ret_code = sfind(a, "200", 1, true)
    if ret_code then
        change_video_compress(myuid,data['video_id'],ok_compress_url,ok_compress_cover_url)
        --update compress video to redis
        local video_info = {
            video = raw_video_url,
            cover = cover_url,
            vinfo = json.decode(vinfo),
            compress_video = ok_compress_url,
        }
        redis_client:hset(config.redis_key.video_prefix .. myuid, data['video_id'], json.encode(video_info))
        print(now_date() .." uid:"..myuid.." compress_video:"..ok_compress_url.." ok")
    else
       print(now_date() .." uid:"..myuid.." compress_video check error raw:"..ok_compress_url)
    end
end

local function deal_moments_pay(myuid, data)
    local uid1 = myuid -- pay credit uid
    local uid2 = data.mm_uid -- get coin uid
    local mm_id = data.mm_id
    local price = data.mm_pricce
    local log_time = data.log_time
    moments_pay_log_insert(uid1,uid2,mm_id,price,log_time)
    print(now_date() .." deal_moments_pay pay-uid:"..uid1.." mm-id:"..mm_id.." get-uid:"..uid2)
    return
end

local function delete_special_moments_info(mm_id)
    local pids = select_moments_special(mm_id)
    for _,pid in pairs(pids) do
        redis_client:zrem(config.redis_key.moments_special_zset_key..pid, mm_id)
    end
end

local function deal_moments_del(myuid, data)
    local mm_type,one2one,mm_info = select_moments_info(myuid,data['mm_id'])
    if  mm_type ~= "1" and mm_type ~= "2" then
        return
    end
    local del_files = ""
    if one2one == "0" then
        for k,v in pairs(mm_info) do
            if v ~= "" then
                local cmd1 = config.upload.aws_s3_cmd_rm .. config.upload.aws_s3_dir_moments .. v
                os.execute(cmd1)
                del_files = del_files .."|".. v
            end
        end
    else
        for k,v in pairs(mm_info) do
            if v ~= "" then
                local cmd1 = config.upload.aws_s3_cmd_rm .. config.upload.aws_s3_dir_one2one .. v
                os.execute(cmd1)
                del_files = del_files .."|".. v
            end
        end
    end
    delete_moments_info(myuid,data['mm_id'])
    --删除封面里面包含的帖子id
    delete_special_moments_info(data['mm_id'])
    --删除点赞的mysql记录
    delete_moments_grade_info(data['mm_id'])
    --删除tags的mysql记录
    delete_moments_tags_info(data['mm_id'])
    print(now_date() .."one2one:"..one2one.." deal_moments_del del-uid:"..myuid.." mm-id:"..data['mm_id'].. " del-files:"..del_files)
    return
end

local function deal_moments_report(myuid, data)
    local mm_id = data.mm_id
    local report_type = data.report_type
    local log_time = data.log_time
    moments_report_insert(myuid,mm_id,report_type,log_time)
end

local function deal_update_avatar(myuid, data)
    update_user_avatar(myuid,data.url)
    print(now_date() .." deal_update_avatar uid:"..myuid.." url:"..data.url)
    return
end

local function deal_newcomer_send_fcm(myuid, data)
    local time = data.time
    local now_time_value = now_time()
    if now_time_value - time < 60 then
        sleep(120)
    elseif now_time_value - time < 120 then
        sleep(60)
    end
    print("welcome new kid "..myuid)
    local fcm_data = data.fcm_data
    redis_client:lpush(config.redis_key.fcm_redis_key, fcm_data)
    print "send one2one moments"
    local all_uids = config.send_one2one_moments_uids
    for k,uid in ipairs(all_uids) do
        local cando_time = now_time() + k * 25
        local base_info_tmp = redis_client:hget(config.redis_key.user_prefix .. uid, "base_info")
        local ok_base_info = json.decode(base_info_tmp) or nil
        if ok_base_info then
            local queue_data = {
                queue_type = "newcomer_fcm_one2one",
                from_uid = uid,
                to_uid = myuid,
                cando_time = cando_time,
                base_info = ok_base_info,
            }
            redis_client:lpush(config.redis_key.queue_list_key, json.encode(queue_data))
        end
    end
end

local function deal_moments_add_isgood(myuid, data)
    local mm_id = data.mm_id
    update_moments_isgood(mm_id,1)
end

local function deal_moments_cancel_isgood(myuid, data)
    local mm_id = data.mm_id
    update_moments_isgood(mm_id,0)
end

local function deal_hide_special_moments_info(myuid,data)
    local mm_id = data['mm_id']
    local pids = select_moments_special(mm_id)
    for _,pid in pairs(pids) do
        redis_client:zrem(config.redis_key.moments_special_zset_key..pid, mm_id)
    end
end

while true do
    local json_data = redis_client:lpop(config.redis_key.cron_list_key)
    if not json_data then
        --print(now_date() .. " all done")
        break
    end
    local ok_data = json.decode(json_data)
    local  act = ok_data['act']
    print(now_date().." ===start "..act.."===")
    if act == "fans" then --个人页 关注 取消关注
        deal_fans_act(ok_data['uid'],ok_data['data'])
    elseif act == "setcover" then -- 设置视频cover
        deal_set_cover(ok_data['uid'],ok_data['data'])
    elseif act == "del_video" then -- 删除视频
        deal_del_video(ok_data['uid'],ok_data['data'])
    elseif act == "update_uname" then -- 修改昵称
        deal_update_name(ok_data['uid'],ok_data['data'])
    elseif act == "update_brief" then -- 修改简介
        deal_update_brief(ok_data['uid'],ok_data['data'])
    elseif act == "compress_video" then -- 压缩视频
        deal_compress_video(ok_data['uid'],ok_data['data'])
    elseif act == "moments_pay" then -- 记录moments日志
        deal_moments_pay(ok_data['uid'],ok_data['data'])
    elseif act == "moments_del" then -- 删除moments日志
        deal_moments_del(ok_data['uid'],ok_data['data'])
    elseif act == "moments_report" then -- moments举报
        deal_moments_report(ok_data['uid'],ok_data['data'])
    elseif act == "update_avatar" then -- 换头像
        deal_update_avatar(ok_data['uid'],ok_data['data'])
    elseif act == "newcomer_send_fcm" then -- newcomer-fcm
        deal_newcomer_send_fcm(ok_data['uid'],ok_data['data'])
    elseif act == "moments_add_isgood" then -- 设置精选
        deal_moments_add_isgood(ok_data['uid'],ok_data['data'])
    elseif act == "moments_cancel_isgood" then -- 取消精选
        deal_moments_cancel_isgood(ok_data['uid'],ok_data['data'])
    elseif act == "hide_special_moments" then -- 影藏帖子,需要删除专题里面的帖子id
        deal_hide_special_moments_info(ok_data['uid'],ok_data['data'])
    end
    print(now_date().." ===end "..act.."===")
end