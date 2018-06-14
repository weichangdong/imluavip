local DB = require("app2.lib.mysql")
local config = require("app2.config.config")
local db = DB:new(config.turn_mysql)
local turn_model = {}

function turn_model:insert_turn_user(uid,domain,token)
    return db:query("insert into turnusers_lt(realm,name,hmackey) values(?,?,?)",{domain,uid,token})
end

function turn_model:update_turn_user(uid,token)
    local res, err = db:query("update turnusers_lt set hmackey=? where name=?", {token, uid})
    return res, err
end
return turn_model