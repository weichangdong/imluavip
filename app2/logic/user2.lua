local user2_router = {}
local email_code_ttl = 600
local redis = require("app2.lib.redis")
local config = require("app2.config.config")
local my_redis = redis:new()
local mysql = require("app2.model.user")
local mysql_user_extend = require("app2.model.user_extend")
local mysql_video = require("app2.model.video")
local ngx = ngx
local md5 = ngx.md5
local exit = ngx.exit
local sleep = ngx.sleep
local utils = require("app2.lib.utils")
local json = require("cjson.safe")
local turn = require("app2.model.turn")
local send_email = require("app2.lib.email")
local mms_model = require("app2.model.mms")
local table_object  = json.encode_empty_table_as_object

local tinsert = table.insert
local tconcat = table.concat
local tsort = table.sort
local tonumber = tonumber
local tostring = tostring
local match = string.match
local slen = string.len
local gsub = string.gsub
local pairs = pairs
local ipairs = ipairs
local io = io
local string = string
local ngx_quote_sql_str = ngx.quote_sql_str
local shared_cache = ngx.shared.fresh_token_limit
local default_level = 1

local function access_limit(res, key, limit_num, limit_time)
    local time = limit_time or 60
    local num = limit_num or 0
    local key = 'v3_'..key
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

user2_router.login = function(req, res, next)
    local re = {}
    local raw_post_data = req.body
    utils.check_para(raw_post_data)
    local raw_post_data = utils.decrypt(raw_post_data, req.query.aes)
    local post_data = json.decode(raw_post_data)
    if utils.is_table_empty(post_data) then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local email = post_data['email']
    utils.check_para(email)
    local pass = post_data['passwd']
    if not pass or slen(pass) ~= 32 then
        ngx.print('{"ret":3}')
        exit(200)
    end
    if not utils.check_email(email) then
        ngx.print('{"ret":6}')
        exit(200)
    end
    local uniq = post_data['uniq']
    if not uniq or uniq == "" or slen(uniq) ~= 32 then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local country = post_data['country']
    utils.check_para(country)
    local language = post_data['language']
    utils.check_para(language)
    local save_pass = md5(pass..config.redis_key.pass_key)
    local result, _ = mysql:query_by_pass(email, save_pass)
    if utils.is_table_empty(result) or utils.is_table_empty(result[1]) or not result[1].id then
        access_limit(res, email, 4, 3600) --1 hours max 5 times
        ngx.print('{"ret":7}')
        exit(200)
    else
        -- login fresh token start
        local old_info = result[1]
        local uid = tostring(old_info.id)
        access_limit(res, uid, 8, 3600) --1 hours max 9 times
        ---block user start---
        local str = my_redis:get(config.redis_key.block_user_key .. uid)
        if not utils.is_redis_null(str) then
            ngx.print('{"ret":44,"msg":"'..str..'"}')
            exit(200)
        end
        ---block user end---
        sleep(0.1)
        ngx.update_time()
        local now_time = ngx.now() * 1000
        local token_raw = now_time .. utils.random()
        local new_token = md5(token_raw)..now_time
        local new_fresh_token = md5(token_raw..'wcd').. utils.random()
        local token_expires = ngx.time() + config.token_ttl
        local mysqlre, _ = mysql:update_access_token_and_other(new_token, new_fresh_token, token_expires,country,uniq,language, uid)
        if mysqlre.affected_rows > 0 then
            local old_access_token = old_info.accesstoken
            local old_uniq = old_info.uniq
            -- 为了刷新token 不去mysql查询 start1
            my_redis:hdel(config.redis_key.token_prefix .. old_access_token,config.redis_key.token_uid_key)
            my_redis:hset(
                config.redis_key.token_prefix .. old_access_token, config.redis_key.token_fresh_token_key,
                1
            )
            my_redis:expire(config.redis_key.token_prefix .. old_access_token, 1800)
            -- end1
            -- update  base info start2
            if old_uniq ~= uniq then
                local base_info = {
                    username = old_info.username,
                    avatar = old_info.avatar,
                    uniq = uniq,
                    gender = old_info.gender,
                    super = old_info.super
                }
                my_redis:hset(config.redis_key.user_prefix .. uid, "base_info",json.encode(base_info))
            end
            --end2
            my_redis:hmset(
                config.redis_key.token_prefix .. new_token,
                config.redis_key.token_uid_key,
                uid,
                config.redis_key.token_fresh_token_key,
                new_fresh_token
            )
            my_redis:expire(config.redis_key.token_prefix .. new_token, config.token_ttl)
            -- update turn mysql token
            local turn_token = md5(uid..':'..config.turn_domain..':'..new_token)
            turn:update_turn_user(uid,turn_token)
            -- login fresh token end
            re["ret"] = 0
            local dat = {
                    uid = uid,
                    clientID = uniq,
                    accessToken = new_token,
                    refreshToken = new_fresh_token,
                    tokenExpires = token_expires,
                    tokenTTL = config.token_ttl,
                    gender = old_info.gender,
                    super = old_info.super
            }
            local aes_dat = utils.encrypt(dat, req.query.aes)
            re["dat"] = aes_dat
            res:json(re)
            exit(200)
        end
    end
    ngx.print('{"ret":5}')
    exit(200)
end

-- 给没有注册过的邮箱发验证码
user2_router.get_code = function(req, res, next)
    local raw_post_data = req.body
    utils.check_para(raw_post_data)
    local raw_post_data = utils.decrypt(raw_post_data, req.query.aes)
    local post_data = json.decode(raw_post_data)
    if utils.is_table_empty(post_data) then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local email = post_data['email']
    utils.check_para(email)
    if not utils.check_email(email) then
        ngx.print('{"ret":6}')
        exit(200)
    end
    local result, _ = mysql:query_by_email(email)
    if not utils.is_table_empty(result) then
        ngx.print('{"ret":13}')
        exit(200)
    end
    local title = "Paramount Verification Code"
    local code = utils.code_random()
    local content_1 = [[
        <html>
        <body>
        <p>Your verification code：</p>
        <p style="font-color: black;font-size: 24px;">
        ]]
    local content_2 =[[   
        </p>
        <p>Thank you!</p>
        <p>Paramount</p>
        </body>
        </html>
    ]]
    local content = content_1..code..content_2
    local send_re = send_email.doSend(title, content, email)

    my_redis:setex(config.redis_key.email_code_prefix..email, email_code_ttl,code)
    if send_re then
        ngx.print('{"ret":0}')
    else
        ngx.print('{"ret":8}')
    end
    exit(200)
end

-- 给注册过重置密码的邮箱发送验证码
user2_router.get_code_reset = function(req, res, next)
    local raw_post_data = req.body
    utils.check_para(raw_post_data)
    local raw_post_data = utils.decrypt(raw_post_data, req.query.aes)
    local post_data = json.decode(raw_post_data)
    if utils.is_table_empty(post_data) then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local email = post_data['email']
    utils.check_para(email)
    if not utils.check_email(email) then
        ngx.print('{"ret":6}')
        exit(200)
    end
    local result, _ = mysql:query_by_email(email)
    if utils.is_table_empty(result) or utils.is_table_empty(result[1]) or not result[1].id then
        ngx.print('{"ret":14}')
        exit(200)
    end
    local title = "Paramount Verification Code"
    local code = utils.code_random()
    local content_1 = [[
        <html>
        <body>
        <p>Your verification code：</p>
        <p style="font-color: black;font-size: 24px;">
        ]]
    local content_2 =[[   
        </p>
        <p>Thank you!</p>
        <p>Paramount</p>
        </body>
        </html>
    ]]
    local content = content_1..code..content_2
    local send_re = send_email.doSend(title, content, email)

    my_redis:setex(config.redis_key.email_code_prefix..email, email_code_ttl,code)
    if send_re then
        ngx.print('{"ret":0}')
    else
        ngx.print('{"ret":8}')
    end
    exit(200)
end

-- 注册的验证码 验证接口
user2_router.verify_code = function(req, res, next)
    local re = {}
    local raw_post_data = req.body
    utils.check_para(raw_post_data)
    local raw_post_data = utils.decrypt(raw_post_data, req.query.aes)
    local post_data = json.decode(raw_post_data)
    if utils.is_table_empty(post_data) then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local email = post_data['email']
    utils.check_para(email)
    local code = post_data['code']
    utils.check_para(code)
    if not utils.check_email(email) then
        ngx.print('{"ret":6}')
        exit(200)
    end
    local cache_code = my_redis:get(config.redis_key.email_code_prefix..email)
    if not utils.is_redis_null(cache_code) and cache_code == code then
        local result, _ = mysql:query_by_email(email)
        if not utils.is_table_empty(result) then
            my_redis:del(config.redis_key.email_code_prefix .. email)
            ngx.print('{"ret":13}')
            exit(200)
        end
        re["ret"] = 0
        local dat = {
            res = 1
        }
        local aes_dat = utils.encrypt(dat, req.query.aes)
        re["dat"] = aes_dat
        -- 为了防止验证邮箱ok后，真正注册的时候，又换邮箱
        my_redis:expire(config.redis_key.email_code_prefix .. email, email_code_ttl)
        res:json(re)
        exit(200)
    end
    re["ret"] = 0
    local dat = {
        res = 2
    }
    local aes_dat = utils.encrypt(dat, req.query.aes)
    re["dat"] = aes_dat
    res:json(re)
    exit(200)
end

-- 忘记密码的验证码 验证接口
user2_router.verify_code_reset = function(req, res, next)
    local re = {}
    local raw_post_data = req.body
    utils.check_para(raw_post_data)
    local raw_post_data = utils.decrypt(raw_post_data, req.query.aes)
    local post_data = json.decode(raw_post_data)
    if utils.is_table_empty(post_data) then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local email = post_data['email']
    utils.check_para(email)
    local code = post_data['code']
    utils.check_para(code)
    if not utils.check_email(email) then
        ngx.print('{"ret":6}')
        exit(200)
    end
    local cache_code = my_redis:get(config.redis_key.email_code_prefix..email)
    if not utils.is_redis_null(cache_code) and cache_code == code then
        local result, _ = mysql:query_by_email(email)
        if utils.is_table_empty(result) or utils.is_table_empty(result[1]) or not result[1].id then
            my_redis:del(config.redis_key.email_code_prefix .. email)
            ngx.print('{"ret":14}')
            exit(200)
        end
        re["ret"] = 0
        local dat = {
            res = 1
        }
        local aes_dat = utils.encrypt(dat, req.query.aes)
        re["dat"] = aes_dat
        -- 为了防止验证邮箱ok后，真正重置密码的时候，又换邮箱
        my_redis:expire(config.redis_key.email_code_prefix .. email, email_code_ttl)
        res:json(re)
        exit(200)
    end
    re["ret"] = 0
    local dat = {
        res = 2
    }
    local aes_dat = utils.encrypt(dat, req.query.aes)
    re["dat"] = aes_dat
    res:json(re)
    exit(200)
end

-- 注册用户
user2_router.register_user = function(req, res, next)
    local re = {}
    local raw_post_data = req.body
    if not raw_post_data or raw_post_data == "" then
        ngx.print('{"ret":3}')
        exit(200)
    end

    local raw_post_data = utils.decrypt(raw_post_data, req.query.aes)
    local post_data = json.decode(raw_post_data)
    if utils.is_table_empty(post_data) then
        ngx.print('{"ret":3}')
        exit(200)
    end

    local username = post_data["username"]
    local uname_len = utils.utf8len(username)
    if uname_len < 4 or uname_len > 30 then
        ngx.print('{"ret":3}')
        exit(200)
    end
    if not utils.filter(username) then
        ngx.print('{"ret":24}')
        exit(200) 
    end
    local email = post_data["email"]
    utils.check_para(email)
    if not utils.check_email(email) then
        ngx.print('{"ret":6}')
        exit(200)
    end
    local passwd = post_data["passwd"]
    if not passwd or slen(passwd) ~= 32 then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local code = post_data["code"]
    utils.check_para(code)
    local uniq = post_data["uniq"]
    if not uniq or uniq == "" or slen(uniq) ~= 32 then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local pkg = post_data["pkg"]
    utils.check_para(pkg)
    
    local gender = post_data["gender"]
    if gender ~= "1" and  gender ~= "2" then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local country = post_data["country"]
    utils.check_para(country)
    local language = post_data["language"]
    utils.check_para(language)
    local myos = post_data["os"]
    utils.check_para(myos)
    local pkgver = post_data["pkgver"]
    utils.check_para(pkgver)
    local pkgint = post_data["pkgint"]
    utils.check_para(pkgint)
    local instime = post_data["instime"]
    utils.check_para(instime)

    local cache_code =  my_redis:get(config.redis_key.email_code_prefix..email)
    if utils.is_redis_null(cache_code) or cache_code ~= code then
        ngx.print('{"ret":10}')
        exit(200)
    end

    -- have already register(应该不会出现)
    local result, _ = mysql:query_by_email(email)
    if not utils.is_table_empty(result) then
        ngx.print('{"ret":13}')
        exit(200)
    end
    sleep(0.1)
    ngx.update_time()
    local token_time = ngx.now() *  1000
    local token_raw = token_time .. utils.random()
    local accessToken = md5(token_raw)..token_time
    local refreshToken = md5(token_raw .. "_wcd")..utils.random()
    local tokenExpires = ngx.time() + config.token_ttl
    local avatar = config.default_avatar[gender]
    local save_pass = md5(passwd..config.redis_key.pass_key)
    local createTime = ngx.time()
    local result = mysql:insert_user(
        0,
        email,
        "",
        save_pass,
        username,
        avatar,
        gender,
        accessToken,
        refreshToken,
        tokenExpires,
        country,
        myos,
        uniq,
        language,
        pkg,
        pkgver,
        pkgint,
        instime,
        createTime
    )
    if result and result.insert_id then
        my_redis:hmset(
            config.redis_key.token_prefix .. accessToken,
            config.redis_key.token_uid_key,
            result.insert_id,
            config.redis_key.token_fresh_token_key,
            refreshToken
        )
        my_redis:expire(config.redis_key.token_prefix .. accessToken, config.token_ttl)
        local base_info = {
            username = username,
            avatar = avatar,
            uniq = uniq,
            gender = gender,
            super = 0
        }
        -- save anchor base info
        my_redis:hmset(config.redis_key.user_prefix .. result.insert_id, "base_info", json.encode(base_info),"ifollow", 0, "followme", 0)

        -- insert into data to user_extend
        local my_default_level = default_level
        if gender == "2" then
            my_default_level = 2
        end
        mysql_user_extend:insert_user(result.insert_id, my_default_level, 0, 0, 0)

        -- insert user and token to turn mysql
        --md5(uid:test.com:token))
        local turn_token = md5(result.insert_id..':'..config.turn_domain..':'..accessToken)
        turn:insert_turn_user(result.insert_id,config.turn_domain, turn_token)
        my_redis:del(config.redis_key.email_code_prefix .. email)
        
        ----------send fcm start----------
        local uid = tostring(result.insert_id)
        local myuid = config.fcm_send_from_uid
        local base_info_tmp = my_redis:hget(config.redis_key.user_prefix .. myuid, "base_info")
        local my_base_info = json.decode(base_info_tmp) or {}
        local msg
        --1 male 2 female
        if gender == "1" then 
            msg = "welcome to paramount，here lots of beauty are waiting to be flirted. lighten your mind to find them. What you want we all have."
        else
            msg = "welcome to paramount，you can  make one-to-one show or post video or pictures to get more attention. You will have fun and make great money here. How to make money https://goo.gl/tXTbqw"
        end
        local fcm_son_data = {
            type = "im",
            title = "imfcm",
            alert = msg,
            accessory = {
                    mime = "image/png",
                    url = "png",
            },
            to = uid,
            from = {
                    uid = myuid,
                    uniq = my_base_info["uniq"],
                    super = my_base_info["super"] or 0,
                    username = my_base_info["username"],
                    avatar = my_base_info["avatar"],
            },
            msgid = myuid ..':3'..createTime * 1000,
            time = createTime,
            level = "system",
        }
        local fcm_data = {
            uid = uid,
            class = "unlock",
            time = createTime,
            data = json.encode(fcm_son_data)
        }
        --my_redis:lpush(config.redis_key.fcm_redis_key, json.encode(fcm_data))
        local need_cron_data = {
            act = 'newcomer_send_fcm',
            uid = uid,
            data = {
                time = createTime,
                fcm_data = json.encode(fcm_data)
            }
        }
        my_redis:rpush(config.redis_key.cron_list_key, json.encode(need_cron_data))
        ----------send fcm end----------

        local dat = {
                uid = tostring(result.insert_id),
                clientID = uniq,
                accessToken = accessToken,
                refreshToken = refreshToken,
                tokenExpires = tokenExpires,
                tokenTTL = config.token_ttl,
                gender = gender
        }
        local aes_dat = utils.encrypt(dat, req.query.aes)
        local re = {
            ret = 0,
            dat = aes_dat
        }
        res:json(re)
        exit(200)
    else
        ngx.print('{"ret":5}')
        exit(200)
    end
end

user2_router.reset_pass = function(req, res, next)
    local re = {}
    local raw_post_data = req.body
    utils.check_para(raw_post_data)
    local raw_post_data = utils.decrypt(raw_post_data, req.query.aes)
    local post_data = json.decode(raw_post_data)
    if utils.is_table_empty(post_data) then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local email = post_data['email']
    utils.check_para(email)
    local code = post_data['code']
    utils.check_para(code)
    local pass = post_data['passwd']
    if not pass or slen(pass) ~= 32 then
        ngx.print('{"ret":3}')
        exit(200)
    end
    if not utils.check_email(email) then
        ngx.print('{"ret":6}')
        exit(200)
    end
    local cache_code =  my_redis:get(config.redis_key.email_code_prefix..email)
    if utils.is_redis_null(cache_code) or cache_code ~= code then
        ngx.print('{"ret":10}')
        exit(200)
    end
    local result, _ = mysql:query_by_email(email)
    if utils.is_table_empty(result) or utils.is_table_empty(result[1]) or not result[1].id then
        ngx.print('{"ret":14}')
        exit(200)
    end
    local save_pass = md5(pass..config.redis_key.pass_key)
    local mysql_re = mysql:update_pass(save_pass, result[1].id)
    if mysql_re and mysql_re.affected_rows > 0 then
        ngx.print('{"ret":0}')
        exit(200)
    end
    ngx.print('{"ret":5}')
    exit(200)
end

-- 增加新的视频
user2_router.add_video = function(req, res, next)
    local raw_post_data = req.body
    utils.check_para(raw_post_data)
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

    -- check  total video num
    local uid = req.params.uid
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
    
    video_url = gsub(video_url,config.upload.aws_preupload_url,config.upload.resource_url)

    local vinfo_json = json.encode(vinfo)
    --mysql:update_user_zhubo(uid)
    local video_info = {
        video = video_url,
        cover = cover_url,
        vinfo = vinfo
    }
    local video_re = mysql_video:insert_video(uid, video_url, cover_url, vinfo_json, 0)
    if video_re and video_re.insert_id then
        my_redis:hset(config.redis_key.video_prefix .. uid, video_re.insert_id, json.encode(video_info))
        if not have_cover then
            mysql:update_user_zhubo(uid)
            my_redis:hset(config.redis_key.video_prefix .. uid, 'iscover', video_re.insert_id)
            my_redis:sadd(config.redis_key.all_anchors_uid, uid)
            local shared_cache_data = my_redis:smembers(config.redis_key.all_anchors_uid)
            shared_cache:set(config.redis_key.shared_cache_anchor_uids,tconcat(shared_cache_data,","))
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

-- 获取主播状态
user2_router.get_states = function(req, res, next)
    local re = {}
    local raw_post_data = req.body
    utils.check_para(raw_post_data)
    local raw_post_data = utils.decrypt(raw_post_data, req.query.aes)
    local post_data = json.decode(raw_post_data)
    if utils.is_table_empty(post_data) then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local ids = post_data['ids']
    utils.check_para(ids)
    local all_ids = utils.string_split(ids,',')
    local re_data = {}
    for _,uid in ipairs(all_ids) do
        local state = my_redis:hget(config.redis_key.user_prefix .. uid,'state')
        if not utils.is_redis_null(state) then
            local one = {
                uid = uid,
                state = tonumber(state)
            }
            tinsert(re_data,one)
        end
    end
    local dat = {
        list = re_data
    }
    local aes_dat = utils.encrypt(dat, req.query.aes)
    res:json({
        ret = 0,
        dat = aes_dat
    })
    exit(200)
end

-- 查看其他人主页
user2_router.look_others_homepage = function(req, res, next)
    local id = req.params.id
    local myuid = req.params.uid
    utils.check_para(id)
    local re = {}
    local all_info = my_redis:hmget(config.redis_key.user_prefix .. id, "base_info", "other_info","ifollow","followme")
    if utils.is_redis_null_table(all_info) then
        ngx.print('{"ret":6000}')
        exit(200)
    end
    local icare_data = 0
    if id ~= myuid then
        local is_my_fans = my_redis:zscore(config.redis_key.follow_me_prefix .. id, myuid)
        if is_my_fans then
            icare_data = 1
        end
    end

    local  video_info_tmp = my_redis:hgetall(config.redis_key.video_prefix .. id)
    local data_len = 0
    if not utils.is_redis_null_table(video_info_tmp) then
        data_len = #video_info_tmp 
    end
    local video_list = {}
    local cover_id
    for i=1,data_len,2 do
        if video_info_tmp[i] == "iscover" then
            cover_id = video_info_tmp[i+1]
        else
            video_list[video_info_tmp[i]] = json.decode(video_info_tmp[i+1])
        end
    end
    local video_list_ok = {}
    for id,v in pairs(video_list) do
        local iscover = 0
        if id == cover_id then
            iscover = 1
        end
        local one = {
            id = id,
            video = v.video,
            compress_video = v.compress_video or "",
            cover = v.cover,
            iscover = iscover
        }
        tinsert(video_list_ok,one)
    end
    tsort(video_list_ok, function(a, b)
        if tonumber(a.id) >  tonumber(b.id) then
            return true
        end
    end)
    local is_pvip = my_redis:exists(config.redis_key.vip_user_key..id)
    local moments_list = {}
    local moments_len = 0
    local my_ids = my_redis:zrevrangebyscore(config.redis_key.moments_myids_key..id,"+inf",0,"limit",0,3)
    if not utils.is_redis_null_table(my_ids) then
        moments_len = my_redis:zcard(config.redis_key.moments_myids_key..id)
        for _,v in ipairs(my_ids) do
            local is_unlock = 0
            local mm_redis_key = config.redis_key.moments_prefix_hash_key..v
            local real_data_tmp = my_redis:hmget(mm_redis_key,"data","tags")
            if not utils.is_redis_null(real_data_tmp) and not utils.is_redis_null(real_data_tmp[1]) then
                local real_data = json.decode(real_data_tmp[1]) or {}
                local uid = real_data.uid
                        local real_data_price = real_data.price
                        if is_pvip == 0 and uid ~= myuid then
                            if real_data_price > 0 then
                                local is_payed = my_redis:hexists(mm_redis_key, config.redis_key.moments_pay_uid_key .. myuid)
                                if is_payed == 1 then
                                    is_unlock = 1
                                end
                            end
                        end
                        --1:img-list 2:video
                        local tags = json.decode(real_data_tmp[2]) or {}
                        local one
                        if real_data.add_type == 1 then
                            one = {
                                id = tonumber(v),
                                time_stamp = real_data.time_stamp,
                                add_type = 1,
                                base_url = real_data.base_url,
                                img_urls = real_data.img_urls,
                                price = real_data_price,
                                position = real_data.position,
                                mm_from = real_data.mm_from or 0,
                                desc = real_data.desc,
                                unlock = is_unlock,
                                tags = tags,
                            }
                        else
                            one = {
                                id = tonumber(v),
                                time_stamp = real_data.time_stamp,
                                add_type = 2,
                                base_url = real_data.base_url,
                                video_cover = real_data.video_cover,
                                video_url = real_data.video_url,
                                video_width = real_data.video_width,
                                video_height = real_data.video_height,
                                price = real_data_price,
                                position = real_data.position,
                                mm_from = real_data.mm_from or 0,
                                desc = real_data.desc,
                                unlock = is_unlock,
                                tags = tags,
                            }
                        end

                        mms_model:merge_mm_info(one, myuid)

                        tinsert(moments_list, one)
            end
        end
    end

    local base_info = json.decode(all_info[1]) or {}
    local other_info = json.decode(all_info[2]) or {}
    local data = {
        uid = id,
        username = base_info["username"],
        avatar = base_info["avatar"],
        gender = base_info["gender"],
        super = base_info["super"] or 0,
        brief = other_info["brief"],
        telents = {},
        tags = {},
        videolist = video_list_ok,
        momentslen = moments_len,
        momentslist = moments_list,
        ifollow = tonumber(all_info[3]),
        followme = tonumber(all_info[4]),
        price = other_info["price"],
        icare = icare_data,
        pvip = is_pvip
    }
    local aes_dat = utils.encrypt(data, req.query.aes)
    res:json({
        ret = 0,
        dat = aes_dat
        }
    )
    exit(200)
end

-- 查看个人myself主页
user2_router.look_myself_page = function(req, res, next)
    local myuid = req.params.uid
    local re = {}
    local all_info = my_redis:hmget(config.redis_key.user_prefix .. myuid, "base_info", "other_info","ifollow","followme")
    if utils.is_redis_null_table(all_info) then
        ngx.print('{"ret":6000}')
        exit(200)
    end
   
    local base_info = json.decode(all_info[1]) or {}
    local other_info = json.decode(all_info[2]) or {}
    local data = {
        uid = myuid,
        username = base_info["username"],
        avatar = base_info["avatar"],
        gender = base_info["gender"],
        super = base_info["super"] or 0,
        brief = other_info["brief"],
        telents = {},
        tags = {},
        price = other_info["price"],
        ifollow = tonumber(all_info[3]),
        followme = tonumber(all_info[4]),
    }
    local aes_dat = utils.encrypt(data, req.query.aes)
    res:json({
        ret = 0,
        dat = aes_dat
        }
    )
    exit(200)
end


-- 查看视频列表
user2_router.look_my_video = function(req, res, next)
    local myuid = req.params.uid
    local re = {}
    local  video_info_tmp = my_redis:hgetall(config.redis_key.video_prefix .. myuid)
    local data_len = 0
    if not utils.is_redis_null_table(video_info_tmp) then
        data_len = #video_info_tmp 
    end
    local video_list = {}
    local cover_id
    for i=1,data_len,2 do
        if video_info_tmp[i] == "iscover" then
            cover_id = video_info_tmp[i+1]
        else
            video_list[video_info_tmp[i]] = json.decode(video_info_tmp[i+1])
        end
    end
    local video_list_ok = {}
    for id,v in pairs(video_list) do
        local iscover = 0
        if id == cover_id then
            iscover = 1
        end
        local one = {
            id = id,
            video = v.video,
            compress_video = v.compress_video or "",
            cover = v.cover,
            iscover = iscover 
        }
        tinsert(video_list_ok,one)
    end
    tsort(video_list_ok, function(a, b)
        if tonumber(a.id) >  tonumber(b.id) then
            return true
        end
    end)
    local data = {
        videolist = video_list_ok
    }
    local aes_dat = utils.encrypt(data, req.query.aes)
    res:json({
        ret = 0,
        dat = aes_dat
        }
    )
    exit(200)
end

-- 查看粉丝 type=1 （i follow）  type=2 （follow me）
user2_router.look_fans = function(req, res, next)
    local re = {} 
    local act_type = req.params.type
    local uid = req.params.uid
    local fans_redis_key
    local limit_num
    if act_type == "1" then
        fans_redis_key = config.redis_key.i_follow_prefix .. uid
        limit_num = -1
    elseif act_type == "2" then
        fans_redis_key = config.redis_key.follow_me_prefix .. uid
        limit_num = 300
    else
        ngx.print('{"ret":3}')
        exit(200)
    end
    local all_uids = my_redis:zrevrange(fans_redis_key, 0, limit_num)
    if utils.is_redis_null(all_uids) then
        re["ret"] = 0
        local dat = {
            list = {}
        }
        local aes_dat = utils.encrypt(dat, req.query.aes)
        re["dat"] = aes_dat
        res:json(re)
        exit(200)
    end
    local ok_re ={}
    for _,uid in ipairs(all_uids) do
        local u_info = my_redis:hget(config.redis_key.user_prefix .. uid, 'base_info')
        if not utils.is_redis_null(u_info) then
            local user_info = json.decode(u_info)
            local one = {
                uid = uid,
                username = user_info['username'],
                avatar = user_info['avatar'],
                super = user_info["super"] or 0,
            }
            tinsert(ok_re, one)
        end
    end
    local dat = {
        list = ok_re
    }
    local aes_dat = utils.encrypt(dat, req.query.aes)
    re["ret"] = 0
    re["dat"] = aes_dat
    res:json(re)
    exit(200)
end


-- 查看粉丝 type=1 （i follow）  type=2 （follow me）
user2_router.look_my_fans = function(req, res, next)
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
    local id = tonumber(post_data['id'])
    utils.check_para(id)

    local per_page_num = 20
    local fans_redis_key = config.redis_key.follow_me_prefix .. myuid
    local all_uids 
    if id == 0 then
        all_uids = my_redis:zrevrange(fans_redis_key, 0, per_page_num-1)
    else
        local rank = my_redis:zrevrank(fans_redis_key,id)
        if not rank then
            ngx.print('{"ret":3}')
            exit(200)
        end
        if rank == 0 then
            all_uids = my_redis:zrevrange(fans_redis_key, 0, per_page_num-1)
        else
            all_uids = my_redis:zrevrange(fans_redis_key, rank+1, rank+per_page_num)
        end
    end 
    if utils.is_redis_null(all_uids) then
        re["ret"] = 0
        local dat = {
            list = {}
        }
        local aes_dat = utils.encrypt(dat, req.query.aes)
        re["dat"] = aes_dat
        res:json(re)
        exit(200)
    end
    local ok_re ={}
    for _,uid in ipairs(all_uids) do
        local u_info = my_redis:hget(config.redis_key.user_prefix .. uid, 'base_info')
        if not utils.is_redis_null(u_info) then
            local user_info = json.decode(u_info)
            local one = {
                uid = uid,
                username = user_info['username'],
                avatar = user_info['avatar'],
                super = user_info["super"] or 0,
            }
            tinsert(ok_re, one)
        end
    end
    local dat = {
        list = ok_re
    }
    local aes_dat = utils.encrypt(dat, req.query.aes)
    re["ret"] = 0
    re["dat"] = aes_dat
    res:json(re)
    exit(200)
end

-- 关注／取消关注 type=1 关注某个人  type=2 取消关注某个人
user2_router.do_follow = function(req, res, next)
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
    local ids = post_data['ids']
    utils.check_para(ids)
    local all_ids = utils.string_split(ids,',')
    local act_type = post_data['type']
    if act_type ~= 1 and act_type ~= 2 then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local tell = post_data['tell'] or 0
    if tell ~= 0 and tell ~= 1 then
        ngx.print('{"ret":3}')
        exit(200)
    end

    local now_time = ngx.time()
    local num = 0
    local all_ok_uids = {}
    local check_rep = {}
    for _,uid in ipairs(all_ids) do
        if uid ~= myuid then
            local if_exists = my_redis:exists(config.redis_key.user_prefix .. uid)
            if  if_exists == 1 then
                if check_rep[uid] then
                    ngx.print('{"ret":3}')
                    exit(200)
                else
                    --tinsert(all_key, now_time)
                    --tinsert(all_key, uid) 
                    tinsert(all_ok_uids, uid)
                    num = num + 1
                    check_rep[uid] = 1
                end
            else
                ngx.print('{"ret":3}')
                exit(200)   
            end
        else
            ngx.print('{"ret":3}')
            exit(200)
        end
    end
    check_rep = nil
    local need_sync_uids = {}
    local need_act = false
    if num > 0 then
        if act_type == 1 then --关注
            --my_redis:zadd(config.redis_key.i_follow_prefix .. myuid, unpack(all_key))
            -- 关注someone之后，增加myuid 的ifollow数量，增加关注someone的followme的数量
            for _,ok_uid in ipairs(all_ok_uids) do
                local is_done = my_redis:zadd(config.redis_key.i_follow_prefix .. myuid, now_time, ok_uid)
                if is_done == 1 then
                    my_redis:hincrby(config.redis_key.user_prefix .. myuid, "ifollow", 1)
                    my_redis:hincrby(config.redis_key.user_prefix .. ok_uid, "followme", 1)
                    my_redis:zadd(config.redis_key.follow_me_prefix .. ok_uid, now_time, myuid)
                    tinsert(need_sync_uids, ok_uid)
                    need_act = true
                end
                
            end
        else
            -- 取消关注someone之后，减少myuid 的ifollow数量，减少关注someone的followme的数量
            for _,ok_uid in ipairs(all_ok_uids) do
                local is_cancel = my_redis:zrem(config.redis_key.i_follow_prefix .. myuid, ok_uid)
                if is_cancel == 1 then
                    tinsert(need_sync_uids, ok_uid)
                    need_act = true
                    local now_num = my_redis:hincrby(config.redis_key.user_prefix .. myuid, "ifollow", -1)
                    if now_num < 0 then
                        my_redis:hset(config.redis_key.user_prefix .. myuid, "ifollow", 0)
                    end

                    local is_cancel = my_redis:zrem(config.redis_key.follow_me_prefix .. ok_uid, myuid)
                    if is_cancel == 1 then
                        local now_num = my_redis:hincrby(config.redis_key.user_prefix .. ok_uid, "followme", -1)
                        -- 防止hack
                        if now_num < 0 then
                            my_redis:hset(config.redis_key.user_prefix .. ok_uid, "followme", 0)
                        end
                    end
                end
            end 
        end
        if need_act then
            -- sync data to mysql per 12 hours
            local need_cron_data = {
                act = 'fans',
                uid = myuid,
                data = {
                    act_type = act_type,
                    now_time = now_time,
                    all_ok_uids = need_sync_uids,
                    num = num
                }
            }
            my_redis:rpush(config.redis_key.cron_list_key, json.encode(need_cron_data))
        end
    end
    if tell == 1  then
        local myuid = tonumber(myuid)
        local need_ok_num = 3
        local ok_info = {}
        local ok_num = 0
        local limit_num = 100
        -- girl
        for i=1,20 do
            if ok_num >= need_ok_num then
                break
            end
            local limit_start = (i-1) * limit_num
            local one = mysql:get_user_gender_by_limit(2,limit_start,limit_num)
            for _,tmp in pairs(one) do
                if ok_num >= need_ok_num then
                    break
                end
                local uid = tmp.id
                if myuid ~= uid  then
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
                for _,tmp in pairs(one) do
                    if ok_num >= need_ok_num then
                        break
                    end
                    local uid = tmp.id
                    if myuid ~= uid  then
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
    else
        ngx.print('{"ret":0}')
        exit(200)
    end
    
end

-- 设置封面
user2_router.set_cover = function(req, res, next)
    local re = {}
    local myuid = req.params.uid
    local id = req.params.id
    utils.check_para(id)
    local check_exist = my_redis:hexists(config.redis_key.video_prefix .. myuid, id)
    if check_exist ~= 1 then
        ngx.print('{"ret":3}')
        exit(200)
    end
    my_redis:hset(config.redis_key.video_prefix .. myuid, "iscover", id)
    -- sync act
    local need_cron_data = {
            act = 'setcover',
            uid = myuid,
            data = {
                cover_id = id
            }
    }
    my_redis:rpush(config.redis_key.cron_list_key, json.encode(need_cron_data))
    ngx.print('{"ret":0}')
    exit(200)
end

user2_router.del_video = function(req, res, next)
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
    local id = post_data['id']
    utils.check_para(id)
    local is_del = 0 
    local old_cover_id = my_redis:hget(config.redis_key.video_prefix .. myuid, "iscover")
    local total_video_num = my_redis:hlen(config.redis_key.video_prefix .. myuid)
    if total_video_num > 2 and id == old_cover_id then
        ngx.print('{"ret":3}')
        exit(200)
    end
    if id == old_cover_id then 
        is_del = my_redis:del(config.redis_key.video_prefix .. myuid)
        my_redis:srem(config.redis_key.all_anchors_uid, myuid)
        local shared_cache_data = my_redis:smembers(config.redis_key.all_anchors_uid)
        shared_cache:set(config.redis_key.shared_cache_anchor_uids,tconcat(shared_cache_data,","))
    else
         is_del = my_redis:hdel(config.redis_key.video_prefix .. myuid, id)
    end
    --[[
    if id == old_cover_id then
        local  video_info_tmp = my_redis:hkeys(config.redis_key.video_prefix .. myuid)
        local total_num = #video_info_tmp
        -- 视频只有一个(include the key iscover) 删除的话 就不是主播身份了
        if total_num <= 2 then
            my_redis:del(config.redis_key.video_prefix .. myuid)
            my_redis:srem(config.redis_key.all_anchors_uid, myuid)
        else
            local max_id = 0
            for i=1,total_num do
                if video_info_tmp[i] ~= "iscover" then
                    local ttt = tonumber(video_info_tmp[i])
                    if  ttt > max_id then
                        max_id = ttt
                    end
                end
            end
            my_redis:hset(config.redis_key.video_prefix .. myuid, "iscover", max_id)
            my_redis:hdel(config.redis_key.video_prefix .. myuid, id)
            change_cover = max_id
        end 
    else
        is_del = my_redis:hdel(config.redis_key.video_prefix .. myuid, id)
    end
    --]]
    -- sync act
    if is_del == 1 then
        local need_cron_data = {
                act = 'del_video',
                uid = myuid,
                data = {
                    del_id = id,
                    change_id = 0
                }
        }
        my_redis:rpush(config.redis_key.cron_list_key, json.encode(need_cron_data))
    end
    ngx.print('{"ret":0}')
    exit(200)
end

-- 
user2_router.update_username = function(req, res, next)
    local myuid = req.params.uid
    local raw_post_data = req.body
    utils.check_para(raw_post_data)
    local raw_post_data = utils.decrypt(raw_post_data, req.query.aes)
    local post_data = json.decode(raw_post_data)
    if utils.is_table_empty(post_data) then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local username = post_data['username']
    local uname_len = utils.utf8len(username)
    if uname_len < 4 or uname_len > 30 then
        ngx.print('{"ret":3}')
        exit(200)
    end
    if not utils.filter(username) then
        ngx.print('{"ret":24}')
        exit(200) 
    end
    local cache_base_info = my_redis:hget(config.redis_key.user_prefix .. myuid, "base_info")
    cache_base_info = json.decode(cache_base_info)
    local base_info = {
            username = username,
            avatar = cache_base_info.avatar,
            uniq = cache_base_info.uniq,
            gender = cache_base_info.gender,
            super = cache_base_info.super
    }
    my_redis:hset(config.redis_key.user_prefix .. myuid,"base_info", json.encode(base_info))
    -- sync act
    local need_cron_data = {
            act = 'update_uname',
            uid = myuid,
            data = {
                name = ngx_quote_sql_str(username)
            }
    }
    my_redis:rpush(config.redis_key.cron_list_key, json.encode(need_cron_data))
    ngx.print('{"ret":0}')
    exit(200)
end

-- 
user2_router.update_brief = function(req, res, next)
    local myuid = req.params.uid
    local raw_post_data = req.body
    utils.check_para(raw_post_data)
    local raw_post_data = utils.decrypt(raw_post_data, req.query.aes)
    local post_data = json.decode(raw_post_data)
    if utils.is_table_empty(post_data) then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local brief = post_data['brief'] or ""
    --todo check brief inclue vaild char
    local cache_info_tmp = my_redis:hget(config.redis_key.user_prefix .. myuid, "other_info")
    local cache_info = json.decode(cache_info_tmp) or {}
    local base_info_tmp = my_redis:hget(config.redis_key.user_prefix .. myuid, "base_info")
    local my_base_info = json.decode(base_info_tmp) or {}
    local gender = tonumber(my_base_info.gender)
    local default_price = config.default_price
    if gender == 2 then
        default_price = config.default_girl_price
    end
    local other_info = {
            tags = cache_info.tags or {},
            telents = cache_info.telents or {},
            brief = brief,
            price = cache_info.price or default_price
    }
    table_object(false)
    my_redis:hmset(config.redis_key.user_prefix .. myuid,"other_info", json.encode(other_info),"price",other_info.price)
    -- sync act
    local need_cron_data = {
            act = 'update_brief',
            uid = myuid,
            data = {
                brief = ngx.encode_base64(brief)
                --brief = ngx_quote_sql_str(brief)
            }
    }
    my_redis:rpush(config.redis_key.cron_list_key, json.encode(need_cron_data))
    ngx.print('{"ret":0}')
    exit(200)
end

user2_router.check_fans = function(req, res, next)
    local re = {}
    local raw_post_data = req.body
    utils.check_para(raw_post_data)
    local raw_post_data = utils.decrypt(raw_post_data, req.query.aes)
    local post_data = json.decode(raw_post_data)
    if utils.is_table_empty(post_data) then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local ids = post_data['ids']
    utils.check_para(ids)
    local myuid = req.params.uid
    local all_ids = utils.string_split(ids,',')
    local re_data = {}
    for _,uid in ipairs(all_ids) do
        local icare_data = 0
        local is_my_fans = my_redis:zscore(config.redis_key.follow_me_prefix .. uid, myuid)
        if is_my_fans then
            icare_data = 1
        end
        local one = {
            uid = uid,
            icare = icare_data
        }
        tinsert(re_data, one)
    end
    local dat =  {
            list = re_data
    }
    local aes_dat = utils.encrypt(dat, req.query.aes)
    res:json({
        ret = 0,
        dat = aes_dat
    })
    exit(200)
end

user2_router.up_token = function(req, res, next)
    local re = {}
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
    local token = post_data['token']
    utils.check_para(token)
	local now_time = ngx.time()
    local myuid = req.params.uid
    local fcm_data = {
        queue_type = "fcm",
        uid = myuid,
        uniq = uniq,
        fcmtoken = token,
        uptime = now_time
    }
    my_redis:lpush(config.redis_key.queue_list_key, json.encode(fcm_data))
    ngx.print('{"ret":0}')
    exit(200)
end

user2_router.query_anchor = function(req, res, next)
    local myuid = req.params.uid
    local is_anchor = my_redis:sismember(config.redis_key.all_anchors_uid, myuid)
    local raw_data = my_redis:hkeys(config.redis_key.user_prefix .. myuid)
    local have_order = 0
    local re = {}
    local raw_data_len = #raw_data
    for i=1,raw_data_len do
        local anchor_key = match(raw_data[i], "^a:(%d+)")
        if anchor_key then
            have_order = 1
            break
        end
    end
    re["ret"] = 0
    local dat = {
        is_anchor = is_anchor,
        have_order = have_order
    }
    local aes_dat = utils.encrypt(dat, req.query.aes)
    re["dat"] = aes_dat
    res:json(re)
    ngx.exit(200)
end

user2_router.check_input = function(req, res, next)
    local re = {}
    local myuid = req.params.uid
    local raw_post_data = req.body
    utils.check_para(raw_post_data)
    local post_data = json.decode(raw_post_data)
    if utils.is_table_empty(post_data) then
       ngx.print('{"ret":3}')
        exit(200)
    end
    local username = post_data['username']
    local uname_len = utils.utf8len(username)
    if uname_len < 4 or uname_len > 30 then
        ngx.print('{"ret":3}')
        exit(200)
    end
    if not utils.filter(username) then
        ngx.print('{"ret":24}')
        exit(200) 
    end
    re["ret"] = 0
    re["dat"] = "ok"
    res:json(re)
    ngx.exit(200)
end

return user2_router
