local google_token_router = {}
local ngx = ngx
local md5 = ngx.md5
local exit = ngx.exit
local utils = require("app2.lib.utils")
local json = require("cjson.safe")
local config = require("app2.config.config")
local http = require "resty.http"
local httpc = http.new()
local google_callback_url = "http://localhost:2222/google/callback"

function google_token_router.google_authorize(req,res,next)
  local url = "https://accounts.google.com/o/oauth2/auth"
  local scope = "https://www.googleapis.com/auth/androidpublisher"
  local qs = {
    client_id = config.voucher.client_id,
    redirect_uri =  google_callback_url,
    response_type = "code",
    scope = scope,
    approval_prompt = 'force',
    access_type = 'offline',
  }
  local jump_url = url .. "?" .. utils.encode_query_string(qs)
  local html_jump_url = "<a href="..jump_url..">click me".."</a>"
  ngx.say(html_jump_url)
  ngx.exit(200)
end

function google_token_router.google_callback(req,res,next)
  local re = {}
  local googleAuthUrl = "https://www.googleapis.com/oauth2/v4/token"
  local code = req.query.code

  if code == nil or code == "" then
    ngx.say("error")
    return
  end

  httpc:set_timeout(30000)
  local ok_body_table = {
      client_id = config.voucher.client_id,
      client_secret = config.voucher.client_secret,
      code = code,
      grant_type = "authorization_code",
      redirect_uri = google_callback_url,
      approval_prompt = 'force',
      access_type = 'offline',
      prompt = 'force',
  }
  local ok_body = utils.encode_query_string(ok_body_table)
  local result, err = httpc:request_uri(googleAuthUrl, {
        ssl_verify = false,
        method = "POST",
        body = ok_body,
        headers = {
            ["Accept"] = "application/json",
            ["Content-Type"] = "application/x-www-form-urlencoded; charset=UTF-8",
        }
  })
  local reason = result.reason
  local http_code = result.status
  if http_code == 200 then
    local data = json.decode(result.body)
    local dat = {
      access_token = data.access_token,
      refresh_token = data.refresh_token,
      expires_in = data.expires_in
    }
    re["ret"] = 0
    re['dat'] = dat
    res:json(re)
    exit(200)
  else
      local error_info = "code:"..http_code.." reason:"..reason.." body:"..result.body
      ngx.say(error_info)
      exit(200)
  end
end

return google_token_router