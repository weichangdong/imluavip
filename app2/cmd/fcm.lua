package.path = package.path .. ";/data/v3-p2papi/?.lua;/usr/local/luarocks/share/lua/5.1/?.lua;;"
package.cpath = package.cpath .. ";/usr/local/luarocks/lib/lua/5.1/?.so;;"
--package.path = package.path .. ";/work/bailemen-api/?.lua;;"
--package.cpath = package.cpath .. ";/usr/local/lib/lua/5.1/?.so;;"
local my_redis = require("app2.lib.cmd_redis")
local config = require("app2.config.config")
local json = require("cjson.safe")
local luasql = require "luasql.mysql"
local curl = require("luacurl")
local socket = require('socket')
local mysql_con = luasql.mysql()
local table_object  = json.encode_empty_table_as_object

local tinsert = table.insert
local tconcat = table.concat
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
local ioopen = io.open
local ceil = math.ceil

local function sleep(n)
    local n = n or 0.1
    socket.select(nil, nil, n)
end

local function conn_redis()
        return my_redis.connect(config.redis_config['write']['HOST'],config.redis_config['write']['PORT'])
end

local function now_date()
        return os.date("%Y-%m-%d %H:%M:%S")
end

local function now_time()
        return os.time()
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
        do return end
        if conn then
                conn:close()
        end
end

local re,redis_client = pcall(conn_redis)
if not re then
        print(now_date() .." redis error\n")
        os.exit()
end

local  function select_all_tags_id(start_num,limit_num)
        local conn = connect_db()   
        local sql = sformat([[
    select id FROM tags_data limit %s,%s]], start_num,limit_num)
        local cur = conn:execute(sql)
        if not cur then
                return nil
        end
        local row = cur:fetch({},"a")
        if not row then
                return nil
        end
        local all_tids = {}
        while row do
                tinsert(all_tids,row.id)
                row = cur:fetch(row,"a")
        end
        cur:close()
        close_db(conn)
        return all_tids
end

local  function select_all_tags_total_num()
        local conn = connect_db()   
        local total_num = 0
        local total_cur = conn:execute("select  count(1) as num from tags_data")
        local total_row = total_cur:fetch({},"a")
        if total_row then
                total_num = total_row.num
        end
        total_cur:close()
        close_db(conn)
        return total_num
end

local  function select_moments_tags_num(tids)
        local conn = connect_db()   
        local total_num = 0
        if not tids then return nil end
        local str_tids = tconcat(tids,",")
        local total_cur = conn:execute("select  count(1) as  num,tid  from  moments_tags_data where  tid in ("..str_tids..") group by tid")
        --print("select  count(1) as  num,tid  from  moments_tags_data where  tid in ("..str_tids..") group by tid")
        local total_row = total_cur:fetch({},"a")
        if not total_row  or tonumber(total_row.num) == 0 then
                return nil
        end
        local all_tids_num = {}
        while total_row do
                all_tids_num[total_row.tid] = total_row.num
                total_row = total_cur:fetch(total_row,"a")
        end
        total_cur:close()
        close_db(conn)
        return all_tids_num
end

local  function select_top20()
        local conn = connect_db()   
        local cur = conn:execute("select *  from  tags_data where  recom=1")
        local row = cur:fetch({},"a")
        local recom_num = 0
        local ok_tags = {}
        if not row then
                recom_num = 0
        else
                while row do
                        tinsert(ok_tags,{
                                id = tonumber(row.id),
                                tname = row.tname,
                                recom = tonumber(row.recom),
                                mm_num = tonumber(row.mm_num),
                        })
                        row = cur:fetch(row,"a")
                        recom_num = recom_num + 1
                end  
        end
        cur:close()
        local  need_num = 20
        if recom_num < need_num then
                local tmp_num = need_num - recom_num
                local cur = conn:execute("select *  from  tags_data where  recom=0 order by mm_num desc  limit "..tmp_num)
                local row = cur:fetch({},"a")
                while row do
                        tinsert(ok_tags,{
                                id = tonumber(row.id),
                                tname = row.tname,
                                recom = tonumber(row.recom),
                                mm_num = tonumber(row.mm_num),
                        })
                        row = cur:fetch(row,"a")
                end  
        end
        close_db(conn)
        return ok_tags
end

local function update_tags_moments_num(need_update)
        if not need_update then return end
        local conn = connect_db()
        for tid,tid_num in pairs(need_update) do
                local sql = sformat([[
                        update tags_data set mm_num=%s where id=%s limit 1]], tid_num, tid)
                conn:execute(sql)
        end
        close_db(conn)
end

local  function make_top20_tags()
        local  total_num = select_all_tags_total_num()
        local limit_num = 500
        local  times = ceil(total_num/limit_num)
        for go=0,times do
                local start_num = go*limit_num
                local all_tids = select_all_tags_id(start_num,limit_num)
                if not all_tids then
                        break
                end
                local need_update_num = select_moments_tags_num(all_tids)
                if not need_update_num then
                        break
                end
                update_tags_moments_num(need_update_num)
        end
        local top20_data = select_top20()
        local  json_data = json.encode(top20_data)
        redis_client:set(config.redis_key.moments_tags_data_key, json_data)
        print(now_date() .." make tags top20 ok")
end

local function send_fcm()
   -- {"class":"post","data":"{\"type\":\"topic\",\"msgid\":\"491512530150\",\"time\":1512530150,\"from\":{\"uid\":49,\"name\":\"KATE\",\"avatar\":\"\"},\"level\":\"system\",\"title\":\"KATE\",\"alert\":\"Hello, are you free, talk with me for a while.\"}","topic":"test_all"}
   print(now_date() .. " send fcm")
   local log_time = now_time()
   local fcm_son_data = {
        type = "topic",
        msgid = log_time * 1000,
        time = log_time,
        from = {
                uid = config.fcm_send_from_uid,
                username = "KATE",
                avatar = "",
        },
        level = "system",
        title = "all-push",
        alert = "hey guys, you have a new babe moment,check it",
    }
    local fcm_data = {
        topic = config.fcm_push_topic_value,
        class = "post",
        data = json.encode(fcm_son_data)
    }
    redis_client:lpush(config.redis_key.fcm_redis_key, json.encode(fcm_data))
end
send_fcm()
make_top20_tags()