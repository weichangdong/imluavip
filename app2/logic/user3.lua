local user3_router = {}
local redis = require("app2.lib.redis")
local config = require("app2.config.config")
local my_redis = redis:new()
local mysql_user = require("app2.model.user")
local mysql_user_extend = require("app2.model.user_extend")
local mysql_money = require("app2.model.money")
local ngx = ngx
local md5 = ngx.md5
local exit = ngx.exit
local utils = require("app2.lib.utils")
local json = require("cjson.safe")
local send_email = require("app2.lib.email")
local table_object = json.encode_empty_table_as_object

local tinsert = table.insert
local tsort = table.sort
local tonumber = tonumber
local tostring = tostring
local match = string.match
local slen = string.len
local pairs = pairs
local ipairs = ipairs
local io = io
local os = os
local string = string
local ngx_quote_sql_str = ngx.quote_sql_str
local shared_cache = ngx.shared.fresh_token_limit
local COIN_LOG_TYPE = 1
local CREDIT_LOG_TYPE = 2
local MAX_LIMIT_NUM = 20

local LOG_FROM_MONEY = 1
local LOG_FROM_MONEY_EXTRA = 2
local LOG_FROM_EXCHANGE = 3
local LOG_FROM_CONSUME = 4
local LOG_FROM_GET_MONEY = 5
local LOG_FROM_DAILY_GIFT = 6

user3_router.money2credit_config = function(req, res, next)
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
    local pub_id = post_data['cid']
    utils.check_para(pub_id)
    local version_code = post_data['ver_code'] or 0
    local give_data = 0
    if version_code > config.version_code_check then
        give_data = 1
    end
    local info = my_redis:hgetall(config.redis_key.money2credit_config_key..pub_id)
    if utils.is_redis_null_table(info) then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local is_buy = 0
    local pay_type_tmp = my_redis:hget(config.redis_key.user_prefix .. myuid,"payed")
    if not utils.is_redis_null(pay_type_tmp) and  pay_type_tmp == "2"  then
        is_buy = 1
    end
    local data_len = #info
    local data = {}
    for i = 1, data_len, 2 do
        local one = json.decode(info[i + 1])
        if give_data == 0 and one.vip == 0 then
            tinsert(data, one)
        end
        if give_data == 1 then
            if is_buy == 1 then
                if one.vip ~= 2 then
                    tinsert(data, one)
                end
            else
                tinsert(data, one)
            end
        end
    end
    tsort(data, function(a, b)
        if a.credit < b.credit then
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

user3_router.coin2credit_config = function(req, res, next)
    local info = my_redis:hgetall(config.redis_key.coin2credit_config_key)
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

-- 点数收入支出log
user3_router.credit_log = function(req, res, next)
    local myuid = req.params.uid
    local page = tonumber(req.params.page)
    local re = {}
    if not page or page == "" or page < 1 then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local limit = tonumber(req.params.limit)
    if not limit or limit > MAX_LIMIT_NUM then
        limit = 10
    end
    local from_page = (page - 1) * limit
    local data = mysql_money:select_credit_log(myuid, from_page, limit)
    local ok_data = {}
    for k, v in pairs(data) do
        local one = {
            time = v.log_time,
            type = v.type,
            credit = v.num
        }
        tinsert(ok_data, one)
    end
    local dat = {
        list = ok_data
    }
    local aes_dat = utils.encrypt(dat, req.query.aes)
    re["ret"] = 0
    re["dat"] = aes_dat
    res:json(re)
    exit(200)
end

-- 金币收入支出log
user3_router.coin_log = function(req, res, next)
    local myuid = req.params.uid
    local page = tonumber(req.params.page)
    local re = {}
    if not page or page == "" or page < 1 then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local limit = tonumber(req.params.limit)
    if not limit or limit > MAX_LIMIT_NUM then
        limit = 10
    end
    local from_page = (page - 1) * limit
    local data = mysql_money:select_coin_log(myuid, from_page, limit)
    local ok_data = {}
    for k, v in pairs(data) do
        local one = {
            time = v.log_time,
            type = v.type,
            coin = v.num
        }
        tinsert(ok_data, one)
    end
    re["ret"] = 0
    local dat = {
        list = ok_data
    }
    local aes_dat = utils.encrypt(dat, req.query.aes)
    re["dat"] = aes_dat
    res:json(re)
    exit(200)
end

-- 金币兑换成点数
user3_router.coin_to_credit = function(req, res, next)
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
    local id = post_data["id"]
    utils.check_para(id)
    local uniq = post_data["uniq"]
    if not uniq or uniq == "" or slen(uniq) ~= 32 then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local cfg_info_tmp = my_redis:hget(config.redis_key.coin2credit_config_key, id)
    if utils.is_redis_null(cfg_info_tmp) then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local cfg_info = json.decode(cfg_info_tmp)
    local need_coin = cfg_info.coin
    local get_credit = cfg_info.credit
    local base_info_tmp = my_redis:hget(config.redis_key.user_prefix .. myuid, "base_info")
    if utils.is_redis_null(base_info_tmp) then
        ngx.log(ngx.ERR, "==[no base info] func:coin_to_credit uid:" .. myuid .. "==")
        ngx.print('{"ret":5}')
        exit(200)
    end
    local base_info = json.decode(base_info_tmp)
    local my_uniq = base_info["uniq"]
    if my_uniq ~= uniq then
        re["ret"] = 17
        res:json(re)
        exit(200)
    end

    local user_extend_info = mysql_user_extend:select_user_info(myuid)
    local db_now_coin = user_extend_info[1].coin
    local db_now_credit = user_extend_info[1].credit
    if db_now_coin < need_coin then
        ngx.print('{"ret":16}')
        exit(200)
    end
    local op = 0
    local select2_re, update2_re = {}, {}
    mysql_money:transaction_start()
    -- do deduce coin
    local update1_re, select1_re = mysql_user_extend:update_user_coin(myuid, -need_coin)
    if not update1_re then
        mysql_money:transaction_rollback()
        op = 18
    --elseif update1_re.affected_rows == 1 and select1_re and select1_re[1].coin + need_coin == db_now_coin then
    elseif update1_re.affected_rows == 1 and select1_re and select1_re[1].coin  then
        -- do add credit
        update2_re, select2_re = mysql_user_extend:update_user_credit(myuid, get_credit)
        --if update2_re.affected_rows == 1 and select2_re[1].credit == db_now_credit + get_credit then
        if update2_re.affected_rows == 1 and select2_re[1].credit  then
            mysql_money:transaction_commit()
        else
            mysql_money:transaction_rollback()
            op = 18
        end
    else
        mysql_money:transaction_rollback()
        op = 18
    end

    if op == 18 then
        ngx.print('{"ret":18}')
        exit(200)
    end

    local re_coint = db_now_coin
    if select1_re and select1_re[1] then
        re_coint = select1_re[1].coin
    end

    local re_credit = db_now_credit
    if select2_re and select2_re[1] then
        re_credit = select2_re[1].credit
    end
    local log_time = ngx.time()
    local result = mysql_money:insert_exchange_log(myuid, need_coin, get_credit, id, log_time)
    if result and result.insert_id then
        -- 扣除金币log
        mysql_money:insert_coin_log(myuid, LOG_FROM_EXCHANGE, result.insert_id, -need_coin, log_time)
        -- 增加点数log
        mysql_money:insert_credit_log(myuid, LOG_FROM_EXCHANGE, result.insert_id, get_credit, log_time)
    else
        -- 扣除金币log
        mysql_money:insert_coin_log(myuid, LOG_FROM_EXCHANGE, 0, -need_coin, log_time)
        -- 增加点数log
        mysql_money:insert_credit_log(myuid, LOG_FROM_EXCHANGE, 0, get_credit, log_time)
        local log_info = "==[exchange insert log error] uid:" .. myuid .. "cfg_id:" .. id .. "=="
        ngx.log(ngx.ERR, log_info)
    end

    re["ret"] = 0
    local dat = {
        credit = re_credit,
        coin = re_coint
    }
    local aes_dat = utils.encrypt(dat, req.query.aes)
    re["dat"] = aes_dat
    res:json(re)
    exit(200)
end

user3_router.up_level = function(req, res, next)
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
    local email = post_data["email"]
    utils.check_para(email)
    if not utils.check_email(email) then
        ngx.print('{"ret":6}')
        exit(200)
    end
    local url = post_data["url"] or ""
    local log_time = ngx.time()
    local last_do_time = mysql_money:select_uplevel_log(myuid)
    if not utils.is_table_empty(last_do_time) then
        if log_time - last_do_time[1].log_time < 86400 then
            ngx.print('{"ret":19}')
            exit(200)
        end
    end
    local user_extend_info = mysql_user_extend:select_user_info(myuid)
    local db_now_level = user_extend_info[1].level
    mysql_money:insert_uplevel_log(myuid, email, db_now_level, log_time, url)
    --[[
    local title = "Anchor re-rating"
    local content = "uid:"..myuid.." email:"..email .." current level:"..db_now_level
    local send_re = send_email.doSend(title, content, config.customer_service_email)
    ]]
    ngx.print('{"ret":0}')
    exit(200)
end

user3_router.get_money = function(req, res, next)
    local myuid = req.params.uid
    local raw_post_data = req.body
    utils.check_para(raw_post_data)
    local raw_post_data = utils.decrypt(raw_post_data, req.query.aes)
    local post_data = json.decode(raw_post_data)
    if utils.is_table_empty(post_data) then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local email = post_data["email"]
    utils.check_para(email)
    if not utils.check_email(email) then
        ngx.print('{"ret":6}')
        exit(200)
    end
    local log_time = ngx.time()
    local last_do_time = mysql_money:select_getmoney_log(myuid)
    if not utils.is_table_empty(last_do_time) then
        if log_time - last_do_time[1].log_time < 86400 then
            ngx.print('{"ret":20}')
            exit(200)
        end
    end
    mysql_money:insert_getmoney_log(myuid,email,0,0,0,log_time,0)
    local title = "I want to get money"
    local content = "uid:"..myuid.." email:"..email
    local send_re = send_email.doSend(title, content, config.customer_service_email)
    ngx.print('{"ret":0}')
    exit(200)
end

user3_router.daily_gift = function(req, res, next)
    ngx.print('{"ret":21}')
    exit(200)
    local re = {}
    local myuid = req.params.uid
    local log_time = ngx.time()
    local today = os.date("%Y%m%d", log_time - 57600)
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
                get_credit = config.daily_gift_num
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
end

user3_router.session_info = function(req, res, next)
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
    local session_id = post_data["sess_id"]
    utils.check_para(session_id)
    local sess_info_tmp = my_redis:hmget(config.redis_key.session_is_key .. session_id,"spent","cost","earn","giftcost","giftearn")
    if utils.is_redis_null_table(sess_info_tmp) then
        ngx.sleep(3)
        sess_info_tmp = my_redis:hmget(config.redis_key.session_is_key .. session_id,"spent","cost","earn","giftcost","giftearn")
        if utils.is_redis_null_table(sess_info_tmp) then
            ngx.print('{"ret":23}')
            exit(200)
        end
    end
    
    local time_long = sess_info_tmp[1]
    local cost = sess_info_tmp[2]
    local earn = sess_info_tmp[3]
    local gift_cost = sess_info_tmp[4]
    local gift_earn = sess_info_tmp[5]
    local money_info = mysql_user_extend:select_user_info(myuid)
    if not money_info or not money_info[1] then
        ngx.print('{"ret":5}')
        exit(200)
    end
    local now_credit = money_info[1].credit
    re["ret"] = 0
    local dat = {
        time = tonumber(time_long),
        credit = tonumber(now_credit),
        cost = tonumber(cost) or 0,
        earn = tonumber(earn) or 0,
        giftcost = tonumber(gift_cost) or 0,
        giftearn = tonumber(gift_earn) or 0,
    }
    local aes_dat = utils.encrypt(dat, req.query.aes)
    re['dat'] = aes_dat
    res:json(re)
    exit(200)
end

user3_router.my_wallet = function(req, res, next)
    local re = {}
    local myuid = req.params.uid
    local money_info = mysql_user_extend:select_user_info(myuid)
    if utils.is_table_empty(money_info) then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local now_coin = money_info[1].coin
    local now_credit = money_info[1].credit
    local now_total_income = money_info[1].total_income
    local vip_etime = money_info[1].vip_etime
    local remain_time = 0
    local now_time = ngx.time()
    if vip_etime > now_time then
        remain_time = vip_etime - now_time
    end
    re["ret"] = 0
    local dat = {
        credit = now_credit,
        total_income = now_total_income,
        coin = now_coin,
        remain = remain_time
    }
    local aes_dat = utils.encrypt(dat, req.query.aes)
    re['dat'] = aes_dat
    res:json(re)
    exit(200)
end

user3_router.set_coin_credit = function(req, res, next)
    local re = {}
    local myuid = req.params.uid
    local raw_post_data = req.body
    utils.check_para(raw_post_data)
    local raw_post_data = utils.decrypt(raw_post_data, req.query.aes)
    local post_data = json.decode(raw_post_data)
    local coin = post_data["coin"]
    local credit = post_data["credit"]
    if not coin or coin < 0  or not credit or  credit < 0 then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local update1_re = mysql_user_extend:update_user_coin_credit(myuid,coin,credit)
    if update1_re.affected_rows == 1 then
        ngx.print('{"ret":0}')
        exit(200)
    end
    ngx.print('{"ret":5}')
    exit(200)
end

user3_router.test_jia_me = function(req, res, next)
    local raw_post_data = req.body
    utils.check_para(raw_post_data)
    local raw_post_data = utils.encrypt(raw_post_data, nil)
    ngx.say(raw_post_data)
end

user3_router.test_jie_me = function(req, res, next)
    local raw_post_data = req.body
    utils.check_para(raw_post_data)
    local raw_post_data = utils.decrypt(raw_post_data, nil)
    ngx.say(raw_post_data)
end

user3_router.reset_email = function(req, res, next)
    local raw_post_data = req.body
    utils.check_para(raw_post_data)
    local post_data = json.decode(raw_post_data)
    local email = post_data.email or nil
    local uid = post_data.uid or nil
    if email then
        mysql_user:update_user_email(email,nil)
        ngx.say(email.." email reset ok")
    elseif uid then
        mysql_user:update_user_email(nil,uid)
        ngx.say(uid.." fb reset ok")
    end
end

return user3_router