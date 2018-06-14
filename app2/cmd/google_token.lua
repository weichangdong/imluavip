package.path = package.path .. ";/data/v3-p2papi/?.lua;/usr/local/luarocks/share/lua/5.1/?.lua;;"
package.cpath = package.cpath .. ";/usr/local/luarocks/lib/lua/5.1/?.so;;"
local my_redis = require("app2.lib.cmd_redis")
local config = require("app2.config.config")
local json = require("cjson.safe")
local curl = require("luacurl")

local tconcat = table.concat
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

local function conn_redis()
        return my_redis.connect(config.redis_config['write']['HOST'],config.redis_config['write']['PORT'])
end

local function now_date()
        return os.date("%Y-%m-%d %H:%M:%S")
end

local function now_time()
        return os.time()
end

local re,redis_client = pcall(conn_redis)
if not re then
        print(now_date() .." redis error\n")
        os.exit()
end

local function lua_curl()
    local header_info = {
         'Content-Type: application/x-www-form-urlencoded; charset=UTF-8',
    }
    local url = config.voucher.google_url
    local post_data = "grant_type=refresh_token&client_id="..config.voucher.client_id.."&client_secret="..config.voucher.client_secret.."&refresh_token="..config.voucher.refresh_token
    local c = curl.new()
    c:setopt(curl.OPT_URL, url)
    c:setopt(curl.OPT_SSL_VERIFYHOST,0)
    c:setopt(curl.OPT_SSL_VERIFYPEER,false)
    c:setopt(curl.OPT_HEADER, false)
    c:setopt(curl.OPT_CUSTOMREQUEST, "POST")
    c:setopt(curl.OPT_HTTPHEADER,tconcat(header_info,"\n"))
    c:setopt(curl.OPT_POSTFIELDS, post_data)

    local t = {}
    c:setopt(curl.OPT_WRITEFUNCTION, function(param, buf)
        tinsert(t, buf)
        return #buf
    end)
    c:perform()
    return tconcat(t)
end

local function lua_curl_paypal()
    local header_info = {
         'Accept: application/json',
         'Accept-Language: en_US',
    }
    local url = "https://"..config.voucher.paypal_access_token_url
    local post_data = "grant_type=client_credentials"
    local c = curl.new()
    c:setopt(curl.OPT_URL, url)
    c:setopt(curl.OPT_SSL_VERIFYHOST,0)
    c:setopt(curl.OPT_SSL_VERIFYPEER,false)
    c:setopt(curl.OPT_HEADER, false)
    c:setopt(curl.OPT_CUSTOMREQUEST, "POST")
    c:setopt(curl.OPT_USERPWD, config.voucher.paypal_client_id..":"..config.voucher.paypal_secret)
    c:setopt(curl.OPT_HTTPHEADER,tconcat(header_info,"\n"))
    c:setopt(curl.OPT_POSTFIELDS, post_data)
    
    local t = {}
    c:setopt(curl.OPT_WRITEFUNCTION, function(param, buf)
        tinsert(t, buf)
        return #buf
    end)
    c:perform()
    return tconcat(t)
end

local ttl = redis_client:ttl(config.redis_key.access_token_key)
local act_do = 0
if ttl < 30 then
    local wcd = lua_curl()
    local ok_info = json.decode(wcd)
    local expires_in = ok_info.expires_in
    local access_token = ok_info.access_token
    redis_client:setex(config.redis_key.access_token_key, expires_in, access_token)
    act_do = 1
end
if act_do == 1 then
        print(now_date().." gg ttl:"..ttl)
end

local ttl = redis_client:ttl(config.redis_key.paypal_access_token_key)
local act_do = 0
if ttl < 30 then
    local wcd = lua_curl_paypal()
    local ok_info = json.decode(wcd)
    local expires_in = ok_info.expires_in
    local access_token = ok_info.access_token
    redis_client:setex(config.redis_key.paypal_access_token_key, expires_in, access_token)
    act_do = 1
end
if act_do == 1 then
        print(now_date().." paypal ttl:"..ttl)
end

