-- 这期先以实现功能为主 2017.12
local config = require("app2.config.config")
local json  = require("cjson.safe")
local utils = require("app2.lib.utils")
local mms_model = require("app2.model.mms")
local redis = require("app2.lib.redis")
local my_redis = redis:new()

local ngx = ngx
local md5 = ngx.md5
local exit = ngx.exit
local pcall = pcall
local table_object  = json.encode_empty_table_as_object

local tinsert = table.insert
local tsort = table.sort
local tonumber = tonumber
local tostring = tostring
local match = string.match
local slen = string.len
local pairs = pairs
local ipairs = ipairs
local string = string
local ngx_quote_sql_str = ngx.quote_sql_str

local _M = { _VERSION = '0.0.1' }

_M.grade_mm = function(req, res, next)
    local post_data = {}
    local raw_post_data = req.body
    utils.check_para(raw_post_data)
    raw_post_data = utils.decrypt(raw_post_data, req.query.aes)
    post_data = json.decode(raw_post_data)
    if utils.is_table_empty(post_data) then
        ngx.print('{"ret":3}')
        exit(200)
    end

    -- 先简单校验
    if not post_data.id or not post_data.like or not post_data.unlike then
        ngx.print('{"ret":3}')
        exit(200)
    end

    local grade_uid = req.params.uid
    local ctime = ngx.now() * 1000
    mms_model:add_grade(grade_uid, post_data.id, post_data.like, post_data.unlike, ctime)
    ngx.print('{"ret":0}')
    exit(200)
end


_M.mylike = function(req, res, next)
    local post_data = {}
    local raw_post_data = req.body
    utils.check_para(raw_post_data)
    raw_post_data = utils.decrypt(raw_post_data, req.query.aes)
    post_data = json.decode(raw_post_data)
    if utils.is_table_empty(post_data) then
        ngx.print('{"ret":3}')
        exit(200)
    end

    -- 先简单校验
    if not post_data.ugm_id then
        ngx.print('{"ret":3}')
        exit(200)
    end
    
    local myuid = req.params.uid
    local is_vip = my_redis:exists(config.redis_key.vip_user_key .. myuid)
    local list_info = mms_model:get_my_like_list(myuid, tonumber(post_data.ugm_id))
    if not list_info then
        ngx.print('{"ret":37}')
        exit(200)
    end

    local dat = {
        list  = list_info,
        vip   = is_vip
    }
    local aes_dat = utils.encrypt(dat, req.query.aes)
    local re = {}
    re["ret"] = 0
    re["dat"] = aes_dat
    res:json(re)
    exit(200)
end

return _M
