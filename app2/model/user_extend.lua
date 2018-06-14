local DB = require("app2.lib.mysql")
local db = DB:new()
local user_extend_model = {}

function user_extend_model:insert_user(uid,level,total_income,credit,coin)
    return db:query("insert into user_extend(uid,level,total_income,credit,coin) values(?,?,?,?,?)",{uid,level,total_income,credit,coin})
end

function user_extend_model:select_user_info(uid)
    local db = DB:new()
    return db:query("select total_income,credit,coin,level,vip_etime,pay_num from  user_extend where uid=? limit 1",{uid})
end

-- 扣除金币 有可能减为负数 但是unsigned 会阻止这个行为
function user_extend_model:update_user_coin(uid,num)
    local re1, err =  db:query("update  user_extend  set coin=coin+? where uid=? limit 1",{num,uid})
    if err then 
        --ngx.log(ngx.ERR,err)
        return nil,nil
    end
    local re2, _ =  db:query("select coin from  user_extend where uid=? limit 1",{uid})
    return re1,re2
end

-- 添加点数
function user_extend_model:update_user_credit(uid,num)
    local re1,err =  db:query("update  user_extend  set credit=credit+? where uid=? limit 1",{num,uid})
    if err then
        return nil,nil
    end
    local re2, _ =  db:query("select credit from  user_extend where uid=? limit 1",{uid})
    return re1,re2
end

function user_extend_model:update_user_credit_moments(uid,num)
    local re1,err =  db:query("update  user_extend  set credit=credit+? where uid=? and credit>=? limit 1",{num,uid,-num})
    if err then
        local re2, _ =  db:query("select credit from  user_extend where uid=? limit 1",{uid})
        return nil,re2
    end
    local re2, _ =  db:query("select credit from  user_extend where uid=? limit 1",{uid})
    return re1,re2
end

function user_extend_model:update_user_coin_credit(uid,coin,credit)
    local re1, _ =  db:query("update  user_extend  set credit=?,coin=? where uid=? limit 1",{credit,coin,uid})
    return re1
end

function user_extend_model:update_user_total_income(uid,num)
    local re1, _ =  db:query("update  user_extend  set total_income=total_income+? where uid=? limit 1",{num,uid})
    return re1
end

function user_extend_model:update_user_level(uid,level)
    local re1, _ =  db:query("update  user_extend  set level=? where uid=? limit 1",{level,uid})
    return re1
end

function user_extend_model:update_user_vip(switch,uid,vip_stime,vip_etime,vip_time)
    if switch == 0 then
        local re1,err =  db:query("update  user_extend  set vip_stime=?,vip_etime=? where uid=? limit 1",{vip_stime,vip_etime,uid})
        if err then
            return nil
        end
        return re1
    elseif switch == 1 then
        local re1,err =  db:query("update  user_extend  set vip_etime=vip_etime+? where uid=? limit 1",{vip_time,uid})
        if err then
            return nil
        end
        return re1
    end
end

function user_extend_model:update_user_pay_num(num,uid)
    local re1,err =  db:query("update user_extend set pay_num=pay_num+? where uid=? limit 1",{num,uid})
end

function user_extend_model:select_user_info_byids(uids)
    local db = DB:new()
    return db:query("select uid,total_income,credit,coin,level,vip_etime,pay_num from  user_extend where uid in ("..uids..")")
end

function user_extend_model:select_payded_users_info(query_type)
    local db = DB:new()
    if query_type == 1 then
    return db:query("select uid,total_income,credit,coin,level,vip_etime,pay_num from  user_extend where pay_num>0 order by pay_num desc")
    elseif query_type == 2  then
        return db:query("select uid,total_income,credit,coin,level,vip_etime,pay_num from  user_extend where credit>0 order by credit desc limit  1000")
    end
end
return user_extend_model