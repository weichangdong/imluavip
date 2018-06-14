local ngx = ngx
local ngx_md5 = ngx.md5
local string_upper = string.upper
local table_sort = table.sort
local table_concat = table.concat
local ngx_time = ngx.time
local ngx_now = ngx.now
local string_format = string.format
local string_gsub = string.gsub
local resty_string = require "resty.string"
local config = require("app2.config.config")
local utils = require("app2.lib.utils")
local hmac = require "resty.hmac"
require("LuaXml")
local _M = {}

function _M.generate_nonce_str()
    return ngx_md5(ngx_now()..utils.random())
end

-- 将Lua table 生成xml格式的string
function _M.generate_xml(resp_data)
    local xml_data = xml.new("xml")
    for key, val in pairs(resp_data) do
        xml_data:append(key)[1] = val
    end
    return xml.str(xml_data)
end

local function lua_hmac_sha256(raw_data)
    local hmac_sha256 = hmac:new(config.voucher.weixin_sign_key, hmac.ALGOS.SHA256)
    if not hmac_sha256 then
        ngx.say("failed to create the hmac_sha256 object")
        return
    end

    ok = hmac_sha256:update(raw_data)
    if not ok then
        ngx.say("hmac_sha256 failed to add data")
        return
    end
    local mac = hmac_sha256:final()  -- binary mac
    return resty_string.to_hex(mac)
end

function _M.parse_wxxml(wx_xml)
    local return_xml_data = xml.eval(wx_xml)
    local return_xml_table = {}
    local num = 0
    for key, val in pairs(return_xml_data) do
        if key > 0 then
            if type(val) == 'table' then
                return_xml_table[val[0]] = val[1]
                num = num + 1
            end
        end
    end
    return num,return_xml_table
end

function _M.check_hmac_sign(re_data)
    local wx_sign = re_data.sign
    re_data.sign = nil
    local tmp = {}
    local count = 1
    for k,v in pairs(re_data) do
        tmp[count] = k .. "=" .. v
        count = count + 1
    end
    table_sort(tmp)
    local result_str = table_concat(tmp, "&") .. "&key=" .. config.voucher.weixin_sign_key
    local our_sign = string_upper(lua_hmac_sha256(result_str))
    if our_sign == wx_sign then
        return true
    end
    return false
end

function _M.generate_sign(resp_data)
    local tmp = {}
    local count = 1
    for k,v in pairs(resp_data) do
        tmp[count] = k .. "=" .. v
        count = count + 1
    end
    table_sort(tmp)
    local result_str = table_concat(tmp, "&") .. "&key=" .. config.voucher.weixin_sign_key
    return result_str,string_upper(lua_hmac_sha256(result_str))
end

function _M.generate_orderid()
    local now_time = ngx_now() * 1000 --len=13
    local local_time = ngx.localtime()
    local ymd = string_gsub(local_time,"[- :]","") --len=14
    local order_id = ymd..now_time..utils.img_random()
    return order_id
end
return _M