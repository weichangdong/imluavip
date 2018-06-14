local user5_router = {}
local redis = require("app2.lib.redis")
local config = require("app2.config.config")
local my_redis = redis:new()
local mysql = require("app2.model.user")
local mysql_user_extend = require("app2.model.user_extend")
local mysql_money = require("app2.model.money")
local mms_model = require("app2.model.mms")
local mm_tag_model = require("app2.model.mm_tag")
local ngx = ngx
local md5 = ngx.md5
local exit = ngx.exit
local sleep = ngx.sleep
local pcall = pcall
local iopopen = io.popen
local utils = require("app2.lib.utils")
local json = require("cjson.safe")
local table_object  = json.encode_empty_table_as_object

local tinsert = table.insert
local tsort = table.sort
local tonumber = tonumber
local tostring = tostring
local match = string.match
local ngxmatch = ngx.re.match
local slen = string.len
local pairs = pairs
local ipairs = ipairs
local io = io
local string = string
local ngx_quote_sql_str = ngx.quote_sql_str
local shared_cache = ngx.shared.fresh_token_limit
local moments_list_limit_num = 20
local LOG_FROM_MOMENT_PAY = 8
local LOG_FROM_ONE2ONE_PAY = 9

local function access_limit(res, key, limit_num, limit_time)
    local time = limit_time or 60
    local num = limit_num or 0
    local key = 'user5_'..key
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

user5_router.price_list = function(req, res, next)
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
    local free_data_img = {yes = {0}, no = {5,25}}
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

user5_router.letsgo_mm_list = function(req, res, next)
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
    utils.check_para(post_data.time_stamp)
    local time_stamp = tonumber(post_data.time_stamp)
    if not time_stamp or time_stamp < 0 then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local id = post_data.id
    utils.check_para(id)

    local need_so = post_data.so or 0
    local gender = post_data.gender or 0
    local add_type = post_data.add_type or 0
    local pay = post_data.pay or 0

    local updown = post_data.updown
    local all_ids = {}
    local ok_info = {}
    if need_so == 0 then
        if time_stamp == 0 then
            all_ids = my_redis:zrevrangebyscore(config.redis_key.moments_prefix_zset_key,"+inf",0,"limit",0,moments_list_limit_num)
            if utils.is_redis_null_table(all_ids) then
                ngx.print('{"ret":35}')
                exit(200)
            end
        --1=down向下刷新，就是下拉 获取最新数据
        elseif updown == 1 then
            local rank = my_redis:zrevrank(config.redis_key.moments_prefix_zset_key,id)
            if rank == 0 then
                ngx.print('{"ret":36}')
                exit(200)
            else
                all_ids = my_redis:zrevrangebyscore(config.redis_key.moments_prefix_zset_key,"+inf",0,"limit",0,moments_list_limit_num)
            end
        --2=up 向上滑动 获取旧的数据
        elseif updown == 2 then
            all_ids = my_redis:zrevrangebyscore(config.redis_key.moments_prefix_zset_key,time_stamp - 1,"-inf","limit",0,moments_list_limit_num)
            if utils.is_redis_null_table(all_ids) then
                ngx.print('{"ret":37}')
                exit(200)
            end
        else
            ngx.print('{"ret":3}')
            exit(200)
        end
else
    utils.check_num_value(add_type)
    utils.check_num_value(pay)
    utils.check_num_value(gender)
    local add_type_so,pay_so,gender_so = nil,nil,nil
    if add_type ~= 0 then
        add_type_so = add_type
    end
    if pay ~= 0 then
        pay_so = pay
    end
    if gender ~= 0 then
        gender_so = gender
    end
    if time_stamp == 0 then
        local all_ids_info = mm_tag_model:get_mm_ids_by_where(add_type_so,pay_so,gender_so,moments_list_limit_num,nil,nil)
        if utils.is_table_empty(all_ids_info) then
            ngx.print('{"ret":35}')
            exit(200)
        end
        for _,v  in pairs(all_ids_info) do
            tinsert(all_ids,v.id)
        end
    elseif updown == 1 then
        local rank_tmp = mm_tag_model:get_mm_ids_by_where(add_type_so,pay_so,gender_so,1,nil,nil)
        if not rank_tmp  then
            ngx.print('{"ret":36}')
            exit(200)
        elseif rank_tmp[1] and tonumber(rank_tmp[1].id) == id then
            ngx.print('{"ret":36}')
            exit(200)
        else
            local all_ids_info = mm_tag_model:get_mm_ids_by_where(add_type_so,pay_so,gender_so,moments_list_limit_num,nil,nil)
            if utils.is_table_empty(all_ids_info) then
                ngx.print('{"ret":36}')
                exit(200)
            end
            for _,v  in pairs(all_ids_info) do
                tinsert(all_ids,v.id)
            end
        end
    elseif updown == 2 then
        local all_ids_info = mm_tag_model:get_mm_ids_by_where(add_type_so,pay_so,gender_so,moments_list_limit_num,nil,id)
        if utils.is_table_empty(all_ids_info) then
            ngx.print('{"ret":37}')
            exit(200)
        end
        for _,v  in pairs(all_ids_info) do
            tinsert(all_ids,v.id)
        end
    else
        ngx.print('{"ret":3}')
        exit(200)
    end
end
    local is_vip = 0
    if myuid then
        is_vip = my_redis:exists(config.redis_key.vip_user_key..myuid)
    end
    local last_rand_num = 2
    local is_pvip = 0
    local all_pvips = {}
    local base_info_tmp_all = {}
    for _,v in ipairs(all_ids) do
        local if_weather_follow = 0
        local is_unlock = 0
        local mm_redis_key = config.redis_key.moments_prefix_hash_key..v
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
                        if is_vip == 0 and real_data_price > 0 then
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
                            id = tonumber(v),
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
                            id = tonumber(v),
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
                end
            end
        end
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

user5_router.letsgo_mm_pay = function(req, res, next)
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
    local time_stamp = tonumber(post_data.time_stamp)
    utils.check_para(time_stamp)
    local one2one = post_data["one2one"] or 0
    if one2one ~= 0 and one2one ~= 1 then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local mm_redis_key,log_from_type
    if one2one == 0 then
        mm_redis_key = config.redis_key.moments_prefix_hash_key..id
        log_from_type = LOG_FROM_MOMENT_PAY
    else
        mm_redis_key = config.redis_key.one2one_prefix_hash_key..id
        log_from_type = LOG_FROM_ONE2ONE_PAY
    end
    local real_data_tmp = my_redis:hget(mm_redis_key,"data")
    if utils.is_redis_null(real_data_tmp) then
        ngx.print('{"ret":41}')
        exit(200)
    end
    local real_data = json.decode(real_data_tmp) or {}
    local real_data_price = real_data.price
    if real_data_price == 0 then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local uid = real_data.uid
    if uid == myuid then
        ngx.print('{"ret":3}')
        exit(200)
    end
    -- vip need not to pay
    if one2one == 0 then
        local is_vip = my_redis:exists(config.redis_key.vip_user_key..myuid)
        if is_vip == 1 then
            ngx.print('{"ret":43}')
            exit(200)
        end
    end
    -- do not check if  payed
    local is_payed = my_redis:hexists(mm_redis_key, config.redis_key.moments_pay_uid_key .. myuid)
    if is_payed == 1 then
        ngx.print('{"ret":43}')
        exit(200)
    end

    local log_time = ngx.time()
    local logger = require("app2.lib.logger")
    logger.close()
    logger.new(config.save_log.important_log_file)

    mysql_money:transaction_start()
    -- do deduce credit
    local update1_re, select1_re = mysql_user_extend:update_user_credit_moments(myuid, -real_data_price)
    if update1_re and update1_re.affected_rows == 0 then
        mysql_money:transaction_rollback()
        local log_voucher_info = "[moments pay error not enough] cost-credit-uid:"..myuid.. " credit:-" ..real_data_price.." mm-id:"..id.." have-num:"..select1_re[1].credit
        logger.info(log_voucher_info)
        local dat = {
            credit = select1_re[1].credit or 0,
            code = 38,
        }
        local aes_dat = utils.encrypt(dat, req.query.aes)
        re["ret"] = 0
        re["dat"] = aes_dat
        res:json(re)
        exit(200)
    elseif update1_re and update1_re.affected_rows == 1 and select1_re and select1_re[1].credit  then
        -- do add coin
        update2_re, select2_re = mysql_user_extend:update_user_coin(uid, real_data_price)
        if update2_re.affected_rows == 1 and select2_re[1].coin  then
            mysql_money:transaction_commit()
            local ok = my_redis:hset(mm_redis_key,config.redis_key.moments_pay_uid_key .. myuid, log_time)
            rand_unlock_num =  utils.custom_random(1,7)
            my_redis:hincrby(mm_redis_key,"unlock_num", rand_unlock_num)
            --reduce credit
            mysql_money:insert_credit_log(myuid, log_from_type, id, -real_data_price, log_time)
            -- add coin
            mysql_money:insert_coin_log(uid, log_from_type, id, real_data_price, log_time)
            mysql_user_extend:update_user_total_income(uid, real_data_price)
            -- sync act moments pay
            local need_cron_data = {
                    act = 'moments_pay',
                    uid = myuid,
                    data = {
                        mm_uid = uid,
                        mm_id = id,
                        mm_pricce = real_data_price,
                        log_time = log_time,
                    }
            }
            my_redis:rpush(config.redis_key.cron_list_key, json.encode(need_cron_data))
            -- send push msg to uid
            local tmp_base_info = my_redis:hget(config.redis_key.user_prefix .. myuid, "base_info")
            local base_info = json.decode(tmp_base_info) or {}
            local username = base_info["username"]

            local fcm_son_data = {
                    type = "im",
                    title = "pay moment",
                    alert = username .." like your sercet moment,pay and unlock it,you can check it on charging record:)",
                    accessory = {
                            mime = "image/png",
                            url = "png",
                    },
                    to = uid,
                    from = {
                            uid = myuid,
                            uniq = base_info["uniq"],
                            super = base_info["super"] or 0,
                            username = username,
                            avatar = base_info["avatar"],
                    },
                    msgid = myuid ..':'..one2one..log_time * 1000,
                    time = log_time,
                    level = "system",
            }
            local fcm_data = {
                uid = uid,
                class = "unlock",
                time = log_time,
                data = json.encode(fcm_son_data)
            }
            my_redis:lpush(config.redis_key.fcm_redis_key, json.encode(fcm_data))
            ngx.print('{"ret":0}')
            exit(200)
        else
            mysql_money:transaction_rollback()
            local log_voucher_info = "[moments pay error-1 ] one2one:"..one2one.." add-coin-uid:"..uid.. " coin:" ..real_data_price.." mm-id:"..id
            logger.info(log_voucher_info)
            ngx.print('{"ret":39}')
            exit(200)
        end
    else
        mysql_money:transaction_rollback()
        local log_voucher_info = "[moments pay error-2 ] one2one:"..one2one.." add-coin-uid:"..uid.. " coin:" ..real_data_price.." mm-id:"..id
        logger.info(log_voucher_info)
        ngx.print('{"ret":39}')
        exit(200)
    end

end

user5_router.letsgo_add_video = function(req,res,next)
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
    local video_url = post_data["video_url"]
    utils.check_para(video_url)
    local one2one = post_data["one2one"] or 0
    if one2one ~= 0 and one2one ~= 1 then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local price = post_data["price"]
    utils.check_para(price)
    price = tonumber(price)
    --its possible moments and one2one have different config 
    if one2one == 0 then
        if not utils.weather_in_array(price, {0,15,30,75}) then
            ngx.print('{"ret":3}')
            exit(200)
        end
        if not post_data["position"] then
            ngx.print('{"ret":3}')
            exit(200)
        end
        local position = post_data["position"] or ""
        if utils.utf8len(position) > 50 then
            ngx.print('{"ret":3}')
            exit(200)
        end
    else
        if not utils.weather_in_array(price, {0,15,30,75}) then
            ngx.print('{"ret":3}')
            exit(200)
        end
        if post_data["position"] then
            ngx.print('{"ret":3}')
            exit(200)
        end
    end
    
    if not post_data["desc"] then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local desc = post_data["desc"] or ""
    if utils.utf8len(desc) > 150 then
        ngx.print('{"ret":3}')
        exit(200)
    end
    --tags
    local  tags = {}
    local tags_num = 0
    if post_data["tags"] and post_data["tags"][1] and post_data["tags"][1].id then
        local tags_data = post_data["tags"]
        for k,v in pairs(tags_data) do
            if k > 10 then
                ngx.print('{"ret":3}')
                exit(200)
            end
            local tid = v.id
            local tname = v.name
            local order = v.order
            if utils.utf8len(tname) < 1 or utils.utf8len(tname) > 10 or not ngxmatch(tname,"^[0-9a-zA-Z]*$","jo") then
                ngx.print('{"ret":3}')
                exit(200)
            end
            tags[k] = {
                tid = tonumber(tid),
                tname = tname,
                order = order,
            }
            tags_num = k
        end
    end

    local queue_type = "moments_video"
    if one2one == 1 then
        queue_type = "one2one_video"
    end
    local queue_data = {
            queue_type = queue_type,
            uid = myuid,
            price = price,
            position = post_data["position"] or "",
            desc = desc,
            video_url = video_url,
            retry_times = 0,
            mm_from = post_data["mm_from"] or 0,
            tags = tags,
            tags_num = tags_num,
    }
    my_redis:lpush(config.redis_key.queue_list_key, json.encode(queue_data))
    ngx.print('{"ret":0}')
    exit(200)
end

user5_router.letsgo_mm_del = function(req, res, next)
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
    local time_stamp = tonumber(post_data.time_stamp)
    utils.check_para(time_stamp)

    local mm_redis_key = config.redis_key.moments_prefix_hash_key..id
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
    --[[
    local del_time_stamp = tonumber(my_redis:zscore(config.redis_key.moments_prefix_zset_key,id))
    if del_time_stamp ~= time_stamp then
        ngx.print('{"ret":3}')
        exit(200)
    end
    ]]
    -- del zset ids
    my_redis:zrem(config.redis_key.moments_prefix_zset_key, id)
    -- del the real data
    my_redis:del(mm_redis_key)
    -- del users data
    my_redis:zrem(config.redis_key.moments_myids_key..myuid, id)
    -- del isgood list
    my_redis:zrem(config.redis_key.moments_isgood_zset_key, id)
    --[[201711211707
        虽然这种方式,会快一点,但是逻辑有点多 by wcd 2017-11-21 edit
    local time_stamp_tmp = my_redis:hmget(config.redis_key.moments_max_min_timestamp_key,"max","min")
    local max_time_stamp = tonumber(time_stamp_tmp[1])
    local min_time_stamp = tonumber(time_stamp_tmp[2])
    if del_time_stamp > max_time_stamp  then
       local tmp = my_redis:zrevrangebyscore(config.redis_key.moments_prefix_zset_key,"+inf",0,"limit",0,1,"WITHSCORES")
        local new_max = tmp[2]
        my_redis:hset(config.redis_key.moments_max_min_timestamp_key,"max", new_max)
    elseif del_time_stamp < min_time_stamp then
        local tmp = my_redis:zrangebyscore(config.redis_key.moments_prefix_zset_key,0,"+inf","limit",0,1,"WITHSCORES")
        local new_min = tmp[2]
        my_redis:hset(config.redis_key.moments_max_min_timestamp_key,"min", new_min)
    end
    --]]
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

user5_router.letsgo_get_mylist = function(req, res, next)
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
    local uid = post_data.uid
    utils.check_para(uid)
    local same_uid = false
    if myuid == uid then 
        same_uid  = true
    end
    local time_stamp = tonumber(post_data.time_stamp)
    utils.check_para(time_stamp)
    local my_ids = {}
    if time_stamp == 0 then 
        my_ids = my_redis:zrevrangebyscore(config.redis_key.moments_myids_key..uid,"+inf",0,"limit",0,moments_list_limit_num)
    else
        my_ids = my_redis:zrevrangebyscore(config.redis_key.moments_myids_key..uid,time_stamp-1,"-inf","limit",0,moments_list_limit_num)
    end
    if utils.is_redis_null_table(my_ids) then
            ngx.print('{"ret":40}')
            exit(200)
    end
    local base_info_tmp = my_redis:hget(config.redis_key.user_prefix .. uid, "base_info")
    if utils.is_redis_null(base_info_tmp) then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local base_info = json.decode(base_info_tmp)
    local if_weather_follow = 0
    local is_pvip
    local is_vip = my_redis:exists(config.redis_key.vip_user_key..myuid)
    if not same_uid then
        local is_my_fans = my_redis:zscore(config.redis_key.follow_me_prefix .. uid, myuid)
        if not utils.is_redis_null(is_my_fans) then
            if_weather_follow = 1
        end
        is_pvip = my_redis:exists(config.redis_key.vip_user_key..uid)
    else
        is_pvip = is_vip
    end
    
    
    local base_info_ok = {
        uid = uid,
        username = base_info.username,
        avatar = base_info.avatar,
        icare = if_weather_follow,
        super = base_info.super or 0,
        pvip = is_pvip,
    }
    local ok_info = {}
    for _,v in ipairs(my_ids) do
        local is_unlock = 0
        local mm_redis_key = config.redis_key.moments_prefix_hash_key..v
        local real_data_tmp = my_redis:hmget(mm_redis_key,"data","tags")
        if not utils.is_redis_null(real_data_tmp) and not utils.is_redis_null(real_data_tmp[1]) then
            local real_data = json.decode(real_data_tmp[1]) or {}
            local uid = real_data.uid
            if uid then 
                    
                    local unlock_num,hot_num = 0,0
                    local real_data_price = real_data.price
                    if not same_uid then
                        if is_vip == 0 and real_data_price > 0 then
                            local is_payed = my_redis:hexists(mm_redis_key, config.redis_key.moments_pay_uid_key .. myuid)
                            if is_payed == 1 then
                                is_unlock = 1
                            end
                        end
                    end
                    if real_data_price > 0 then
                        unlock_num = my_redis:hget(mm_redis_key,"unlock_num")
                        unlock_num = tonumber(unlock_num) or 0
                        --hot_num = utils.img_random()
                        hot_num = my_redis:hget(mm_redis_key,"hot")
                    else
                        hot_num = my_redis:hget(mm_redis_key,"hot")   
                    end
                    local tags = json.decode(real_data_tmp[2]) or {}
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
                            position = real_data.position,
                            mm_from = real_data.mm_from or 0,
                            desc = real_data.desc,
                            hot_num = tonumber(hot_num),
                            unlock_num = unlock_num,
                            unlock = is_unlock,
                            h5_url = "moments/share/",
                            tags = tags,
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
                            position = real_data.position,
                            mm_from = real_data.mm_from or 0,
                            desc = real_data.desc,
                            hot_num = tonumber(hot_num),
                            unlock_num = unlock_num,
                            unlock = is_unlock,
                            h5_url = "moments/share/",
                            tags = tags,
                        }
                    end

                    mms_model:merge_mm_info(one, myuid)

                    tinsert(ok_info, one)
            end
        end
    end
    local dat = {
        vip = is_vip,
        list  = ok_info,
        base_info = base_info_ok,
    }
    local aes_dat = utils.encrypt(dat, req.query.aes)
    re["ret"] = 0
    re["dat"] = aes_dat
    res:json(re)
    exit(200)
end

user5_router.letsgo_mm_report = function(req, res, next)
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
    local report_type = post_data.type
    utils.check_para(report_type)
    access_limit(res, "report_"..myuid)
    local log_time = ngx.time()
    local need_cron_data = {
        act = 'moments_report',
        uid = myuid,
        data = {
            mm_id = id,
            report_type = report_type,
            log_time = log_time,
        }
    }
    my_redis:rpush(config.redis_key.cron_list_key, json.encode(need_cron_data))
    ngx.print('{"ret":0}')
    exit(200)
end

user5_router.mm_imperial_sword = function(req, res, next)
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
    local report_type = post_data.type
    utils.check_para(report_type)
    local base_info_tmp = my_redis:hget(config.redis_key.user_prefix .. myuid, "base_info")
    if  utils.is_redis_null(base_info_tmp) then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local base_info = json.decode(base_info_tmp)
    local is_super = base_info.super or 0
    if is_super == 0 then
        ngx.print('{"ret":3}')
        exit(200)
    else
        --1.设置为精选  2.取消精选 3.设置为隐藏 4.删除帖子
        local mm_redis_key = config.redis_key.moments_prefix_hash_key..id
        if report_type == 1 then
            local data_tmp = my_redis:hget(mm_redis_key,"data")
            if utils.is_redis_null(data_tmp) then
                ngx.print('{"ret":3}')
                exit(200)
            end
            ngx.update_time()
            local good_time_stamp = ngx.now() * 1000
            my_redis:hset(mm_redis_key,"good_time",good_time_stamp)
            my_redis:zadd(config.redis_key.moments_isgood_zset_key, good_time_stamp, id)
            -- sync act moments add is_good
            local need_cron_data = {
                act = 'moments_add_isgood',
                uid = myuid,
                data = {
                    mm_id = id,
                }
            }
            my_redis:rpush(config.redis_key.cron_list_key, json.encode(need_cron_data))
        elseif report_type == 2 then
            -- del isgood list
            my_redis:zrem(config.redis_key.moments_isgood_zset_key, id)
            my_redis:hdel(mm_redis_key, "good_time")
            -- sync act moments cancel is_good
            local need_cron_data = {
                    act = 'moments_cancel_isgood',
                    uid = myuid,
                    data = {
                        mm_id = id,
                    }
            }
            my_redis:rpush(config.redis_key.cron_list_key, json.encode(need_cron_data))
        elseif report_type == 3 then
            -- del zset ids
            -- selectedlist
            my_redis:zrem(config.redis_key.moments_isgood_zset_key, id)
            my_redis:hdel(mm_redis_key, "good_time")
            -- moments
            my_redis:zrem(config.redis_key.moments_prefix_zset_key, id)
            -- sync act moments cancel is_good
            local need_cron_data = {
                act = 'moments_cancel_isgood',
                uid = myuid,
                data = {
                    mm_id = id,
                }
            }
            my_redis:rpush(config.redis_key.cron_list_key, json.encode(need_cron_data))
        elseif report_type == 4 then
            local data_tmp = my_redis:hget(mm_redis_key,"data")
            if utils.is_redis_null(data_tmp) then
                ngx.print('{"ret":3}')
                exit(200)
            end
            local real_data = json.decode(data_tmp)
            local owner_uid = real_data.uid
            -- del zset ids
            my_redis:zrem(config.redis_key.moments_prefix_zset_key, id)
            -- del the real data
            my_redis:del(mm_redis_key)
            -- del users data
            my_redis:zrem(config.redis_key.moments_myids_key..owner_uid, id)
            -- del isgood list
            my_redis:zrem(config.redis_key.moments_isgood_zset_key, id)
            local need_cron_data = {
                act = 'moments_del',
                uid = owner_uid,
                data = {
                    mm_id = id,
                }
            }
            my_redis:rpush(config.redis_key.cron_list_key, json.encode(need_cron_data))
        end
        ngx.print('{"ret":0}')
        exit(200)
    end
end

-- 推荐列表 
user5_router.stars_list_config = function(req, res, next)
    local info = my_redis:get(config.redis_key.stars_list_config_key)
    local ok_data
    if utils.is_redis_null(info) then
        ok_data = {}
    else
        ok_data =  json.decode(info)
    end
    local re = {}
    local aes_dat = utils.encrypt(ok_data, req.query.aes)
    re["ret"] = 0
    re["dat"] = aes_dat
    res:json(re)
    exit(200)
end

user5_router.mm_selected_list = function(req, res, next)
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
    utils.check_para(post_data.time_stamp)
    local time_stamp = tonumber(post_data.time_stamp)
    if not time_stamp or time_stamp < 0 then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local id = post_data.id
    utils.check_para(id)
    local updown = post_data.updown
    local all_ids = {}
    local ok_info = {}
    if time_stamp == 0 then
        all_ids = my_redis:zrevrangebyscore(config.redis_key.moments_isgood_zset_key,"+inf",0,"limit",0,moments_list_limit_num)
        if utils.is_redis_null_table(all_ids) then
            ngx.print('{"ret":35}')
            exit(200)
        end
    --1=down向下刷新，就是下拉 获取最新数据
    elseif updown == 1 then
        local rank = my_redis:zrevrank(config.redis_key.moments_isgood_zset_key,id)
        if rank == 0 then
            ngx.print('{"ret":36}')
            exit(200)
        else
            all_ids = my_redis:zrevrangebyscore(config.redis_key.moments_isgood_zset_key,"+inf",0,"limit",0,moments_list_limit_num)
            if utils.is_redis_null_table(all_ids) then
                ngx.print('{"ret":36}')
                exit(200)
            end
        end
    --2=up 向上滑动 获取旧的数据
    elseif updown == 2 then
        all_ids = my_redis:zrevrangebyscore(config.redis_key.moments_isgood_zset_key,time_stamp - 1,"-inf","limit",0,moments_list_limit_num)
        if utils.is_redis_null_table(all_ids) then
            ngx.print('{"ret":37}')
            exit(200)
        end
    else
        ngx.print('{"ret":3}')
        exit(200)
    end
    local is_vip = 0
    if myuid then
        is_vip = my_redis:exists(config.redis_key.vip_user_key..myuid)
    end
    local last_rand_num = 2
    local ok_num = 0
    local is_pvip = 0
    local all_pvips = {}
    local base_info_tmp_all = {}
    for _,v in ipairs(all_ids) do
        local if_weather_follow = 0
        local is_unlock = 0
        local mm_redis_key = config.redis_key.moments_prefix_hash_key..v
        local real_data_tmp = my_redis:hmget(mm_redis_key,"data","good_time","tags")
        if not utils.is_redis_null(real_data_tmp) and not utils.is_redis_null(real_data_tmp[1]) and not utils.is_redis_null(real_data_tmp[2]) then
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
                        if is_vip == 0 and real_data_price > 0 then
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
                    local good_time_stamp = tonumber(real_data_tmp[2])
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
                            time_stamp = good_time_stamp,
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
                            time_stamp = good_time_stamp,
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
        vip = is_vip
    }
    local aes_dat = utils.encrypt(dat, req.query.aes)
    re["ret"] = 0
    re["dat"] = aes_dat
    res:json(re)
    exit(200)
end

user5_router.up_mylevel = function(req, res, next)
    local myuid = req.params.uid
    local raw_post_data = req.body
    utils.check_para(raw_post_data)
    local raw_post_data = utils.decrypt(raw_post_data, 1)
    local post_data = json.decode(raw_post_data)
    if utils.is_table_empty(post_data) then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local up_to_level = post_data.level
    if not  up_to_level or up_to_level == "" then
        ngx.print("up_to_level is needed")
        exit(200)
    end

    local other_info_tmp = my_redis:hget(config.redis_key.user_prefix ..myuid, "other_info")
    if not other_info_tmp then
        ngx.print("this uid has no  other_info")
        exit(200)
    end
    local old_other_info = json.decode(other_info_tmp)
    
    local level_info_tmp = my_redis:hget(config.redis_key.level_config_key, up_to_level)
    if not level_info_tmp then
        ngx.print("this level is  wrong")
        exit(200)
    end
    local  level_info = json.decode(level_info_tmp)
    if not level_info then
        ngx.print("this level is  wrong")
        exit(200)
    end
    local new_credit = level_info.credit
    local now_level = level_info.level
    local update_re, _ = mysql_user_extend:update_user_level(myuid, now_level)
    if update_re.affected_rows == 1 then
        local other_info = {
            tags = old_other_info.tags,
            telents = old_other_info.telents,
            brief = old_other_info.brief,
            price = new_credit
        }
        table_object(false)
        my_redis:hmset(config.redis_key.user_prefix .. myuid, "other_info",json.encode(other_info),"price",new_credit)
        ngx.say("now-level:"..now_level.." now-price:"..new_credit)
    else
       ngx.say("error") 
    end
end

return user5_router
