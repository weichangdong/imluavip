local user6_router = {}
local redis = require("app2.lib.redis")
local config = require("app2.config.config")
local my_redis = redis:new()
local mysql = require("app2.model.user")
local mysql_user_extend = require("app2.model.user_extend")
local mysql_money = require("app2.model.money")
local ngx = ngx
local md5 = ngx.md5
local exit = ngx.exit
local sleep = ngx.sleep
local pcall = pcall
local iopopen = io.popen
local utils = require("app2.lib.utils")
local json = require("cjson.safe")
local mms_model = require("app2.model.mms")
local mm_tag_model = require("app2.model.mm_tag")
local table_object  = json.encode_empty_table_as_object

local tinsert = table.insert
local tsort = table.sort
local tonumber = tonumber
local tostring = tostring
local match = string.match
local slen = string.len
local tconcat = table.concat
local pairs = pairs
local ipairs = ipairs
local io = io
local string = string
local ngx_quote_sql_str = ngx.quote_sql_str
local shared_cache = ngx.shared.fresh_token_limit
local moments_list_limit_num = 20
local LOG_FROM_DAILY_GIFT = 6

local function access_limit(res, key, limit_num, limit_time)
    local time = limit_time or 60
    local num = limit_num or 0
    local key = 'user6_'..key
    local limit_v = shared_cache:get(key)
    if not limit_v then
        shared_cache:set(key, 1, time)
    else
        if limit_v > num then
            res:status(400):json({})
            exit(200)
        end
        shared_cache:incr(key, 1)
    end
end

user6_router.one2one_price_list = function(req, res, next)
    local re = {}
    --[[
    local data_video = {yes = {0,15,30,75},no = {}}
    local data_img = {yes = {0,5,25},no = {}}
    local dat = {
        credits_img = data_img,
        credits_video = data_video,
    }
    local aes_dat = utils.encrypt(dat, req.query.aes)
    re["ret"] = 0
    re["dat"] = aes_dat
    res:json(re)
    exit(200)
    ]]
    local myuid = req.params.uid
    local other_info_tmp = my_redis:hget(config.redis_key.user_prefix .. myuid,'price')
    local free_data_video = {yes = {0,15}, no = {30,75}}
    local free_data_img = {yes = {0,5}, no = {25}}
    if  utils.is_redis_null(other_info_tmp) then
        local dat = {
            credits_img = free_data_img,
            credits_video = free_data_video,
        }
        local aes_dat = utils.encrypt(dat, req.query.aes)
        re["ret"] = 0
        re["dat"] = aes_dat
        res:json(re)
        exit(200)
    end
    local price = tonumber(other_info_tmp)
    local data_video,data_img
    if not price or price == 0 then
        data_video = free_data_video
        data_img = free_data_img
    else
        data_video = {yes = {0,15,30,75},no = {}}
        data_img = {yes = {0,5,25},no = {}}
    end
    local dat = {
        credits_img = data_img,
        credits_video = data_video,
    }
    local aes_dat = utils.encrypt(dat, req.query.aes)
    re["ret"] = 0
    re["dat"] = aes_dat
    res:json(re)
    exit(200)
end

user6_router.one2one_lets_del = function(req, res, next)
    local re = {}
    local myuid = req.params.uid
    local raw_post_data = req.body
    utils.check_para(raw_post_data)
    local raw_post_data = utils.decrypt(raw_post_data, req.query.aes)
    local post_data = json.decode(raw_post_data)
    if utils.is_table_empty(post_data) then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local id = post_data.id
    utils.check_para(id)
    local time_stamp = post_data.time_stamp
    utils.check_para(time_stamp)

    local mm_redis_key = config.redis_key.one2one_prefix_hash_key..id
    local data_tmp = my_redis:hget(mm_redis_key,"data")
    if utils.is_redis_null(data_tmp) then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local real_data = json.decode(data_tmp)
    local uid = real_data.uid
    if myuid ~= uid then
        ngx.print('{"ret":3}')
        exit(200)
    end
    -- del the real data
    my_redis:del(mm_redis_key)
    -- del users data
    my_redis:zrem(config.redis_key.one2one_myids_key..myuid, id)
    -- sync act moments del
    local need_cron_data = {
            act = 'moments_del',
            uid = myuid,
            data = {
                mm_id = id,
            }
    }
    my_redis:rpush(config.redis_key.cron_list_key, json.encode(need_cron_data))
    ngx.print('{"ret":0}')
    exit(200)
end

user6_router.one2one_mylist = function(req, res, next)
    local re = {}
    local myuid = req.params.uid
    local raw_post_data = req.body
    utils.check_para(raw_post_data)
    local raw_post_data = utils.decrypt(raw_post_data, req.query.aes)
    local post_data = json.decode(raw_post_data)
    if utils.is_table_empty(post_data) then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local updown = post_data.updown
    if updown ~= 1  and updown ~= 2 then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local id = post_data.id
    utils.check_para(id)
    local time_stamp = tonumber(post_data.time_stamp)
    utils.check_para(time_stamp)

    local base_info_tmp = my_redis:hget(config.redis_key.user_prefix .. myuid, "base_info")
    if utils.is_redis_null(base_info_tmp) then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local base_info = json.decode(base_info_tmp)
    local is_vip = my_redis:exists(config.redis_key.vip_user_key..myuid)
    local base_info_ok = {
        uid = myuid,
        username = base_info.username,
        avatar = base_info.avatar,
        super = base_info.super or 0,
        vip = is_vip
    }

    local all_ids
    if time_stamp == 0 then
        all_ids = my_redis:zrevrangebyscore(config.redis_key.one2one_myids_key..myuid,"+inf",0,"limit",0,moments_list_limit_num)
        if utils.is_redis_null_table(all_ids) then
            ngx.print('{"ret":35}')
            exit(200)
        end
    --1=down向下刷新，就是下拉 获取最新数据
    elseif updown == 1 then
        local rank = my_redis:zrevrank(config.redis_key.one2one_myids_key..myuid,id)
        if not rank or rank == 0 then
            ngx.print('{"ret":36}')
            exit(200)
        else
            all_ids = my_redis:zrevrangebyscore(config.redis_key.one2one_myids_key..myuid,"+inf",0,"limit",0,moments_list_limit_num)
        end
    --2=up 向上滑动 获取旧的数据
    elseif updown == 2 then
        all_ids = my_redis:zrevrangebyscore(config.redis_key.one2one_myids_key..myuid,time_stamp - 1,"-inf","limit",0,moments_list_limit_num)
        if utils.is_redis_null_table(all_ids) then
            ngx.print('{"ret":37}')
            exit(200)
        end
    else
        ngx.print('{"ret":3}')
        exit(200)
    end

    local ok_info = {}
    local ok_num = 0
    for _,v in ipairs(all_ids) do
        local mm_redis_key = config.redis_key.one2one_prefix_hash_key..v
        local real_data_tmp = my_redis:hget(mm_redis_key,"data")
        if not utils.is_redis_null(real_data_tmp) then
            local real_data = json.decode(real_data_tmp) or {}
            local uid = real_data.uid
            if uid then
                    local real_data_price = real_data.price
                    --1:img-list 2:video
                    local one
                    if real_data.add_type == 1 then
                        one = {
                            id = tonumber(v),
                            time_stamp = real_data.time_stamp,
                            add_type = 1,
                            img_urls = real_data.img_urls,
                            base_url = real_data.base_url,
                            price = real_data_price,
                            desc = real_data.desc,
                            mm_from = real_data.mm_from or 0,
                        }
                    else
                        one = {
                            id = tonumber(v),
                            time_stamp = real_data.time_stamp,
                            add_type = 2,
                            base_url = real_data.base_url,
                            video_url = real_data.video_url,
                            video_cover = real_data.video_cover,
                            video_width = real_data.video_width,
                            video_height = real_data.video_height,
                            price = real_data_price,
                            desc = real_data.desc,
                            mm_from = real_data.mm_from or 0,
                        }
                    end

                    mms_model:merge_mm_info(one, myuid)

                    tinsert(ok_info, one)
                    ok_num = ok_num + 1
            end
        end
    end
    if ok_num == 0 and time_stamp == 0 then
        ngx.print('{"ret":35}')
        exit(200)
    elseif ok_num == 0 and updown == 1 then
        ngx.print('{"ret":36}')
        exit(200)
    elseif ok_num == 0 and updown == 2 then
        ngx.print('{"ret":37}')
        exit(200)
    end
    local dat = {
        list  = ok_info,
        base_info = base_info_ok,
    }
    local aes_dat = utils.encrypt(dat, req.query.aes)
    re["ret"] = 0
    re["dat"] = aes_dat
    res:json(re)
    exit(200)
end

user6_router.editor_all_list = function(req, res, next)
    local re = {}
    local raw_post_data = req.body
    utils.check_para(raw_post_data)
    local raw_post_data = utils.decrypt(raw_post_data, req.query.aes)
    local post_data = json.decode(raw_post_data)
    if utils.is_table_empty(post_data) then
        ngx.print('{"ret":3}')
        exit(200)
    end
    if not post_data.md5 then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local data_md5 = my_redis:get(config.redis_key.moments_special_md5_key)
    if post_data.md5 == data_md5 or utils.is_redis_null(data_md5) then
        ngx.print('{"ret":45}')
        exit(200)
    end
    local data = my_redis:mget(config.redis_key.moments_special_data_key,config.redis_key.moments_banner_data_key)
    if utils.is_redis_null(data[1]) and utils.is_redis_null(data[2]) then
        ngx.print('{"ret":45}')
        exit(200)
    end
    
    -- banner data
    local ok_info = json.decode(data[1]) or {}
    local ok_banner_info = json.decode(data[2]) or {}
    local dat = {
        list  = ok_info,
        md5 = data_md5,
        banner = ok_banner_info,
    }
    local aes_dat = utils.encrypt(dat, req.query.aes)
    re["ret"] = 0
    re["dat"] = aes_dat
    res:json(re)
    exit(200)
end

user6_router.editor_one_list = function(req, res, next)
    local re = {}
    local  myuid = nil
    if req.params.uid then
        myuid = req.params.uid
    end
    local raw_post_data = req.body
    utils.check_para(raw_post_data)
    local raw_post_data = utils.decrypt(raw_post_data, req.query.aes)
    local post_data = json.decode(raw_post_data)
    if utils.is_table_empty(post_data) then
        ngx.print('{"ret":3}')
        exit(200)
    end
    utils.check_para(post_data.pid)
    local pid = post_data.pid
    local all_ids
    local time_stamp = tonumber(post_data.time_stamp)
    utils.check_para(time_stamp)
    if time_stamp == 0 then
        all_ids = my_redis:zrevrangebyscore(config.redis_key.moments_special_zset_key..pid,"+inf",0,"limit",0,moments_list_limit_num)
    else
        all_ids = my_redis:zrevrangebyscore(config.redis_key.moments_special_zset_key..pid,time_stamp-1,"-inf","limit",0,moments_list_limit_num)
    end
    if utils.is_redis_null_table(all_ids) then
            ngx.print('{"ret":40}')
            exit(200)
    end
    local is_vip = 0
    if myuid then
        is_vip = my_redis:exists(config.redis_key.vip_user_key..myuid)
    end
    local last_rand_num = 2
    local ok_num = 0
    local ok_info = {}
    local is_pvip = 0
    local all_pvips = {}
    local base_info_tmp_all = {}
    for _,v in ipairs(all_ids) do
        local if_weather_follow = 0
        local is_unlock = 0
        local mm_redis_key = config.redis_key.moments_prefix_hash_key..v
        local real_data_tmp = my_redis:hmget(mm_redis_key,"data","special_time","tags")
        if not utils.is_redis_null(real_data_tmp) and not utils.is_redis_null(real_data_tmp[1]) and not utils.is_redis_null(real_data_tmp[2]) then
            local real_data = json.decode(real_data_tmp[1]) or {}
            local uid = real_data.uid
            if uid then
                local real_data_price = tonumber(real_data.price)
                local hot_num
                local rand_num
                local unlock_num = 0
                if real_data_price > 0 then
                    hot_num = my_redis:hincrby(mm_redis_key,"hot", 1)
                    --hot_num = utils.img_random()
                    unlock_num = my_redis:hget(mm_redis_key,"unlock_num")
                    unlock_num = tonumber(unlock_num) or 0
                else
                    rand_num = utils.fb_random(3)
                    if rand_num == last_rand_num then
                        rand_num = 1
                    end
                    hot_num = my_redis:hincrby(mm_redis_key,"hot", rand_num)
                    last_rand_num = rand_num
                end
                local base_info_tmp
                if base_info_tmp_all[uid] then
                    base_info_tmp = base_info_tmp_all[uid]
                else
                    base_info_tmp = my_redis:hget(config.redis_key.user_prefix .. uid, "base_info")
                    base_info_tmp_all[uid] = base_info_tmp
                end

                if not utils.is_redis_null(base_info_tmp) then
                    local base_info = json.decode(base_info_tmp)
                    if myuid and myuid ~= uid then
                        local is_my_fans = my_redis:zscore(config.redis_key.follow_me_prefix .. uid, myuid)
                        if not utils.is_redis_null(is_my_fans) then
                            if_weather_follow = 1
                        end
                        if is_vip == 0 and myuid ~= uid and real_data_price > 0 then
                            local is_payed = my_redis:hexists(mm_redis_key, config.redis_key.moments_pay_uid_key .. myuid)
                            if is_payed == 1 then
                                is_unlock = 1
                            end
                        end

                        if not all_pvips[uid] then
                            is_pvip = my_redis:exists(config.redis_key.vip_user_key..uid)
                            all_pvips[uid] = is_pvip
                        else
                            is_pvip = all_pvips[uid]
                        end
                    elseif myuid == uid then
                        is_pvip = is_vip
                    end
                    local sp_time_stamp = tonumber(real_data_tmp[2])
                    local tags = json.decode(real_data_tmp[3]) or {}

                    local one
                    --1:img-list 2:video
                    if real_data.add_type == 1 then
                        one = {
                            uid = uid,
                            username = base_info.username,
                            avatar = base_info.avatar,
                            icare = if_weather_follow,
                            super = base_info.super or 0,
                            id = tonumber(v),
                            time_stamp = sp_time_stamp,
                            add_type = 1,
                            img_urls = real_data.img_urls,
                            base_url = real_data.base_url,
                            price = real_data_price,
                            position = real_data.position,
                            mm_from = real_data.mm_from or 0,
                            desc = real_data.desc,
                            hot_num = hot_num,
                            unlock_num = unlock_num,
                            unlock = is_unlock,
                            h5_url = "moments/share/",
                            pvip = is_pvip,
                            tags = tags,
                        }
                    else
                        one = {
                            uid = uid,
                            username = base_info.username,
                            avatar = base_info.avatar,
                            icare = if_weather_follow,
                            super = base_info.super or 0,
                            id = tonumber(v),
                            time_stamp = sp_time_stamp,
                            add_type = 2,
                            video_url = real_data.video_url,
                            base_url = real_data.base_url,
                            video_cover = real_data.video_cover,
                            video_width = real_data.video_width,
                            video_height = real_data.video_height,
                            price = real_data_price,
                            position = real_data.position,
                            mm_from = real_data.mm_from or 0,
                            desc = real_data.desc,
                            hot_num = hot_num,
                            unlock_num = unlock_num,
                            unlock = is_unlock,
                            h5_url = "moments/share/",
                            pvip = is_pvip,
                            tags = tags,
                        }
                    end

                    mms_model:merge_mm_info(one, myuid)

                    tinsert(ok_info, one)
                    ok_num = ok_num + 1
                end
            end
        end
    end
    if ok_num == 0  then
        ngx.print('{"ret":40}')
        exit(200)
    end
    local dat = {
        list  = ok_info,
        vip = is_vip
    }
    local aes_dat = utils.encrypt(dat, req.query.aes)
    re["ret"] = 0
    re["dat"] = aes_dat
    res:json(re)
    exit(200)
end

user6_router.daily_send_credit_vip = function(req, res, next)
    local type_switch = config.daily_send_type_switch
    if type_switch == 0 then
        ngx.print('{"ret":21}')
        exit(200)
    end
    local re = {}
    local myuid = req.params.uid
    local log_time = ngx.time()
    local today = os.date("%Y%m%d", log_time - 57600) --utc-8 base utc+8
    if type_switch == 1 then --credit
        --local your_key = config.redis_key.daily_gift_key .. myuid..':'..today
        local your_key = config.redis_key.daily_gift_key .. myuid
        local total_get_times = my_redis:scard(your_key)
        if total_get_times >= config.daily_gift_max_times then
            ngx.print('{"ret":21}')
            exit(200)
        end
        local is_get = my_redis:sismember(your_key,today)
        if is_get == 1 then
            ngx.print('{"ret":21}')
            exit(200)
        end
        local update2_re, select2_re = mysql_user_extend:update_user_credit(myuid, config.daily_gift_num)
        local now_credit = 0
        if update2_re and update2_re.affected_rows == 1  then
                my_redis:sadd(your_key, today)
                mysql_money:insert_credit_log(myuid, LOG_FROM_DAILY_GIFT, 0, config.daily_gift_num, log_time)
                now_credit = select2_re[1].credit
                re["ret"] = 0
                local dat = {
                    credit = now_credit,
                    get_credit = config.daily_gift_num,
                    type = 0,
                    get_time = 0,
                }
                local aes_dat = utils.encrypt(dat, req.query.aes)
                re["dat"] = aes_dat
                res:json(re)
                exit(200)
        else
            local log_info = "==[daily_gift error] uid:" .. myuid .. "=="
            ngx.log(ngx.ERR, log_info)
            ngx.print('{"ret":22}')
            exit(200)
        end
    elseif type_switch == 2 then --vip
        local is_vip = my_redis:exists(config.redis_key.vip_user_key..myuid)
        if is_vip == 1 then
            ngx.print('{"ret":21}')
            exit(200)
        end
        local is_send_vip = my_redis:exists(config.redis_key.send_tmp_vip_user_key..myuid)
        if is_send_vip == 1 then
            ngx.print('{"ret":47}')
            exit(200)
        end
        local your_key = config.redis_key.daily_vip_key .. myuid
        local total_get_times = my_redis:scard(your_key)
        if total_get_times >= config.daily_vip_max_times then
            ngx.print('{"ret":21}')
            exit(200)
        end
        local is_get = my_redis:sismember(your_key,today)
        if is_get == 1 then
            ngx.print('{"ret":21}')
            exit(200)
        end
        my_redis:sadd(your_key, today)
        my_redis:setex(config.redis_key.send_tmp_vip_user_key..myuid, config.daily_vip_num * 60 + 300,log_time)
        mysql_money:insert_vip_log(myuid,0,log_time,log_time + config.daily_vip_num * 60)
        re["ret"] = 0
        local dat = {
            credit = 0,
            get_credit = 0,
            type = 1,
            get_time = config.daily_vip_num,
        }
        local aes_dat = utils.encrypt(dat, req.query.aes)
        re["dat"] = aes_dat
        res:json(re)
        exit(200)
    end
end

user6_router.anchors_online_list = function(req, res, next)
    local re = {}
    local  myuid = nil
    if req.params.uid then
        myuid = tonumber(req.params.uid)
    end
    local raw_post_data = req.body
    utils.check_para(raw_post_data)
    local raw_post_data = utils.decrypt(raw_post_data, req.query.aes)
    local post_data = json.decode(raw_post_data)
    if utils.is_table_empty(post_data) then
        ngx.print('{"ret":3}')
        exit(200)
    end
    utils.check_para(post_data.uniq)
    local need_ok_num = 12
    local ok_info = {}
    local ok_num = 0
    local limit_num = 1000
    -- girl
    for i=1,20 do
        if ok_num >= need_ok_num then
            break
        end
        local limit_start = (i-1) * limit_num
        local one = mysql:get_user_gender_by_limit(2,limit_start,limit_num)
        if not one then
            break
        end
        for _,tmp in pairs(one) do
            if ok_num >= need_ok_num then
                break
            end
            local uid = tmp.id
            if myuid ~= uid then
                local state = my_redis:hget(config.redis_key.user_prefix .. uid,'state')
                state = tonumber(state) or 0
                if state > 0 and state < 5 then
                    local ok_one_info = {
                        uid = uid,
                        username = tmp["username"],
                        avatar = tmp["avatar"],
                        gender = 2,
                        super = tmp["super"],
                    }
                    tinsert(ok_info, ok_one_info)
                    ok_num = ok_num + 1
                end
            end
        end
    end
    -- boy
    if ok_num < need_ok_num then
        for i=1,10 do
            if ok_num >= need_ok_num then
                break
            end
            local limit_start = (i-1) * limit_num
            local one = mysql:get_user_gender_by_limit(1,limit_start,limit_num)
            if not one then
                break
            end
            for _,tmp in pairs(one) do
                if ok_num >= need_ok_num then
                    break
                end
                local uid = tmp.id
                if myuid ~= uid then
                    local state = my_redis:hget(config.redis_key.user_prefix .. uid,'state')
                    state = tonumber(state) or 0
                    if state > 0 and state < 5 then
                        local ok_one_info = {
                            uid = uid,
                            username = tmp["username"],
                            avatar = tmp["avatar"],
                            gender = 1,
                            super = tmp["super"],
                        }
                        tinsert(ok_info, ok_one_info)
                        ok_num = ok_num + 1
                    end
                end
            end
        end
    end
    local dat = {
        list  = ok_info,
    }
    local aes_dat = utils.encrypt(dat, req.query.aes)
    re["ret"] = 0
    re["dat"] = aes_dat
    res:json(re)
    exit(200)
end

user6_router.online_by_ids = function(req, res, next)
    local re = {}
    local myuid = req.params.uid
    local raw_post_data = req.body
    utils.check_para(raw_post_data)
    local raw_post_data = utils.decrypt(raw_post_data, req.query.aes)
    local post_data = json.decode(raw_post_data)
    if utils.is_table_empty(post_data) then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local uids = post_data['uids']
    utils.check_para(uids)
    local all_uids = utils.string_split(uids,',')
    local total_len = #all_uids
    if total_len > 100 then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local ok_info = {}
    local all_uinfo = mysql_user_extend:select_user_info_byids(uids)
    for  _,one in pairs(all_uinfo) do
        local uid = one.uid
        local base_info_tmp = my_redis:hmget(config.redis_key.user_prefix .. uid,"base_info","state")
        if not utils.is_redis_null(base_info_tmp) and not utils.is_redis_null(base_info_tmp[1])  then
            local base_info = json.decode(base_info_tmp[1])
            local is_pay = 0
            if one.pay_num > 0 then
                is_pay = 1
            end
            local is_online = 0
            local state = tonumber(base_info_tmp[2]) or 0
            if state > 0 and state < 5 then
                is_online = 1
            end
            local ok_one = {
                uid = uid,
                username = base_info.username,
                avatar = base_info.avatar,
                super = base_info.super,
                gender = base_info.gender,
                remin_credit = one.credit,
                is_pay = is_pay,
                online = is_online,
            }
            tinsert(ok_info,ok_one)
        end
    end
    local dat = {
        list  = ok_info,
    }
    local aes_dat = utils.encrypt(dat, req.query.aes)
    re["ret"] = 0
    re["dat"] = aes_dat
    res:json(re)
    exit(200)
end

user6_router.top100_online = function(req, res, next)
    local re = {}
    local myuid = req.params.uid
    local raw_post_data = req.body
    utils.check_para(raw_post_data)
    local raw_post_data = utils.decrypt(raw_post_data, req.query.aes)
    local post_data = json.decode(raw_post_data)
    if utils.is_table_empty(post_data) then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local ok_num = 0
    local top_num_limit = 100
    local selected_uids = {}
    local ok_info = {}
    local all_payed_uinfo = mysql_user_extend:select_payded_users_info(1)
    for  _,one in pairs(all_payed_uinfo) do
        if ok_num > top_num_limit then
            break
        end
        local uid = one.uid
        local base_info_tmp = my_redis:hmget(config.redis_key.user_prefix .. uid,"base_info","state")
        if not utils.is_redis_null(base_info_tmp) and not utils.is_redis_null(base_info_tmp[1])  then
            local base_info = json.decode(base_info_tmp[1])
            local is_pay = 0
            if one.pay_num > 0 then
                is_pay = 1
            end
            local state = tonumber(base_info_tmp[2]) or 0
            if state > 0 and state < 5 then
                local ok_one = {
                    uid = uid,
                    username = base_info.username,
                    avatar = base_info.avatar,
                    super = base_info.super,
                    gender = base_info.gender,
                    remin_credit = one.credit,
                    is_pay = is_pay,
                }
                tinsert(ok_info,ok_one)
                ok_num = ok_num + 1
                selected_uids[uid] = 1
            end
        end
    end
    if ok_num < top_num_limit then
        local all_have_credit_uinfo = mysql_user_extend:select_payded_users_info(2)
        for  _,one in pairs(all_have_credit_uinfo) do
            if ok_num > top_num_limit then
                break
            end
            local uid = one.uid
            if not selected_uids[uid]  then
                local base_info_tmp = my_redis:hmget(config.redis_key.user_prefix .. uid,"base_info","state")
                if not utils.is_redis_null(base_info_tmp) and not utils.is_redis_null(base_info_tmp[1])  then
                    local base_info = json.decode(base_info_tmp[1])
                    local is_pay = 0
                    if one.pay_num > 0 then
                        is_pay = 1
                    end
                    local state = tonumber(base_info_tmp[2]) or 0
                    if state > 0 and state < 5 then
                        local ok_one = {
                            uid = uid,
                            username = base_info.username,
                            avatar = base_info.avatar,
                            super = base_info.super,
                            gender = base_info.gender,
                            remin_credit = one.credit,
                            is_pay = is_pay,
                        }
                        tinsert(ok_info,ok_one)
                        ok_num = ok_num + 1
                    end
                end
            end
        end
    end
    local dat = {
        list  = ok_info,
    }
    local aes_dat = utils.encrypt(dat, req.query.aes)
    re["ret"] = 0
    re["dat"] = aes_dat
    res:json(re)
    exit(200)
end


user6_router.tags_list = function(req,res,next)
    local raw_post_data = req.body
    utils.check_para(raw_post_data)
    local raw_post_data = utils.decrypt(raw_post_data, req.query.aes)
    local post_data = json.decode(raw_post_data)
    if utils.is_table_empty(post_data) then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local uniq = post_data['uniq']
    utils.check_para(uniq)
    local tags_info = my_redis:get(config.redis_key.moments_tags_data_key)
    local dat = {
        list  = json.decode(tags_info) or {},
    }
    local aes_dat = utils.encrypt(dat, req.query.aes)
    local re  = {}
    re["ret"] = 0
    re["dat"] = aes_dat
    res:json(re)
    exit(200)
end

user6_router.tag_moments_list = function(req, res, next)
    local re = {}
    local  myuid = nil
    if req.params.uid then
        myuid = req.params.uid
    end
    local raw_post_data = req.body
    utils.check_para(raw_post_data)
    local raw_post_data = utils.decrypt(raw_post_data, req.query.aes)
    local post_data = json.decode(raw_post_data)
    if utils.is_table_empty(post_data) then
        ngx.print('{"ret":3}')
        exit(200)
    end
    utils.check_para(post_data.tid)
    local tid = tonumber(post_data.tid)
    local id = post_data.id
    utils.check_para(id)
    id = tonumber(id)
    local all_ids
    local time_stamp = tonumber(post_data.time_stamp)
    utils.check_para(time_stamp)
    if time_stamp == 0 then
        all_ids = mm_tag_model:get_tag_mm_ids(tid,moments_list_limit_num,nil,nil)
    else
        all_ids = mm_tag_model:get_tag_mm_ids(tid,moments_list_limit_num,nil,id)
    end
    if utils.is_table_empty(all_ids) then
            ngx.print('{"ret":40}')
            exit(200)
    end
    local is_vip = 0
    if myuid then
        is_vip = my_redis:exists(config.redis_key.vip_user_key..myuid)
    end
    local last_rand_num = 2
    local ok_num = 0
    local ok_info = {}
    local is_pvip = 0
    local all_pvips = {}
    local base_info_tmp_all = {}
    for _,v in pairs(all_ids) do
        local if_weather_follow = 0
        local is_unlock = 0
        local mm_redis_key = config.redis_key.moments_prefix_hash_key..v.mm_id
        local real_data_tmp = my_redis:hmget(mm_redis_key,"data","tags")
        if not utils.is_redis_null(real_data_tmp) and not utils.is_redis_null(real_data_tmp[1]) then
            local real_data = json.decode(real_data_tmp[1]) or {}
            local uid = real_data.uid
            if uid then
                local real_data_price = real_data.price
                local hot_num
                local rand_num
                local unlock_num = 0
                if real_data_price > 0 then
                    hot_num = my_redis:hincrby(mm_redis_key,"hot", 1)
                    --hot_num = utils.img_random()
                    unlock_num = my_redis:hget(mm_redis_key,"unlock_num")
                    unlock_num = tonumber(unlock_num) or 0
                else
                    rand_num = utils.fb_random(3)
                    if rand_num == last_rand_num then
                        rand_num = 1
                    end
                    hot_num = my_redis:hincrby(mm_redis_key,"hot", rand_num)
                    last_rand_num = rand_num
                end
                local base_info_tmp
                if base_info_tmp_all[uid] then
                    base_info_tmp = base_info_tmp_all[uid]
                else
                    base_info_tmp = my_redis:hget(config.redis_key.user_prefix .. uid, "base_info")
                    base_info_tmp_all[uid] = base_info_tmp
                end

                if not utils.is_redis_null(base_info_tmp) then
                    local base_info = json.decode(base_info_tmp)
                    if myuid and myuid ~= uid then
                        local is_my_fans = my_redis:zscore(config.redis_key.follow_me_prefix .. uid, myuid)
                        if not utils.is_redis_null(is_my_fans) then
                            if_weather_follow = 1
                        end
                        if is_vip == 0 and myuid ~= uid and real_data_price > 0 then
                            local is_payed = my_redis:hexists(mm_redis_key, config.redis_key.moments_pay_uid_key .. myuid)
                            if is_payed == 1 then
                                is_unlock = 1
                            end
                        end

                        if not all_pvips[uid] then
                            is_pvip = my_redis:exists(config.redis_key.vip_user_key..uid)
                            all_pvips[uid] = is_pvip
                        else
                            is_pvip = all_pvips[uid]
                        end
                    elseif myuid == uid then
                        is_pvip = is_vip
                    end
                    local tags = json.decode(real_data_tmp[2]) or {}
                    local one
                    --1:img-list 2:video
                    if real_data.add_type == 1 then
                        one = {
                            uid = uid,
                            username = base_info.username,
                            avatar = base_info.avatar,
                            icare = if_weather_follow,
                            super = base_info.super or 0,
                            id = tonumber(v.mm_id),
                            time_stamp = real_data.time_stamp,
                            add_type = 1,
                            img_urls = real_data.img_urls,
                            base_url = real_data.base_url,
                            price = real_data_price,
                            position = real_data.position,
                            mm_from = real_data.mm_from or 0,
                            desc = real_data.desc,
                            hot_num = hot_num,
                            unlock_num = unlock_num,
                            unlock = is_unlock,
                            h5_url = "moments/share/",
                            pvip = is_pvip,
                            tags = tags,
                        }
                    else
                        one = {
                            uid = uid,
                            username = base_info.username,
                            avatar = base_info.avatar,
                            icare = if_weather_follow,
                            super = base_info.super or 0,
                            id = tonumber(v.mm_id),
                            time_stamp = real_data.time_stamp,
                            add_type = 2,
                            video_url = real_data.video_url,
                            base_url = real_data.base_url,
                            video_cover = real_data.video_cover,
                            video_width = real_data.video_width,
                            video_height = real_data.video_height,
                            price = real_data_price,
                            position = real_data.position,
                            mm_from = real_data.mm_from or 0,
                            desc = real_data.desc,
                            hot_num = hot_num,
                            unlock_num = unlock_num,
                            unlock = is_unlock,
                            h5_url = "moments/share/",
                            pvip = is_pvip,
                            tags = tags,
                        }
                    end

                    mms_model:merge_mm_info(one, myuid)

                    tinsert(ok_info, one)
                    ok_num = ok_num + 1
                end
            end
        end
    end
    if ok_num == 0  then
        ngx.print('{"ret":40}')
        exit(200)
    end
    local dat = {
        list  = ok_info,
        vip = is_vip
    }
    local aes_dat = utils.encrypt(dat, req.query.aes)
    re["ret"] = 0
    re["dat"] = aes_dat
    res:json(re)
    exit(200)
end

return user6_router
