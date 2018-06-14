local DB = require("app2.lib.mysql")
local config = require("app2.config.config")
local db = DB:new()
local video_model = {}

function video_model:insert_video(uid,video,cover,vinfo,iscover)
    return db:query("insert into user_video(uid,video,cover,vinfo,iscover) values(?,?,?,?,?)",{uid,video,cover,vinfo,iscover})
end

return video_model