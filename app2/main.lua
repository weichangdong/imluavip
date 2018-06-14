local lor = require("lor.index")
local user1_router = require("app2.logic.user1")
local user2_router = require("app2.logic.user2")
local user3_router = require("app2.logic.user3")
local user4_router = require("app2.logic.user4")
local user5_router = require("app2.logic.user5")
local user6_router = require("app2.logic.user6")
local moments_router = require("app2.logic.moments")
local html_router = require("app2.logic.html")
local upload_router = require("app2.logic.uploader")
local voucher_router = require("app2.logic.voucher")
local mulupload_router = require("app2.logic.muluploader")
local config = require("app2.config.config")
local app = lor()
local redis = require("app2.lib.redis")
local utils = require("app2.lib.utils")
local json = require("cjson.safe")
local error_500 = {ret = 5}
local error_404 = {ret = 4}
local exit = ngx.exit

-- 用于刷新token 传过来的token有可能已经过期
local check_header = function(req, res, next)
    local token = req.headers["APPINFO"]
    if not token or token == "" or type(token) ~= "string" then
        ngx.print('{"ret":3}')
        exit(200)
    end
    req.params.token = token
    next()
end


-- 验证token
local check_token = function(req, res, next)
    local token = req.headers["APPINFO"]
    if not token or token == "" or type(token) ~= "string" then
        res:status(401):json({})
        exit(200)
    end
    local my_redis = redis:new()
    local ok_uid = my_redis:hget(config.redis_key.token_prefix .. token, config.redis_key.token_uid_key)
    if utils.is_redis_null(ok_uid) then
        res:status(401):json({})
        exit(200)
    else
        local str = my_redis:get(config.redis_key.block_user_key .. ok_uid)
        if not utils.is_redis_null(str) then
            ngx.print('{"ret":44,"msg":"'..str..'"}')
            exit(200)
        end
        req.params.uid = ok_uid
        req.params.token = token
        --ngx.ctx.uid = ok_uid
    end
    next()
end


-- 特殊验证token
local sp_check_token = function(req, res, next)
    local token = req.headers["APPINFO"]
    if token and token ~= "" and type(token) == "string" then
        local my_redis = redis:new()
        local ok_uid = my_redis:hget(config.redis_key.token_prefix .. token, config.redis_key.token_uid_key)
        if utils.is_redis_null(ok_uid) then
            --ngx.log(ngx.ERR,"kim=="..token.."==kim")
            res:status(401):json({})
            exit(200)
        else
            local str = my_redis:get(config.redis_key.block_user_key .. ok_uid)
            if not utils.is_redis_null(str) then
                ngx.print('{"ret":44,"msg":"'..str..'"}')
                exit(200)
            end
            req.params.uid = ok_uid
            req.params.token = token
            --ngx.ctx.uid = ok_uid
        end
    end
    next()
end

local check_ip = function(req, res, next)
    local ip = utils.get_client_ip()
    if ip ~= "127.0.0.1" then
        ngx.say("Access is not allowed "..ip)
        res:status(401):json({})
        exit(403)
    end
    next()
end

-- 1期接口
app:get("/",function(req, res, next)
        ngx.say(config.redis_key.queue_list_key)
        exit(200)
end)

app:get("/tags", check_token, user1_router.get_tags)
--app:post("/resource/video", check_token, upload_router.upload_video)
app:post("/resource/image", check_token, upload_router.upload_img)
app:post("/anchor", check_token, user1_router.update_anchor)
app:get("/anchors/details", check_token, user1_router.get_anchor)
app:post("/anchors/all", sp_check_token, user1_router.get_allanchors)
app:get("/anchors/mine", check_token, user1_router.get_myanchors)
app:get("/anchors/audiences", check_token, user1_router.get_audiences)
app:get("/account/refresh", check_header, user1_router.refresh_token)
app:get("/config", check_token, user1_router.get_config)

-- 2期接口
app:post("/account/getcodereset", user2_router.get_code_reset)
app:post("/account/login", user2_router.login)
app:post("/account/getcode", user2_router.get_code)
app:post("/account/verifycodereset", user2_router.verify_code_reset)
app:post("/account/verifycode", user2_router.verify_code)
app:post("/account/register", user2_router.register_user)
app:post("/account/resetpass", user2_router.reset_pass)
app:post("/account/avatar", check_token, upload_router.update_avatar)  
app:get("/homepage/look/:id", check_token, user2_router.look_others_homepage)
app:get("/homepage/me", check_token, user2_router.look_myself_page)
app:get("/homepage/fans/:type", check_token, user2_router.look_fans)
app:post("/homepage/follow", check_token, user2_router.do_follow)
app:post("/account/updatename", check_token, user2_router.update_username)
app:post("/account/updatebrief", check_token, user2_router.update_brief)
app:get("/account/setcover/:id", check_token, user2_router.set_cover)
app:post("/resource/delvideo", check_token, user2_router.del_video)
app:post("/anchors/state", user2_router.get_states)
app:post("/account/addvideo", check_token, user2_router.add_video)
app:post("/homepage/checkfans", check_token, user2_router.check_fans)
app:post("/fcm/token", check_token, user2_router.up_token)
app:get("/anchors/queryanchor", check_token, user2_router.query_anchor)
app:get("/homepage/myvideo", check_token, user2_router.look_my_video)

-- 3期接口
--local google_token_router = require("app2.logic.token")
--app:get("/google/authorize", google_token_router.google_authorize)
--app:get("/google/callback", google_token_router.google_callback)
app:post("/money/money2creditconfig", check_token, user3_router.money2credit_config)
app:get("/money/coin2creditconfig", check_token, user3_router.coin2credit_config)
app:get("/money/creditlog/:page/:limit", check_token, user3_router.credit_log)
app:get("/money/coinlog/:page/:limit", check_token, user3_router.coin_log)
app:post("/money/coin2credit", check_token, user3_router.coin_to_credit)
app:post("/money/uplevel", check_token, user3_router.up_level)
app:post("/money/getmoney", check_token, user3_router.get_money)
app:get("/money/dailygift", check_token, user3_router.daily_gift)
app:post("/money/sessioninfo", check_token, user3_router.session_info)
app:get("/money/mywallet", check_token, user3_router.my_wallet)
app:post("/money/getpayload", check_token, voucher_router.google_paypal_get_payload)
app:post("/money/payverify", check_token, voucher_router.google_pay_verify)

--4期接口
app:get("/money/giftconfig", check_token, user4_router.gift_config)
app:post("/account/fblogin", user4_router.fb_login)
app:post("/money/prepayid", check_token, voucher_router.weixin_zhifubao_get_prepayid)
app:post("/money/payquery", check_token, voucher_router.weixin_zhifubao_pay_query)
app:post("/wxpay/notify", voucher_router.weixin_pay_notify)
app:get("/resource/preupload/:type", check_token, user4_router.gogogo_preupload)

--5期接口
app:get("/moments/pricelist", check_token, user5_router.price_list)
app:post("/moments/letsaddimg", check_token, mulupload_router.letsgo_add_img)
app:post("/moments/letsaddvideo", check_token, user5_router.letsgo_add_video)
app:post("/moments/letslist", sp_check_token, user5_router.letsgo_mm_list)
app:post("/moments/letspay", check_token, user5_router.letsgo_mm_pay)
app:post("/moments/letsdel", check_token, user5_router.letsgo_mm_del)
app:post("/moments/report", check_token, user5_router.letsgo_mm_report)
app:get("/moments/share/:id", html_router.letsgo_get_html)
app:post("/moments/mylist", check_token, user5_router.letsgo_get_mylist)

--6期接口
app:post("/account/fbcheck", user4_router.fb_check)
app:get("/account/starslist", check_token, user5_router.stars_list_config)
app:get("/one2one/pricelist", check_token, user6_router.one2one_price_list)
app:post("/one2one/letsaddimg", check_token, mulupload_router.one2one_add_img)
app:post("/one2one/letsdel", check_token, user6_router.one2one_lets_del)
app:post("/one2one/mylist", check_token, user6_router.one2one_mylist)
app:post("/moments/selectedlist", sp_check_token, user5_router.mm_selected_list)
app:post("/moments/imperialsword", check_token, user5_router.mm_imperial_sword)

--12月第1周需求
app:post("/editor/alllist", sp_check_token, user6_router.editor_all_list)
app:post("/editor/onelist", check_token, user6_router.editor_one_list)

--12月第2周需求
app:post("/anchors/online", sp_check_token, user6_router.anchors_online_list)
app:get("/money/dailysend", check_token, user6_router.daily_send_credit_vip)
app:post("/optools/onlinebyids", check_token, user6_router.online_by_ids)
app:post("/optools/toponline", check_token, user6_router.top100_online)
app:post("/homepage/myfans", check_token, user2_router.look_my_fans)
app:post("/moments/grade", check_token,  moments_router.grade_mm)
app:post("/moments/mylike", check_token, moments_router.mylike)

--1月第1周需求
app:post("/moments/tagmmlist", sp_check_token, user6_router.tag_moments_list)
app:post("/moments/tags", check_token, user6_router.tags_list)

--paypal
app:post("/paypal/notify", voucher_router.paypal_gogogo_notify)
app:post("/money/paypalquery", check_token, voucher_router.paypal_gogogo_query)

-- 测试工具
app:post("/check_input", user2_router.check_input)
app:post("/setcoincredit", check_token, user3_router.set_coin_credit)
app:post("/uplevel", check_token, user5_router.up_mylevel)
app:post("/jiame", check_ip, user3_router.test_jia_me)
app:post("/jieme", check_ip, user3_router.test_jie_me)
app:get("/paypal/wcd_test", voucher_router.wcd_test)
app:get("/paypal/cls_first_voucher", check_token, voucher_router.set_first_voucher)
app:post("/reset_email", user3_router.reset_email)
--app:get("/repair", user1_router.repair)

app:erroruse(function(err, req, res, next)
        if req:is_found() ~= true then
            res:status(404):json(error_404)
        else
            ngx.log(ngx.ERR, err)
            res:status(500):json(error_500)
        end
end)
app:run()
