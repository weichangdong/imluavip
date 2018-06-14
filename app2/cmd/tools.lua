package.path = package.path .. ";/data/v3-p2papi/?.lua;/usr/local/luarocks/share/lua/5.1/?.lua;;"
package.cpath = package.cpath .. ";/usr/local/luarocks/lib/lua/5.1/?.so;;"
local my_redis = require("app2.lib.cmd_redis")
local config = require("app2.config.config")
local dkjson = require("app2.lib.dkjson")
local json = require("cjson")
local luasql = require "luasql.mysql"
local mysql_con = luasql.mysql()
local socket = require('socket')
--json.encode_empty_table_as_object()

local tinsert = table.insert
local tsort = table.sort
local tonumber = tonumber
local match = string.match
local ssub = string.sub
local sfind = string.find
local sformat = string.format
local pairs = pairs
local ipairs = ipairs
local io = io
local string = string
local os = os
local mrandom = math.random
local mrandomseed = math.randomseed
local md5 = require "md5"
local conn,turn_conn

local function conn_redis()
        return my_redis.connect(config.redis_config['write']['HOST'],config.redis_config['write']['PORT'])
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

local connect_turn_db = function()
         turn_conn = mysql_con:connect(config.turn_mysql.connect_config['database'],config.turn_mysql.connect_config['user'],config.turn_mysql.connect_config['password'],config.turn_mysql.connect_config['host'],config.turn_mysql.connect_config['port'])
         if not turn_conn then
           print("connect mysql turn error")
           return
        end
         turn_conn:execute "SET NAMES UTF-8"
         return turn_conn
end

local close_turn_db = function(turn_conn)
    turn_conn:close()
end

local function now_date()
        return os.date("%Y-%m-%d %H:%M:%S")
end

local function now_time()
        return os.time()
end

local function is_table_empty(t)
    if t == nil or _G.next(t) == nil then
        return true
    else
        return false
    end
end

local function weather_in_array(value, tab)
    for _, v in pairs(tab) do
        if v == value then
            return true
        end
    end
    return false
end

local re,redis_client = pcall(conn_redis)
if not re then
        print(now_date() .." redis error\n")
        os.exit()
end

local select_money2credit_config = function()
    local conn = connect_db()
    local sql = "select * from  money2credit_config"
    local cur = conn:execute(sql)
    if not cur then
        return {}
    end
    local row = cur:fetch({},"a")
    if not row then
        return {}
    end
    local re = {}
    while row do
        local id = row['id']
        re[id] = {
            usd = row.usd,
            product_id = row.product_id,
            credit = row.credit,
            extra_credit = row.extra_credit,
            cid = row.cid,
            best_seller = row.best_seller,
            vip = row.vip,
            desc = row.desc,
            vip_time = row.vip_time,
        }
        row = cur:fetch(row,"a")
    end
    cur:close()
    close_db(conn)
    return re
end

local make_money2credit_config = function()
    local db_info = select_money2credit_config()
    local ok_num = 0

    local all_cids  = redis_client:keys(config.redis_key.money2credit_config_key.."*")
    for _,redis_cid_key in pairs(all_cids) do
        redis_client:del(redis_cid_key)
    end
    for id,row in pairs(db_info) do
        local cid = row.cid
        local one = {
            id = tonumber(id),
            usd = row.usd,
            product_id = row.product_id,
            credit = tonumber(row.credit),
            extra_credit = tonumber(row.extra_credit),
            best_seller = tonumber(row.best_seller),
            vip = tonumber(row.vip),
            desc = row.desc,
            vip_time = tonumber(row.vip_time),
        }
        redis_client:hset(config.redis_key.money2credit_config_key..cid, id, json.encode(one))
        ok_num = ok_num + 1
    end
    print("ok num:"..ok_num)
end

local select_coin2credit_config = function()
    local conn = connect_db()
    local sql = "select * from  coin2credit_config"
    local cur = conn:execute(sql)
    if not cur then
        return {}
    end
    local row = cur:fetch({},"a")
    if not row then
        return {}
    end
    local re = {}
    while row do
        local id = row['id']
        re[id] = {
            coin = row.coin,
            credit = row.credit,
        }
        row = cur:fetch(row,"a")
    end
    cur:close()
    close_db(conn)
    return re
end

local select_level_config = function()
    local conn = connect_db()
    local sql = "select * from  income_level_config"
    local cur = conn:execute(sql)
    if not cur then
        return {}
    end
    local row = cur:fetch({},"a")
    if not row then
        return {}
    end
    local re = {}
    while row do
        local level = row['level']
        re[level] = {
            level = row.level,
            credit = row.credit,
        }
        row = cur:fetch(row,"a")
    end
    cur:close()
    close_db(conn)
    return re
end

local select_gift_config = function()
    local conn = connect_db()
    local sql = "select * from  gift_config"
    local cur = conn:execute(sql)
    if not cur then
        return {}
    end
    local row = cur:fetch({},"a")
    if not row then
        return {}
    end
    local re = {}
    while row do
        local id = row.id
        re[id] = {
            id = row.id,
            type = row.type,
            credit = row.credit,
            coin = row.coin,
            name = row.name,
            icon_url =  row.icon_url,
            json_url =  row.json_url,
        }
        row = cur:fetch(row,"a")
    end
    cur:close()
    close_db(conn)
    return re
end

local make_coin2credit_config = function()
    local db_info = select_coin2credit_config()
    local ok_num = 0
    
    redis_client:del(config.redis_key.coin2credit_config_key)
    for id,row in pairs(db_info) do
        local one = {
            id = tonumber(id),
            coin = tonumber(row.coin),
            credit = tonumber(row.credit),
        }
        redis_client:hset(config.redis_key.coin2credit_config_key, id, json.encode(one))
        ok_num = ok_num + 1
    end
    print("ok num:"..ok_num)
end

local do_gift_config = function()
    local db_info = select_gift_config()
    local ok_num = 0
    redis_client:del(config.redis_key.gift_config_key)
    for id,row in pairs(db_info) do
        local one = {
            id = tonumber(id),
            type = tonumber(row.type),
            coin = tonumber(row.coin),
            credit = tonumber(row.credit),
            name = row.name,
            icon_url =  row.icon_url,
            json_url =  row.json_url,
        }
        redis_client:hset(config.redis_key.gift_config_key, id, json.encode(one))
        ok_num = ok_num + 1
    end
    print("ok num:"..ok_num)
end

local income_level_config = function()
    local db_info = select_level_config()
    local ok_num = 0
    for level,row in pairs(db_info) do
        local one = {
            level = tonumber(row.level),
            credit = tonumber(row.credit),
        }
        redis_client:hset(config.redis_key.level_config_key, level, json.encode(one))
        ok_num = ok_num + 1
    end
    print("ok num:"..ok_num)
end

local update_user_level = function(uid,level)
    local conn = connect_db()
    local sql = sformat([[
    update user_extend set level=%s where uid=%s limit 1]], level, uid)
    conn:execute(sql)
    close_db(conn)
end

local update_user_zhubo = function(userid,zhubo,telents,tags)
    local conn = connect_db()
    local sql = sformat([[
    update user set zhubo=%s,telents='%s',tags='%s' where id=%s limit 1]], zhubo,telents,tags,userid)
    conn:execute(sql)
    close_db(conn)
end

local do_uplevel = function()
    local uid = arg[2]
    if not  uid or uid == "" then
        print("uid is needed")
        os.exit()
    end
    local other_info_tmp = redis_client:hget(config.redis_key.user_prefix ..uid, "other_info")
    if not other_info_tmp then
        print("this uid has no  other_info")
        os.exit()
    end
    local old_other_info = json.decode(other_info_tmp)
    local up_to_level = arg[3]
    if not  up_to_level or up_to_level == "" then
        print("up_to_level is needed")
        os.exit()
    end
    local level_info_tmp = redis_client:hget(config.redis_key.level_config_key, up_to_level)
    if not level_info_tmp then
        print("this level is  wrong")
        os.exit()
    end
    local  level_info = json.decode(level_info_tmp)
    local new_credit = level_info.credit
    local now_level = level_info.level
    update_user_level(uid, now_level)
    local other_info = {
        tags = old_other_info.tags,
        telents = old_other_info.telents,
        brief = old_other_info.brief,
        price = new_credit
    }
   -- setmetatable(other_info.tags, json.empty_array_mt)
    redis_client:hset(config.redis_key.user_prefix .. uid, "other_info",dkjson.encode(other_info))
    redis_client:hset(config.redis_key.user_prefix .. uid, "price",new_credit)
    print("Uid:"..uid.." Now level:"..now_level.." From price ["..old_other_info.price.."] change to ["..new_credit.."]")
end

local transaction_start = function()
    local conn = connect_db()
    local sql = "START TRANSACTION"
    conn:execute(sql)
end

local transaction_rollback = function()
    local conn = connect_db()
    local sql = "ROLLBACK"
    conn:execute(sql)
end

local transaction_commit = function()
    local conn = connect_db()
    local sql = "COMMIT"
    conn:execute(sql)
end

local select_user_extend_info = function(uid)
    local conn = connect_db()
    local sql = sformat([[
      select coin FROM user_extend WHERE uid=%s]], uid)
    local cur = conn:execute(sql)
    local row = cur:fetch({},"a")
    if not row then
        return 0
    end
    cur:close()
    close_db(conn)
    return row['coin']
end

local reduce_user_coin = function(uid,num)
    local conn = connect_db()
    local sql = sformat([[
    update  user_extend  set coin=coin+%s where uid=%s limit 1]], num, uid)
    local re = conn:execute(sql)
    close_db(conn)
    if re == 1 then
        return true
    end
    return false
end

local insert_coin_log = function(uid, type, table_id, num, log_time)
    local conn = connect_db()
    local sql = sformat([[
      INSERT INTO coin_bill_log(`uid`,`type`,`table_id`,`num`,`log_time`)
      VALUES ('%s', '%s', '%s', '%s', '%s')]], uid, type, table_id, num, log_time)
    local re = conn:execute(sql)
    close_db(conn)
    if re then
        return true
    end
    return false
end

local insert_user = function(loginname,password,username,avatar,gender,accessToken,refreshToken,tokenexpires,country,myos,uniq,language,pkg,pkgver,pkgint,instime,createTime)
    local conn = connect_db()
    local sql = sformat([[
      insert into user(loginname,password,username,avatar,gender,accesstoken,refreshtoken,tokenexpires,country,os,uniq,language,pkg,pkgver,pkgint,instime,createtime)
      VALUES ('%s', '%s', '%s', '%s', '%s','%s', '%s', '%s', '%s', '%s','%s', '%s', '%s', '%s', '%s','%s', '%s')]], loginname,password,username,avatar,gender,accessToken,refreshToken,tokenexpires,country,myos,uniq,language,pkg,pkgver,pkgint,instime,createTime)
    local re = conn:execute(sql)
    close_db(conn)
    return re
end

local insert_extend_user = function(uid,level,total_income,credit,coin)
    local conn = connect_db()
    local sql = sformat([[
      insert into user_extend(uid,level,total_income,credit,coin)
       VALUES ('%s', '%s', '%s', '%s', '%s')]], uid,level,total_income,credit,coin)
    local re = conn:execute(sql)
    close_db(conn)
    return re
end

local insert_video = function(uid,video,cover,vinfo,iscover)
    local conn = connect_db()
    local sql = sformat([[
        insert into user_video(uid,video,cover,vinfo,iscover)
       VALUES ('%s', '%s', '%s', '%s', '%s')]], uid,video,cover,vinfo,iscover)
    local re = conn:execute(sql)
    close_db(conn)
    return re
end

local select_user_video = function(uid)
    local conn = connect_db()
    local sql = sformat([[
      select id FROM user_video WHERE uid=%s limit 1]], uid)
    local cur = conn:execute(sql)
    local row = cur:fetch({},"a")
    if not row then
        return 0
    end
    cur:close()
    close_db(conn)
    return row['id']
end

local insert_turn_user = function(uid,domain,token)
    local conn = connect_turn_db()
    local sql = sformat([[
      insert into turnusers_lt(realm,name,hmackey)
       VALUES ('%s', '%s', '%s')]], domain,uid,token)
    local re = conn:execute(sql)
    close_turn_db(conn)
    return re
end

-- 未来应该是接口形式的，传入log id，查询对应的一些信息，就不用人工输入了
local get_money = function()
    local uid = arg[2]
    if not  uid or uid == "" then
        print("uid is needed")
        os.exit()
    end
    local need_reduce_coin = arg[3]
    if not  need_reduce_coin or need_reduce_coin == "" or  tonumber(need_reduce_coin)<1 then
        print("coin num is needed")
        os.exit()
    end
    print("Reduce uid=["..uid.."] coin num ["..need_reduce_coin.."]")
    io.write("Please confirm the info above, if confirmed, Enter 'yes',or Enter 'no':\n")
    local ask = io.read("*l")
    if ask == "yes" then
        local db_now_coin = select_user_extend_info(uid)
        if db_now_coin < need_reduce_coin then
            print("Error uid:["..uid.."]coin is not enough need:["..need_reduce_coin.."] now have["..db_now_coin.."]")
            os.exit()
        end
        local exec_ok = reduce_user_coin(uid, -need_reduce_coin)
        local last_re = false
        if not exec_ok then
            print("Error uid:["..uid.."]coin is not enough")
            os.exit()
        else
            last_re = insert_coin_log(uid, 5, 0, -need_reduce_coin, now_time())
        end
        if last_re then
            print("OK")
        else
            print("Log Error")
        end
    else
        print("Cancel")
    end

end

local select_video_info = function(uid)
    local conn = connect_db()
    local sql
    if uid == "all" then
        sql = "select * from  user_video"
    else
        sql = "select * from  user_video where uid="..uid
    end
    local cur = conn:execute(sql)
    if not cur then
        return {}
    end
    local row = cur:fetch({},"a")
    if not row then
        return {}
    end
    local re = {}
    while row do
        local id = row.id
        re[id] = {
            uid = row.uid,
            video = row.video,
            cover = row.cover,
            vinfo = row.vinfo,
            iscover = row.iscover
        }
        row = cur:fetch(row,"a")
    end
    cur:close()
    close_db(conn)
    return re
end

local select_fans_info = function(uid)
    local conn = connect_db()
    local sql
    if uid == "all" then
        sql = "select * from  user_fans"
    else
        sql = "select * from  user_fans where uid1="..uid .. "or uid2="..uid
    end
    local cur = conn:execute(sql)
    if not cur then
        return {}
    end
    local row = cur:fetch({},"a")
    if not row then
        return {}
    end
    local re = {}
    while row do
        local id = row.id
        re[id] = {
            createtime = row.createtime,
            uid1 = row.uid1,
            uid2 = row.uid2
        }
        row = cur:fetch(row,"a")
    end
    cur:close()
    close_db(conn)
    return re
end

local select_users_info = function(uid,email)
    local conn = connect_db()
    local sql
    if email == 1 then
        if uid == "all" then
            sql = "select id,loginname,username,gender,zhubo,avatar,telents,tags,uniq from  user"
        else
            sql = "select id,loginname,username,gender,zhubo,avatar,telents,tags,uniq from  user where loginname='"..uid.."'"
        end
    elseif email == 2 then
        if uid == "all" then
            sql = "select id,loginname,username,gender,zhubo,avatar,telents,tags,uniq from  user where gender=2"
        else
            sql = "select id,loginname,username,gender,zhubo,avatar,telents,tags,uniq from  user where id="..uid
        end
    else
        if uid == "all" then
            sql = "select id,loginname,username,gender,zhubo,avatar,telents,tags,uniq from  user"
        else
            sql = "select id,loginname,username,gender,zhubo,avatar,telents,tags,uniq from  user where id="..uid
        end
    end
    
    local cur = conn:execute(sql)
    if not cur then
        return {}
    end
    local row = cur:fetch({},"a")
    if not row then
        return {}
    end
    local re = {}
    while row do
        local id = row.id
        re[id] = {
            username = row.username,
            gender = row.gender,
            zhubo = row.zhubo,
            avatar = row.avatar,
            telents = row.telents,
            tags = row.tags,
            uniq = row.uniq,
            loginname = row.loginname,
        }
        row = cur:fetch(row,"a")
    end
    cur:close()
    close_db(conn)
    return re
end

local select_users_extend_info = function(uid)
    local conn = connect_db()
    local sql
    if uid == "all" then
        sql = "select * from  user_extend"
    else
        sql = "select * from user_extend where uid="..uid
    end
    local cur = conn:execute(sql)
    if not cur then
        return {}
    end
    local row = cur:fetch({},"a")
    if not row then
        return {}
    end
    local re = {}
    while row do
        local id = row.uid
        re[id] = {
            level = row.level,
            credit = row.credit,
            coin = row.coin,
            total_income = row.total_income
        }
        row = cur:fetch(row,"a")
    end
    cur:close()
    close_db(conn)
    return re
end

local select_table_info_by_tablename = function(table_name)
    local conn = connect_db()
    local sql =  "select * from "..table_name
    local cur = conn:execute(sql)
    if not cur then
        return {}
    end
    local row = cur:fetch({},"a")
    if not row then
        return {}
    end
    local re = {}
    while row do
        local id = row.id
        re[id] = {
            grade_uid = row.grade_uid,
            mm_id = row.mm_id,
        }
        row = cur:fetch(row,"a")
    end
    cur:close()
    close_db(conn)
    return re
end

local  function delete_table_info_by_sql(del_sql)
    local conn = connect_db()
    local re = conn:execute(del_sql)
    close_db(conn)
end

local update_redis_from_db_video = function()
    local uid = arg[2]
    if not uid or uid == "" then
        print("uid is needed")
        os.exit()
    end
    local all_video = select_video_info(uid)
    local ok_num = 0
    for id,tmp in pairs(all_video)  do
        local myuid = tmp.uid
        local iscover = tmp.iscover
        local video_info = {
            video = tmp.video,
            compress_video = tmp.compress_video or "",
            cover = tmp.cover,
            vinfo = dkjson.decode(tmp.vinfo)
        }
        redis_client:hset(config.redis_key.video_prefix .. myuid, id, json.encode(video_info))
        if iscover == "1" then
            redis_client:hset(config.redis_key.video_prefix .. myuid, "iscover", id)
        end
        ok_num = ok_num + 1
    end
    print("Ok num:"..ok_num)
end

local update_redis_from_db_fans = function(uid)
    local uid = arg[2]
    if not uid or uid == "" then
        print("uid is needed")
        os.exit()
    end
    local all_fans = select_fans_info(uid)
    local ok_num = 0
    for id,tmp in pairs(all_fans)  do
        local uid1 = tmp.uid1
        local uid2 = tmp.uid2
        local score = tmp.createtime
        redis_client:zadd(config.redis_key.i_follow_prefix .. uid2, score, uid1)
        redis_client:zadd(config.redis_key.follow_me_prefix .. uid1, score, uid2)
        ok_num = ok_num + 1
    end
    print("Ok num:"..ok_num)
end

local update_redis_from_db_users = function(uid)
    local uid = arg[2]
    if not uid or uid == "" then
        print("uid is needed")
        os.exit()
    end
    local all_users = select_users_info(uid, 0)
    local all_user_extend = select_users_extend_info(uid)
    local all_level_info_tmp = redis_client:hgetall(config.redis_key.level_config_key)
    local all_level_info = {}
    for k,v in pairs(all_level_info_tmp) do
        all_level_info[k] = json.decode(v)
    end
    local ok_num = 0
    for id,tmp in pairs(all_users) do
        local base_info = {
                username = tmp.username,
                avatar = tmp.avatar,
                uniq = tmp.uniq,
                gender = tmp.gender,
                super = tmp.super
        }
        local user_level = all_user_extend[id].level
        local tags,telents = {},{}
        if tmp.tags ~= "" then
            tags = json.decode(tmp.tags) 
        end
        if tmp.telents ~= "" then
            telents = json.decode(tmp.telents) 
        end
        local other_info = {
            tags = tags,
            telents = telents,
            brief = tmp.brief or "",
            price = all_level_info[user_level].credit
        }
        local ifollow_num = redis_client:zcard(config.redis_key.i_follow_prefix..id)
        local followme_num = redis_client:zcard(config.redis_key.follow_me_prefix..id)
        redis_client:hmset(config.redis_key.user_prefix ..id, "base_info", json.encode(base_info), "other_info",dkjson.encode(other_info),"ifollow", ifollow_num, "followme", followme_num,"price",all_level_info[user_level].credit)
        ok_num = ok_num + 1
    end
    print("Ok num:"..ok_num)
end

local make_user_be_super = function(uid)
    local conn = connect_db()
    local sql = sformat([[
    update user set super=1 where id=%s limit 1]], uid)
    conn:execute(sql)
    close_db(conn)
end

local function make_super_user()
    local uid = arg[2]
    if not uid or uid == "" then
        print("uid is needed")
        os.exit()
    end
    make_user_be_super(uid)
    local old_base_info_tmp = redis_client:hget(config.redis_key.user_prefix ..uid, "base_info")
    local old_base_info = json.decode(old_base_info_tmp)
    local base_info = {
        username = old_base_info.username,
        avatar = old_base_info.avatar,
        uniq = old_base_info.uniq,
        gender = old_base_info.gender,
        super = 1
    }
    redis_client:hset(config.redis_key.user_prefix ..uid, "base_info", json.encode(base_info))
    print("Ok")
end

local function show_user_info()
    local uid = arg[2]
    if not uid or uid == "" or uid == "all" then
        print("uid is needed")
        os.exit()
    end
    local use_email = 0
    if sfind(uid,"@") then
        use_email = 1
    end
    local user_info_tmp = select_users_info(uid,use_email)
    local myuid
    for k,v in pairs(user_info_tmp) do
        myuid = k
    end
    if not myuid then
        print("user info not found")
        os.exit()
    end
    local user_info = user_info_tmp[myuid]
    local user_info_extend_tmp = select_users_extend_info(myuid)
    local user_info_extend = user_info_extend_tmp[myuid]
    print("|------------------------------------------------------------------------------------------------|")
    local show_info = "|uid:"..myuid.."|username:"..user_info['username'].."|loginname:"..user_info['loginname'].."|total_income:"..user_info_extend['total_income'].."|level:"..user_info_extend['level'].."|credit:"..user_info_extend['credit'].."|coin:"..user_info_extend['coin'].."|"
    print(show_info)
    print("|------------------------------------------------------------------------------------------------|")
end

local delete_user_all = function(uid)
    local conn = connect_db()
    local sql = sformat([[
      DELETE FROM user WHERE id=%s limit 1]], uid)
    conn:execute(sql)

    local sql = sformat([[
      DELETE FROM user_extend WHERE uid=%s limit 1]], uid)
    conn:execute(sql)

    local sql = sformat([[
      DELETE FROM user_video WHERE uid=%s]], uid)
    conn:execute(sql)

    local sql = sformat([[
      DELETE FROM user_video WHERE uid=%s]], uid)
    conn:execute(sql)

    local sql = sformat([[
      DELETE FROM coin2credit_log WHERE uid=%s]], uid)
    conn:execute(sql)

    local sql = sformat([[
      DELETE FROM coin_bill_log WHERE uid=%s]], uid)
    conn:execute(sql)

    local sql = sformat([[
      DELETE FROM credit_bill_log WHERE uid=%s]], uid)
    conn:execute(sql)

    local sql = sformat([[
      DELETE FROM fcm_token WHERE uid=%s]], uid)
    conn:execute(sql)

    local sql = sformat([[
      DELETE FROM getmoney_log WHERE uid=%s]], uid)
    conn:execute(sql)

    local sql = sformat([[
      DELETE FROM uplevel_log WHERE uid=%s]], uid)
    conn:execute(sql)

    local sql = sformat([[
      DELETE FROM usd_purchase_log WHERE uid=%s]], uid)
    conn:execute(sql)

    -- 删除粉丝数据 存在遗漏  需要对关注她的人的数量做减法
    local sql = sformat([[
      DELETE FROM user_fans WHERE uid1=%s or uid2=%s]], uid, uid)
    conn:execute(sql)
    close_db(conn)
end

local clear_user_money = function(uid)
    local conn = connect_db()
    local sql = sformat([[
      update user_extend set total_income=0,credit=0,coin=0 WHERE uid=%s limit 1]], uid)
    conn:execute(sql)

    local sql = sformat([[
      DELETE FROM coin2credit_log WHERE uid=%s]], uid)
    conn:execute(sql)

    local sql = sformat([[
      DELETE FROM coin_bill_log WHERE uid=%s]], uid)
    conn:execute(sql)

    local sql = sformat([[
      DELETE FROM credit_bill_log WHERE uid=%s]], uid)
    conn:execute(sql)

    local sql = sformat([[
      DELETE FROM getmoney_log WHERE uid=%s]], uid)
    conn:execute(sql)

    close_db(conn)
end

local function clear_user_info()
    local uid = arg[2]
    if not uid or uid == "" or uid == "all" then
        print("uid is needed")
        os.exit()
    end
    --  删除用户所有信息 还是只是清除金币相关
    local delete_all = arg[3]
    local act_type = false
    if delete_all and  delete_all == "1" then
        act_type = true
    end
    local all_uids = select_users_extend_info(uid)
    for myuid,v in pairs(all_uids) do
       -- if act_type then
            delete_user_all(myuid)
            redis_client:del(config.redis_key.user_prefix .. myuid)
            redis_client:del(config.redis_key.video_prefix .. myuid)
            redis_client:del(config.redis_key.i_follow_prefix .. myuid)
            redis_client:del(config.redis_key.follow_me_prefix .. myuid)
            redis_client:srem(config.redis_key.all_anchors_uid, myuid)
      --  else
         --   clear_user_money(myuid)
       -- end
        print(myuid.." uid delete ok\n")
    end
end

local function sleep(n)
    local n = n or 0.2
    socket.select(nil, nil, n)
end
local function random(ttt)
    mrandomseed(ttt)
    return mrandom(1, 9999)
end

local function pl_create_user()
    local num = arg[2]
    if not num or num == "" then
        print("num is needed")
        os.exit()
    end
    if tonumber(num) > 5000 then
        print("max num is 1000")
        os.exit()
    end
    -- 是否成为主播
    local to_be_zhubo = false

    for i = 1,num do
        local ok_email = "imtest"..i.."@paramount.com"
        local ok_username = "imtest"..i
        local post_data = {
            username = ok_username,
            email = ok_email,
            passwd = md5.sumhexa("123456789"),
            uniq = md5.sumhexa(ok_email),
            pkg = "com.qihoo.mm.paramount",
            gender = "2",
            country = "CN",
            language = "zh",
            os = "Android",
            pkgver = '1.0.0',
            pkgint = 1,
            instime = os.time()
        }
        local username = post_data["username"]
        local email = post_data["email"]
        local passwd = post_data["passwd"]
        local uniq = post_data["uniq"]
        local pkg = post_data["pkg"]
        local gender = post_data["gender"]
        local country = post_data["country"]
        local language = post_data["language"]
        local myos = post_data["os"]
        local pkgver = post_data["pkgver"]
        local pkgint = post_data["pkgint"]
        local instime = post_data["instime"]

        -- have already register(应该不会出现)
        local result = select_users_info(email,1)
        if _G.next(result) ~= nil then
            print(email .. " is  exists")
            os.exit()
        end

        sleep()
        local createTime = socket.gettime() * 1000
        local createTime = math.ceil(createTime)
        local token_raw = createTime .. random(createTime)
        local accessToken = md5.sumhexa(token_raw)..createTime
        local refreshToken = md5.sumhexa(token_raw .. "_wcd")..random(createTime)
        local tokenExpires = os.time() + 5184000
        local avatar = config.default_avatar[gender]
        local createTime = os.time()
        local save_pass = md5.sumhexa(passwd..config.redis_key.pass_key)
        local insert_ok = insert_user(
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
            createTime)
        if insert_ok  then 
            local user_info_tmp = select_users_info(email,1)
            local myuid
            for k,v in pairs(user_info_tmp) do
                myuid = k
            end
            redis_client:hmset(
                config.redis_key.token_prefix .. accessToken,
                config.redis_key.token_uid_key,
                myuid,
                config.redis_key.token_fresh_token_key,
                refreshToken
            )
            redis_client:expire(config.redis_key.token_prefix .. accessToken, 5184000)
            local base_info = {
                username = username,
                avatar = avatar,
                uniq = uniq,
                gender = gender,
                super = 0
            }
            -- save anchor base info
            redis_client:hmset(config.redis_key.user_prefix .. myuid, "base_info", json.encode(base_info),"ifollow", 0, "followme", 0)
            local default_level = 2
            insert_extend_user(myuid, default_level, 0, 0, 0)
            local turn_token = md5.sumhexa(myuid..':'..config.turn_domain..':'..accessToken)
            local turn_re = insert_turn_user(myuid,config.turn_domain, turn_token)
            local print_info = myuid..","..email..","..accessToken
            if not turn_re  then
                print("insert into turn  error")
                print(print_info)
                os.exit()
            end
            if to_be_zhubo then
                -- 成为主播接口
                local post_data_2 = {
                    cover = "http://wcd.cloudfront.net/150537099296602.jpg",
                    video = "http://wcd.cloudfront.net/150537098984677.mp4",
                    vinfo = {
                        rotation = 0,
                        width = 368,
                        height = 640
                    }
                }
                local cover_url = post_data_2["cover"] or ""
                local video_url = post_data_2["video"] or ""
                local vinfo = post_data_2["vinfo"] or {}
                local telents = post_data_2["telents"] or {}
                local tags = post_data_2["tags"] or {}

                local vinfo_json = json.encode(vinfo)
                local telents_json = json.encode(telents)
                local tags_json = json.encode(tags)
        
                local zhubo = 1
                update_user_zhubo(myuid, zhubo, telents_json, tags_json)
                local other_info = {
                    tags = tags,
                    telents = telents,
                    brief = "im test",
                    price = 6,
                }
                redis_client:hset(config.redis_key.user_prefix .. myuid, "other_info",dkjson.encode(other_info))
                redis_client:hset(config.redis_key.user_prefix .. myuid, "price",6)
                redis_client:sadd(config.redis_key.all_anchors_uid, myuid)

                local video_info = {
                    video = video_url,
                    cover = cover_url,
                    vinfo = vinfo
                }
                insert_video(myuid, video_url, cover_url, vinfo_json, 1)
                local video_id = select_user_video(myuid)
                redis_client:hset(config.redis_key.video_prefix .. myuid, video_id, json.encode(video_info))
                redis_client:hset(config.redis_key.video_prefix .. myuid, 'iscover', video_id)
                print(print_info)
            else
                print(print_info)
            end
        end
    end
end

local do_stars_list_config = function()
    --local stars_uids = {14671,11834,11182,10704,13830,15175,12983,13431,15696,12348,12425,10927,15607,16553,14180,10639,15222,13259,10906,13486,12415,12754,12961,12011,14950,11120,11889,12410,15041,13070}
    local stars_uids = {21,44,45,46,47,9,54,13,14,15,16,17,18,19,20} -- online
    local ok_info = {}
    local ok_num = 0
    for _,uid in pairs(stars_uids) do
        local base_info_tmp = redis_client:hget(config.redis_key.user_prefix .. uid, "base_info")
        if  base_info_tmp then
            local old_base_info = json.decode(base_info_tmp)
            local one = {
                avatar = old_base_info.avatar,
                uid = uid,
            }
            table.insert(ok_info,one)
            ok_num = ok_num + 1
        end
    end
    redis_client:set(config.redis_key.stars_list_config_key,json.encode(ok_info))
    print("Ok num:"..ok_num)
end

local do_uplevel_all_free_girls = function()
    local now_level = 2
    local new_credit = 6
    local all_girls_info = select_users_info("all",2)
    for uid,v in pairs(all_girls_info) do
        local other_info_tmp = redis_client:hget(config.redis_key.user_prefix ..uid, "other_info")
        if  other_info_tmp then
            local old_other_info = json.decode(other_info_tmp)
            local old_price = tonumber(old_other_info.price) or 0
            if old_price == 0 then
                update_user_level(uid, now_level)
                local other_info = {
                    tags = {},
                    telents = {},
                    brief = old_other_info.brief,
                    price = new_credit
                }
                redis_client:hset(config.redis_key.user_prefix .. uid, "other_info",dkjson.encode(other_info))
                redis_client:hset(config.redis_key.user_prefix .. uid, "price",new_credit)
                print("Uid:"..uid.. " ok ]")
            end
        end
    end
end

local function deal_user_grade_mms_table()
    --select  count(1) as  wcd,id  from user_grade_mms  group by  grade_uid,mm_id having  wcd>1;
    local all_grade_info = select_table_info_by_tablename("user_grade_mms")
    local ok_info = {}
    for id,v in pairs(all_grade_info) do
        local ok_key = v.grade_uid.."-"..v.mm_id
        --if weather_in_array(ok_key,ok_info) then
        if ok_info[ok_key] then
            delete_table_info_by_sql("delete  from user_grade_mms where  id="..id)
            --print("del-id"..ok_key)
            --print(ok_key)
        else
            ok_info[ok_key] = 1
            --tinsert(ok_info,ok_key)
        end
        --break
    end
    print("deal done")
end


local function help()
    local help = [[
        lua tools.lua help
        lua tools.lua money2credit_config usd充值点数套餐配置
        lua tools.lua coin2credit_config 金币兑换点数套餐配置
        lua tools.lua gift_config 礼物赠送套餐配置
        lua tools.lua level_config 主播等级收入配置
        lua tools.lua uplevel {uid} {level} 提升某个uid到level等级
        lua tools.lua getmoney {uid} {coin} 提现扣除某个uid金币
        lua tools.lua db2redis_video {uid|all} 恢复mysql video数据到redis（uid|all）
        lua tools.lua db2redis_fans {uid|all} 恢复mysql fans数据到redis（uid|all）
        lua tools.lua db2redis_users {uid|all} 恢复mysql user数据到redis（uid|all）
        lua tools.lua superuser {uid} 设置某个uid成为super管理员
        lua tools.lua userinfo {uid|email} 根据uid或者邮箱查看用户信息  
        lua tools.lua clearuserinfo {uid} del_all(1)| 清除金币点数以及日志和完全删除用户操作（慎重！！！）
        lua tools.lua plcreateuser num 新建测试用户
        lua tools.lua stars_list_config  关注列表配置
        lua tools.lua uplevel_all_girls 修改之前免费的女孩
        lua tools.lua deal_dian_zan 处理之前点赞垃圾数据
        
    ]]
    print(help)
end
local act = arg[1]
if not act or act == "" or  act == "help" then
    help()
elseif act == "money2credit_config" then
    make_money2credit_config()
elseif act == "coin2credit_config" then
    make_coin2credit_config()
elseif act == "level_config" then
    income_level_config()
elseif act == "uplevel" then
    do_uplevel()
elseif act == "getmoney" then
    get_money()
elseif act == "db2redis_video" then
    update_redis_from_db_video()
elseif act == "db2redis_fans" then
    update_redis_from_db_fans()
elseif act == "db2redis_users" then
    update_redis_from_db_users()
elseif act == "superuser" then
    make_super_user()
elseif act == "userinfo" then
    show_user_info()
elseif act == "clearuserinfo" then
    --clear_user_info()
    print("its danger")
    os.exit()
elseif act == "plcreateuser" then
    --print("its danger")
    --os.exit()
    pl_create_user()
elseif act == "gift_config" then
    do_gift_config()
elseif act == "stars_list_config" then
    do_stars_list_config()
elseif act == "uplevel_all_girls" then
    do_uplevel_all_free_girls()
elseif act == "deal_dian_zan" then
    deal_user_grade_mms_table()
end
