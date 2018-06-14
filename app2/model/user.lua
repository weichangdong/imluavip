local DB = require("app2.lib.mysql")
local db = DB:new()
local user_model = {}

function user_model:insert_user(fbid,loginname,fbemail,password,username,avatar,gender,accessToken,refreshToken,tokenexpires,country,myos,uniq,language,pkg,pkgver,pkgint,instime,createTime)
    return db:query("insert into user(fbid,loginname,fbemail,password,username,avatar,gender,accesstoken,refreshtoken,tokenexpires,country,os,uniq,language,pkg,pkgver,pkgint,instime,createtime) values(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",{fbid,loginname,fbemail,password,username,avatar,gender,accessToken,refreshToken,tokenexpires,country,myos,uniq,language,pkg,pkgver,pkgint,instime,createTime})
end

function user_model:query_by_ids(usernames)
   local res, err =  db:query("select id from user where username in(" .. usernames .. ")")
   return res, err
end

function user_model:query_fresh_token(old_token, fresh_token)
   local res, err =  db:query("select id from user where accesstoken=? and refreshtoken=?", {old_token, fresh_token})
   return res, err
end

function user_model:query_by_id(id)
    local result, err =  db:query("select * from user where id=?", {tonumber(id)})
    return result, err
end
function user_model:query_by_pass(loginname, passwd)
   local res, err =  db:query("select id,uniq,accesstoken,username,gender,avatar,super from user where loginname=? and password=?", {loginname, passwd})
   return res, err
end

function user_model:query_by_email(email)
    local result, err =  db:query("select id from user where loginname=?", {email})
    return result, err
end

function user_model:query_by_fbemail(email)
    local result, err =  db:query("select id,fbid,uniq,accesstoken,username,gender,avatar,super from user where loginname=?", {email})
    return result, err
end

function user_model:query_by_fbid(fbid)
    local result, err =  db:query("select id,fbid,uniq,accesstoken,username,gender,avatar,super from user where fbid!=0 and fbid=?", {fbid})
    return result, err
end

function user_model:update_user_fbid(fbid,uid)
    local res, err =  db:query("update user set fbid=? where id=? limit 1", {fbid,uid})
    return res, err
end

function user_model:get_tags()
    local result, err =  db:query("select name from tags")
    return result, err
end

-- return user, err
function user_model:query_by_username(username)
   	local res, err =  db:query("select * from user where username=? limit 1", {username})

   	if not res or err or type(res) ~= "table" or #res ~=1 then
		return nil, err or "error"
    end

	return res[1], err
end

function user_model:update_access_token(token,fresh_token,tokenexpires, userid)
    local res, err = db:query("update user set accesstoken=?,refreshtoken=?,tokenexpires=? where id=? limit 1", {token,  fresh_token,tokenexpires, userid})
    return res, err
end
function user_model:update_access_token_and_other(token,fresh_token,tokenexpires,country,uniq,language,userid)
    return  db:query("update user set accesstoken=?,refreshtoken=?,tokenexpires=?,country=?,uniq=?,language=? where id=? limit 1", {token,fresh_token,tokenexpires,country,uniq,language,userid})
end

function user_model:update_user_avatar(avatar, uid)
    local db = DB:new()
    local res, err = db:query("update user set avatar=? where id=? limit 1", {avatar, uid})
    return res, err
end

function user_model:update_user_zhubo(uid)
    local res, err =  db:query("update user set zhubo=1 where id=? limit 1", {uid})
    return res, err
end

function user_model:update_user(userid,zhubo,telents,tags)
    local res, err = db:query("update user set zhubo=?,telents=?,tags=? where id=?", {zhubo,telents,tags,userid})
    return res, err
end

function user_model:update_pass(pass, userid)
    local res, err = db:query("update user set password=? where id=?", {pass,userid})
    return res, err
end

function user_model:get_all_user()
    local res, err = db:query("select * from user")
    return res, err
end

function user_model:get_all_video()
    local res, err = db:query("select * from user_video")
    return res, err
end

function user_model:get_user_gender_by_limit(gender,start,limit_num)
    local res, err = db:query("select  id,super,username,avatar from user where gender=? order by id desc limit ?,?",{gender,start,limit_num})
    return res, err
end

function user_model:update_user_email(email,uid)
    if email then
        db:query("update user set loginname=concat('nouse_',loginname) where loginname=? limit 1", {email})
    elseif uid then
        db:query("update user set fbid=concat('10',fbid) where id=? limit 1", {uid})
    end
end

return user_model