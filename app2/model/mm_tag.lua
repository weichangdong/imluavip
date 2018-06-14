local DB = require("app2.lib.mysql")
local db = DB:new()
local mm_tag_model = {}

function mm_tag_model:get_mm_ids_by_where(add_type_so,pay_so,gender_so,limit_num,need_new,need_old)
    local where = " one2one=0 "
    if need_new then
        where = where .. " and `id`>"..need_new
    end
    if need_old then
        where = where .. " and `id`<"..need_old
    end
    if add_type_so then
        where = where .. " and `type`="..add_type_so
    end
    if pay_so then
        if pay_so == 1 then
            where = where .. " and price>0"
        else
            where = where .. " and price=0"
        end
    end
    if gender_so then
        where = where .. " and `gender`="..gender_so
    end
    where = where .. " order by id desc limit "..limit_num
    local sql = "select  id from moments_data where "..where
    --ngx.say(sql)
    local res, err = db:query(sql)
    return res, err
end

function mm_tag_model:get_tag_mm_ids(tid,limit_num,need_new,need_old)
    local where = " `tid`="..tid
    if need_new then
        where = where .. " and `mm_id`>"..need_new
    end
    if need_old then
        where = where .. " and `mm_id`<"..need_old
    end
    where = where .. " order by id desc limit "..limit_num
    local sql = "select  mm_id from moments_tags_data where "..where
    --ngx.say(sql)
    local res, err = db:query(sql)
    if res then
        return res, err
    else
        return {},{}
    end
    
end

return mm_tag_model