local user4_router = {}
local redis = require("app2.lib.redis")
local config = require("app2.config.config")
local my_redis = redis:new()
local mysql = require("app2.model.user")
local mysql_user_extend = require("app2.model.user_extend")
local ngx = ngx
local md5 = ngx.md5
local exit = ngx.exit
local sleep = ngx.sleep
local pcall = pcall
local iopopen = io.popen
local utils = require("app2.lib.utils")
local json = require("cjson.safe")
local turn = require("app2.model.turn")
local table_object  = json.encode_empty_table_as_object
local ssl = require "ssl"
local https = require "ssl.https"

local tinsert = table.insert
local tsort = table.sort
local tonumber = tonumber
local tostring = tostring
local match = string.match
local slen = string.len
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

local function fb_login_check(fbtoken)
    local logger = require("app2.lib.logger")
    logger.close()
    logger.new(config.save_log.important_log_file)
    local ok_url = "https://graph.facebook.com/debug_token?access_token="..config.voucher.fb_appid.."|"..config.voucher.fb_appsecret.."&input_token="..fbtoken
    --ngx.log(ngx.ERR,ok_url)
    local body, code = https.request(ok_url)
    if code ~= 200 then
        local log_voucher_info = "[fb login check error] fbtoken:"..fbtoken.."code:"..code
        logger.info(log_voucher_info)
        return 2,'http code error'
    elseif not body then
        return 3,'body empty'
    end
    return 0,body
end

local fb_register_user = function(fbid,post_data)
    local re = {}
    local createTime = ngx.time()
    local email = post_data["email"] or ""
    local username = post_data["username"]
    local passwd = post_data["passwd"]
    local uniq = post_data["uniq"]
    local pkg = post_data["pkg"]
    local gender = post_data["gender"]
    local country = post_data["country"]
    local language = post_data["language"]
    local myos = post_data["os"]
    local pkgver = post_data["pkgver"]
    local pkgint = post_data["pkgint"]
    local instime = post_data["instime"] or createTime
    sleep(0.1)
    ngx.update_time()
    local token_time = ngx.now() *  1000
    local token_raw = token_time .. utils.random()
    local accessToken = md5(token_raw)..token_time
    local refreshToken = md5(token_raw .. "_wcd")..utils.random()
    local tokenExpires = ngx.time() + config.token_ttl
    
    local avatar
    if not post_data["avatar"] or post_data["avatar"] == "" then
        avatar = config.default_avatar[gender]
    else
        avatar = post_data["avatar"]
    end
    local save_pass = md5(passwd..config.redis_key.pass_key)
    
    local result = mysql:insert_user(
        fbid,
        "",
        email,
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
        mysql_user_extend:insert_user(result.insert_id, default_level, 0, 0, 0)
        -- insert user and token to turn mysql
        --md5(uid:test.com:token))
        local turn_token = md5(result.insert_id..':'..config.turn_domain..':'..accessToken)
        turn:insert_turn_user(result.insert_id,config.turn_domain, turn_token)

        ----------send fcm start----------
        local uid = tostring(result.insert_id)
        local myuid = config.fcm_send_from_uid
        local base_info_tmp = my_redis:hget(config.redis_key.user_prefix .. myuid, "base_info")
        local my_base_info = json.decode(base_info_tmp) or {}
        local msg
        --1 boy 2 girl
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
                gender = gender,
                super = 0
        }
        return 0,dat
    else
        return 1
    end
end

user4_router.fb_login = function(req, res, next)
    local re = {}
    local raw_post_data = req.body
    utils.check_para(raw_post_data)
    local raw_post_data = utils.decrypt(raw_post_data, req.query.aes)
    local post_data = json.decode(raw_post_data)
    if utils.is_table_empty(post_data) then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local fbuid = post_data['fbuid']
    utils.check_para(fbuid)
    local fbtoken = post_data['fbtoken']
    utils.check_para(fbtoken)
    local email = post_data['email']
    local pass = md5("www.wcd.news")
    post_data["passwd"] = pass
    local uniq = post_data['uniq']
    if not uniq or slen(uniq) ~= 32 then
        ngx.print('{"ret":3}')
        exit(200)
    end
    if not  post_data['username'] or post_data['username'] == "" then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local country = post_data['country']
    utils.check_para(country)
    local language = post_data['language']
    utils.check_para(language)
    if post_data['gender'] ~= "1" and post_data['gender'] ~= "2" then
        ngx.print('{"ret":3}')
        exit(200)
    end
    utils.check_para(post_data["os"])
    utils.check_para(post_data["pkgver"])
    utils.check_para(post_data["pkgint"])

    local save_pass = md5(pass..config.redis_key.pass_key)
    local result = mysql:query_by_fbid(fbuid)
    if utils.is_table_empty(result) or utils.is_table_empty(result[1]) or not result[1].id then
        --fb注册
          -- goto fb to check
        local ok,ok_re,fb_re_tmp
        ok,ok_re,fb_re_tmp = pcall(fb_login_check, fbtoken)
        if not ok then
            sleep(0.1)
            ok,ok_re,fb_re_tmp = pcall(fb_login_check, fbtoken)
        end
        if not ok or ok_re ~= 0 then
            ngx.print('{"ret":28}')
            exit(200)
        end
        local fb_re = json.decode(fb_re_tmp)
        if fb_re.data.user_id ~= fbuid then
            ngx.print('{"ret":29}')
            exit(200)
        end
        local isok,re_dat = fb_register_user(fbuid,post_data)
        if isok ~= 0 then
            ngx.print('{"ret":5}')
            exit(200)
        end
        re["ret"] = 0
        local aes_dat = utils.encrypt(re_dat, req.query.aes)
        re["dat"] = aes_dat
        res:json(re)
        exit(200)
    else
        local need_fb_check = utils.fb_random(100)
        if need_fb_check > 70 then
            local ok,ok_re,fb_re_tmp
            ok,ok_re,fb_re_tmp = pcall(fb_login_check, fbtoken)
            if not ok or ok_re ~= 0  then
                ngx.print('{"ret":28}')
                exit(200)
            end
            local fb_re = json.decode(fb_re_tmp)
            if fb_re.data.user_id ~= fbuid or not fb_re.data.is_valid then
                ngx.print('{"ret":29}')
                exit(200)
            end
        end
        -- login fresh token start
        local old_info = result[1]
        local uid = tostring(old_info.id)
        -- 如果fb的email和之前的相同，则更新之前的用户
        --[[
        if old_info.fbid ~= fbuid then
            mysql:update_user_fbid(fbuid, old_info.id)
        end
        ]]
        access_limit(res, uid, 50, 86400)
        sleep(0.1)

        ---block user start---
        local str = my_redis:get(config.redis_key.block_user_key .. uid)
        if not utils.is_redis_null(str) then
            ngx.print('{"ret":44,"msg":"'..str..'"}')
            exit(200)
        end
        ---block user end---

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

user4_router.gift_config = function(req, res, next)
    local info = my_redis:hgetall(config.redis_key.gift_config_key)
    if utils.is_redis_null_table(info) then
        ngx.print('{"ret":5}')
        exit(200)
    end
    local data_len = #info
    local data = {}
    for i = 1, data_len, 2 do
        tinsert(data, json.decode(info[i + 1]))
    end
    tsort(data, function(a, b)
        if a.coin < b.coin then
            return true
        end
    end)
    local re = {}
    local aes_dat = utils.encrypt(data, req.query.aes)
    re["ret"] = 0
    re["dat"] = aes_dat
    res:json(re)
    exit(200)
end

user4_router.gogogo_preupload = function(req, res, next)
    local act_type = req.params.type
    local go_cmd
    if not act_type or act_type == "0" then
        go_cmd = config.go_preupload_cmd
    else
        go_cmd = config.go_preupload_moments_cmd
    end
    local link = iopopen(go_cmd)
    local go_url = link:read("*l")
    local re = {}
    if not go_url or go_url == "" then
        ngx.print('{"ret":5}')
        exit(200)
    end
    local data = {
        url = go_url
    }
    local aes_dat = utils.encrypt(data, req.query.aes)
    re["ret"] = 0
    re["dat"] = aes_dat
    res:json(re)
    exit(200)
end

user4_router.fb_check = function(req, res, next)
    local re = {}
    local raw_post_data = req.body
    utils.check_para(raw_post_data)
    local raw_post_data = utils.decrypt(raw_post_data, req.query.aes)
    local post_data = json.decode(raw_post_data)
    if utils.is_table_empty(post_data) then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local fbid = post_data['fbid']
    utils.check_para(fbid)
    local result = mysql:query_by_fbid(fbid)
    local ok_res = 1
    if utils.is_table_empty(result) or utils.is_table_empty(result[1]) or not result[1].id then
        ok_res = 2
    end
    local data = {
        res = ok_res
    }
    local aes_dat = utils.encrypt(data, req.query.aes)
    re["ret"] = 0
    re["dat"] = aes_dat
    res:json(re)
    exit(200)
end

return user4_router