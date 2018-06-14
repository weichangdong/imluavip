local upload_router = {}
local upload = require("resty.upload")
-- local uuid = require("app2.lib.uuid")
local utils = require("app2.lib.utils")
local config = require("app2.config.config")
local redis = require("app2.lib.redis")
local mysql = require("app2.model.user")
local json = require("cjson.safe")

local sfind = string.find
local match = string.match
local os = os
local io = io
local exit = ngx.exit
local shared_cache = ngx.shared.fresh_token_limit

local function getextension(filename)
    return filename:match(".+%.(%w+)$")
end

local function access_limit(res, key, limit_num, limit_time)
    local time = limit_time or 60
    local num = limit_num or 0
    local key = 'up_'..key
    local limit_v = shared_cache:get(key)
    if not limit_v then
        shared_cache:set(key, 1, time)
    else
        if limit_v > num then
            --res:status(400):json({})
            ngx.print('{"ret":3}')
            exit(200)
        end
        shared_cache:incr(key, 1)
    end
end

local function _multipart_formdata(config,which,save_prefix)
    local form, err = upload:new(config.chunk_size)
    if not form then
        ngx.log(ngx.ERR, "failed to new upload: ", err)
        ngx.print('{"ret":3}')
        exit(200)
    end
    local which = which
    form:set_timeout(config.recieve_timeout)

    --local unique_name = uuid()
    local unique_name = ngx.time() .. utils.img_random()
    local success, msg = false, ""
    local file, origin_filename, filename, path, extname, url, err
    local prefix, suffix
    local isFile = false
    local params = {}
    local paramKey, paramValue

    while true do
        local typ, res, err = form:read()

        if not typ then
            success = false
            msg = "failed to read"
            ngx.log(ngx.ERR, "failed to read: ", err)
            return success, msg
        end

        if err then
            ngx.log(ngx.ERR, "read form err: ", err)
        end

        if typ == "header" then
            prefix, suffix = res[1], res[2]

            if prefix == "Content-Disposition" then
                paramKey = match(suffix, 'name="(.-)"')
                origin_filename = match(suffix, 'filename="(.-)"')
                if origin_filename then
                    isFile = true
                else
                    isFile = false
                end
            elseif prefix == "Content-Type" then
                filetype = suffix
            end

            if isFile and origin_filename and filetype then
                if not extname then
                    extname = getextension(origin_filename)
                    extname = extname:lower()
                end

                if which == 0  and extname ~= "mp4"
                then
                    success = false
                    msg = "not allowed upload file type"
                    ngx.log(ngx.ERR, "not allowed upload file type:", origin_filename)
                    return success, msg
                end

                if which == 1  and extname ~= "png" and extname ~= "jpg" and extname ~= "jpeg" and extname ~= "bmp" and extname ~= "gif"
                 then
                    success = false
                    msg = "not allowed upload file type"
                    ngx.log(ngx.ERR, "not allowed upload file type:", origin_filename)
                    return success, msg
                end

                

                filename = unique_name .. "." .. extname
                if save_prefix then
                    filename = save_prefix .. "/" .. filename
                end
                path = config.dir .. "/" .. filename

                file, err = io.open(path, "w+")

                if err then
                    success = false
                    msg = "open file error"
                    ngx.log(ngx.ERR, "open file error:", err)
                    return success, msg
                end
            end
        elseif typ == "body" then
            if isFile then
                if file then
                    file:write(res)
                    success = true
                else
                    success = false
                    msg = "upload file error"
                    ngx.log(ngx.ERR, "upload file error, path:", path)
                    return success, msg
                end
            else
                success = true
                paramValue = res
            end
        elseif typ == "part_end" then
            if isFile then
                file:close()
                url = filename
                file = nil
                filename = nil
                origin_filename = nil
                isFile = false
                filetype = nil
            else
                params[paramKey] = paramValue
            end
        elseif typ == "eof" then
            break
        end
    end

    return success, msg, url, params
end

upload_router.upload_video = function(req, res, next)
    local upload_config = {
        dir = config.upload.save_dir,
        chunk_size = 4096,
        recieve_timeout = 30000,
        resource_url = config.upload.resource_url,
        aws_s3_dir = config.upload.aws_s3_dir,
        aws_s3_cmd = config.upload.aws_s3_cmd
    }
    local success, msg, file_name, params = _multipart_formdata(upload_config, 0, nil)
    if not success then
        ngx.print('{"ret":5003}')
        exit(200)
    end
    -- upload video to aws s3
    local upload_cmd = upload_config.aws_s3_cmd .. upload_config.dir .. file_name .. upload_config.aws_s3_dir .. file_name
    os.execute(upload_cmd)
    local check_cmd = "curl -sI " .. upload_config.resource_url .. file_name
    local t = io.popen(check_cmd)
    local a = t:read("*line")
    local ret_code = sfind(a, "200", 1, true)
    if not ret_code then
        ngx.print('{"ret":5003}')
        exit(200)
    end
    local dat = {
        url = upload_config.resource_url .. file_name
    }
    local aes_dat = utils.encrypt(dat, req.query.aes)
    res:json(
        {
            ret = 0,
            dat = aes_dat
        }
    )
end

upload_router.upload_img = function(req, res, next)
    local uid = req.params.uid
    access_limit(res, "img_"..uid)
    local upload_config = {
        dir = config.upload.save_dir,
        chunk_size = 4096,
        recieve_timeout = 30000,
        resource_url = config.upload.resource_url,
        aws_s3_dir = config.upload.aws_s3_dir,
        aws_s3_cmd = config.upload.aws_s3_cmd
    }
    local success, msg, file_name, params = _multipart_formdata(upload_config,1,nil)
    if not success then
        ngx.print('{"ret":5003}')
        exit(200)
    end
    -- upload img to aws s3
    local upload_cmd = upload_config.aws_s3_cmd .. upload_config.dir .. file_name .. upload_config.aws_s3_dir .. file_name
    os.execute(upload_cmd)
    local check_cmd = "curl -sI " .. upload_config.resource_url .. file_name
    local t = io.popen(check_cmd)
    local a = t:read("*line")
    local ret_code = sfind(a, "200", 1, true)
    if not ret_code then
        ngx.print('{"ret":5003}')
        exit(200)
    end
    local dat = {
        url = upload_config.resource_url .. file_name
    }
    local aes_dat = utils.encrypt(dat, req.query.aes)
    res:json(
        {
            ret = 0,
            dat = aes_dat
        }
    )
end

upload_router.update_avatar = function(req, res, next)
    local uid = req.params.uid
    access_limit(res, "avatar_"..uid)
    local upload_config = {
        dir = config.upload.save_dir,
        chunk_size = 4096,
        recieve_timeout = 20000,
        resource_url = config.upload.resource_url,
        aws_s3_dir = config.upload.aws_s3_dir,
        aws_s3_cmd = config.upload.aws_s3_cmd
    }
    local success, msg, file_name, params = _multipart_formdata(upload_config,1,'avatar')
    if not success then
        ngx.print('{"ret":5003}')
        exit(200)
    end
    -- upload img to aws s3
    local upload_cmd = upload_config.aws_s3_cmd .. upload_config.dir .. file_name .. upload_config.aws_s3_dir .. file_name
    os.execute(upload_cmd)
    local check_cmd = "curl -sI " .. upload_config.resource_url .. file_name
    local t = io.popen(check_cmd)
    local a = t:read("*line")
    local ret_code = sfind(a, "200", 1, true)
    if not ret_code then
        ngx.print('{"ret":5003}')
        exit(200)
    end
    local url = upload_config.resource_url .. file_name
    local my_redis = redis:new()
    local user_base_info = my_redis:hget(config.redis_key.user_prefix .. uid, "base_info")
    local ok_user_base_info = json.decode(user_base_info) or nil
    if not ok_user_base_info then
        ngx.print('{"ret":3}')
        exit(200)
    end

    local base_info = {
        username = ok_user_base_info.username,
        avatar = url,
        uniq = ok_user_base_info.uniq,
        gender = ok_user_base_info.gender,
        super = ok_user_base_info.super
    }
    -- save anchor base info
    my_redis:hset(config.redis_key.user_prefix .. uid, "base_info", json.encode(base_info))
    local dat = {
        url = url
    }
    local aes_dat = utils.encrypt(dat, req.query.aes)
    res:json({
            ret = 0,
            dat = aes_dat
    })
    -- sync data to mysql
    local need_cron_data = {
        act = 'update_avatar',
        uid = uid,
        data = {
            url = url
        }
    }
    my_redis:rpush(config.redis_key.cron_list_key, json.encode(need_cron_data))
    exit(200)
end

return upload_router
