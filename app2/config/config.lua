local instance_id

if ngx then
  local shared_cache = ngx.shared.fresh_token_limit
  instance_id = shared_cache:get("instance_id_value")
  if not instance_id then
    instance_id = os.getenv("instance_id") or "i-wcd"
    shared_cache:set("instance_id_value", instance_id)
  end
else
  instance_id = os.getenv("instance_id") or "i-wcd"
end

local myconfig =   {
  -- redis
  redis_config = {
    read = {
      HOST = "127.0.0.1",
      PORT = 6379,
    },
    write = {
      HOST = "127.0.0.1",
      PORT = 6379,
    }
  },
  mysql = {
		timeout = 5000,
		connect_config = {
			  host = "127.0.0.1",
	      port = 3306,
	      database = "bailemen",
	      user = "root",
	      password = "root",
	      max_packet_size = 1024 * 1024
		},
		pool_config = {
			max_idle_timeout = 20000, -- 20s
      pool_size = 50 -- connection pool size
		}
	},-- end mysql
  turn_mysql = {
		timeout = 5000,
		connect_config = {
			  host = "127.0.0.1",
	      port = 3306,
	      database = "turn",
	      user = "turn",
	      password = "turn",
	      max_packet_size = 1024 * 1024
		},
		pool_config = {
			max_idle_timeout = 20000, -- 20s
        	pool_size = 50 -- connection pool size
		}
	},-- end turn mysql
  turn_domain = 'test.com',
  server_config = {
    webSocket = {
      heartBeat = {
          ["2g"] = 20,
          ["3g"] = 20,
          ["4g"] = 20,
          ["5g"] = 20,
          ["wifi"] = 20
      },
      urls= {
        "wss:///ws"
      }
    },
    iceServers = {
      {
        credentialType = "password",
        urls = {
            "turn:127.0.0.1:3478"
        },
    }
    }
  },-- end server_config
  redis_key = {
    token_prefix = 'token:',
    token_uid_key = 'uid',
    user_prefix = 'user:',
    all_anchors_uid = 'all_anchors_uid',
    token_fresh_token_key = 'fresh_token',
    email_code_prefix = 'email:',
    video_prefix = 'video:',
    i_follow_prefix = 'ifollow:',
    follow_me_prefix = 'followme:',
    cron_list_key = 'cron_list',
    queue_list_key = 'queue_list:'..instance_id,
    pass_key = 'imlua.vip',
    money2credit_config_key = 'cfg:money2credit:',
    coin2credit_config_key = 'cfg:coin2credit',
    level_config_key = 'cfg:level',
    daily_gift_key = 'day_gift:',
    session_is_key = 'SESS:',
    access_token_key = 'gg_access_token',
    paypal_access_token_key = 'paypal_access_token',
    gift_config_key = 'cfg:gift',
    moments_prefix_zset_key = "mm_ids_list",
    moments_max_min_timestamp_key = "mm_max_min",
    moments_prefix_hash_key = "mm_data:",
    moments_pay_uid_key = "pay:",
    moments_myids_key = "mymm:",
    fcm_redis_key = "IM",
    shared_cache_anchor_uids = "anchor_uids",
    paypal_voucher_lock_key = "paypal_lock:",
    stars_list_config_key = "cfg:stars_list",
    one2one_prefix_hash_key = "o2o_data:",
    one2one_myids_key = "myo2o:",
    moments_isgood_zset_key = "mm_ids_good",
    block_user_key = "block:",
    vip_user_key = "vip:",
    moments_special_md5_key = "mm_special_data_md5",
    moments_special_data_key = "mm_special_data",
    moments_special_zset_key = "mm_ids_special",
    daily_vip_key = 'day_vip:',
    send_tmp_vip_user_key = "send_vip:",
  },
  upload = {
    save_dir = "/work/bailemen-api/resource/",
    resource_url = "http://wcd.cloudfront.net/",
    aws_s3_dir = " s3://wcd-test/",
    aws_s3_cmd = "/usr/local/bin/aws s3 cp --quiet ",
    aws_s3_cmd_rm = "/usr/local/bin/aws s3 rm ",
    aws_s3_dir_compress = " s3://wcd-test/compress/",
    resource_url_compress = "http://wcd.cloudfront.net/compress/",
    aws_preupload_url = "http:/wcd.s3%-accelerate%.amazonaws%.com/",
    save_img_dir_moments = "/work/bailemen-api/resource/moments/",
    resource_url_moments = "http://wcd.cloudfront.net/moments/",
    aws_s3_dir_moments = " s3://wcd-test/moments/",
    resource_url_one2one = "http://wcd.cloudfront.net/one2one/",
    aws_s3_dir_one2one = " s3://wcd-test/one2one/",
    save_img_dir_one2one = "/data/v3-p2papi/resource/one2one/",
  },
  default_avatar = {
      ["1"] = "http://wcd.cloudfront.net/avatar/boy.png",
      ["2"] = "http://wcd.cloudfront.net/avatar/girl.png" 
  },
  token_ttl = 259200,
  customer_service_email = "wcd@gmail.com",
  daily_gift_num = 30,
  daily_gift_max_times = 7,
  daily_vip_num = 15,
  daily_vip_max_times = 3,
  voucher = {
    google_url = "https://accounts.google.com/o/oauth2/token",
    client_id = "wcd-wcd.apps.googleusercontent.com",
    client_secret = "UJgIii-wcd",
    refresh_token = "1/cT2-wcd",
    google_public_key = "wcd",
    fb_appid = "wcd",
    fb_appsecret = "wcd",
    weixin_appid = "wcd",
    weixin_mch_id = "gogogo",
    weixin_notify_url = "https://xxx/wxpay/notify",
    weixin_sign_key = "gogogo",
    paypal_access_token_url = "api.sandbox.paypal.com/v1/oauth2/token",
    paypal_client_id = "wcd",
    paypal_secret = "wcd",
    paypal_order_select_url = "https://api.sandbox.paypal.com/v1/payments/payment/",
    paypal_order_check_url = "https://ipnpb.sandbox.paypal.com/cgi-bin/webscr",
  },
  save_log = {
    voucher_check_log_file = "/work/bailemen-api/log/voucher-check.log",
    important_log_file = "/work/bailemen-api/log/important-log.log",
  },
  default_price = 0,
  default_girl_price = 6,
  go_preupload_cmd = "/work/bailemen-api/app2/cmd/upimg",
  go_preupload_moments_cmd = "/work/bailemen-api/app2/cmd/upimg -t=moments",
  compress_video_raw_dir = "/work/bailemen-api/app2/resource/video_raw/",
  compress_video_ok_dir = "/work/bailemen-api/app2/resource/video_ok/",
  img_convert_cmd = "/usr/bin/convert -quality 75 ",
  img_identify_cmd = "/usr/bin/identify ",
  ffmpeg_cmd = "/usr/local/ffmpeg/ffmpeg",
  ffprobe_cmd = "/usr/local/ffmpeg/ffprobe",
  version_code_check = 9,
  daily_send_type_switch = 2,--0:close 1:credit 2:vip
}

return myconfig
