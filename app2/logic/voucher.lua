local voucher_router = {}
local redis = require("app2.lib.redis")
local config = require("app2.config.config")
local my_redis = redis:new()
local mysql_user = require("app2.model.user")
local mysql_user_extend = require("app2.model.user_extend")
local mysql_money = require("app2.model.money")
local ngx = ngx
local md5 = ngx.md5
local exit = ngx.exit
local sleep = ngx.sleep
local pay_utils = require("app2.lib.pay_utils")
local utils = require("app2.lib.utils")
local uuid = require("app2.lib.uuid")
local u_cipher = require "app2.lib.cipher"
local json = require("cjson.safe")
local http = require "resty.http"
local pcall = pcall
local ssl = require "ssl"
local myhttps = require "ssl.https"

local tinsert = table.insert
local tconcat = table.concat
local tsort = table.sort
local tonumber = tonumber
local tostring = tostring
local match = string.match
local sgsub = string.gsub
local slen = string.len
local sfind = string.find
local ssub = string.sub
local pairs = pairs
local ipairs = ipairs
local io = io
local os = os
local string = string

local LOG_FROM_MONEY = 1
local LOG_FROM_MONEY_EXTRA = 2

local send_msg = function(content)
    local url = "http://wcd.360safe.com/wcd.php"
    local httpc = http.new()
    httpc:set_timeout(30000)
    local content = content or "google access token error"
    local result, err = httpc:request_uri(url, {
        ssl_verify = false,
        method = "POST",
        body = "key=wcd&mobile=1111111111111&content="..content,
        headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded; charset=UTF-8",
        }
    })
end

local get_access_token = function()
    local logger = require("app2.lib.logger")
    logger.close()
    logger.new(config.save_log.important_log_file)
    local url = config.voucher.google_url
    local httpc = http.new()
    httpc:set_timeout(90000)
    local result, err = httpc:request_uri(url, {
        ssl_verify = false,
        method = "POST",
        body = "grant_type=refresh_token&client_id="..config.voucher.client_id.."&client_secret="..config.voucher.client_secret.."&refresh_token="..config.voucher.refresh_token,
        headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded; charset=UTF-8",
        }
    })
    local log_info
    if not result then
        log_info = "[access token] failed to request: " ..err
        logger.info(log_info)
        return nil
    end
    --请求之后，状态码
    local status = result.status
    local reason = result.reason
    if status ~= 200 then
        log_info = "[google access token] status error status: " ..status .." reason:".. reason
        logger.info(log_info)
        return nil
    elseif not result.body then
        log_info = "[google access token] access_token error reason:".. reason
        logger.info(log_info)
        return nil
    else
        local ok_body = json.decode(result.body)
        local access_token = ok_body.access_token
        local expires_in = ok_body.expires_in - 2
        my_redis:setex(config.redis_key.access_token_key, expires_in, access_token)
        return access_token,expires_in
    end
end

local function google_order_verify(product_id,package_name,purchase_token)
    local access_token
    access_token = my_redis:get(config.redis_key.access_token_key)
    if utils.is_redis_null(access_token) then
        access_token = get_access_token()
        if not access_token then
            access_token = get_access_token()
            if not access_token then
                return 4
            end
        end
    end
    local logger = require("app2.lib.logger")
    logger.close()
    logger.new(config.save_log.voucher_check_log_file)
    local ok_url = "https://www.googleapis.com/androidpublisher/v2/applications/"..package_name.."/purchases/products/"..product_id.."/tokens/"..purchase_token.."?access_token="..access_token
    local httpc = http.new()
    httpc:set_timeout(90000)
    local result, err = httpc:request_uri(ok_url, {
        ssl_verify = false,
        method = "GET",
        headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded; charset=UTF-8",
        }
    })
    if not err then
        err = ''
    end
    local log_voucher_info = "[google verify error 1] package_name:"..package_name.." purchase_token:"..purchase_token.."error_info:"..err.."reason:"..result.reason
        logger.info(log_voucher_info)
    if not result then
        -- todo  log
        local log_voucher_info = "[google verify error 1] package_name:"..package_name.." purchase_token:"..purchase_token.."error_info:"..err
        logger.info(log_voucher_info)
        return 1,err
    end
    --请求之后，状态码
    local status = result.status
    local reason = result.reason
    if status ~= 200 then
        local log_voucher_info = "[google verify error 2] package_name:"..package_name.." purchase_token:"..purchase_token.."reason:"..reason
        logger.info(log_voucher_info)
        return 2,reason
    elseif not result.body then
        return 3,reason
    end
    return 0,result.body
end

local function google_order_verify_wcd(product_id,package_name,purchase_token)
    local access_token
    access_token = my_redis:get(config.redis_key.access_token_key)
    if utils.is_redis_null(access_token) then
        access_token = get_access_token()
        if not access_token then
            access_token = get_access_token()
            if not access_token then
                return 4
            end
        end
    end
    local logger = require("app2.lib.logger")
    logger.close()
    logger.new(config.save_log.voucher_check_log_file)
    local ok_url = "https://www.googleapis.com/androidpublisher/v2/applications/"..package_name.."/purchases/products/"..product_id.."/tokens/"..purchase_token.."?access_token="..access_token
    local body, code = myhttps.request(ok_url)
    if code ~= 200 then
        local log_voucher_info = "[google verify error] package_name:"..package_name.." purchase_token:"..purchase_token.."code:"..code
        logger.info(log_voucher_info)
        return 2,'http code error'
    elseif not body then
        return 3,'body empty'
    end
    return 0,body
end

local function purchase_verify(sign_content, sig) 
    local pub_key = u_cipher.trans_rsa_pub_key(config.voucher.google_public_key)
    return u_cipher.verify_rsa_sign(sign_content, sig, pub_key, "RSA-SHA1")
end

voucher_router.google_paypal_get_payload = function(req, res, next)
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
    local id = post_data['id']
    utils.check_para(id)
    local my_type = post_data['type'] or 0
    if my_type ~= 1 and my_type ~= 0 then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local info_tmp = my_redis:hget(config.redis_key.money2credit_config_key..pub_id, id)
    if utils.is_redis_null(info_tmp) then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local info = json.decode(info_tmp)
    local usd = info.usd
    local credit = info.credit
    local extra_credit = info.extra_credit
    local product_id = info.product_id
    local is_vip = info.vip
    local vip_time = info.vip_time

    local old_result = mysql_money:select_old_payload(myuid,pub_id,product_id,my_type)
    if not utils.is_table_empty(old_result) and not utils.is_table_empty(old_result[1]) and old_result[1].payload then
        re["ret"] = 0
        local dat = {
            payload = old_result[1].payload
        }
        local aes_dat = utils.encrypt(dat, req.query.aes)
        re["dat"] = aes_dat
        res:json(re)
        exit(200)
    end

    local status,consume_state,purchase_time = 0,0,0
    local package_name,order_id = '',''
    local log_time = ngx.time()
    ngx.update_time()
    local order_time = ngx.now() *  1000 .. my_type
    local payload_num = uuid.generate()..'-'..order_time

    local result = mysql_money:insert_payload(myuid,my_type,status,package_name,consume_state,payload_num,order_id,usd,credit,extra_credit,pub_id,product_id,purchase_time,log_time,order_time,is_vip,vip_time)
    if result and result.insert_id then
        re["ret"] = 0
        local dat = {
            payload = payload_num
        }
        local aes_dat = utils.encrypt(dat, req.query.aes)
        re["dat"] = aes_dat
        res:json(re)
        exit(200)
    else
        ngx.print('{"ret":5}')
        exit(200)
    end
end

voucher_router.google_pay_verify = function(req, res, next)
    local re = {}
    local myuid = tonumber(req.params.uid)
    local raw_post_data = req.body
    utils.check_para(raw_post_data)
    local raw_post_data = utils.decrypt(raw_post_data, req.query.aes)
    local post_data = json.decode(raw_post_data)
    if utils.is_table_empty(post_data) then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local sig = post_data.sign_data
    utils.check_para(sig)
    local sign_content = post_data.purchase_data
    utils.check_para(sign_content)
    local ok_sign_content = json.decode(sign_content)
    if not ok_sign_content then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local ok = purchase_verify(sign_content, sig)
    local logger = require("app2.lib.logger")
    logger.close()
    logger.new(config.save_log.voucher_check_log_file)

    if not ok then
        local log_voucher_info = "[google local verify error] uid:"..myuid.." sig:"..sig.."  sign_content:"..sign_content
        logger.info(log_voucher_info)
        ngx.print('{"ret":25}')
        exit(200)
    end
    local log_time = ngx.time()
    local payload_num = ok_sign_content.developerPayload
    local last_pos = sfind(payload_num, "-[^-]*$")
    local order_time = ssub(payload_num, last_pos+1)
    local voucher_info_tmp = mysql_money:select_payload(order_time)
    if utils.is_table_empty(voucher_info_tmp) or utils.is_table_empty(voucher_info_tmp[1]) or not voucher_info_tmp[1].id then
        local log_voucher_info = "[google select payload  from  mysql error] uid:"..myuid.." order_time:"..order_time.." payload_num:"..payload_num
        logger.info(log_voucher_info)
        ngx.print('{"ret":3}')
        exit(200)
    end
    local voucher_info = voucher_info_tmp[1]
    if voucher_info.status ~= 0 then
        ngx.print('{"ret":27}')
        exit(200)
    end
    if  voucher_info.payload ~= payload_num then
        local log_voucher_info = "[google payload num not equal error] uid:"..myuid.." db-uid:".. voucher_info.uid.."  db-data:"..voucher_info.payload .. " input-data:"..payload_num
        logger.info(log_voucher_info)
        ngx.print('{"ret":3}')
        exit(200)
    end
    local order_id = ok_sign_content.orderId
    local package_name = ok_sign_content.packageName
    local purchase_time = ok_sign_content.purchaseTime
    local purchase_token = ok_sign_content.purchaseToken
    local product_id = ok_sign_content.productId
    local add_credit_num = voucher_info.credit
    local add_extra_credit_num = voucher_info.extra_credit
    local is_vip = voucher_info.vip
    local vip_time = voucher_info.vip_time
    local total_add_credit_num = add_credit_num
    local usd = voucher_info.usd
    if add_extra_credit_num > 0 then
        total_add_credit_num = total_add_credit_num + add_extra_credit_num
    end
    local ok,ok_re,google_re_tmp
    ok,ok_re,google_re_tmp = pcall(google_order_verify_wcd, product_id,package_name,purchase_token)
    if not ok then
        sleep(0.1)
        ok,ok_re,google_re_tmp = pcall(google_order_verify_wcd, product_id,package_name,purchase_token)
        if not ok then
            sleep(0.1)
            ok,ok_re,google_re_tmp = pcall(google_order_verify_wcd, product_id,package_name,purchase_token)
            if not ok then
                local log_voucher_info = "[google http error retry-3]"
                logger.info(log_voucher_info)
            end
        end
    end
    if ok_re == 0 then --if-1
        local google_re = json.decode(google_re_tmp)
        if google_re.orderId == order_id and google_re.developerPayload == payload_num and google_re.purchaseState == 0  then --if-2
            local consume_state = google_re.consumptionState --消耗商品类型
            local update1_re = mysql_money:update_payload(1,package_name,consume_state,order_id,purchase_time,log_time,voucher_info.id)
            if update1_re and update1_re.affected_rows == 1 then --if-3
                if is_vip == 0 then  --if-4
                    local update2_re, select2_re = mysql_user_extend:update_user_credit(voucher_info.uid, total_add_credit_num)
                    if update2_re and update2_re.affected_rows == 1  then
                        mysql_user_extend:update_user_pay_num(usd,voucher_info.uid)
                        my_redis:hsetnx(config.redis_key.user_prefix .. voucher_info.uid,"payed",1)
                        mysql_money:insert_credit_log(voucher_info.uid, LOG_FROM_MONEY, voucher_info.id, add_credit_num, log_time)
                        if add_extra_credit_num > 0 then 
                            mysql_money:insert_credit_log(voucher_info.uid, LOG_FROM_MONEY_EXTRA, voucher_info.id, add_extra_credit_num, log_time)
                        end
                        -- ok
                        local log_voucher_info = "[google voucher ok] uid:"..voucher_info.uid.." payload:"..voucher_info.payload.." db-id:"..voucher_info.id.." addcredit:"..total_add_credit_num
                        logger.info(log_voucher_info)
                        re["ret"] = 0
                        local dat = {
                            add_credit = total_add_credit_num,
                            now_redit = select2_re[1].credit,
                            voucher_uid = voucher_info.uid,
                            current_uid = myuid,
                            vip = 0
                        }
                        local aes_dat = utils.encrypt(dat, req.query.aes)
                        re["dat"] = aes_dat
                        res:json(re)
                        exit(200)
                    else
                        -- add  credit error
                        mysql_money:update_payload(3,package_name,consume_state,order_id,purchase_time,log_time,voucher_info.id)
                        local log_voucher_info = "[google voucher add credit error] uid:"..myuid.." payload:"..voucher_info.payload.." db-id:"..voucher_info.id
                        logger.info(log_voucher_info)
                        ngx.print('{"ret":26}')
                        exit(200)
                    end
                elseif is_vip == 1 and vip_time > 0 then --if-4
                    local now_time = ngx.time()
                    local vip_expire_time = now_time + vip_time
                    local vip_user_key = config.redis_key.vip_user_key..voucher_info.uid
                    local old_vip_time = my_redis:ttl(vip_user_key)
                    local switch = 0 --no vip or expired
                    local new_vip_time = vip_time
                    if old_vip_time > 0 then
                        switch = 1
                        new_vip_time = new_vip_time + old_vip_time
                    end
                    local update2_re = mysql_user_extend:update_user_vip(switch,voucher_info.uid, now_time, vip_expire_time, vip_time)
                    if update2_re and update2_re.affected_rows == 1  then
                        if switch == 0 then
                            my_redis:setex(vip_user_key,vip_time,1)
                        else
                            my_redis:expire(vip_user_key,new_vip_time)
                        end
                        mysql_user_extend:update_user_pay_num(usd,voucher_info.uid)
                        my_redis:hsetnx(config.redis_key.user_prefix .. voucher_info.uid,"payed",1)
                        mysql_money:insert_vip_log(voucher_info.uid, voucher_info.id, now_time, vip_expire_time)
                        -- ok
                        local log_voucher_info = "[google voucher vip-time ok] uid:"..voucher_info.uid.." payload:"..voucher_info.payload.." db-id:"..voucher_info.id.." add-time:"..vip_time
                        logger.info(log_voucher_info)
                        re["ret"] = 0
                        local dat = {
                            add_time = vip_time,
                            now_time = new_vip_time,
                            voucher_uid = voucher_info.uid,
                            current_uid = myuid,
                            vip = 1
                        }
                        local aes_dat = utils.encrypt(dat, req.query.aes)
                        re["dat"] = aes_dat
                        res:json(re)
                        exit(200)
                    else
                        -- add  vip-time error
                        mysql_money:update_payload(3,package_name,consume_state,order_id,purchase_time,log_time,voucher_info.id)
                        local log_voucher_info = "[google voucher add vip-time error] uid:"..myuid.." payload:"..voucher_info.payload.." db-id:"..voucher_info.id
                        logger.info(log_voucher_info)
                        ngx.print('{"ret":46}')
                        exit(200)
                    end
                elseif is_vip == 2 and vip_time > 0 and total_add_credit_num > 0 then --if-4
                    local ok_vip_credit = 0
                    local update2_re, select2_re = mysql_user_extend:update_user_credit(voucher_info.uid, total_add_credit_num)
                    if update2_re and update2_re.affected_rows == 1  then
                        mysql_money:insert_credit_log(voucher_info.uid, LOG_FROM_MONEY, voucher_info.id, add_credit_num, log_time)
                        if add_extra_credit_num > 0 then 
                            mysql_money:insert_credit_log(voucher_info.uid, LOG_FROM_MONEY_EXTRA, voucher_info.id, add_extra_credit_num, log_time)
                        end
                    else
                        local log_voucher_info = "[google voucher add credit-viptime credit error] uid:"..voucher_info.uid.." payload:"..voucher_info.payload.." db-id:"..voucher_info.id
                        logger.info(log_voucher_info)
                        ok_vip_credit = 1
                    end
        
                    -- add vip-time
                    local now_time = ngx.time()
                    local vip_expire_time = now_time + vip_time
                    local vip_user_key = config.redis_key.vip_user_key..voucher_info.uid
                    local old_vip_time = my_redis:ttl(vip_user_key)
                    local switch = 0 --no vip or expired
                    local new_vip_time = vip_time
                    if old_vip_time > 0 then
                        switch = 1
                        new_vip_time = new_vip_time + old_vip_time
                    end
                    local update3_re = mysql_user_extend:update_user_vip(switch,voucher_info.uid,now_time,vip_expire_time, vip_time)
                    if update3_re and update3_re.affected_rows == 1  then --if-4
                        if switch == 0 then
                            my_redis:setex(vip_user_key,vip_time,1)
                        else
                            my_redis:expire(vip_user_key,new_vip_time)
                        end
                        mysql_user_extend:update_user_pay_num(usd,voucher_info.uid)
                        my_redis:hset(config.redis_key.user_prefix .. voucher_info.uid,"payed",2)
                        mysql_money:insert_vip_log(voucher_info.uid, voucher_info.id, now_time, vip_expire_time)
                        re["ret"] = 0
                        local dat = {
                            --add_time = vip_time,
                            --now_time = new_vip_time,
                            add_credit = total_add_credit_num,
                            now_redit = select2_re[1].credit,
                            vip = 1
                        }
                        local aes_dat = utils.encrypt(dat, req.query.aes)
                        re["dat"] = aes_dat
                        res:json(re)
                        exit(200)
                    else --if-4
                        local log_voucher_info = "[google voucher add credit-viptime viptime error] uid:"..voucher_info.uid.." prepayid:"..voucher_info.payload.." db-id:"..voucher_info.id
                        logger.info(log_voucher_info)
                        ok_vip_credit = 2
                    end --if-4
                    if ok_vip_credit ~= 0 then
                        mysql_money:update_payload(3,log_time,id)
                    end
                    -- add credit error or add viptime error
                    ngx.print('{"ret":46}')
                    exit(200)
                end --if-4
            else --if-3
                local log_voucher_info = "[google voucher update_payload error] uid:"..myuid.." payload:"..voucher_info.payload.." db-id:"..voucher_info.id
                        logger.info(log_voucher_info)
                        ngx.print('{"ret":5}')
                        exit(200)
            end --if-3
        else --if-2
            -- google  check  error
            mysql_money:update_payload(2,package_name,consume_state,order_id,purchase_time,log_time,voucher_info.id)
            local log_voucher_info = "[google check error] uid:"..myuid.." google-orderId:"..google_re.orderId.." payload:"..voucher_info.payload.." google-state:"..google_re.purchaseState
            logger.info(log_voucher_info)
            ngx.print('{"ret":25}')
            exit(200)
        end --if-2
    else --if-1
        -- google  http  error
        if not google_re_tmp then
            google_re_tmp = 'no return'
        end
        mysql_money:update_payload(4,package_name,0,order_id,purchase_time,log_time,voucher_info.id)
        local log_voucher_info = "[google http error] uid:"..myuid.." google-return:"..ok_re.." error-info:"..google_re_tmp.." product_id:"..product_id .. " package_name:"..package_name.. " purchase_token:"..purchase_token
        logger.info(log_voucher_info)
        local queue_data = {
            queue_type = "gg_voucher",
            uid = myuid,
            package_name = package_name,
            product_id = product_id,
            purchase_token = purchase_token
        }
        --TODO
        --my_redis:lpush(config.redis_key.queue_list_key, json.encode(queue_data))
        ngx.print('{"ret":5}')
        exit(200)
    end --if-1
    ngx.print('{"ret":5}')
    exit(200)
end

local function weixin_prepayid(raw_post_data,raw_data)
    local logger = require("app2.lib.logger")
    logger.close()
    logger.new(config.save_log.voucher_check_log_file)
    local post_data = pay_utils.generate_xml(raw_post_data)
    local ok_url = "https://api.mch.weixin.qq.com/pay/unifiedorder"
    local re_body, code = myhttps.request(ok_url,post_data)
    if code ~= 200 then
        local log_voucher_info = "[weixin get prepayid code error] raw data:"..raw_data.."code:"..code
        logger.info(log_voucher_info)
        return 2,'http code error'
    elseif not re_body then
        local log_voucher_info = "[weixin get prepayid body error] raw data:"..raw_data
        logger.info(log_voucher_info)
        return 3,'body empty'
    end
    return 0,re_body
end

local function weixin_querypay(raw_post_data,raw_data)
    local logger = require("app2.lib.logger")
    logger.close()
    logger.new(config.save_log.voucher_check_log_file)
    local post_data = pay_utils.generate_xml(raw_post_data)
    local ok_url = "https://api.mch.weixin.qq.com/pay/orderquery"
    local re_body, code = myhttps.request(ok_url,post_data)
    if code ~= 200 then
        local log_voucher_info = "[weixin querypay code error] raw data:"..raw_data.."code:"..code
        logger.info(log_voucher_info)
        return 2,'http code error'
    elseif not re_body then
        local log_voucher_info = "[weixin querypay body error] raw data:"..raw_data
        logger.info(log_voucher_info)
        return 3,'body empty'
    end
    return 0,re_body
end

voucher_router.weixin_zhifubao_get_prepayid = function(req, res, next)
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
    --微信=1 支付宝=2
    local cfg_type = post_data['type']
    utils.check_para(cfg_type)
    local pub_id = post_data['pub_id']
    utils.check_para(pub_id)
    local cfg_id = post_data['id']
    utils.check_para(cfg_id)
    local uniq_id = post_data['uniq']
    utils.check_para(uniq_id)
    local info_tmp = my_redis:hget(config.redis_key.money2credit_config_key..pub_id, cfg_id)
    if utils.is_redis_null(info_tmp) then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local logger = require("app2.lib.logger")
    logger.close()
    logger.new(config.save_log.voucher_check_log_file)
    local info = json.decode(info_tmp)
    local total_fee = tonumber(info.rmb)
    local product_id = info.product_id
    local credit = info.credit
    local extra_credit = info.extra_credit

    local lua_nonce_str = pay_utils.generate_nonce_str()
    local ip = ngx.var.remote_addr or "127.0.0.1"
    local out_trade_no = pay_utils.generate_orderid()
    
    local raw_post_data = {
        appid = config.voucher.weixin_appid,
        mch_id = config.voucher.weixin_mch_id,
        nonce_str = lua_nonce_str,
        sign_type = "HMAC-SHA256",
        spbill_create_ip = ip,
        trade_type = "APP",
        notify_url = config.voucher.weixin_notify_url,
        body = "paramount-"..cfg_id,
        total_fee = total_fee,
        out_trade_no = out_trade_no
    }
    local raw_data,lua_sign = pay_utils.generate_sign(raw_post_data)
    raw_post_data.sign = lua_sign

    local ok,ok_re,weixin_re_tmp
    ok,ok_re,weixin_re_tmp = pcall(weixin_prepayid, raw_post_data, raw_data)
    if not ok then
        sleep(0.1)
        ok,ok_re,weixin_re_tmp = pcall(weixin_prepayid, raw_post_data, raw_data)
        if not ok then
                local log_voucher_info = "[weixin get prepayid http error retry-2]"
                logger.info(log_voucher_info)
                ngx.print('{"ret":5}')
                exit(200)
        end
    end
    if ok_re ~= 0 then
        ngx.print('{"ret":5}')
        exit(200)
    end
    local wx_data = pay_utils.parse_wxxml(weixin_re_tmp)
    if wx_data.return_code ~= "SUCCESS" then
        local log_voucher_info = "[weixin return data  error] err_code:"..wx_data.err_code.." err_des:"..wx_data.err_code_des
        logger.info(log_voucher_info)
        ngx.print('{"ret":5}')
        exit(200)
    end
    if wx_data.result_code == "NOTENOUGH" then 
        ngx.print('{"ret":30}')
        exit(200)
    elseif wx_data.result_code == "ORDERPAID" then 
       ngx.print('{"ret":31}')
        exit(200)
    elseif wx_data.result_code ~= "SUCCESS" then
        local log_voucher_info = "[weixin return data  error] result_code:"..wx_data.result_code.." err_code:"..wx_data.err_code.." err_des:"..wx_data.err_code_des
        logger.info(log_voucher_info)
        ngx.print('{"ret":5}')
        exit(200)
    end

    local check_ok = pay_utils.check_hmac_sign(wx_data)
    if not check_ok then
        local log_voucher_info = "[weixin hmac sign check error] re-body:"..weixin_re_tmp
        logger.info(log_voucher_info)
        ngx.print('{"ret":3}')
        exit(200)
    end

    local appid = wx_data.appid
    local mch_id = wx_data.mch_id
    if appid ~= raw_post_data.appid or mch_id ~= raw_post_data.mch_id then
        local log_voucher_info = "[weixin return error]"
        logger.info(log_voucher_info)
        ngx.print('{"ret":5}')
        exit(200)
    end
    local prepay_id = wx_data.prepay_id
    local noncestr = wx_data.noncestr
    local sign = wx_data.sign
    local status = 0
    local finish_time = 0
    local log_time = ngx.time()
    local result = mysql_money:insert_weixin_payload(myuid,cfg_type,status,raw_post_data.appid,raw_post_data.mch_id,prepay_id,raw_post_data.out_trade_no,noncestr,sign,raw_post_data.trade_type,raw_post_data.body,raw_post_data.total_fee,credit,extra_credit,pub_id,product_id,finish_time,log_time,ip,uniq_id)
    if not result or not result.insert_id then
        ngx.print('{"ret":5}')
        exit(200)
    end
    local data = {
        weixin = {
            appid = appid,
            partnerid = mch_id,
            prepayid = prepay_id,
            package = "Sign=WXPay",
            noncestr = noncestr,
            timestamp = log_time,
            sign = sign
        },
        zhifubao = "",
    }
    local aes_dat = utils.encrypt(data, req.query.aes)
    re["ret"] = 0
    re["dat"] = aes_dat
    res:json(re)
    exit(200)
end

-- weixin && zhifubao
voucher_router.weixin_zhifubao_pay_query = function(req,res,next)
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
    local prepayid = post_data.prepayid
    local order_info_tmp = mysql_money:select_weixin_payload(myuid,prepayid)
    if utils.is_table_empty(order_info_tmp) or utils.is_table_empty(order_info_tmp[1]) or not order_info_tmp[1].id then
        ngx.print('{"ret":5}')
        exit(200)
    end
    local logger = require("app2.lib.logger")
    logger.close()
    logger.new(config.save_log.voucher_check_log_file)
    local order_info = order_info_tmp[1]
    local id = order_info.id
    local status = order_info.status
    if status == 2 then 
        re["ret"] = 0
        local dat = {
            add_credit = order_info.credit + order_info.extra_credit
        }
        local aes_dat = utils.encrypt(dat, req.query.aes)
        re["dat"] = aes_dat
        res:json(re)
        exit(200)
    elseif status == 1 then
        ngx.print('{"ret":32}')
        exit(200)
    elseif status == 4 then
        ngx.print('{"ret":33}')
        exit(200)
    end

    local lua_nonce_str = pay_utils.generate_nonce_str()
    local raw_post_data = {
        appid = order_info.appid,
        mch_id = order_info.mch_id,
        transaction_id = prepayid,
        nonce_str = lua_nonce_str,
    }
    local raw_data,lua_sign = pay_utils.generate_sign(raw_post_data)
    raw_post_data.sign = lua_sign
    
    local ok,ok_re,weixin_re_tmp
    ok,ok_re,weixin_re_tmp = pcall(weixin_querypay, raw_post_data, raw_data)
    if not ok then
        sleep(0.1)
        ok,ok_re,weixin_re_tmp = pcall(weixin_querypay, raw_post_data, raw_data)
        if not ok then
                local log_voucher_info = "[weixin payquery http error retry-2]"
                logger.info(log_voucher_info)
                ngx.print('{"ret":5}')
                exit(200)
        end
    end
    if ok_re ~= 0 then
        ngx.print('{"ret":5}')
        exit(200)
    end
    local wx_data = pay_utils.parse_wxxml(weixin_re_tmp)
    if wx_data.return_code ~= "SUCCESS" then
        local log_voucher_info = "[weixin pay_query return_code error] err-info:"..wx_data.return_msg
        logger.info(log_voucher_info)
        ngx.print('{"ret":5}')
        exit(200)
    end
    if wx_data.result_code ~= "SUCCESS" then
        local log_voucher_info = "[weixin pay_query result_code error] err_code:"..wx_data.err_code
        logger.info(log_voucher_info)
        ngx.print('{"ret":5}')
        exit(200)
    end
    if wx_data.trade_state ~= "SUCCESS" then
        local log_voucher_info = "[weixin pay_query trade_state error] trade_state:"..wx_data.trade_state
        logger.info(log_voucher_info)
        ngx.print('{"ret":5}')
        exit(200)
    end
    local check_ok = pay_utils.check_hmac_sign(wx_data)
    if not check_ok then
        local log_voucher_info = "[weixin pay_query hmac sign check error] re-body:"..weixin_re_tmp
        logger.info(log_voucher_info)
        ngx.print('{"ret":3}')
        exit(200)
    end
    local log_time = ngx.time()
    local add_credit_num = order_info.credit
    local add_extra_credit_num = order_info.extra_credit
    local total_add_credit_num = add_credit_num
    if add_extra_credit_num > 0 then
        total_add_credit_num = total_add_credit_num + add_extra_credit_num
    end
    local update1_re = mysql_money:update_weixin_payload(1,nil,id)
    if update1_re and update1_re.affected_rows == 1 then
        local update2_re, select2_re = mysql_user_extend:update_user_credit(myuid, total_add_credit_num)
        if update2_re and update2_re.affected_rows == 1  then
            mysql_money:update_weixin_payload(2,log_time,id)
            mysql_money:insert_credit_log(myuid, LOG_FROM_MONEY, id, add_credit_num, log_time)
            if add_extra_credit_num > 0 then 
                mysql_money:insert_credit_log(myuid, LOG_FROM_MONEY_EXTRA, id, add_extra_credit_num, log_time)
            end
            local log_voucher_info = "[weixin voucher ok] uid:"..myuid.." prepayid:"..prepayid.." db-id:"..id.." addcredit:"..total_add_credit_num
            logger.info(log_voucher_info)
            re["ret"] = 0
            local dat = {
                add_credit = total_add_credit_num,
                now_redit = select2_re[1].credit,
            }
            local aes_dat = utils.encrypt(dat, req.query.aes)
            re["dat"] = aes_dat
            res:json(re)
            exit(200)
        else
            local log_voucher_info = "[weixin voucher add credit error] uid:"..myuid.." prepayid:"..prepayid.." db-id:"..id
            logger.info(log_voucher_info)
            mysql_money:update_weixin_payload(4,log_time,id)
            ngx.print('{"ret":26}')
            exit(200)
        end
    end
end

voucher_router.weixin_pay_notify = function(req, res, next)
    local re = {}
    local ok_re = "<xml><return_code>SUCCESS</return_code><return_msg>OK</return_msg></xml>"
    local err_re1 = "<xml><return_code>FAIL</return_code><return_msg>param error</return_msg></xml>"
    local err_re2 = "<xml><return_code>FAIL</return_code><return_msg>sign error</return_msg></xml>"
    local raw_post_data = req.body
    local wx_data = pay_utils.parse_wxxml(raw_post_data)
    if not wx_data or wx_data.return_code ~= "SUCCESS" or not wx_data.appid or not  wx_data.transaction_id or not wx_data.out_trade_no or wx_data.result_code ~= "SUCCESS" then
        ngx.print(err_re1)
        exit(200)
    end
    local logger = require("app2.lib.logger")
    logger.close()
    logger.new(config.save_log.voucher_check_log_file)
    local check_ok = pay_utils.check_hmac_sign(wx_data)
    if not check_ok then
        local log_voucher_info = "[wxpay_notify hmac sign check error] re-body:"..raw_post_data
        logger.info(log_voucher_info)
        ngx.print(err_re2)
        exit(200)
    end

    local order_info_tmp = mysql_money:select_weixin_payload_notify(wx_data.out_trade_no)
    if utils.is_table_empty(order_info_tmp) or utils.is_table_empty(order_info_tmp[1]) or not order_info_tmp[1].id then
        local log_voucher_info = "[wxpay_notify select order info error] order-id:"..wx_data.out_trade_no
        logger.info(log_voucher_info)
        ngx.print(err_re1)
        exit(200)
    end
    --status 0:init 1:doing 2:ok 3:notify-sign-error 4:add-credit-error
    if order_info_tmp.status == 2 then
        ngx.print(ok_re)
        exit(200)
    end
    local order_info = order_info_tmp[1]
    if order_info.prepay_id ~= wx_data.transaction_id or  wx_data.appid ~= order_info.appid or wx_data.mch_id ~= order_info.mch_id then
        local log_voucher_info = "[wxpay_notify order info not equal] prepay_id: "..wx_data.prepay_id.." transaction_id:"..wx_data.transaction_id
        logger.info(log_voucher_info)
        ngx.print(err_re1)
        exit(200)
    end

    local queue_data = {
            queue_type = "wx_voucher",
            id = order_info.id
    }
    my_redis:lpush(config.redis_key.queue_list_key, json.encode(queue_data))
    ngx.print(ok_re)
    exit(200)
end

local get_paypal_access_token = function()
    local logger = require("app2.lib.logger")
    logger.close()
    logger.new(config.save_log.important_log_file)
    local url = "https://"..config.voucher.paypal_client_id..":"..config.voucher.paypal_secret.."@"..config.voucher.paypal_access_token_url
    local post_data = "grant_type=client_credentials"
    local body, code = myhttps.request(url,post_data)
    if code ~= 200 then
        local log_voucher_info = "[paypal get token error] error code :"..code
        logger.info(log_voucher_info)
        return 2,'http code error'
    elseif not body then
        local log_voucher_info = "[paypal get token error] body empty:"..code
        logger.info(log_voucher_info)
        return 3,'body empty'
    end
    local ok_body = json.decode(body)
    local access_token = ok_body.access_token
    local expires_in = ok_body.expires_in - 2
    my_redis:setex(config.redis_key.paypal_access_token_key, expires_in, access_token)
    return access_token
end

local function paypal_querypay(id)
    local logger = require("app2.lib.logger")
    logger.close()
    logger.new(config.save_log.voucher_check_log_file)
    local ok_url = config.voucher.paypal_order_select_url
    local access_token = my_redis:get(config.redis_key.paypal_access_token_key)
    if utils.is_redis_null(access_token) then
        access_token = get_paypal_access_token()
        if not access_token then
            access_token = get_paypal_access_token()
            if not access_token then
                return 4
            end
        end
    end
    local url_table = {
        headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] =  "Bearer "..access_token,
        },
        url = config.voucher.paypal_order_select_url .. id,
        method = "GET",
    }
    local re_body, code = myhttps.request(url_table)
    if code ~= 200 then
        local log_voucher_info = "[paypal_querypay_wcd code error] raw id:"..id.."code:"..code
        logger.info(log_voucher_info)
        return 2,'http code error'
    elseif not re_body then
        local log_voucher_info = "[paypal_querypay_wcd body error] raw id:"..id
        logger.info(log_voucher_info)
        return 3,'body empty'
    end
    return 0,re_body
end

local function paypal_querypay_wcd(id)
    local logger = require("app2.lib.logger")
    logger.close()
    logger.new(config.save_log.voucher_check_log_file)
    local ok_url = config.voucher.paypal_order_select_url
    local access_token = my_redis:get(config.redis_key.paypal_access_token_key)
    if utils.is_redis_null(access_token) then
        access_token = get_paypal_access_token()
        if not access_token then
            access_token = get_paypal_access_token()
            if not access_token then
                return 4,""
            end
        end
    end
    local httpc = http.new()
    httpc:set_timeout(90000)
    local result, err = httpc:request_uri(config.voucher.paypal_order_select_url .. id, {
        ssl_verify = false,
        method = "GET",
        headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] =  "Bearer "..access_token,
        }
    })
    local code = result.status
    local reason = result.reason
    local re_body = result.body or nil
    if code ~= 200 then
        local log_voucher_info = "[paypal_querypay code error] raw id:"..id.." code:"..code .. " reason:"..reason
        logger.info(log_voucher_info)
        return 2,'http code error'
    elseif not re_body then
        local log_voucher_info = "[paypal_querypay body error] raw id:"..id
        logger.info(log_voucher_info)
        return 3,'body empty'
    end
    return 0,re_body
end



voucher_router.paypal_gogogo_query = function(req,res,next)
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
    local prepayid = post_data.prepayid
    utils.check_para(prepayid)
    local payid = post_data.payid
    utils.check_para(payid)
    local last_pos = sfind(prepayid, "-[^-]*$")
    local order_time = ssub(prepayid, last_pos+1)
    local order_info_tmp = mysql_money:select_paypal_payload(order_time)
    if utils.is_table_empty(order_info_tmp) or utils.is_table_empty(order_info_tmp[1]) or not order_info_tmp[1].id then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local order_info = order_info_tmp[1]
    local id = order_info.id
    local status = order_info.status
    if order_info.type ~= 1 or order_info.payload ~= prepayid then
        ngx.print('{"ret":3}')
        exit(200)
    end
    if status == 1 then 
        re["ret"] = 0
        local uinfo = mysql_user_extend:select_user_info(myuid)
        local dat = {
            add_credit = order_info.credit + order_info.extra_credit,
            now_redit = uinfo[1].credit,
        }
        local aes_dat = utils.encrypt(dat, req.query.aes)
        re["dat"] = aes_dat
        res:json(re)
        exit(200)
    elseif status == 2 then
        ngx.print('{"ret":32}')
        exit(200)
    elseif status == 4 then
        ngx.print('{"ret":33}')
        exit(200)
    end

    --加锁逻辑
    local lock_key = config.redis_key.paypal_voucher_lock_key..prepayid
    local is_locked = my_redis:get(lock_key)
    if not utils.is_redis_null(is_locked) then
        ngx.print('{"ret":32}')
        exit(200)
    else
        my_redis:setex(lock_key, 5,id)
    end
    local logger = require("app2.lib.logger")
    logger.close()
    logger.new(config.save_log.voucher_check_log_file)
    local ok,ok_re,paypal_re_tmp
    ok,ok_re,paypal_re_tmp = pcall(paypal_querypay_wcd, payid)
    if not ok then
        sleep(0.1)
        ok,ok_re,paypal_re_tmp = pcall(paypal_querypay_wcd, payid)
        if not ok then
                local log_voucher_info = "[paypal_query http error retry-2]"
                logger.info(log_voucher_info)
                my_redis:del(lock_key)
                ngx.print('{"ret":5}')
                exit(200)
        end
    end
    if ok_re ~= 0 then
        my_redis:del(lock_key)
        ngx.print('{"ret":5}')
        exit(200)
    end

    local paypal_data = json.decode(paypal_re_tmp)
    if not paypal_data then
        my_redis:del(lock_key)
        ngx.print('{"ret":3}')
        exit(200)
    end
    if paypal_data.state ~= "approved" or paypal_data.id ~= payid then
        local log_voucher_info = "[paypal_query return data error] err-info: state"..paypal_data.state .. " prepayid:"..prepayid
        logger.info(log_voucher_info)
        my_redis:del(lock_key)
        ngx.print('{"ret":42}')
        exit(200)
    end
    local custom_id = paypal_data.transactions[1].custom or ""
    if prepayid ~= custom_id then
        local log_voucher_info = "[paypal_query return_code error] err-info: custom_id"..custom_id .. " prepayid:"..prepayid
        logger.info(log_voucher_info)
        my_redis:del(lock_key)
        ngx.print('{"ret":42}')
        exit(200)
    end
    local log_time = ngx.time()
    local add_credit_num = order_info.credit
    local add_extra_credit_num = order_info.extra_credit
    local is_vip = tonumber(order_info.vip)
    local vip_time = tonumber(order_info.vip_time)
    local usd = order_info.usd
    local total_add_credit_num = add_credit_num
    if add_extra_credit_num > 0 then
        total_add_credit_num = total_add_credit_num + add_extra_credit_num
    end
    -- update paypal info to mysql
    local update1_re = mysql_money:update_paypal_payload_info(1,id,payid)
    if update1_re and update1_re.affected_rows == 1 then --if-1
        if is_vip == 0 then --if-2
            local update2_re, select2_re = mysql_user_extend:update_user_credit(myuid, total_add_credit_num)
            if update2_re and update2_re.affected_rows == 1  then --if-3
                mysql_money:insert_credit_log(myuid, LOG_FROM_MONEY, id, add_credit_num, log_time)
                if add_extra_credit_num > 0 then 
                    mysql_money:insert_credit_log(myuid, LOG_FROM_MONEY_EXTRA, id, add_extra_credit_num, log_time)
                end
                local log_voucher_info = "[paypal voucher ok] uid:"..myuid.." prepayid:"..prepayid.." db-id:"..id.." addcredit:"..total_add_credit_num
                logger.info(log_voucher_info)
                re["ret"] = 0
                local dat = {
                    add_credit = total_add_credit_num,
                    now_redit = select2_re[1].credit,
                }
                local aes_dat = utils.encrypt(dat, req.query.aes)
                re["dat"] = aes_dat
                my_redis:del(lock_key)
                res:json(re)
                exit(200)
            else --if-3
                local log_voucher_info = "[paypal voucher add credit error] uid:"..myuid.." prepayid:"..prepayid.." db-id:"..id
                logger.info(log_voucher_info)
                mysql_money:update_paypal_payload(3,log_time,id)
                my_redis:del(lock_key)
                ngx.print('{"ret":33}')
                exit(200)
            end --if-3
        elseif  is_vip == 1 and vip_time > 0 then --if-2
            local now_time = ngx.time()
            local vip_expire_time = now_time + vip_time
            local vip_user_key = config.redis_key.vip_user_key..myuid
            local old_vip_time = my_redis:ttl(vip_user_key)
            local switch = 0 --no vip or expired
            local new_vip_time = vip_time
            if old_vip_time > 0 then
                switch = 1
                new_vip_time = new_vip_time + old_vip_time
            end
            local update2_re = mysql_user_extend:update_user_vip(switch,myuid,now_time,vip_expire_time, vip_time)
            if update2_re and update2_re.affected_rows == 1  then --if-3
                if switch == 0 then
                    my_redis:setex(vip_user_key,vip_time,1)
                else
                    my_redis:expire(vip_user_key,new_vip_time)
                end
                mysql_user_extend:update_user_pay_num(usd,myuid)
                my_redis:hsetnx(config.redis_key.user_prefix .. myuid,"payed",1)
                mysql_money:insert_vip_log(myuid, id, now_time, vip_expire_time)
                -- ok
                local log_voucher_info = "[paypal voucher vip-time ok] uid:"..myuid.." payload:"..prepayid.." db-id:"..id.." add-time:"..vip_time
                logger.info(log_voucher_info)
                re["ret"] = 0
                local dat = {
                    add_time = vip_time,
                    now_time = new_vip_time,
                    vip = 1
                }
                local aes_dat = utils.encrypt(dat, req.query.aes)
                re["dat"] = aes_dat
                res:json(re)
                exit(200)
            else --if-3
                -- add  vip-time error
                mysql_money:update_paypal_payload(3,log_time,id)
                local log_voucher_info = "[paypal voucher add vip-time error] uid:"..myuid.." payload:"..prepayid.." db-id:"..id
                logger.info(log_voucher_info)
                ngx.print('{"ret":46}')
                exit(200)
            end --if-3
        elseif is_vip == 2 and vip_time > 0 and  total_add_credit_num > 0 then --if-2
            local ok_vip_credit = 0
            local update2_re, select2_re = mysql_user_extend:update_user_credit(myuid, total_add_credit_num)
            if update2_re and update2_re.affected_rows == 1  then
                mysql_money:insert_credit_log(myuid, LOG_FROM_MONEY, id, add_credit_num, log_time)
                if add_extra_credit_num > 0 then 
                    mysql_money:insert_credit_log(myuid, LOG_FROM_MONEY_EXTRA, id, add_extra_credit_num, log_time)
                end
            else
                local log_voucher_info = "[paypal voucher add credit error] uid:"..myuid.." payload:"..prepayid.." db-id:"..id
                logger.info(log_voucher_info)
                ok_vip_credit = 1
            end

            -- add vip-time
            local now_time = ngx.time()
            local vip_expire_time = now_time + vip_time
            local vip_user_key = config.redis_key.vip_user_key..myuid
            local old_vip_time = my_redis:ttl(vip_user_key)
            local switch = 0 --no vip or expired
            local new_vip_time = vip_time
            if old_vip_time > 0 then
                switch = 1
                new_vip_time = new_vip_time + old_vip_time
            end
            local update3_re = mysql_user_extend:update_user_vip(switch,myuid,now_time,vip_expire_time, vip_time)
            if update3_re and update3_re.affected_rows == 1  then --if-3
                if switch == 0 then
                    my_redis:setex(vip_user_key,vip_time,1)
                else
                    my_redis:expire(vip_user_key,new_vip_time)
                end
                mysql_user_extend:update_user_pay_num(usd,myuid)
                my_redis:hset(config.redis_key.user_prefix .. myuid,"payed",2)
                mysql_money:insert_vip_log(myuid, id, now_time, vip_expire_time)
                re["ret"] = 0
                local dat = {
                    --add_time = vip_time,
                    --now_time = new_vip_time,
                    add_credit = total_add_credit_num,
                    now_redit = select2_re[1].credit,
                }
                local aes_dat = utils.encrypt(dat, req.query.aes)
                re["dat"] = aes_dat
                res:json(re)
                exit(200)
            else --if-3
                local log_voucher_info = "[paypal voucher add credit error] uid:"..myuid.." prepayid:"..prepayid.." db-id:"..id
                logger.info(log_voucher_info)
                ok_vip_credit = 2
            end --if-3
            if ok_vip_credit ~= 0 then
                mysql_money:update_paypal_payload(3,log_time,id)
            end
            ngx.print('{"ret":46}')
            exit(200)
        end --if-2
    else --if-1
        mysql_money:update_paypal_payload(4,log_time,id)
        local log_voucher_info = "[google update_paypal_payload error] uid:"..myuid.." id:"..id
        logger.info(log_voucher_info)
        ngx.print('{"ret":5}')
        exit(200)
    end --if-1
end

voucher_router.paypal_gogogo_notify = function(req, res, next)
    local raw_post_data = req.body_raw
    if not raw_post_data or raw_post_data == "" then
        ngx.print('error')
        exit(200)
    end
    local ok_post_data = "cmd=_notify-validate&"..raw_post_data
    local logger = require("app2.lib.logger")
    logger.close()
    logger.new(config.save_log.voucher_check_log_file)
    local log_voucher_info = "[paypal_gogogo_notify] paypal-raw-data:"..ok_post_data
    logger.info(log_voucher_info)

    local paypal_data = ngx.decode_args(ok_post_data) or nil
    if not paypal_data then
        ngx.print('error')
        logger.info("[paypal_gogogo_notify] decode_args error paypal-raw-data:"..ok_post_data)
        exit(200)
    end
    local payment_status = paypal_data.payment_status
    if payment_status ~= "Completed" or paypal_data.payer_status ~= "verified" then
        ngx.print('error')
        logger.info("[paypal_gogogo_notify] payment_status error status:"..payment_status)
        exit(200)
    end
    local custom_id = paypal_data.custom
    local last_pos = sfind(custom_id, "-[^-]*$")
    local order_time = ssub(custom_id, last_pos+1)
    local order_info_tmp = mysql_money:select_paypal_payload(order_time)
    if utils.is_table_empty(order_info_tmp) or utils.is_table_empty(order_info_tmp[1]) or not order_info_tmp[1].id then
        logger.info("[paypal_gogogo_notify] info error order_time:"..order_time)
        ngx.print('error')
        exit(200)
    elseif tonumber(order_info_tmp[1].status) ~= 0 then
        logger.info("[paypal_gogogo_notify] already-done  done-id:"..order_info_tmp[1].id .." status:"..order_info_tmp[1].status)
        ngx.print('already done')
        exit(200)
    end
    logger.info("[paypal_gogogo_notify] add2queue find-id:"..order_info_tmp[1].id)
    local queue_data = {
            queue_type = "paypal_voucher",
            data = ok_post_data,
            id = order_info_tmp[1].id,
            retry_times = 0,
            prepayid = custom_id,
            need_check_paypal = 1,
    }
    my_redis:lpush(config.redis_key.queue_list_key, json.encode(queue_data))
    exit(200)
end


voucher_router.wcd_test = function(req, res,next)
        local id = "PAY-51J179298T998292RLJG7YAI"
        local ok,error = paypal_querypay_wcd(id)
        ngx.say(ok)
        ngx.say(error)
end 

voucher_router.set_first_voucher = function(req, res,next)
    local myuid = req.params.uid
    my_redis:hset(config.redis_key.user_prefix .. myuid,"payed",0)
    ngx.say("Uid: "..myuid.." ok")
end

return  voucher_router