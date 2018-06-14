local user1_router = {}
local redis = require("app2.lib.redis")
local config = require("app2.config.config")
local my_redis = redis:new()
local mysql = require("app2.model.user")
local mysql_video = require("app2.model.video")
local ngx = ngx
local md5 = ngx.md5
local exit = ngx.exit
local sleep = ngx.sleep
local utils = require("app2.lib.utils")
local json = require("cjson.safe")
local turn = require("app2.model.turn")
local table_object  = json.encode_empty_table_as_object

local tinsert = table.insert
local tconcat = table.concat
local tsort = table.sort
local tonumber = tonumber
local tostring = tostring
local match = string.match
local pairs = pairs
local ipairs = ipairs
local gsub = string.gsub
local io = io
local string = string
local STATE_OFFLINE = 0
local STATE_ONLINE_GENERAL = 1
local STATE_ONLINE_OK = 2
local STATE_ONLINE_BUSY = 3
local STATE_ONLINE_PAUSE = 4
local shared_cache = ngx.shared.fresh_token_limit

local function access_limit(res, key, limit_num, limit_time)
    local time = limit_time or 60
    local num = limit_num or 0
    local key = 'v3_'..key
    local limit_v = shared_cache:get(key)
    if not limit_v then
        shared_cache:set(key, 1, time)
    else
        if limit_v > num then
            --res:status(400):json({})
            ngx.print('{"ret":3}')
            exit(200)
        end
        shared_cache:incr(key, 1)
    end
end

user1_router.repair = function(req, res, next)
    --local all_users,err = mysql:get_all_user()
    local all_uids = my_redis:smembers(config.redis_key.all_anchors_uid)
    for _,uid in pairs(all_uids) do
            local other_info_tmp = my_redis:hget(config.redis_key.user_prefix .. uid,"other_info")
            local other_info = json.decode(other_info_tmp)
            --res:json(other_info)
            local pp = tonumber(other_info.price) or 0
            my_redis:hset(config.redis_key.user_prefix .. uid, "price", pp)
            ngx.say("uid:"..uid .. " price:"..pp)
    end
    ngx.say("all done")
end

-- 
user1_router.get_config = function(req, res, next)
    local config_data = config.server_config
    config_data.iceServers[1].username = req.params.uid
    config_data.iceServers[1].credential = req.params.token
    local aes_dat = utils.encrypt(config_data, req.query.aes)
    local data = {
        ret = 0,
        dat = aes_dat
    }
    res:json(data)
    exit(200)
end

-- 刷新token  一分钟一个client_id最多一次
user1_router.refresh_token = function(req, res, next)
    local re = {}
    local access_token = req.params.token
    local fresh_token = req.query.refreshToken
    local client_id = req.query.clientID
    utils.check_para(fresh_token)
    utils.check_para(client_id)
    access_limit(res, client_id)
    -- 如果token 没有过期  则不用走mysql
    local cache_fresh_token = my_redis:hget(config.redis_key.token_prefix .. access_token, config.redis_key.token_fresh_token_key)
    local uid
    if cache_fresh_token == "1" then
        ngx.print('{"ret":3004}')
        exit(200)
    elseif utils.is_redis_null(cache_fresh_token) then
        local result, _ = mysql:query_fresh_token(access_token, fresh_token)
        if not result or utils.is_table_empty(result[1]) or not result[1].id then
            ngx.print('{"ret":3003}')
            exit(200)
        end
        uid = result[1].id
    else
        if fresh_token ~= cache_fresh_token then
            ngx.print('{"ret":3004}')
            exit(200)
        end
        uid = my_redis:hget(config.redis_key.token_prefix .. access_token, config.redis_key.token_uid_key)
    end
    sleep(0.1)
    ngx.update_time()
    local now_time = ngx.now() * 1000
    local token_raw = now_time .. utils.random()
    local new_token = md5(token_raw)..now_time
    local new_fresh_token = md5(token_raw..'wcd').. utils.random()
    
    local token_expires = ngx.time() + config.token_ttl
    local re, _ = mysql:update_access_token(new_token, new_fresh_token, token_expires, uid)
    if re and re.affected_rows > 0 then
        my_redis:del(config.redis_key.token_prefix .. access_token)
        my_redis:hmset(
            config.redis_key.token_prefix .. new_token,
            config.redis_key.token_uid_key,
            uid,
            config.redis_key.token_fresh_token_key,
            new_fresh_token
        )
        my_redis:expire(config.redis_key.token_prefix .. new_token, config.token_ttl)
        -- update turn mysql token

        local turn_token = ngx.md5(uid..':'..config.turn_domain..':'..new_token)
        turn:update_turn_user(tostring(uid),turn_token)
    end
    local dat = {
            accessToken = new_token,
            refreshToken = new_fresh_token,
            tokenExpires = token_expires,
            tokenTTL = config.token_ttl
    }
    local aes_dat = utils.encrypt(dat, req.query.aes)
    local data = {
        ret = 0,
        dat = aes_dat
    }
    res:json(data)
    exit(200)
end

user1_router.get_tags = function(req, res, next)
    local tags_redis_key = "tags:tags_config"
    local tags_info = my_redis:get(tags_redis_key)
    if utils.is_redis_null(tags_info) then
        tags_info = mysql:get_tags()
        local ok_tags = {}
        for _, v in ipairs(tags_info) do
            tinsert(ok_tags, v.name)
        end
        my_redis:set(tags_redis_key, json.encode(ok_tags))
        res:json(
            {
                ret = 0,
                dat = ok_tags
            }
        )
        exit(200)
    else
        local ok_tags_info = json.decode(tags_info)
        res:json(
            {
                ret = 0,
                dat = ok_tags_info
            }
        )
        exit(200)
    end
end

-- 成为主播
user1_router.update_anchor = function(req, res, next)
    local re = {}
    local raw_post_data = req.body
    if not raw_post_data or raw_post_data == "" then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local uid = req.params.uid
    local raw_post_data = utils.decrypt(raw_post_data, req.query.aes)
    local post_data = json.decode(raw_post_data)
    if not post_data then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local cover_url = post_data["cover"] or ""
    local video_url = post_data["video"] or ""
    local vinfo = post_data["vinfo"] or ""
    if cover_url == "" or video_url == "" or vinfo == "" then
        ngx.print('{"ret":3}')
        exit(200)
    end

    local have_num = my_redis:hlen(config.redis_key.video_prefix .. uid)
    local old_cover_id = my_redis:hget(config.redis_key.video_prefix .. uid, "iscover")
    local have_cover = true
    local top_num = 6
    if utils.is_redis_null(old_cover_id) then
        have_cover = false
        top_num = 5
    end

    if have_num >= top_num then
        ngx.print('{"ret":11}')
        exit(200)
    end
    
    local telents
    if not post_data["telents"] or post_data["telents"] == "" or utils.is_table_empty(post_data["telents"]) then
        telents = {}
    else
        telents = post_data["telents"]
    end
    local tags
    if not post_data["tags"] or post_data["tags"] == "" or utils.is_table_empty(post_data["tags"])   then
        tags = {}
    else
        tags = post_data["tags"]
    end
    local vinfo_json = json.encode(vinfo)
    local telents_json = json.encode(telents)
    local tags_json = json.encode(tags)
    
    local zhubo = 1
    local mysql_re, _ = mysql:update_user(uid, zhubo, telents_json, tags_json)
    -- save anchor video,skill,tags info
    local base_info_tmp = my_redis:hget(config.redis_key.user_prefix .. uid, "base_info")
    local my_base_info = json.decode(base_info_tmp) or {}
    local gender = tonumber(my_base_info.gender)
    local default_price = config.default_price
    if gender == 2 then
        default_price = config.default_girl_price
    end
    local other_info = {
        tags = tags,
        telents = telents,
        brief = "",
        price = default_price,
    }
    table_object(false)
    my_redis:hmset(config.redis_key.user_prefix .. uid, "other_info",json.encode(other_info),"price",default_price)
    my_redis:sadd(config.redis_key.all_anchors_uid, uid)
    local shared_cache_data = my_redis:smembers(config.redis_key.all_anchors_uid)
    shared_cache:set(config.redis_key.shared_cache_anchor_uids,tconcat(shared_cache_data,","))
    -- replace aws s3 preupload url  to cdn
    video_url = gsub(video_url,config.upload.aws_preupload_url,config.upload.resource_url)

    local video_info = {
        video = video_url,
        cover = cover_url,
        vinfo = vinfo
    }
    local video_re = mysql_video:insert_video(uid, video_url, cover_url, vinfo_json, 1)
    if video_re and video_re.insert_id then
        my_redis:hset(config.redis_key.video_prefix .. uid, video_re.insert_id, json.encode(video_info))
        if not have_cover then
            my_redis:hset(config.redis_key.video_prefix .. uid, 'iscover', video_re.insert_id)
        end
        -- sync act compress video
        local need_cron_data = {
                act = 'compress_video',
                uid = uid,
                data = {
                    video_id = video_re.insert_id
                }
        }
        my_redis:rpush(config.redis_key.cron_list_key, json.encode(need_cron_data))
        ngx.print('{"ret":0}')
        exit(200)
    end
    ngx.print('{"ret":5}')
    exit(200)
end

user1_router.get_anchor = function(req, res, next)
    local id = req.params.uid
    local re = {}
    if not id or id == "" then
        ngx.print('{"ret":3}')
        exit(200)
    end
    -- 从redis取
    local all_info = my_redis:hmget(config.redis_key.user_prefix .. id, "state", "base_info")
    if utils.is_redis_null_table(all_info) then
        ngx.print('{"ret":6000}')
        exit(200)
    end

    local video_cover_id = my_redis:hget(config.redis_key.video_prefix .. id, "iscover")
    local video_info = {}
    if not utils.is_redis_null(video_cover_id) then
        local video_info_tmp = my_redis:hget(config.redis_key.video_prefix .. id, video_cover_id)
        video_info = json.decode(video_info_tmp) or {}
    end
    

    local state = all_info[1]
    if utils.is_redis_null(state) then
        state = STATE_ONLINE_GENERAL
    end
    local base_info = all_info[2]
    local base_info = json.decode(base_info) or {}
    local data = {
        state = tonumber(state),
        uid = id,
        username = base_info["username"],
        avatar = base_info["avatar"],
        cover = video_info["cover"],
        video = video_info["video"],
        compress_video = video_info["compress_video"] or "",
        vinfo = video_info["vinfo"],
        telents = {},
        tags = {}
    }
    local aes_dat = utils.encrypt(data, req.query.aes)
    re["ret"] = 0
    re["dat"] = aes_dat
    res:json(re)
    exit(200)
end

-- 获取所有主播列表
user1_router.get_allanchors = function(req, res, next)
    local raw_post_data = req.body
    utils.check_para(raw_post_data)
    local raw_post_data = utils.decrypt(raw_post_data, req.query.aes)
    local post_data = json.decode(raw_post_data)
    if utils.is_table_empty(post_data) then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local uniq_id = post_data["uniq"]
    utils.check_para(uniq_id)
    local shared_cache_data = shared_cache:get(config.redis_key.shared_cache_anchor_uids)
    local all_uids
    if not shared_cache_data then
        all_uids = my_redis:smembers(config.redis_key.all_anchors_uid)
        if all_uids then
        shared_cache:set(config.redis_key.shared_cache_anchor_uids,tconcat(all_uids,","))
        end
    else
        all_uids = utils.string_split(shared_cache_data,",")
    end
    local re = {}
    if utils.is_redis_null(all_uids) then
        re["ret"] = 0
        local dat = {
            currPage = 1,
            nextPage = 0,
            list = {}
        }
        local aes_dat = utils.encrypt(dat, req.query.aes)
        re["dat"] = aes_dat
        res:json(re)
        exit(200)
    end
    local  myuid = nil
    if req.params.uid then
        myuid = req.params.uid
    end
    local all_re = {}
    local order_one,order_two,order_three = {},{},{}
    local all_num = 1
    for _,uid in ipairs(all_uids) do
        local if_weather_follow = 0
        local state_info = my_redis:hget(config.redis_key.user_prefix .. uid, "state")
        if not utils.is_redis_null(state_info) then
            local state = tonumber(state_info)
            if  state == STATE_ONLINE_OK or state == STATE_ONLINE_BUSY or state == STATE_ONLINE_PAUSE  then
                local str = my_redis:get(config.redis_key.block_user_key .. uid)
                if utils.is_redis_null(str) then
                    local all_info = my_redis:hmget(config.redis_key.user_prefix .. uid, "base_info", "price")
                    local base_info = all_info[1]
                    local price = tonumber(all_info[2]) or 0
                    local base_info = json.decode(base_info) or {}
                    if myuid then
                        local is_my_fans = my_redis:zscore(config.redis_key.follow_me_prefix .. uid, myuid)
                        if not utils.is_redis_null(is_my_fans) then
                            if_weather_follow = 1
                        end
                    end
                    local iscover_id = my_redis:hget(config.redis_key.video_prefix .. uid, 'iscover')
                    local tmp_video_info = my_redis:hget(config.redis_key.video_prefix .. uid, iscover_id)
                    local video_info = json.decode(tmp_video_info) or {}
                    local one_info = {
                        state = state,
                        uid = uid,
                        username = base_info['username'],
                        avatar = base_info['avatar'],
                        cover = video_info["cover"],
                        video = video_info["video"],
                        compress_video = video_info["compress_video"] or "",
                        vinfo = video_info["vinfo"],
                        telents = {},
                        tags = {},
                        icare = if_weather_follow,
                        price = price,
                        super = base_info["super"] or 0
                    }
                    tinsert(all_re,one_info)
                    if state == STATE_ONLINE_OK then
                        tinsert(order_one,all_num)
                    elseif state == STATE_ONLINE_BUSY then
                        tinsert(order_two,all_num)
                    elseif state == STATE_ONLINE_PAUSE then
                        tinsert(order_three,all_num)
                    end
                    all_num = all_num + 1
                    if all_num >= 100 then
                        break
                    end
                end
            end
        end
    end

    local ok_order = {}
    for _,key in ipairs(order_one) do
        tinsert(ok_order,all_re[key])
    end
    for _,key in ipairs(order_two) do
        tinsert(ok_order,all_re[key])
    end
    for _,key in ipairs(order_three) do
        tinsert(ok_order,all_re[key])
    end
    local dat =  {
            currPage = 1,
            nextPage = 0,
            list = ok_order
        }
    local aes_dat = utils.encrypt(dat, req.query.aes)
    local ok_re = {
        ret =  0,
        dat = aes_dat
    }
    res:json(ok_re)
    exit(200)
end

user1_router.get_myanchors = function(req, res, next)
    local myuid = req.params.uid
    local re = {}
    local raw_data = my_redis:hgetall(config.redis_key.user_prefix .. myuid)
   if utils.is_redis_null(raw_data) then
        ngx.print('{"ret":3}')
        ngx.exit(200)
    end
   --  思路：通过正则匹配 次序 o 主播 a 当前代码，严格依赖于redis hgetall 返回的数据以下结构
   --[[
       key1
       value1
       key2
       value2
       ...
       key,value成对出现
   ]]
   local one_tmp = {}
   local two_tmp = {}
   local raw_data_len = #raw_data 
   for i=1,raw_data_len,2 do
        local anchor_key = match(raw_data[i], "^a:(%d+)")
        local order_key = match(raw_data[i], "^o:(%d+)")
        
        if anchor_key then
            one_tmp[anchor_key] = {}
            one_tmp[anchor_key]['anchor'] = raw_data[i+1]
        end
        if order_key then
            two_tmp[order_key] = {}
            two_tmp[order_key]['order'] = raw_data[i+1]   
        end
        anchor_key = nil
        order_key = nil
   end
   local ok = {}
   for uid,v in pairs(one_tmp) do
        local ttt = json.decode(v.anchor) or {}
        local my_anchor_info = my_redis:hget(config.redis_key.user_prefix .. uid, 'state')
        local iscover_id = my_redis:hget(config.redis_key.video_prefix .. uid, 'iscover')
        local tmp_video_info = my_redis:hget(config.redis_key.video_prefix .. uid, iscover_id)
        local video_info = json.decode(tmp_video_info) or {}
        tinsert(ok,{
            order = two_tmp[uid].order,
            state = tonumber(my_anchor_info),
            uid = ttt['uid'],
            username = ttt['username'],
            avatar = ttt['avatar'],
            cover = video_info['cover'],
            compress_video = video_info["compress_video"] or "",
            video = video_info['video'],
            vinfo = video_info['vinfo'],
            telents  = {},
            tags = {},
        })
    end
    local dat = {
            currPage = 1,
            nextPage = 0,
            list = ok
    }
    local aes_dat = utils.encrypt(dat, req.query.aes)
    res:json({
        ret = 0,
        dat = aes_dat
    })
    exit(200)
end

user1_router.get_audiences = function(req, res, next)
    local myuid = req.params.uid
    local re = {}
    local raw_data = my_redis:hgetall(config.redis_key.user_prefix .. myuid)
    if utils.is_redis_null(raw_data) then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local raw_data_len = #raw_data 
    local all_looker = {}
    for i=1,raw_data_len,2 do
            local looker_key = match(raw_data[i], "^u:(%d+)")
            if looker_key then
                tinsert(all_looker,json.decode(raw_data[i+1]))
            end
            looker_key = nil
    end
    tsort(all_looker,function(a,b)
        if a.time <= b.time then
            return true
        end
    end)
    local dat = {
        list = all_looker
    }
    local aes_dat = utils.encrypt(dat, req.query.aes)
    res:json({
        ret = 0,
        dat = aes_dat
    })
    exit(200)    
end

return user1_router