local DB = require("app2.lib.mysql")
local config = require("app2.config.config")
local db = DB:new()
local money_model = {}

function money_model:select_credit_log(uid, from_page, limit)
    return db:query("select type,num,log_time from credit_bill_log where uid =? order by id desc limit ?,?",{uid, from_page, limit})
end

function money_model:select_coin_log(uid, from_page, limit)
    return db:query("select type,num,log_time from coin_bill_log where uid =? order by id desc limit ?,?",{uid, from_page, limit})
end

-- 开启事务
function money_model:transaction_start()
    local res, err, errno, sqlstate = db:query("START TRANSACTION")
    if not res then
        ngx.log(ngx.ERR,"START TRANSACTION failed: ", err, ": ", errno, ": ", sqlstate)
        return nil
    end
    return true
end

-- 回滚事务
function money_model:transaction_rollback()
    local res, err, errno, sqlstate = db:query("ROLLBACK")
    if not res then
        ngx.log(ngx.ERR,"ROLLBACK failed: ", err, ": ", errno, ": ", sqlstate)
        return nil
    end
    return true
end

-- 提交事务
function  money_model:transaction_commit()
    local res, err, errno, sqlstate = db:query("COMMIT")
    if not res then
        ngx.log(ngx.ERR,"COMMIT failed:", err, ": ", errno, ": ", sqlstate)
        return nil
    end
    --[[
    local ok, err = self:set_keepalive(conf.pool_config.max_idle_timeout, conf.pool_config.pool_size)
    if not ok then
        ngx.log(ngx.ERR, "failed to set keepalive: ", err)
    end
    ]]
    return true
end

function money_model:insert_exchange_log(uid,cost_coin,get_credit,cfg_id,log_time)
    return db:query("insert into coin2credit_log(uid,cost_coin,get_credit,cfg_id,log_time) values(?,?,?,?,?)",{uid,cost_coin,get_credit,cfg_id,log_time})
end

function money_model:insert_credit_log(uid,type,type_id,num,log_time)
    return db:query("insert into credit_bill_log(uid,type,type_id,num,log_time) values(?,?,?,?,?)",{uid,type,type_id,num,log_time})
end

function money_model:insert_coin_log(uid,type,type_id,num,log_time)
    return db:query("insert into coin_bill_log(uid,type,type_id,num,log_time) values(?,?,?,?,?)",{uid,type,type_id,num,log_time})
end

function money_model:select_uplevel_log(uid)
    return db:query("select log_time from uplevel_log where uid=? order by id  desc limit 1",{uid})
end

function money_model:insert_uplevel_log(uid,email,now_level,log_time,url)
    return db:query("insert into uplevel_log(uid,email,now_level,log_time,url) values(?,?,?,?,?)",{uid,email,now_level,log_time,url})
end

function money_model:select_getmoney_log(uid)
    return db:query("select log_time from getmoney_log where uid=? order by id desc limit 1",{uid})
end

function money_model:insert_getmoney_log(uid,email,status,cost_coin,get_usd,log_time,finish_time)
    return db:query("insert into getmoney_log(uid,email,status,cost_coin,get_usd,log_time,finish_time) values(?,?,?,?,?,?,?)",{uid,email,status,cost_coin,get_usd,log_time,finish_time})
end

function money_model:insert_payload(uid,my_type,status,package_name,consume_state,payload,order_id,usd,credit,extra_credit,pub_id,product_id,purchase_time,log_time,order_time,vip,vip_time)
    return db:query("insert into usd_purchase_log(uid,type,status,package_name,consume_state,payload,order_id,usd,credit,extra_credit,pub_id,product_id,purchase_time,log_time,order_time,vip,vip_time) values(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",{uid,my_type,status,package_name,consume_state,payload,order_id,usd,credit,extra_credit,pub_id,product_id,purchase_time,log_time,order_time,vip,vip_time})
end

function money_model:select_payload(order_time)
    return db:query("select  *  from  usd_purchase_log where order_time=? limit 1",{order_time})
end

function money_model:update_payload(status,package_name,consume_state,order_id,purchase_time,log_time,id)
    return db:query("update usd_purchase_log set status=?,package_name=?,consume_state=?,order_id=?,purchase_time=?,log_time=? where id=? limit 1", {status,package_name,consume_state,order_id,purchase_time,log_time,id})
end

function money_model:select_old_payload(uid,pub_id,product_id,my_type)
    return db:query("select  payload  from  usd_purchase_log where  uid=? and type=? and status=0 and pub_id=? and  product_id=? limit 1",{uid,my_type,pub_id,product_id})
end

function money_model:insert_weixin_payload(uid,type,status,appid,mch_id,prepay_id,order_id,nonce_str,sign,trade_type,body,total_fee,credit,extra_credit,pub_id,product_id,finish_time,log_time,ip,uniq_id)
    return db:query("insert into rmb_purchase_log(uid,type,status,appid,mch_id,prepay_id,order_id,nonce_str,sign,trade_type,body,total_fee,credit,extra_credit,pub_id,product_id,finish_time,log_time,ip,uniq_id) values(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",{uid,type,status,appid,mch_id,prepay_id,order_id,nonce_str,sign,trade_type,body,total_fee,credit,extra_credit,pub_id,product_id,finish_time,log_time,ip,uniq_id})
end

function money_model:select_weixin_payload(uid,prepay_id)
    return db:query("select  id,appid,mch_id,credit,extra_credit,status  from  rmb_purchase_log where  uid=? and prepay_id=? limit 1",{uid,prepay_id})
end

function money_model:update_weixin_payload(status,finish_time,id)
    if finish_time then
        return db:query("update rmb_purchase_log set status=?,finish_time=? where id=? limit 1", {status,finish_time,id})
    else
        return db:query("update rmb_purchase_log set status=? where id=? limit 1", {status,id})
    end 
end

function money_model:select_weixin_payload_notify(order_id)
    return db:query("select  id,uid,appid,mch_id,credit,extra_credit,total_fee,status,prepay_id  from  rmb_purchase_log where order_id=? limit 1",{order_id})
end

function money_model:update_weixin_payload_notify(status,finish_time,prepay_id)
    return db:query("update rmb_purchase_log set status=?,finish_time=? where prepay_id=? limit 1", {status,finish_time,prepay_id})
end

function money_model:select_paypal_payload(order_time)
    return db:query("select  id,status,credit,extra_credit,uid,type,payload,usd,vip,vip_time from  usd_purchase_log where order_time=? limit 1",{order_time})
end

function money_model:update_paypal_payload(status,finish_time,id,payid)
    if finish_time then
        return db:query("update usd_purchase_log set status=?,log_time=? where id=? limit 1", {status,finish_time,id})
    else
        return db:query("update usd_purchase_log set status=? where id=? limit 1", {status,id})
    end 
end

function money_model:update_paypal_payload_info(status,id,payid)
    return db:query("update usd_purchase_log set status=?,order_id=? where id=? limit 1", {status,payid,id})
end

function money_model:insert_vip_log(uid,voucher_id,now_time,expire_time)
    return db:query("insert into vip_time_log(uid,type_id,start_time,expire_time) values(?,?,?,?)",{uid,voucher_id,now_time,expire_time})
end

return money_model