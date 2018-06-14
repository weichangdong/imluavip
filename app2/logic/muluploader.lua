local mulupload_router = {}
local upload = require("resty.upload")
-- local uuid = require("app2.lib.uuid")
local utils = require("app2.lib.utils")
local config = require("app2.config.config")
local redis = require("app2.lib.redis")
local my_redis = redis:new()
local json = require("cjson.safe")

local sfind = string.find
local match = string.match
local os = os
local io = io
local exit = ngx.exit
local tinsert = table.insert
local ngxmatch = ngx.re.match

local function getextension(filename)
    return filename:match(".+%.(%w+)$")
end

local function _multipart_formdata(config,which,save_prefix,one2one)
    local form, err = upload:new(config.chunk_size)
    if not form then
        ngx.log(ngx.ERR, "failed to new upload: ", err)
        ngx.print('{"ret":3}')
        exit(200)
    end
    local which = which
    form:set_timeout(config.recieve_timeout)

    --local unique_name = uuid()
    local unique_name
    local success, msg = false, ""
    local file, origin_filename, filename, path, extname, url, err
    local prefix, suffix
    local isFile = false
    local params = {}
    local paramKey, paramValue
    local urls = {}
    local has_file = false
    local seq_num,tid_num
    local old_seq_num = 0
    local old_tid_num = 0
    local total_num = 0
    local type_prefix = "a"

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
                    seq_num = tonumber(match(origin_filename,"img_(%d+)"))
                    if not seq_num  or seq_num < 1 or seq_num > 9 then
                        ngx.print('{"ret":3}')
                        exit(200)
                    end
                    if seq_num - old_seq_num ~= 1 then
                        ngx.print('{"ret":3}')
                        exit(200)
                    end
                    old_seq_num = seq_num
                else
                    isFile = false
                    --tag check
                    tid_num = tonumber(match(paramKey,"tid_(%d+)"))
                    if tid_num then
                        if tid_num < 1 or tid_num > 10 then
                            ngx.print('{"ret":331}')
                            exit(200)
                        end
                        if tid_num - old_tid_num ~= 1 then
                            ngx.print('{"ret":332}')
                            exit(200)
                        end
                        old_tid_num = tid_num
                    end
                end
                --do param check
                if isFile then 
                    if not params.price or  params.price == "" then
                        ngx.print('{"ret":3}')
                        exit(200)
                    end
                    if one2one == 1 then
                        type_prefix = "b"
                        if params.position then
                            ngx.print('{"ret":3}')
                            exit(200)
                        end
                    else
                        if not params.position or utils.utf8len(params.position) > 50 then
                            ngx.print('{"ret":3}')
                            exit(200)
                        end
                    end
                    if not params.desc or utils.utf8len(params.desc) > 150 then
                        ngx.print('{"ret":3}')
                        exit(200)
                    end

                    if old_tid_num > 0 then
                        local  tname = "tname_"..old_tid_num
                        if not params[tname] or utils.utf8len(params[tname]) < 1 or utils.utf8len(params[tname]) > 10 or not ngxmatch(params[tname],"^[0-9a-zA-Z]*$","jo") then
                            ngx.print('{"ret":333}')
                            exit(200)
                        end
                    end

                end
            elseif prefix == "Content-Type" then
                filetype = suffix
            end

            if isFile and origin_filename and filetype then
                if not extname then
                    extname = getextension(origin_filename)
                    if not extname then
                        ngx.print('{"ret":3}')
                        exit(200)
                    end
                    if origin_filename ~= paramKey.."."..extname then
                        ngx.print('{"ret":3}')
                        exit(200)
                    end
                    extname = extname:lower()
                end

                if which == 0  and extname ~= "mp4"
                then
                    success = false
                    msg = "not allowed upload file type"
                    --ngx.log(ngx.ERR, "not allowed upload file type:", origin_filename)
                    ngx.print('{"ret":3}')
                    exit(200)
                    --return success, msg
                end

                if which == 1  and extname ~= "png" and extname ~= "jpg" and extname ~= "jpeg" and extname ~= "bmp" and extname ~= "gif"
                 then
                    success = false
                    ngx.print('{"ret":3}')
                    exit(200)
                    --msg = "not allowed upload file type"
                    --ngx.log(ngx.ERR, "not allowed upload file type:", origin_filename)
                    --return success, msg
                end
                ngx.update_time()
                unique_name = ngx.now() * 1000
                if extname == "png" then 
                    extname = "jpg"
                end
                filename = type_prefix..unique_name .. "_" .. seq_num.."."..extname
                if save_prefix then
                    filename = save_prefix .. "/" .. filename
                end
                path = config.dir .. filename
                
                --pl do
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
                tinsert(urls, {seq = seq_num, name = filename, ext = extname})
                total_num = total_num + 1
                file:close()
                url = filename
                file = nil
                filename = nil
                origin_filename = nil
                isFile = false
                filetype = nil
                has_file = true
                extname = nil
            else
                params[paramKey] = paramValue
            end
        elseif typ == "eof" then
            break
        end
    end

    return success, msg, url, params, urls, has_file, unique_name,total_num
end

mulupload_router.letsgo_add_img = function(req, res, next)
    local uid = req.params.uid
    local upload_config = {
        dir = config.upload.save_img_dir_moments,
        chunk_size = 4096,
        recieve_timeout = 30000,
    }
    local success, msg, file_name, params, urls, has_file, time_stamp,total_num = _multipart_formdata(upload_config,1,nil,0)
    if not success then
        ngx.print('{"ret":5}')
        exit(200)
    end
    if not has_file then
        ngx.print('{"ret":3}')
        exit(200)
    end

    local price = tonumber(params.price)
    if not utils.weather_in_array(price, {0,5,25}) then
        ngx.print('{"ret":3}')
        exit(200)
    end

    local  tags = {}
    local tags_num = 0
    if params.tid_1 then
        for k=1,10 do
            local tname = "tname_"..k
            local tid = "tid_"..k
            if params[tid] then
                local one = {
                    tid = tonumber(params[tid]),
                    tname = params[tname],
                }
                tags[k] = one
                tags_num = k
            end
        end
    end

    local queue_data = {
            queue_type = "moments_img",
            uid = uid,
            price = params.price,
            position = params.position or "",
            desc = params.desc or "",
            total_num = total_num,
            img_dir = upload_config.dir,
            img_urls = urls,
            mm_from = params.mm_from or 0,
            tags = tags,
            tags_num = tags_num,
    }
    my_redis:lpush(config.redis_key.queue_list_key, json.encode(queue_data))
    ngx.print('{"ret":0}')
    exit(200)
end

mulupload_router.one2one_add_img = function(req, res, next)
    local uid = req.params.uid
    local upload_config = {
        dir = config.upload.save_img_dir_one2one,
        chunk_size = 4096,
        recieve_timeout = 30000,
    }
    local success, msg, file_name, params, urls, has_file, time_stamp,total_num = _multipart_formdata(upload_config,1,nil,1)
    if not success then
        ngx.print('{"ret":5}')
        exit(200)
    end
    if not has_file then
        ngx.print('{"ret":3}')
        exit(200)
    end

    local price = tonumber(params.price)
    if not utils.weather_in_array(price, {0,5,25}) then
        ngx.print('{"ret":3}')
        exit(200)
    end
    local queue_data = {
            queue_type = "one2one_img",
            uid = uid,
            price = params.price,
            desc = params.desc or "",
            total_num = total_num,
            img_dir = upload_config.dir,
            img_urls = urls,
            mm_from = params.mm_from or 0
    }
    my_redis:lpush(config.redis_key.queue_list_key, json.encode(queue_data))
    ngx.print('{"ret":0}')
    exit(200)
end

return mulupload_router