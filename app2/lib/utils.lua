local pairs = pairs
local type = type
local mceil = math.ceil
local mfloor = math.floor
local mrandom = math.random
local mrandomseed = math.randomseed
local mmodf = math.modf
local sgsub = string.gsub
local tinsert = table.insert
local tconcat = table.concat
local sbyte = string.byte
local schar = string.char
local tonumber = tonumber
local sfind = string.find
local ssub = string.sub
local slen = string.len
local sgmatch = string.gmatch
local md5 = ngx.md5
local srep = string.rep
local date = require("app2.lib.date")
local str = require "resty.string"
local socket = require('socket')

local aes = require "resty.aes"
local json = require("cjson.safe")
local table_object  = json.encode_empty_table_as_object
local nettle_base64 = require("resty.nettle.base64")
local ngx_unescape_uri = ngx.unescape_uri
local ngx_escape_uri = ngx.escape_uri
local ngx_encode_base64 = ngx.encode_base64
local ngx_decode_base64 = ngx.decode_base64
local aes_key = "111f4c3d5545fcfcdcac5578133a4fca"
local ngx = ngx
local exit = ngx.exit


local token_key = "imlua.vip"

local _M = {}

function _M.sleep(n)
    local n = n or 0.1
    socket.select(nil, nil, n)
end

function _M.check_para(str)
    if not str or str == "" or type(str) == "table" then
        ngx.print('{"ret":3}')
        exit(200)
    end
end

function _M.check_num_value(num)
    if num ~= 0 and num ~= 1 and  num ~= 2 then
        ngx.print('{"ret":3}')
        exit(200)
    end
end

function _M.clear_slash(s)
    s, _ = sgsub(s, "(/+)", "/")
    return s
end

function _M.encode_query_string(t, sep)
  if sep == nil then
    sep = "&"
  end
  local _escape = ngx_escape_uri
  local i = 0
  local buf = { }
  for k, v in pairs(t) do
    if type(k) == "number" and type(v) == "table" then
      k, v = v[1], v[2]
    end
    buf[i + 1] = _escape(k)
    buf[i + 2] = "="
    buf[i + 3] = _escape(v)
    buf[i + 4] = sep
    i = i + 4
  end
  buf[i] = nil
  return tconcat(buf)
end

function in_array(value, tab)
    for _, v in pairs(tab) do
        if v == value then
            return true
        end
    end
    return false
end

function fromhex(d)
    return (d:gsub('..', function (cc)
        return schar(tonumber(cc, 16))
    end))
end

local function url_encode(s)  
     s = string.gsub(s, "([^%w%.%- ])", function(c) return string.format("%%%02X", string.byte(c)) end)  
    return string.gsub(s, " ", "+")  
end 
  
local function url_decode(s)  
    s = string.gsub(s, '%%(%x%x)', function(h) return string.char(tonumber(h, 16)) end)  
    return s  
end  

-- 加密
function _M.encrypt(data, not_need_aes)
    if not not_need_aes then
        local key = fromhex(aes_key)
        local iv_key = fromhex(srep('0', 32))
        local aes_128_cbc_with_iv = aes:new(key, nil, nil, {iv=iv_key})
        table_object(false)
        local encrypted = aes_128_cbc_with_iv:encrypt(json.encode(data))
        return ngx_escape_uri(ngx_encode_base64(encrypted))
    end
    return data
end

-- 解密
function _M.decrypt(data,not_need_aes)
    if not not_need_aes then
        local key = fromhex(aes_key)
        local iv_key = fromhex(srep('0',32))
        local aes_128_cbc_with_iv = aes:new(key,nil, nil, {iv=iv_key})
        local tmp = nettle_base64.decode(ngx_unescape_uri(data))
        if not tmp then
            ngx.print('{"ret":1}')
            ngx.exit(200)
        end
        local encrypted = aes_128_cbc_with_iv:decrypt(tmp)
        if not encrypted then
            ngx.print('{"ret":2}')
            ngx.exit(200)
        end
        return encrypted
    end
    return data
end

function _M.echo(res, re)
    res:json(re)
    ngx.exit(200)
end


function _M.filter(str)
   local all_strs = sgmatch("$¥￥`·\'‘、\\，,。.～~！!＠@＃#％%＆&×（）()｛｝{}[]【】/：:*＊+＋-－—=＝<﹤|︳……^-∕¦‖︴“《》？?……｜：“《》=\"|;", ".[\128-\191]*")
   for w in all_strs do
        local has = sfind(str, w, 1, true)
        if has then
            return false
        end
    end
    return true
--[[
   local all_error_byte = {226,239,195,96}
   -- 227 jp
   --33-47,58-64,123-126,91-96,
   for w in all_strs do
        local the_byte = sbyte(w)
        if the_byte>=33 and the_byte<=47 then
            return false
        elseif the_byte>=58 and the_byte<=64 then
            return false
        elseif the_byte>=91 and the_byte<=94 then
            return false
        elseif the_byte>=123 and the_byte<=126 then
            return false
        elseif in_array(the_byte, all_error_byte) then
            return false
        end
    end
    return true
    --]]
end

function _M.utf8len(input)
    local len  = slen(input)
    local left = len
    local cnt  = 0
    local arr  = {0, 0xc0, 0xe0, 0xf0, 0xf8, 0xfc}
    while left ~= 0 do
        local tmp = sbyte(input, -left)
        local i   = #arr
        while arr[i] do
            if tmp >= arr[i] then
                left = left - i
                break
            end
            i = i - 1
        end
        cnt = cnt + 1
    end
    return cnt
end

function _M.make_token(uniq)
    local now_time = ngx.now() * 10000
    mrandomseed(now_time)
    local rand_num = mrandom(1, 7777)
    local token_raw = now_time .. rand_num
    mrandomseed(now_time)
    local rand_num = mrandom(9, 9999)
    local new_token = md5(token_raw)..rand_num
    local new_fresh_token = md5(new_token..uniq..token_key)
    return new_token,new_fresh_token
end

function _M.check_email(email)
    local str = email
    local b, e = sfind(str, "@", 1, true)
    local bstr = ""
    local estr = ""
    if b then
        bstr = ssub(str, 1, b - 1)
        estr = ssub(str, e + 1, -1)
    else
        return false
    end

    -- check the string before '@'
    local p1, p2 = sfind(bstr, "[%w%_%-%.]+")
    if (p1 ~= 1) or (p2 ~= slen(bstr)) then
        return false
    end
    -- check .
    if sfind(bstr, "^[%.%-%_]+") then
        return false
    end

    if sfind(bstr, "[%.%-%_]$") then
        return false
    end

    -- check the string after '@'
    if sfind(estr, "^[%.]+") then
        return false
    end
    --  if string.find(estr, "%.[%.]+") then return false end
    if sfind(estr, "@", 1, true) then
        return false
    end
    if sfind(estr, "[%.]+$") then
        return false
    end

    _, count = sgsub(estr, "%.", "")
    if (count < 1) or (count > 3) then
        return false
    end
    return true
end

function _M.is_redis_null(res)
    if res ==  nil then
        return true
    elseif res == ngx.null then
        return true
    end
    return false
end

function _M.is_redis_null_table(res)
    if type(res) == "table" then
        for k, v in pairs(res) do
            if v ~= ngx.null then
                return false
            end
        end
        return true
    elseif res == ngx.null then
        return true
    elseif res == nil then
        return true
    end

    return false
end

function _M.weather_in_array(value, tab)
    for _, v in pairs(tab) do
        if v == value then
            return true
        end
    end
    return false
end

function _M.is_table_empty(t)
    if t == nil or type(t) == "string" or _G.next(t) == nil then
        return true
    else
        return false
    end
end

function _M.table_is_array(t)
    if type(t) ~= "table" then
        return false
    end
    local i = 0
    for _ in pairs(t) do
        i = i + 1
        if t[i] == nil then
            return false
        end
    end
    return true
end

function _M.mixin(a, b)
    if a and b then
        for k, v in pairs(b) do
            a[k] = b[k]
        end
    end
    return a
end

function _M.random()
    mrandomseed(ngx.now() * 10000)
    return mrandom(1, 9999)
end

function _M.img_random()
    mrandomseed(ngx.time())
    return mrandom(10000, 99999)
end

function _M.code_random()
    mrandomseed(ngx.time())
    return mrandom(111111, 999999)
end

function _M.custom_random(start_num,end_num)
    mrandomseed(ngx.time())
    return mrandom(start_num, end_num)
end

function _M.fb_random(num)
    mrandomseed(ngx.time())
    return mrandom(1, num)
end

function _M.total_page(total_count, page_size)
    local total_page = 0
    if total_count % page_size == 0 then
        total_page = total_count / page_size
    else
        --local tmp, _ = mmodf(total_count / page_size)
        --total_page = tmp + 1
        total_page = mceil(total_count / page_size)
    end

    return total_page
end

function _M.now()
    local n = date()
    local result = n:fmt("%Y-%m-%d %H:%M:%S")
    return result
end

function _M.string_split(str, delimiter)
    local result = {}
    for match in (str .. delimiter):gmatch("(.-)" .. delimiter) do
        tinsert(result, match)
    end
    return result
end

function _M.filter_input(s)
    local ss = {}
    local k = 1
    while true do
        if k > #s then
            break
        end
        local c = sbyte(s, k)
        if not c then
            break
        end
        if c < 192 then
            if (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) then
                tinsert(ss, schar(c))
            end
            k = k + 1
        elseif c < 224 then
            k = k + 2
        elseif c < 240 then
            if c >= 228 and c <= 233 then
                local c1 = sbyte(s, k + 1)
                local c2 = sbyte(s, k + 2)
                if c1 and c2 then
                    local a1, a2, a3, a4 = 128, 191, 128, 191
                    if c == 228 then
                        a1 = 184
                    elseif c == 233 then
                        a2, a4 = 190, c1 ~= 190 and 191 or 165
                    end
                    if c1 >= a1 and c1 <= a2 and c2 >= a3 and c2 <= a4 then
                        tinsert(ss, schar(c, c1, c2))
                    end
                end
            end
            k = k + 3
        elseif c < 248 then
            k = k + 4
        elseif c < 252 then
            k = k + 5
        elseif c < 254 then
            k = k + 6
        end
    end
    return tconcat(ss)
end

function _M.base64_decode(str64)
    local b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'  
    local temp={}  
    for i=1,64 do  
        temp[string.sub(b64chars,i,i)] = i  
    end  
    temp['=']=0  
    local str=""  
    for i=1,#str64,4 do  
        if i>#str64 then  
            break  
        end  
        local data = 0  
        local str_count=0  
        for j=0,3 do  
            local str1=string.sub(str64,i+j,i+j)  
            if not temp[str1] then  
                return  
            end  
            if temp[str1] < 1 then  
                data = data * 64  
            else  
                data = data * 64 + temp[str1]-1  
                str_count = str_count + 1  
            end  
        end  
        for j=16,0,-8 do  
            if str_count > 0 then  
                str=str..string.char(math.floor(data/math.pow(2,j)))  
                data=math.mod(data,math.pow(2,j))  
                str_count = str_count - 1  
            end  
        end  
    end  
  
    local last = tonumber(string.byte(str, string.len(str), string.len(str)))  
    if last == 0 then  
        str = string.sub(str, 1, string.len(str) - 1)  
    end  
    return str
end

function _M.base64_encode(source_str)
    local b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'  
    local s64 = ''  
    local str = source_str  
  
    while #str > 0 do  
        local bytes_num = 0  
        local buf = 0  
  
        for byte_cnt=1,3 do  
            buf = (buf * 256)  
            if #str > 0 then  
                buf = buf + string.byte(str, 1, 1)  
                str = string.sub(str, 2)  
                bytes_num = bytes_num + 1  
            end  
        end  
  
        for group_cnt=1,(bytes_num+1) do  
            local b64char = math.fmod(math.floor(buf/262144), 64) + 1  
            s64 = s64 .. string.sub(b64chars, b64char, b64char)  
            buf = buf * 64  
        end  
  
        for fill_cnt=1,(3-bytes_num) do  
            s64 = s64 .. '='  
        end  
    end
    return s64  
end

function _M.var_dump(data, max_level, prefix)
    if type(prefix) ~= "string" then
        prefix = ""
    end
    if type(data) ~= "table" then
        ngx.say(prefix .. tostring(data))
    else
        ngx.say(data)
        if max_level ~= 0 then
            local prefix_next = prefix .. "    "
            ngx.say(prefix .. "{")
            for k, v in pairs(data) do
                io.stdout:write(prefix_next .. k .. " = ")
                if type(v) ~= "table" or (type(max_level) == "number" and max_level <= 1) then
                    ngx.say(v)
                else
                    if max_level == nil then
                        var_dump(v, nil, prefix_next)
                    else
                        var_dump(v, max_level - 1, prefix_next)
                    end
                end
            end
            ngx.say(prefix .. "}")
        end
    end
end

function _M.get_client_ip()
    local headers = ngx.req.get_headers()
    local ip = headers["X-REAL-IP"] or headers["X_FORWARDED_FOR"] or ngx.var.remote_addr or "0.0.0.0"
    local ips = _M.string_split(ip,',')
    return ips[1]
end

-- 通过nginx的变量来取当前的工作环境,如果没有,则认为是线上生产环境
function _M.get_work_env()
    local env = ngx.var.work_env or "online"
    return env
end

function _M.is_online_env()
    local env = _M.get_work_env()
    if "online" == env then
        return true
    else
        return false
    end
end

function _M.is_dev_env()
    local env = _M.get_work_env()
    if "dev" == env then
        return true
    else
        return false
    end
end

function _M.dict2str(dict)
    if 'table' ~= type(dict) then
        return "It is not dict."
    end

    local str = ""
    for k, v in pairs(dict) do
        str = str .. k .. ":" .. tostring(v) .. ", "
    end

    return str
end

return _M
