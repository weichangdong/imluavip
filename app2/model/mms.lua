local json = require("cjson.safe")
local config = require("app2.config.config")
local utils = require("app2.lib.utils")
local DB = require("app2.lib.mysql")
local db = DB:new()
local redis = require("app2.lib.redis")
local my_redis = redis:new()
local sformat  = string.format
local slen = string.len
local tonumber = tonumber
local tostring = tostring
local append  = table.insert
local pairs  = pairs
local ipairs = ipairs
local math = math
local ngx =  ngx

local _M = { _VERSION = '0.0.1' }
_M.__index = _M
_M.db = db
_M.grade_table = "user_grade_mms"
_M.page_size   = 20

--[[
     点赞 {
  "id": 946,
  "like": 1,
  "unlike": 0
}
 取消点赞{
  "id": 946,
  "like": -1,
  "unlike": 0
}
 踩  {
  "id": 946,
  "like": 0,
  "unlike": 1
}
取消踩 {
  "id": 946,
  "like": 0,
  "unlike": -1
}
]]

local  select_grade_info  = function(grade_uid, mm_id)
    local sql = "select  *  from  user_grade_mms where `grade_uid`="..grade_uid.." and `mm_id`="..mm_id
    return db:query(sql)
end

local  add_and_update_grade_info  = function(is_new,old_id,grade_uid, mm_id, like, unlike, ctime,need_del)
    local sql
    if is_new then
        sql = "INSERT INTO user_grade_mms(grade_uid, mm_id, `like`, unlike, ctime) VALUES(?, ?, ?, ?, ?)"
        db:query(sql, {grade_uid, mm_id, like, unlike, ctime})
    elseif old_id > 0 then
        if need_del then
            db:query("delete from  user_grade_mms where `id`="..old_id)
        else
            sql = "update user_grade_mms set `like`="..like..",`unlike`="..unlike..",`ctime`="..ctime.." where `id`="..old_id.. " limit  1"
            db:query(sql)
        end
    end
end


function _M:add_grade(grade_uid, mm_id, like, unlike, ctime)
    local old_info = select_grade_info(grade_uid,mm_id)
    local is_new = true
    local old_id = 0 
    local need_del = false
    if old_info and old_info[1] and old_info[1].id then
        is_new = false
        old_id = tonumber(old_info[1].id)
    end
    if like == 1 and unlike == 0  then --点赞
        add_and_update_grade_info(is_new, old_id, grade_uid, mm_id, 1, 0, ctime, need_del)
    elseif like == -1 and unlike == 0 then --取消点赞
        --这数据直接可以干掉
        need_del = true
        add_and_update_grade_info(is_new, old_id, grade_uid, mm_id, 0, 0, ctime, need_del)
    elseif  like == 0 and unlike == 1 then --踩
        add_and_update_grade_info(is_new, old_id, grade_uid, mm_id, 0, 1, ctime, need_del)
    elseif like == 0 and unlike == -1 then --取消踩
        need_del = true
        add_and_update_grade_info(is_new, old_id, grade_uid, mm_id, 0, 0, ctime, need_del)
    end
end


function _M:get_mm_grade_score(mm_id, grade_uid)
    local score = {id = mm_id, like = 0, unlike = 0, like_num = 0, unlike_num = 0}
    local sql = sformat("SELECT SUM(`like`) AS `like`, SUM(`unlike`) AS unlike FROM %s WHERE mm_id = %d LIMIT 1", self.grade_table,mm_id)
    local res, err, errno, sqlstate = db:query(sql)
    if not res or #res <= 0 or not res[1].like  then
        return score
    end

    local r = res[1]
    -- hard code
    local like   = tonumber(r.like) or 0
    local unlike = tonumber(r.unlike) or 0
    local total  = like + unlike
    -- 赞/踩 总数大于等于10显示
    if total >= 10 then
        score.like_num   = math.floor(like * 100 / total)
        score.unlike_num = 100 - score.like_num
    end

    -- 查看用户对帖子的操作情况
    grade_uid = tonumber(grade_uid)
    if not grade_uid or grade_uid <= 0 then
        return score
    end

    sql = sformat("SELECT `like`, unlike FROM %s WHERE grade_uid = %d AND mm_id = %d ORDER BY id DESC LIMIT 1", self.grade_table, grade_uid, mm_id)
    res, err, errno, sqlstate = db:query(sql)
    if not res or not res[1] or not res[1].like then
        score.like   = 0
        score.unlike = 0
        return score
    end

    r = res[1]
    score.like   = tonumber(r.like)
    score.unlike = tonumber(r.unlike)
    return score
end

-- 默认按操作时间反序,每页20条
function _M:get_my_like_mms_ids(uid, ugm_id)
    --[[
    local sub_sql = sformat("(SELECT id AS ugm_id, grade_uid, mm_id, `like`, unlike FROM %s WHERE id IN(SELECT MAX(id) AS id FROM %s WHERE grade_uid = %d GROUP BY `mm_id`)) AS T", self.grade_table, self.grade_table, uid)
    local sql = sformat("SELECT mm_id, ugm_id, `like`, unlike FROM %s", sub_sql)
    sql = sformat("%s WHERE `like` = 1", sql)
    if ugm_id ~= nil and ugm_id > 0 then
        sql = sformat("%s AND ugm_id < %d", sql, ugm_id)
    end
    sql = sformat("%s ORDER BY ugm_id DESC LIMIT %d", sql, self.page_size)
    ngx.log(ngx.INFO, "[SQL] get_my_like_mms_ids: ", sql)
    --]]
    local sql
    if ugm_id and ugm_id > 0  then
        sql = "select id as ugm_id,mm_id, `like`, unlike from "..self.grade_table.. " where  `like`=1 and `grade_uid`="..uid.." and id<"..ugm_id.." ORDER BY ugm_id DESC LIMIT ".. self.page_size
    else
        sql = "select id as ugm_id,mm_id, `like`, unlike from "..self.grade_table.. " where  `like`=1 and `grade_uid`="..uid.." ORDER BY ugm_id DESC LIMIT ".. self.page_size
    end
    local res, err = db:query(sql)

    return res, err
end

function _M:get_mm_info_from_redis(mm_id, myuid)
    local is_vip = 0
    if myuid then
        is_vip = my_redis:exists(config.redis_key.vip_user_key..myuid)
    end

    local last_rand_num = 2
    local is_pvip = 0
    local all_pvips = {}
    local base_info_tmp_all = {}

    local if_weather_follow = 0
    local is_unlock = 0
    local mm_redis_key = config.redis_key.moments_prefix_hash_key .. mm_id
    local real_data_tmp = my_redis:hmget(mm_redis_key, "data","tags")
    local one = {}
    if not utils.is_redis_null(real_data_tmp) and not utils.is_redis_null(real_data_tmp[1]) then
        local real_data = json.decode(real_data_tmp[1]) or {}
        local uid = real_data.uid
        if uid then
            local real_data_price = real_data.price
            local hot_num
            local rand_num
            local unlock_num = 0
            if real_data_price > 0 then
                --hot_num = my_redis:hincrby(mm_redis_key,"hot", 1)
                hot_num = utils.img_random()
                unlock_num = my_redis:hget(mm_redis_key,"unlock_num")
                unlock_num = tonumber(unlock_num)
            else
                rand_num = utils.fb_random(3)
                if rand_num == last_rand_num then
                    rand_num = 1
                end
                hot_num = my_redis:hincrby(mm_redis_key,"hot", rand_num)
                last_rand_num = rand_num
            end
            local base_info_tmp
            if base_info_tmp_all[uid] then
                base_info_tmp = base_info_tmp_all[uid]
            else
                base_info_tmp = my_redis:hget(config.redis_key.user_prefix .. uid, "base_info")
                base_info_tmp_all[uid] = base_info_tmp
            end
            if not utils.is_redis_null(base_info_tmp) then
                local base_info = json.decode(base_info_tmp)
                if myuid and myuid ~= uid then
                    local is_my_fans = my_redis:zscore(config.redis_key.follow_me_prefix .. uid, myuid)
                    if not utils.is_redis_null(is_my_fans) then
                        if_weather_follow = 1
                    end
                    if is_vip == 0 and real_data_price > 0 then
                        local is_payed = my_redis:hexists(mm_redis_key, config.redis_key.moments_pay_uid_key .. myuid)
                        if is_payed == 1 then
                            is_unlock = 1
                        end
                    end

                    if not all_pvips[uid] then
                        is_pvip = my_redis:exists(config.redis_key.vip_user_key..uid)
                        all_pvips[uid] = is_pvip
                    else
                        is_pvip = all_pvips[uid]
                    end
                elseif myuid == uid then
                    is_pvip = is_vip
                end
                local tags = json.decode(real_data_tmp[2]) or {}
                --1:img-list 2:video
                if real_data.add_type == 1 then -- {
                    one = {
                        uid = uid,
                        username = base_info.username,
                        avatar = base_info.avatar,
                        icare = if_weather_follow,
                        super = base_info.super or 0,
                        id = tonumber(mm_id),
                        time_stamp = real_data.time_stamp,
                        add_type = 1,
                        img_urls = real_data.img_urls,
                        base_url = real_data.base_url,
                        price = real_data_price,
                        position = real_data.position,
                        mm_from = real_data.mm_from or 0,
                        desc = real_data.desc,
                        hot_num = hot_num,
                        unlock_num = unlock_num,
                        unlock = is_unlock,
                        h5_url = "moments/share/",
                        pvip = is_pvip,
                        tags = tags,
                    }
                --}
                else -- {
                    one = {
                        uid = uid,
                        username = base_info.username,
                        avatar = base_info.avatar,
                        icare = if_weather_follow,
                        super = base_info.super or 0,
                        id = tonumber(mm_id),
                        time_stamp = real_data.time_stamp,
                        add_type = 2,
                        video_url = real_data.video_url,
                        base_url = real_data.base_url,
                        video_cover = real_data.video_cover,
                        video_width = real_data.video_width,
                        video_height = real_data.video_height,
                        price = real_data_price,
                        position = real_data.position,
                        mm_from = real_data.mm_from or 0,
                        desc = real_data.desc,
                        hot_num = hot_num,
                        unlock_num = unlock_num,
                        unlock = is_unlock,
                        h5_url = "moments/share/",
                        pvip = is_pvip,
                        tags = tags,
                    }
                end --}
            end
        end
    end
    return one
end

function _M:get_my_like_list(uid, ugm_id)
    local list = {}
    if ugm_id < 0 then
        return nil
    end

    local my_like_mms_ids, err = self:get_my_like_mms_ids(uid, ugm_id)
    if not my_like_mms_ids or #my_like_mms_ids == 0 then
        return nil
    end
    local ok_num = 0
    for k, ugm in ipairs(my_like_mms_ids) do
        local l = self:get_mm_grade_score(ugm.mm_id)
        l.ugm_id = ugm.ugm_id
        -- 用户实际数据覆盖掉默认的
        l.like   = tonumber(ugm.like) or 0
        l.unlike = tonumber(ugm.unlike) or 0

        local mm_info = self:get_mm_info_from_redis(ugm.mm_id, uid)
        if mm_info and mm_info.id then
            for k, v in pairs(mm_info) do
                l[k] = v
            end
            append(list, l)
            ok_num = ok_num + 1
        end
    end
    if ok_num > 0 then
        return list
    end
    return nil
end


function _M:merge_mm_info(mm_info, myuid)
    if not mm_info.id or mm_info.id <= 0 then
        return false
    end

    local mm_score = self:get_mm_grade_score(mm_info.id, myuid)
    mm_info.like   = mm_score.like
    mm_info.unlike = mm_score.unlike
    mm_info.like_num   = mm_score.like_num
    mm_info.unlike_num = mm_score.unlike_num

    return mm_info
end


return _M