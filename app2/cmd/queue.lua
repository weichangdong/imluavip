package.path = package.path .. ";/data/v3-p2papi/?.lua;/usr/local/luarocks/share/lua/5.1/?.lua;;"
package.cpath = package.cpath .. ";/usr/local/luarocks/lib/lua/5.1/?.so;;"
local my_redis = require("app2.lib.cmd_redis")
local config = require("app2.config.config")
local json = require("cjson.safe")
local luasql = require "luasql.mysql"
local socket = require('socket')
local luuid = require "uuid"
local mysql_con = luasql.mysql()
local curl = require("luacurl")
local table_object  = json.encode_empty_table_as_object

local tinsert = table.insert
local tconcat = table.concat
local tsort = table.sort
local tonumber = tonumber
local match = string.match
local ssub = string.sub
local sfind = string.find
local pairs = pairs
local ipairs = ipairs
local io = io
local string = string
local os = os
local sformat = string.format
local ioopen = io.open

local function conn_redis()
        return my_redis.connect(config.redis_config['write']['HOST'],config.redis_config['write']['PORT'])
end

local function sleep_old(n)
        local n = n or 0.1
   socket.select(nil, nil, n)
end

local function sleep(n)
    local num = n or 0.1
    if num < 1 then
        os.execute("usleep 10000")
    else
        os.execute("sleep " .. num)
    end
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

local function lua_curl(post_data)
    local header_info = {
         'Content-Type: application/x-www-form-urlencoded; charset=UTF-8',
    }
    local url = config.voucher.paypal_order_check_url
    local c = curl.new()
    c:setopt(curl.OPT_URL, url)
    c:setopt(curl.OPT_SSL_VERIFYHOST,0)
    c:setopt(curl.OPT_SSL_VERIFYPEER,false)
    c:setopt(curl.OPT_HEADER, false)
    c:setopt(curl.OPT_CUSTOMREQUEST, "POST")
    c:setopt(curl.OPT_HTTPHEADER,tconcat(header_info,"\n"))
    c:setopt(curl.OPT_POSTFIELDS, post_data)

    local t = {}
    c:setopt(curl.OPT_WRITEFUNCTION, function(param, buf)
        tinsert(t, buf)
        return #buf
    end)
    c:perform()
    return tconcat(t)
end

local function lua_curl_get_token_paypal()
    local header_info = {
         'Accept: application/json',
         'Accept-Language: en_US',
    }
    local url = "https://"..config.voucher.paypal_access_token_url
    local post_data = "grant_type=client_credentials"
    local c = curl.new()
    c:setopt(curl.OPT_URL, url)
    c:setopt(curl.OPT_SSL_VERIFYHOST,0)
    c:setopt(curl.OPT_SSL_VERIFYPEER,false)
    c:setopt(curl.OPT_HEADER, false)
    c:setopt(curl.OPT_CUSTOMREQUEST, "POST")
    c:setopt(curl.OPT_USERPWD, config.voucher.paypal_client_id..":"..config.voucher.paypal_secret)
    c:setopt(curl.OPT_HTTPHEADER,tconcat(header_info,"\n"))
    c:setopt(curl.OPT_POSTFIELDS, post_data)
    
    local t = {}
    c:setopt(curl.OPT_WRITEFUNCTION, function(param, buf)
        tinsert(t, buf)
        return #buf
    end)
    c:perform()
    return  tconcat(t)
end


local function lua_curl_query_paypal(post_data)
    if not redis_client then
        re,redis_client = pcall(conn_redis)
    end
    local access_token = redis_client:get(config.redis_key.paypal_access_token_key)
    if not access_token then
        local wcd = lua_curl_get_token_paypal()
        local ok_info = json.decode(wcd)
        local expires_in = ok_info.expires_in
        local access_token = ok_info.access_token
        redis_client:setex(config.redis_key.paypal_access_token_key, expires_in, access_token)
        print(now_date() .." [lua_curl_query_paypal] get access token")
    end
    if not access_token then
        print(now_date() .." [lua_curl_query_paypal] get access token error ")
        return "error"
    end
    local header_info = {
         'Content-Type: application/json',
         'Authorization:Bearer '..access_token,
    }
    local url = config.voucher.paypal_order_select_url .. post_data.order_id
    local c = curl.new()
    c:setopt(curl.OPT_URL, url)
    c:setopt(curl.OPT_SSL_VERIFYHOST,0)
    c:setopt(curl.OPT_SSL_VERIFYPEER,false)
    c:setopt(curl.OPT_HEADER, false)
    c:setopt(curl.OPT_CUSTOMREQUEST, "POST")
    c:setopt(curl.OPT_HTTPHEADER,tconcat(header_info,"\n"))
    c:setopt(curl.OPT_POSTFIELDS, post_data)

    local t = {}
    c:setopt(curl.OPT_WRITEFUNCTION, function(param, buf)
        tinsert(t, buf)
        return #buf
    end)
    c:perform()
    local result = tconcat(t)
    local result_ok = json.decode(result)
    if not result_ok then
        print(now_date() .." [lua_curl_query_paypal] query order-id error order-id:"..post_data.order_id.." db-id:"..post_data.id)
        return "error"
    end
    if result_ok.state ~= "approved" or result_ok.id ~= post_data.order_id or result_ok.transactions[1].custom ~= post_data.payload then
        print(now_date() .."[lua_curl_query_paypal return data error] err-info: state"..result_ok.state .. " prepayid:"..post_data.payload.." return-order-id:"..result_ok.id.." db-order-id:"..post_data.order_id.." db-id:"..post_data.id)
        return "error"
    end
    return "VERIFIED"
end

local function get_path_without_suffix(new_name)
    local pos = sfind(new_name,".",1,true)
    local okok = ssub(new_name,1,pos - 1)
    return okok
end

local function fcm_insert_data(uniq,fcmtoken,uptime,myuid)
    local conn = connect_db()
    local sql = sformat([[
      INSERT INTO fcm_token(`uid`,`uniq`,`token`,`uptime`)
      VALUES ('%s','%s','%s','%s')]], myuid, uniq, fcmtoken, uptime)
    conn:execute(sql)
    close_db(conn)
end


local function insert_moments_video_info(myuid,one2one,add_type,price,position,desc,time_stamp,ok_compress_url,video_cover,video_width,video_height,base_url,mm_from,gender)
    local conn = connect_db()

    local position = conn:escape(position)
    local desc = conn:escape(desc)

    local sql = sformat([[
      INSERT INTO moments_data(`uid`,`one2one`,`type`,`price`,`position`,`desc`,`time_stamp`,`video_url`,`video_cover`,`video_width`,`video_height`,`base_url`,`mm_from`,`gender`)
      VALUES ('%s','%s','%s','%s','%s','%s','%s','%s','%s','%s','%s','%s','%s','%s')]], myuid,one2one,add_type, price, position, desc, time_stamp, ok_compress_url, video_cover, video_width, video_height, base_url,mm_from,gender)
    conn:execute(sql)
    local lastinsert_id = conn:getlastautoid()
    close_db(conn)
    return lastinsert_id
end

local function insert_moments_img_info(myuid,one2one,add_type,price,position,desc,time_stamp,base_url,urls,mm_from,gender)
    local conn = connect_db()
    local img1 = urls[1] or ""
    local img2 = urls[2] or ""
    local img3 = urls[3] or ""
    local img4 = urls[4] or ""
    local img5 = urls[5] or ""
    local img6 = urls[6] or ""
    local img7 = urls[7] or ""
    local img8 = urls[8] or ""
    local img9 = urls[9] or ""

    local position = conn:escape(position)
    local desc = conn:escape(desc)

    local sql = sformat([[
      INSERT INTO moments_data(`uid`,`one2one`,`type`,`price`,`position`,`desc`,`time_stamp`,`base_url`,`img1`,`img2`,`img3`,`img4`,`img5`,`img6`,`img7`,`img8`,`img9`,`mm_from`,`gender`)
      VALUES ('%s','%s','%s','%s','%s','%s','%s','%s','%s','%s','%s','%s','%s','%s','%s','%s','%s','%s','%s')]], myuid,one2one,add_type, price, position, desc, time_stamp, base_url, img1, img2,img3, img4,img5, img6,img7, img8,img9,mm_from,gender)
    conn:execute(sql)
    local lastinsert_id = conn:getlastautoid()
    close_db(conn)
    return lastinsert_id
end

local function fcm_select_token(uid)
    local conn = connect_db()
    local sql = sformat([[select id FROM fcm_token WHERE uid=%s]], uid)
    local cur = conn:execute(sql)
    local row = cur:fetch({},"a")
    cur:close()
    close_db(conn)
    if row and row['id'] then
        return row['id']
    end
    return 0
end

local function voucher_select_order(id)
    local conn = connect_db()
    local sql = sformat([[select uid,appid,mch_id,credit,extra_credit,total_fee,status FROM rmb_purchase_log WHERE id=%s limit 1]], id)
    local cur = conn:execute(sql)
    local row = cur:fetch({},"a")
    if row and row['uid'] then
        return {
            uid = row['uid'],
            appid = row['appid'],
            mch_id = row['mch_id'],
            credit = row['credit'],
            extra_credit = row['extra_credit'],
            status = row['status'],
        }
    end
    cur:close()
    close_db(conn)
    return nil
end

local  select_tag_data_by_where = function(tname)
    local conn = connect_db()
    local sql = sformat([[select * FROM tags_data WHERE tname='%s' limit 1]], tname)
    local cur = conn:execute(sql)
    local row = cur:fetch({},"a")
    if row and row['id'] then
        return {
            tid = row['id'],
            tname = row['tname'],
        }
    end
    cur:close()
    close_db(conn)
    return nil
end

local insert_tag_data = function(tname)
    local conn = connect_db()
    --local tname = conn:escape(tname)

    local sql = sformat([[
      INSERT INTO tags_data(`tname`,`recom`,`mm_num`)
      VALUES ('%s','%s','%s')]], tname,0,1)
    conn:execute(sql)
    local lastinsert_id = conn:getlastautoid()
    close_db(conn)
    return lastinsert_id
end

local  function insert_moments_tag_data(tags_data,mm_id)
    local log_time = now_time()
    local conn = connect_db()
    for k,v in pairs(tags_data) do
        local tid = v.tid
        local tname = v.tname
        local sql = sformat([[select id FROM moments_tags_data WHERE tid=%s and mm_id=%s limit 1]],tid,mm_id)
        local cur = conn:execute(sql)
        local row = cur:fetch({},"a")
        if not row or not row['id'] then
            local sql = sformat([[
                INSERT INTO moments_tags_data(`tid`,`tname`,`mm_id`,`time`)
                VALUES ('%s','%s','%s','%s')]], tid,tname,mm_id,log_time)
            conn:execute(sql)
        end
    end
end

local function voucher_select_paypal_order(id)
    local conn = connect_db()
    local sql = sformat([[select uid,credit,extra_credit,status,vip,vip_time,usd FROM usd_purchase_log WHERE id=%s limit 1]], id)
    local cur = conn:execute(sql)
    local row = cur:fetch({},"a")
    if row and row['uid'] then
        return {
            id = row['id'],
            status = row['status'],
            uid = row['uid'],
            credit = row['credit'],
            extra_credit = row['extra_credit'],
            usd = row['usd'],
            vip = row['vip'],
            vip_time = row['vip_time'],
        }
    end
    cur:close()
    close_db(conn)
    return nil
end

local function fcm_update_token(uniq,fcmtoken,uptime,myuid)
    local conn = connect_db()
    local sql = sformat([[
      update fcm_token set uniq='%s',token='%s',uptime=%s where uid=%s limit 1]], uniq,fcmtoken,uptime,myuid)
    conn:execute(sql)
    close_db(conn)
end

local function update_user_pay_num(num,uid)
    local conn = connect_db()
    local sql = sformat([[
        update user_extend set pay_num=pay_num+%s where uid=%s limit 1]], num,uid)
    conn:execute(sql)
    close_db(conn)
end

local function voucher_update_orderid_status(id,status,finish_time)
    local conn = connect_db()
    local sql 
    if finish_time then 
        sql = sformat([[
      update rmb_purchase_log set status=%s,finish_time=%s  where id=%s limit 1]], status,finish_time,id)
    else
        sql = sformat([[
      update rmb_purchase_log set status=%s  where id=%s limit 1]], status,id)
    end
    local update_re = conn:execute(sql)
    close_db(conn)
    return update_re
end

local function voucher_update_orderid_status_usd(id,status,finish_time)
    local conn = connect_db()
    local sql 
    if finish_time then 
        sql = sformat([[
      update usd_purchase_log set status=%s,log_time=%s  where type=1 and id=%s and status!=1 limit 1]], status,finish_time,id)
    else
        sql = sformat([[
      update usd_purchase_log set status=%s  where  type=1 and id=%s and status!=1  limit 1]], status,id)
    end
    local update_re = conn:execute(sql)
    close_db(conn)
    return update_re
end

local function deal_gg_voucher_check(kid)

end

local function deal_fcm_token(jd)
    local uniq = jd.uniq
    local fcmtoken = jd.fcmtoken
    local uptime = jd.uptime
    local myuid = jd.uid
    local if_exists = fcm_select_token(myuid)
    if if_exists == 0 then
        fcm_insert_data(uniq,fcmtoken,uptime,myuid)
    else
        fcm_update_token(uniq,fcmtoken,uptime,myuid)
    end
end

local  insert_vip_log = function(uid,voucher_id,now_time,expire_time)
    local conn = connect_db()
    local sql = sformat([[
        insert into vip_time_log(uid,type_id,start_time,expire_time)
        VALUES ('%s','%s','%s','%s')]], uid,voucher_id,now_time,expire_time)
    conn:execute(sql)
    close_db(conn)
end

local function add_voucher_credit(id,uid,credit_num,extra_credit_num)
    local conn = connect_db()
    local add_credit_num = credit_num
    local log_time = now_time()
    if  extra_credit_num > 0 then
        add_credit_num = add_credit_num + extra_credit_num
    end
    local sql = sformat([[
      update  user_extend  set credit=credit+%s where uid=%s limit 1]], add_credit_num, uid)
    local affected_rows = conn:execute(sql)
    if affected_rows == 1 then
        local sql = sformat([[
            insert into credit_bill_log(uid,type,type_id,num,log_time)
            VALUES ('%s','%s','%s','%s','%s')]], uid,1,id,credit_num,log_time)
        local re1 = conn:execute(sql)
        if re1 ~= 1 then
            print("insert credit_bill_log log error rmb-table-id:"..id)
        end
        if extra_credit_num > 0 then 
            local sql = sformat([[
            insert into credit_bill_log(uid,type,type_id,num,log_time)
            VALUES ('%s','%s','%s','%s','%s')]], uid,2,id,extra_credit_num,log_time)
            conn:execute(sql)
        end
        close_db(conn)
        return true
    else
        close_db(conn)
        return false
    end
end

local  function add_voucher_credit_and_viptime(id,uid,credit_num,extra_credit_num,vip,vip_time,usd)
    local conn = connect_db()
    local add_credit_num = credit_num
    local log_time = now_time()
    if  extra_credit_num > 0 then
        add_credit_num = add_credit_num + extra_credit_num
    end
    local return_value = false
    -- vip 0:credit 1:vip-time 2:credit&&vip-time 
    if  vip == 0 or vip == 2 then
        local sql = sformat([[
        update  user_extend  set credit=credit+%s where uid=%s limit 1]], add_credit_num, uid)
        local affected_rows = conn:execute(sql)
        if affected_rows == 1 then
            local sql = sformat([[
                insert into credit_bill_log(uid,type,type_id,num,log_time)
                VALUES ('%s','%s','%s','%s','%s')]], uid,1,id,credit_num,log_time)
            local re1 = conn:execute(sql)
            if re1 ~= 1 then
                print("insert credit_bill_log log error rmb-table-id:"..id)
            end
            if extra_credit_num > 0 then 
                local sql = sformat([[
                insert into credit_bill_log(uid,type,type_id,num,log_time)
                VALUES ('%s','%s','%s','%s','%s')]], uid,2,id,extra_credit_num,log_time)
                conn:execute(sql)
            end
            update_user_pay_num(usd,uid)
            if vip == 2 then 
                redis_client:hset(config.redis_key.user_prefix .. uid,"payed",2)
            else
                redis_client:hsetnx(config.redis_key.user_prefix .. uid,"payed",1) 
            end 
            
            return_value = true
        else
            print(now_date() .." [paypal_voucher add credit error] add_voucher_credit_and_viptime-1 error id:"..id)
        end
    end
    if  vip == 1 or vip == 2 then
        local now_time = now_time()
        local vip_expire_time = now_time + vip_time
        local vip_user_key = config.redis_key.vip_user_key..uid
        local old_vip_time = redis_client:ttl(vip_user_key)
        local switch = 0 --no vip or expired
        local new_vip_time = vip_time
        if old_vip_time > 0 then
            switch = 1
            new_vip_time = new_vip_time + old_vip_time
        end
        local vip_time_sql
        if switch == 0 then
            vip_time_sql = sformat([[
                update  user_extend  set vip_stime=%d,vip_etime=%d where uid=%d limit 1]], vip_stime,vip_etime,uid)
        elseif switch == 1 then
            vip_time_sql = sformat([[
                update  user_extend  set vip_etime=vip_etime+%d where uid=%d limit 1]], vip_time,uid)
        end
        local affected_rows = conn:execute(vip_time_sql)
        if affected_rows == 1 then
            insert_vip_log(uid, id, now_time, vip_expire_time)
            update_user_pay_num(usd,uid)
            if vip == 1 then
                redis_client:hsetnx(config.redis_key.user_prefix .. uid,"payed",1)
            else
                redis_client:hset(config.redis_key.user_prefix .. uid,"payed",2)
            end
            if switch == 0 then
                redis_client:setex(vip_user_key,vip_time,1)
            elseif switch == 1 then
                redis_client:expire(vip_user_key,new_vip_time)
            end
            return_value = true
        else
            print(now_date() .." [paypal_voucher add vip-time error] add_voucher_credit_and_viptime-2 error id:"..id)
        end
        
    end
    close_db(conn)
    --  有一个成功 就算成功. 为了防止一个失败,然后队列retry add多次.
    return return_value
end

local function deal_weinxin_voucher_notify(data)
    local id = data.id
    local order_info = voucher_select_order(id)
    if not order_info then
        print("what's wrong! error-id:"..id)
        return
    end
    local retry_times = data.retry_times or 0
    local status = order_info.status
    local uid = order_info.uid
    local credit_num = order_info.credit
    local extra_credit_num = order_info.extra_credit
    if status == 2 then
        print("db-id already ok id:"..id)
        return
    elseif status == 1 then
        local queue_data = {
            queue_type = "wx_voucher",
            id = id,
            retry_times = 0,
        }
        redis_client:lpush(config.redis_key.queue_list_key, json.encode(queue_data))
    elseif status == 4 and retry_times < 4 then
        local add_re = add_voucher_credit(id,uid,credit_num,extra_credit_num)
        if add_re then
            local finish_time = now_time()
            local update_re = voucher_update_orderid_status(id,2,finish_time)
            if update_re ~= 1 then
                print("[weinxin_voucher error] id:"..id)
            end 
        else
            local queue_data = {
                queue_type = "wx_voucher",
                id = id,
                retry_times = retry_times + 1,
            }
            redis_client:lpush(config.redis_key.queue_list_key, json.encode(queue_data))
            print("[weinxin_voucher error] add credit  error id:"..id.." retry_times:"..retry_times)
        end
        return
    elseif status == 0 then
        local update_re = voucher_update_orderid_status(id,1,nil)
        if update_re ~= 1 then
            local queue_data = {
                queue_type = "wx_voucher",
                id = id,
                retry_times = retry_times,
            }
            redis_client:lpush(config.redis_key.queue_list_key, json.encode(queue_data))
            print("[weinxin_voucher error] error id:"..id)
            return
        end

        local add_re = add_voucher_credit(id,uid,credit_num,extra_credit_num)
        if add_re then
            local finish_time = now_time()
            local update_re = voucher_update_orderid_status(id,2,finish_time)
            if update_re ~= 1 then
                print("[weinxin_voucher error] error id:"..id)
            end 
        else
            voucher_update_orderid_status(id,4,nil)
            local queue_data = {
                queue_type = "wx_voucher",
                id = id,
                retry_times = retry_times + 1,
            }
            redis_client:lpush(config.redis_key.queue_list_key, json.encode(queue_data))
            print("[weinxin_voucher error] add credit  error id:"..id)
        end
    end
    return
end

local function deal_wcd_test(data)
    if data.retry_times < 10 then
        local queue_data = {
            queue_type = "test",
            retry_times = data.retry_times + 1
        }
        redis_client:lpush(config.redis_key.queue_list_key, json.encode(queue_data))
        print(data.retry_times)
    else
       local info =  now_date() .. "retry_times:"..data.retry_times
       print(info)
    end
    return
end

local function file_exists(path)
    local file = ioopen(path, "rb")
    if file then 
    file:close()
    return true
    end
    return false
end

local function get_del_path(del)
    local last_pos = sfind(del, "/[^/]*$")
    local del_path = ssub(del, last_pos+1)
    return del_path
end

local function deal_moments_video(data)
    local myuid = data.uid
    local price = tonumber(data.price)
    local position = data.position
    local desc = data.desc
    local mm_from = data.mm_from
    --local time_stamp = tonumber(data.time_stamp)
    local video_url = data.video_url
    local raw_video_name = get_del_path(video_url)
    local tags = data.tags
    local tags_num = data.tags_num or 0

    local luuid_str = luuid.new("time")
    local rand_str = ssub(luuid_str,1,8)
    local new_name = "mm_"..rand_str..raw_video_name
    local raw_file_name = config.upload.compress_video_raw_dir..raw_video_name
    local new_file_name = config.upload.compress_video_ok_dir .. new_name
    if not file_exists(raw_file_name) then
        local down_cmd = "wget -q -O '"..raw_file_name.."' '"..video_url.."'"
        os.execute(down_cmd)
    end
    if not file_exists(raw_file_name) then
        print("moments_video down file error "..down_cmd)
        return
    end
    local check_filesize_cmd = "du -k "..raw_file_name .. "|awk '{print $1}'"
    local t = io.popen(check_filesize_cmd)
    local file_size = t:read("*line")
    file_size = tonumber(file_size)
    if file_size > 3072 then --3m
        local compress_cmd = config.ffmpeg_cmd.." -y -v error -i "..raw_file_name.." -strict -2 -vcodec libx264 -preset ultrafast -crf 30 -acodec aac -ar 44100 -ac 2 -b:a 96k "..new_file_name
        if not file_exists(new_file_name) then 
            os.execute(compress_cmd) 
        end
    else
        local cp_cmd = "cp -f "..raw_file_name .. " " ..new_file_name
        os.execute(cp_cmd)
        --print(cp_cmd)
    end
    if not file_exists(new_file_name) then 
        print(now_date() .." moments_video error raw:"..raw_file_name)
        return
    end
    
    --------add video cover start--------
    local new_cover_name = get_path_without_suffix(new_name) .. ".jpg"
    local new_cover_file_name = config.upload.compress_video_ok_dir .. new_cover_name
    -- get the compress video cover
    local get_cover_cmd = config.ffmpeg_cmd.." -y -v error -i "..new_file_name.."  -vframes 1 -q:v 2  -f mjpeg "..new_cover_file_name
    if not file_exists(new_cover_file_name) then
        os.execute(get_cover_cmd)
    end
    if not file_exists(new_cover_file_name) then
        print(now_date() .." moments_video get cover error :".." cmd:"..get_cover_cmd)
        return
    end
    local upload_video_cover_cmd = config.upload.aws_s3_cmd .. new_cover_file_name .. config.upload.aws_s3_dir_moments .. new_cover_name .." 1>/dev/null 2>&1 >>/dev/null"
    os.execute(upload_video_cover_cmd)
    local ok_cover_compress_url = config.upload.resource_url_moments .. new_cover_name
    local check_cmd = "curl -sI " .. ok_cover_compress_url
    local t = io.popen(check_cmd)
    local a = t:read("*line")
    local ret_code = sfind(a, "200", 1, true)
    if not ret_code then
        print(now_date() .." moments_video video-cover check error raw:"..ok_cover_compress_url)
        return
    end
    --------add video cover end--------

    --------get width_height start--------
    local get_width_height_cmd = config.ffprobe_cmd.." -v quiet -print_format json -show_streams " .. new_file_name
    local t = io.popen(get_width_height_cmd)
    local a = t:read("*all")
    local ffprobe_info = json.decode(a)
    local video_width = tonumber(ffprobe_info.streams[1].width) or 540 
    local video_height = tonumber(ffprobe_info.streams[1].height) or 960
    --------get width_height end--------

    local upload_video_cmd = config.upload.aws_s3_cmd .. new_file_name .. config.upload.aws_s3_dir_moments .. new_name .." 1>/dev/null 2>&1 >>/dev/null"
    os.execute(upload_video_cmd)
    local ok_compress_url = config.upload.resource_url_moments .. new_name
    local check_cmd = "curl -sI " .. ok_compress_url
    local t = io.popen(check_cmd)
    local a = t:read("*line")
    local ret_code = sfind(a, "200", 1, true)
    if not ret_code then
        print(now_date() .." moments_video check error raw:"..ok_compress_url)
        return
    end
    local time_stamp_tmp = socket.gettime() * 1000
    local time_stamp = math.ceil(time_stamp_tmp)
    --1:img-list 2:video
    local base_info_tmp = redis_client:hget(config.redis_key.user_prefix .. myuid, "base_info")
    local my_base_info = json.decode(base_info_tmp) or {}
    local gender = my_base_info.gender or 0

    --deal  tags_data
    local redis_tags_data = {}
    for tnum=1,tags_num do
        local tag_data = tags[tnum]
        local tid = tag_data.tid
        local tname = tag_data.tname
        if tid == 0 then
            local db_tags = select_tag_data_by_where(tname)
            if db_tags and  db_tags.tid then
                tid = db_tags.tid
                tname = db_tags.tname
            else
                tid = insert_tag_data(tname)
            end

        end
        -- 暂时认定客户端传的id是合法的(可以在这里查询下tid是否存在)
        tinsert(redis_tags_data,{
            tid = tonumber(tid),
            tname = tname,
        })
    end

    local mm_id = insert_moments_video_info(myuid,0,2,price,position,desc,time_stamp,new_name,new_cover_name,video_width,video_height,config.upload.resource_url_moments,mm_from,gender)
    mm_id = tonumber(mm_id)
    if not mm_id or mm_id <= 0 then
        print(now_date() .." moments_video insert-video-error:time_stamp"..time_stamp)
        return
    end
    -- deal tags_mm_data
    insert_moments_tag_data(redis_tags_data,mm_id)

    local real_data = {
        uid = myuid,
        add_type = 2,
        price = price,
        base_url = config.upload.resource_url_moments,
        video_url = new_name,
        video_cover = new_cover_name,
        video_width = video_width,
        video_height = video_height,
        time_stamp = time_stamp,
        position = position,
        desc = desc,
        mm_from = mm_from,
    }
    redis_client:hmset(config.redis_key.moments_prefix_hash_key..mm_id,"hot",0,"data",json.encode(real_data),"tags",json.encode(redis_tags_data))
    redis_client:zadd(config.redis_key.moments_myids_key..myuid, time_stamp, mm_id)
    redis_client:zadd(config.redis_key.moments_prefix_zset_key, time_stamp, mm_id)
    --update mm_max_min
    --[[201711211707
    local time_stamp_tmp = redis_client:hmget(config.redis_key.moments_max_min_timestamp_key,"max","min")
    local max_time_stamp = tonumber(time_stamp_tmp[1]) or 0
    local min_time_stamp = tonumber(time_stamp_tmp[2]) or 0
    if time_stamp > max_time_stamp or  max_time_stamp == 0 then
        redis_client:hset(config.redis_key.moments_max_min_timestamp_key,"max", time_stamp)
    end
    if time_stamp < min_time_stamp  or min_time_stamp == 0 then
        redis_client:hset(config.redis_key.moments_max_min_timestamp_key,"min", time_stamp)
    end
    ]]
    print(now_date() .." moments-video-ok:uid:"..myuid.." id:"..mm_id)
    --del raw video file
    local cmd1 = config.upload.aws_s3_cmd_rm .. config.upload.aws_s3_dir .. raw_video_name
    os.execute(cmd1)
    return
end

local function deal_moments_img(data)
    local myuid = data.uid
    local price = tonumber(data.price)
    local position = data.position
    local desc = data.desc
    local mm_from = data.mm_from
    --local time_stamp = tonumber(data.time_stamp)
    local img_urls = data.img_urls
    local img_dir = data.img_dir
    local total_num = tonumber(data.total_num)
    local tags = data.tags
    local tags_num = data.tags_num or 0

    local seq_files = {}
    local ok_num = 0
    for _,tmp in pairs(img_urls) do
        local seq_num = tmp.seq
        local img_name = tmp.name
        local extname = tmp.ext
        --type:gif

        local luuid_str = luuid.new("time")
        local rand_str = ssub(luuid_str,1,8)
        local new_img_name = "mm_"..rand_str..img_name
        local raw_file_name = img_dir .. img_name
        local new_file_name = img_dir .. new_img_name
        
        if file_exists(raw_file_name) then
            local check_filesize_cmd = "du -k "..raw_file_name .. "|awk '{print $1}'"
            local t = io.popen(check_filesize_cmd)
            local file_size = t:read("*line")
            file_size = tonumber(file_size)
            local check_gif_img_cmd = config.img_identify_cmd ..raw_file_name .. "|grep  GIF|wc -l"
            --print("cmd:"..check_gif_img_cmd)
            local t = io.popen(check_gif_img_cmd)
            local file_img_wc = t:read("*line")
            file_img_wc = tonumber(file_img_wc)
            --print("cmd-wcd:"..file_img_wc)
            if file_size > 300 and file_img_wc < 2 then --kb
                local check_webp_img_cmd = config.img_identify_cmd ..raw_file_name .. "|grep  WEBP|wc -l"
                local t1 = io.popen(check_webp_img_cmd)
                local file_webp_img_wc = t1:read("*line")
                file_webp_img_wc = tonumber(file_webp_img_wc)
                if file_webp_img_wc < 1 then
                    local convert_cmd = config.img_convert_cmd .. raw_file_name .. " "..new_file_name
                    os.execute(convert_cmd)
                    if not file_exists(new_file_name) then
                        print("moments_img convert file error "..convert_cmd)
                        return
                    end
                else
                    new_file_name = raw_file_name
                end
            else
                new_file_name = raw_file_name
            end
            local upload_img_cmd = config.upload.aws_s3_cmd .. new_file_name .. config.upload.aws_s3_dir_moments .. new_img_name .." 1>/dev/null 2>&1 >>/dev/null"
            os.execute(upload_img_cmd)
            local ok_convert_url = config.upload.resource_url_moments .. new_img_name
            local check_cmd = "curl -sI " .. ok_convert_url
            local t = io.popen(check_cmd)
            local a = t:read("*line")
            local ret_code = sfind(a, "200", 1, true)
            --local ok_convert_url = config.upload.resource_url_moments .. new_img_name
            local ret_code = true
            if ret_code then
                seq_files[seq_num] = new_img_name
                ok_num = ok_num + 1
            else
                print(now_date() .." moments_img check error "..ok_convert_url)
            end
        end
    end
    if ok_num == 0 then
        print(now_date() .." moments_img num error ")
        return
    end

    if total_num ~= ok_num then
        print(now_date() .." moments_img queue num not equal raw_num:"..total_num .. " ok_num:"..ok_num)
    end
    local time_stamp_tmp = socket.gettime() * 1000
    local time_stamp = math.ceil(time_stamp_tmp)
    --1:img-list 2:video
    local base_info_tmp = redis_client:hget(config.redis_key.user_prefix .. myuid, "base_info")
    local my_base_info = json.decode(base_info_tmp) or {}
    local gender = my_base_info.gender or 0

    --deal  tags
    local redis_tags_data = {}
    for tnum=1,tags_num do
        local tag_data = tags[tnum]
        local tid = tag_data.tid
        local tname = tag_data.tname
        if tid == 0 then
            local db_tags = select_tag_data_by_where(tname)
            if db_tags and  db_tags.tid then
                tid = db_tags.tid
                tname = db_tags.tname
            else
                tid = insert_tag_data(tname)
            end
        end
        -- 暂时认定客户端传的id是合法的(可以在这里查询下tid是否存在)
        tinsert(redis_tags_data,{
            tid = tonumber(tid),
            tname = tname,
        })
    end

    local mm_id = insert_moments_img_info(myuid,0,1,price,position,desc,time_stamp,config.upload.resource_url_moments,seq_files,mm_from,gender)
    if not mm_id or mm_id <= 0 then
        print(now_date() .." moments_img insert-imgs-error:time_stamp "..time_stamp)
        return
    end

    -- deal tags_mm_data
    insert_moments_tag_data(redis_tags_data,mm_id)
    local real_data = {
        uid = myuid,
        add_type = 1,
        price = price,
        base_url = config.upload.resource_url_moments,
        img_urls = seq_files,
        time_stamp = time_stamp,
        position = position,
        desc = desc,
        mm_from = mm_from,
    }
    redis_client:hmset(config.redis_key.moments_prefix_hash_key..mm_id,"hot",0,"data",json.encode(real_data),"tags",json.encode(redis_tags_data))
    redis_client:zadd(config.redis_key.moments_myids_key..myuid, time_stamp, mm_id)
    redis_client:zadd(config.redis_key.moments_prefix_zset_key, time_stamp, mm_id)
    print(now_date() .." moments_img-ok:uid:"..myuid.." id:"..mm_id)
    return
end

-- one2one
local function deal_one2one_img(data)
    local myuid = data.uid
    local price = tonumber(data.price)
    local desc = data.desc
    --local time_stamp = tonumber(data.time_stamp)
    local img_urls = data.img_urls
    local img_dir = data.img_dir
    local total_num = tonumber(data.total_num)
    local mm_from = data.mm_from

    local seq_files = {}
    local ok_num = 0
    for _,tmp in pairs(img_urls) do
        local seq_num = tmp.seq
        local img_name = tmp.name
        local extname = tmp.ext
        --type:gif

        local luuid_str = luuid.new("time")
        local rand_str = ssub(luuid_str,1,8)
        local new_img_name = "oo_"..rand_str..img_name
        local raw_file_name = img_dir .. img_name
        local new_file_name = img_dir .. new_img_name
        
        if file_exists(raw_file_name) then
            local check_filesize_cmd = "du -k "..raw_file_name .. "|awk '{print $1}'"
            local t = io.popen(check_filesize_cmd)
            local file_size = t:read("*line")
            file_size = tonumber(file_size)
            local check_gif_img_cmd = config.img_identify_cmd ..raw_file_name .. "|grep  GIF|wc -l"
            --print("cmd:"..check_gif_img_cmd)
            local t = io.popen(check_gif_img_cmd)
            local file_img_wc = t:read("*line")
            file_img_wc = tonumber(file_img_wc)
            --print("cmd-wcd:"..file_img_wc)
            if file_size > 300 and file_img_wc < 2 then --kb
                local check_webp_img_cmd = config.img_identify_cmd ..raw_file_name .. "|grep  WEBP|wc -l"
                local t1 = io.popen(check_webp_img_cmd)
                local file_webp_img_wc = t1:read("*line")
                file_webp_img_wc = tonumber(file_webp_img_wc)
                if file_webp_img_wc < 1 then
                    local convert_cmd = config.img_convert_cmd .. raw_file_name .. " "..new_file_name
                    os.execute(convert_cmd)
                    if not file_exists(new_file_name) then
                        print("one2one_img convert file error "..convert_cmd)
                        return
                    end
                else
                    new_file_name = raw_file_name
                end
            else
                new_file_name = raw_file_name
            end
            local upload_img_cmd = config.upload.aws_s3_cmd .. new_file_name .. config.upload.aws_s3_dir_one2one .. new_img_name .." 1>/dev/null 2>&1 >>/dev/null"
            os.execute(upload_img_cmd)
            local ok_convert_url = config.upload.resource_url_one2one .. new_img_name
            local check_cmd = "curl -sI " .. ok_convert_url
            local t = io.popen(check_cmd)
            local a = t:read("*line")
            local ret_code = sfind(a, "200", 1, true)
            local ret_code = true
            if ret_code then
                seq_files[seq_num] = new_img_name
                ok_num = ok_num + 1
            else
                print(now_date() .." one2one_img check error "..ok_convert_url)
            end
        end
    end
    if ok_num == 0 then
        print(now_date() .." one2one_img num error ")
        return
    end

    if total_num ~= ok_num then
        print(now_date() .." one2one_img queue num not equal raw_num:"..total_num .. " ok_num:"..ok_num)
    end
    local time_stamp_tmp = socket.gettime() * 1000
    local time_stamp = math.ceil(time_stamp_tmp)
    --1:img-list 2:video
    local base_info_tmp = redis_client:hget(config.redis_key.user_prefix .. myuid, "base_info")
    local my_base_info = json.decode(base_info_tmp) or {}
    local gender = my_base_info.gender or 0
    local mm_id = insert_moments_img_info(myuid,1,1,price,"",desc,time_stamp,config.upload.resource_url_one2one,seq_files,mm_from,gender)
    if not mm_id or mm_id <= 0 then
        print(now_date() .." one2one_img insert-imgs-error:time_stamp "..time_stamp)
        return
    end
    local real_data = {
        uid = myuid,
        add_type = 1,
        price = price,
        base_url = config.upload.resource_url_one2one,
        img_urls = seq_files,
        time_stamp = time_stamp,
        desc = desc,
        mm_from = mm_from,
    }
    redis_client:hset(config.redis_key.one2one_prefix_hash_key..mm_id,"data",json.encode(real_data))
    redis_client:zadd(config.redis_key.one2one_myids_key..myuid, time_stamp, mm_id)
    print(now_date() .." one2one_img-ok:uid:"..myuid.." id:"..mm_id)
    return
end

--one2one
local function deal_one2one_video(data)
    local myuid = data.uid
    local price = tonumber(data.price)
    local desc = data.desc
    local video_url = data.video_url
    local mm_from = data.mm_from
    local raw_video_name = get_del_path(video_url)

    local luuid_str = luuid.new("time")
    local rand_str = ssub(luuid_str,1,8)
    local new_name = "oo_"..rand_str..raw_video_name
    local raw_file_name = config.upload.compress_video_raw_dir..raw_video_name
    local new_file_name = config.upload.compress_video_ok_dir .. new_name
    if not file_exists(raw_file_name) then
        local down_cmd = "wget -q -O '"..raw_file_name.."' '"..video_url.."'"
        os.execute(down_cmd)
    end
    if not file_exists(raw_file_name) then
        print("one2one_video down file error "..down_cmd)
        return
    end
    local check_filesize_cmd = "du -k "..raw_file_name .. "|awk '{print $1}'"
    local t = io.popen(check_filesize_cmd)
    local file_size = t:read("*line")
    file_size = tonumber(file_size)
    if file_size > 3072 then --3m
        local compress_cmd = config.ffmpeg_cmd.." -y -v error -i "..raw_file_name.." -strict -2 -vcodec libx264 -preset ultrafast -crf 30 -acodec aac -ar 44100 -ac 2 -b:a 96k "..new_file_name
        if not file_exists(new_file_name) then 
            os.execute(compress_cmd) 
        end
    else
        local cp_cmd = "cp -f "..raw_file_name .. " " ..new_file_name
        os.execute(cp_cmd)
        --print(cp_cmd)
    end
    if not file_exists(new_file_name) then 
        print(now_date() .." one2one_video error raw:"..raw_file_name)
        return
    end
    
    --------add video cover start--------
    local new_cover_name = get_path_without_suffix(new_name) .. ".jpg"
    local new_cover_file_name = config.upload.compress_video_ok_dir .. new_cover_name
    -- get the compress video cover
    local get_cover_cmd = config.ffmpeg_cmd.." -y -v error -i "..new_file_name.."  -vframes 1 -q:v 2  -f mjpeg "..new_cover_file_name
    if not file_exists(new_cover_file_name) then
        os.execute(get_cover_cmd)
    end
    if not file_exists(new_cover_file_name) then
        print(now_date() .." one2one_video get cover error :".." cmd:"..get_cover_cmd)
        return
    end
    local upload_video_cover_cmd = config.upload.aws_s3_cmd .. new_cover_file_name .. config.upload.aws_s3_dir_one2one .. new_cover_name .." 1>/dev/null 2>&1 >>/dev/null"
    os.execute(upload_video_cover_cmd)
    local ok_cover_compress_url = config.upload.resource_url_one2one .. new_cover_name
    local check_cmd = "curl -sI " .. ok_cover_compress_url
    local t = io.popen(check_cmd)
    local a = t:read("*line")
    local ret_code = sfind(a, "200", 1, true)
    if not ret_code then
        print(now_date() .." one2one_video video-cover check error raw:"..ok_cover_compress_url)
        return
    end
    --------add video cover end--------

    --------get width_height start--------
    local get_width_height_cmd = config.ffprobe_cmd.." -v quiet -print_format json -show_streams " .. new_file_name
    local t = io.popen(get_width_height_cmd)
    local a = t:read("*all")
    local ffprobe_info = json.decode(a)
    local video_width = tonumber(ffprobe_info.streams[1].width) or 540 
    local video_height = tonumber(ffprobe_info.streams[1].height) or 960
    --------get width_height end--------

    local upload_video_cmd = config.upload.aws_s3_cmd .. new_file_name .. config.upload.aws_s3_dir_one2one .. new_name .." 1>/dev/null 2>&1 >>/dev/null"
    os.execute(upload_video_cmd)
    local ok_compress_url = config.upload.resource_url_one2one .. new_name
    local check_cmd = "curl -sI " .. ok_compress_url
    local t = io.popen(check_cmd)
    local a = t:read("*line")
    local ret_code = sfind(a, "200", 1, true)
    if not ret_code then
        print(now_date() .." one2one_video check error raw:"..ok_compress_url)
        return
    end
    local time_stamp_tmp = socket.gettime() * 1000
    local time_stamp = math.ceil(time_stamp_tmp)
    --1:img-list 2:video
    local base_info_tmp = redis_client:hget(config.redis_key.user_prefix .. myuid, "base_info")
    local my_base_info = json.decode(base_info_tmp) or {}
    local gender = my_base_info.gender or 0

    local mm_id = insert_moments_video_info(myuid,1,2,price,"",desc,time_stamp,new_name,new_cover_name,video_width,video_height,config.upload.resource_url_one2one,mm_from,gender)
    mm_id = tonumber(mm_id)
    if not mm_id or mm_id <= 0 then
        print(now_date() .." one2one_video insert-video-error:time_stamp"..time_stamp)
        return
    end
    local real_data = {
        uid = myuid,
        add_type = 2,
        price = price,
        base_url = config.upload.resource_url_one2one,
        video_url = new_name,
        video_cover = new_cover_name,
        video_width = video_width,
        video_height = video_height,
        time_stamp = time_stamp,
        desc = desc,
        mm_from = mm_from,
    }
    redis_client:hset(config.redis_key.one2one_prefix_hash_key..mm_id,"data",json.encode(real_data))
    redis_client:zadd(config.redis_key.one2one_myids_key..myuid, time_stamp, mm_id)
    print(now_date() .." one2one_video-ok:uid:"..myuid.." id:"..mm_id)
    --del raw one2one video file
    local cmd1 = config.upload.aws_s3_cmd_rm .. config.upload.aws_s3_dir .. raw_video_name
    os.execute(cmd1)
    return
end

-- 0:init 1:ok 2:check-error 3:add-credit-error
local function deal_paypal_voucher_notify(wcd_data)
    local paypal_data = wcd_data.data
    local id = wcd_data.id
    local prepayid = wcd_data.prepayid
    -- lock
    local lock_key = config.redis_key.paypal_voucher_lock_key..prepayid
    local is_locked = redis_client:get(lock_key)
    if is_locked then
        local queue_data = {
            queue_type = "paypal_voucher",
            id = id,
            retry_times = 0,
            prepayid = prepayid,
            need_check_paypal = 1,
            data = '',
        }
        redis_client:lpush(config.redis_key.queue_list_key, json.encode(queue_data))
        print(now_date() .."[deal_paypal_voucher_notify] get the lock lock-id:"..is_locked)
        return
    else
        redis_client:setex(lock_key, 5,id)
    end

    local retry_times = tonumber(wcd_data.retry_times)
    local need_check_paypal = wcd_data.need_check_paypal
    local tmp_info_1 = voucher_select_paypal_order(id)
    local status_1 = tonumber(tmp_info_1.status)
    local myuid = tmp_info_1.uid
    if status_1 == 0 and need_check_paypal == 1 then
        local paypal_return = lua_curl(paypal_data)
        local ret_code = sfind(paypal_return, "VERIFIED", 1, true)
        if not ret_code then
            local finish_time = now_time()
            voucher_update_orderid_status_usd(id,2,finish_time)
            print(now_date() .." [paypal_voucher error] verified uid:"..myuid.." id:"..id.." re-data:"..paypal_return.." post-data:"..paypal_data)
            redis_client:del(lock_key)
            return
        else
            print(now_date() .." [paypal_voucher verified ok] verified uid:"..myuid.." id:"..id.." re-data:"..paypal_return)
        end
    end

    local tmp_info = voucher_select_paypal_order(id)
    local status = tonumber(tmp_info.status)
    local credit_num = tonumber(tmp_info.credit)
    local extra_credit_num = tonumber(tmp_info.extra_credit)
    local vip = tonumber(tmp_info.vip)
    local usd = tmp_info.usd
    local vip_time = tonumber(tmp_info.vip_time)
    if status == 1 then
        print(now_date() .." [paypal_voucher error] paypal voucher db-id already ok id:"..id)
        redis_client:del(lock_key)
        return
    elseif status == 3 and retry_times < 4 then
        local add_re = add_voucher_credit_and_viptime(id,myuid,credit_num,extra_credit_num,vip,vip_time,usd)
        if add_re then
            local finish_time = now_time()
            local update_re = voucher_update_orderid_status_usd(id,1,finish_time)
            if update_re ~= 1 then
                print(now_date() .." [paypal_voucher error] voucher_update_orderid_status_usd error id:"..id.." status:2")
                redis_client:del(lock_key)
                return
            else
                if vip == 0 then 
                    print(now_date() .." [paypal_voucher ok]  id:"..id.." uid:"..myuid .. " credit_num:"..credit_num.."   extra_credit_num:"..extra_credit_num)
                else
                    print(now_date() .." [paypal_voucher ok]  id:"..id.." uid:"..myuid .. " credit_num:"..credit_num.."   extra_credit_num:"..extra_credit_num.." vip:"..vip.." vip-time:"..vip_time)
                end
                redis_client:del(lock_key)
            end
        else
            local queue_data = {
                queue_type = "paypal_voucher",
                id = id,
                retry_times = retry_times + 1,
                need_check_paypal = 0,
                prepayid = prepayid,
                data = '',
            }
            redis_client:lpush(config.redis_key.queue_list_key, json.encode(queue_data))
            print(now_date() .. "[paypal_voucher error] add credit  error id:"..id.." retry_times:"..retry_times)
            redis_client:del(lock_key)
            return
        end
    elseif status == 0 then
        local add_re = add_voucher_credit_and_viptime(id,myuid,credit_num,extra_credit_num,vip,vip_time,usd)
        if add_re then
            local finish_time = now_time()
            local update_re = voucher_update_orderid_status_usd(id,1,finish_time)
            if update_re ~= 1 then
                print(now_date() .." [paypal_voucher error] voucher_update_orderid_status_usd error id:"..id)
            end
            if vip == 0 then
                print(now_date() .." [paypal_voucher ok]  id:"..id.." uid:"..myuid .. " credit_num:"..credit_num.."   extra_credit_num:"..extra_credit_num)
            else
                print(now_date() .." [paypal_voucher ok]  id:"..id.." uid:"..myuid .. " credit_num:"..credit_num.."   extra_credit_num:"..extra_credit_num.." vip:"..vip.." vip-time:"..vip_time)
            end
            redis_client:del(lock_key)
            return
        else
            voucher_update_orderid_status_usd(id,3,nil)
            local queue_data = {
                queue_type = "paypal_voucher",
                id = id,
                prepayid = prepayid,
                retry_times = retry_times + 1,
                need_check_paypal = 0,
                data = '',
            }
            redis_client:lpush(config.redis_key.queue_list_key, json.encode(queue_data))
            print(now_date() .." [paypal_voucher error] add credit  error id:"..id)
            redis_client:del(lock_key)
            return
        end
    else
        print(now_date() .." [paypal_voucher error] status-error:"..status.." retry_times:"..retry_times)
    end
end

local deal_newcomer_fcm_one2one = function(data)
    local cando_time = data.cando_time
    local from_uid = data.from_uid
    local to_uid = data.to_uid
    local base_info = data.base_info
    local now_time_value = now_time()
    if cando_time <= now_time_value then
        local real_data_id = redis_client:zrange(config.redis_key.one2one_myids_key..from_uid,-1,-1)
        if not real_data_id or not real_data_id[1] then
            print(now_date() .."[newcomer-one2one-fcm error] no-info from_uid:"..from_uid.." to_uid:"..to_uid)
            return 0
        end
        real_data_id = real_data_id[1]
        local real_data_tmp = redis_client:hget(config.redis_key.one2one_prefix_hash_key .. real_data_id,"data")
        local real_data = json.decode(real_data_tmp) or {}
        local o2o_data
        if real_data.add_type == 1 then
            o2o_data = {
                id = tonumber(real_data_id),
                time_stamp = real_data.time_stamp,
                add_type = 1,
                img_urls = real_data.img_urls,
                base_url = real_data.base_url,
                price = real_data.price,
                position = real_data.position,
                mm_from = real_data.mm_from,
                desc = real_data.desc,
            }
        elseif real_data.add_type == 2 then
            o2o_data = {
                id = tonumber(real_data_id),
                time_stamp = real_data.time_stamp,
                add_type = 2,
                base_url = real_data.base_url,
                video_url = real_data.video_url,
                video_cover = real_data.video_cover,
                video_width = real_data.video_width,
                video_height = real_data.video_height,
                price = real_data.price,
                position = real_data.position,
                mm_from = real_data.mm_from,
                desc = real_data.desc,
            }
        else
            return 0
        end
        local  one2one_data = json.encode(o2o_data)
        local fcm_son_data = {
            type = "im",
            title = "newcomer",
            alert = "Hi, could u chat with me for a while?",
            accessory = {
                    mime = "moment/json",
                    url = one2one_data,
            },
            to = to_uid,
            from = {
                    uid = from_uid,
                    uniq = base_info.uniq,
                    super = base_info.super or 0,
                    username = base_info.username,
                    avatar = base_info.avatar,
            },
            msgid = from_uid ..':'..now_time_value * 1000,
            time = now_time_value,
            level = "user",
        }
        local fcm_data = {
            uid = to_uid,
            class = "unlock",
            time = now_time_value,
            data = json.encode(fcm_son_data)
        }
        sleep(1)
        redis_client:lpush(config.redis_key.fcm_redis_key, json.encode(fcm_data))
        print(now_date() .. " [newcomer-one2one-fcm ok] from-uid:"..from_uid .. " to-uid:"..to_uid)
        return 0
    end
    return 1
end

local function deal_queue(raw_data)
    local decode_data = json.decode(raw_data)
    if not decode_data then
        return
    end
    local queue_type = decode_data.queue_type
    if queue_type ~= "newcomer_fcm_one2one" then
        print(now_date().." ======start=======" ..queue_type)
    end
    if queue_type == "fcm" then
        deal_fcm_token(decode_data)
    elseif queue_type == "gg_voucher" then
        deal_gg_voucher_check(decode_data)
    elseif queue_type == "wx_voucher" then
        deal_weinxin_voucher_notify(decode_data)
    elseif queue_type == "test" then
        deal_wcd_test(decode_data)
    elseif queue_type == "moments_video" then
        deal_moments_video(decode_data)
    elseif queue_type == "moments_img" then
        deal_moments_img(decode_data)
    elseif queue_type == "paypal_voucher" then
        deal_paypal_voucher_notify(decode_data)
    elseif queue_type == "one2one_img" then
        deal_one2one_img(decode_data)
    elseif queue_type == "one2one_video" then
        deal_one2one_video(decode_data)
    elseif queue_type == "newcomer_fcm_one2one" then
        local re = deal_newcomer_fcm_one2one(decode_data)
        if re == 1 then
            sleep(3)
            redis_client:lpush(config.redis_key.queue_list_key, raw_data)
        end
    end
    if queue_type ~= "newcomer_fcm_one2one" then
        print(now_date().." ======end=======" ..queue_type)
    end
end


local function receive(prod)
    local status, value = coroutine.resume(prod)
    return value
end

local function send(x)
    coroutine.yield(x)
end

local function get_data()
    local co = coroutine.create(function()
        while true do
            if not redis_client then
                print(now_date().." redis error")
                os.exit()
            end
            local x = redis_client:rpop(config.redis_key.queue_list_key)
            if x then
                send(x)
            else
                sleep(8)
            end
           sleep() 
        end
    end)
	return co
end

local function insert_data(prod)
    while true do
        local x = receive(prod)
        -- 入库
        deal_queue(x)
    end
end
if config.redis_key.queue_list_key == "queue_list:" then
    print("instance_id error")
    os.exit()
else
    print(config.redis_key.queue_list_key)
end
local p = get_data()
insert_data(p)