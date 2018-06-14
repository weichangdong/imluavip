local _M = {}
local socket = require "socket"
local base = _G
local function _protect(co, status, ...)
    if not status then
        local msg = ...
        if base.type(msg) == "table" then
            return nil, msg[1]
        else
            base.error(msg, 0)
        end
    end
    if coroutine.status(co) == "suspended" then
        return _protect(co, coroutine.resume(co, coroutine.yield(...)))
    else
        return ...
    end
end
function socket.protect(f)
    return function(...)
        local co = coroutine.create(f)
        return _protect(co, coroutine.resume(co, ...))
    end
end

local smtp = require "socket.smtp"
local ssl = require "ssl"
local https = require "ssl.https"
local ltn12 = require "ltn12"
local mime = require("mime")

-- send email start
function sslCreate()
    local sock = socket.tcp()
    sock:settimeout(60, 'b')
    sock:settimeout(90, 't')
    return setmetatable(
        {
            connect = function(_, host, port)
                local r, e = sock:connect(host, port)
                if not r then
                    return r, e
                end
                sock = ssl.wrap(sock, {mode = "client", protocol = "tlsv1", ssl_version = "tlsv3"})
                return sock:dohandshake()
            end
        },
        {
            __index = function(t, n)
                return function(_, ...)
                    return sock[n](sock, ...)
                end
            end
        }
    )
end

function sendMessage(subject, body, send_to)
    local msg = {
        headers = {
            to = send_to,
            subject = subject
        },
        body = body
    }

    local ok, err =
        smtp.send {
        from = "<wcd@gmail.com>",
        rcpt = {send_to},
        source = smtp.message(msg),
        user = "wcd@gmail.com",
        password = "wcd",
        server = "smtp.gmail.com",
        port = 465,
        create = sslCreate
    }

    if not ok then
        --ngx.log(ngx.ERR,err)
        return false
    else
        return true
    end
end

function _M.doSend(title, content, send_to)
    local msg = {
        preamble = "If your client doesn't understand attachments, \r\n" ..
            "it will still display the preamble and the epilogue.\r\n" ..
                "Preamble will probably appear even in a MIME enabled client.",
        [1] = {
            headers = {
                ["content-type"] = "text/html; charset=utf-8"
            },
            body = mime.eol(0, content)
        },
        --
        --[[
		[2] = {
		  headers = {
			["content-type"] = 'image/png; name="lemon.png"',
			["content-disposition"] = 'attachment; filename="lemon.png"',
			["content-description"] = 'a beautiful image',
			["content-transfer-encoding"] = "BASE64"
		  },
		  body = ltn12.source.chain(
			ltn12.source.file(io.open("lemon.png", "rb")),
			ltn12.filter.chain(
			  mime.encode("base64"),
			  mime.wrap()
			)
		  )
		},
	]] 
    epilogue = "This might also show up, but after the attachments"
    }
    local send_to  = "<" .. send_to .. ">"
    for i = 1, 2 do
        local re = sendMessage(title, msg, send_to)
        if re then
            return true
        end
    end
end
return _M