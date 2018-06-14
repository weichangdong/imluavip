# imluavip
# 因为用lua的开发之路还是蛮辛苦的,所以如果觉得对你有用,或者帮到你了,请给个star.^_^.
# 一些说明
- 因为自己爱好搞域名,所以当准备或者正在学习某个东西的时候,就喜欢搞一个相关的域名.开始是这么开始的,但是结局和这个域名有多大关联和影响,就不得而知了......

- 比如为了学golang,买了xuego.wang(已经贱卖掉了),letsgo.xin,letsgo.site,letsgo.kim(买了这些域名后百度出了莱茨狗,本以为会发笔小财呢,然而这3只狗还赖在我这里,无人问津),gogogo.kim,还有最近的golang.ren域名.

- 比如为了学lua,买了imlua.vip域名,这也是这个github项目命名的由来.

- 比如为了锻炼身体,做仰卧起坐,买了situp.vip域名.买了xuewu.ren的域名.

- 废话了这么多,虽然好几个域名现在已经准备放弃了,但是他还是起到了一定的激励作用.

- 上面的域名,价钱可谈,这才是上面布拉布拉一堆的中心思想!!!

# 功能说明
- 有发送email的.
- 有google,paypal充值的.
- 有微信,支付宝充值的(代码都写得差不多了,但是没有调试,需要公司账户).
- 两种模式下(ngx和lua)一些常用的库.mysql(有事务),redis,json,djson,xml,aes,uuid,log, lua_shared_dict等等.

# config文件说明

- 一些之前用的,涉及域名,密钥之类的,我都改了下,要是还有残余的话,看到的话,麻烦给告知下,我删下.
- mysql数据表的话,暂时就不列出来了,没多大参考价值.觉得这套唯一的价值,就是有些代码片段可以作为参考.
- 为啥叫app2,不是app呢,因为当时一台服务器部署2套lua的服务,然后因为require就会出现a项目 require b项目的文件.
- 当然还有一份http的api的文档,也隐掉了.

# 环境部署说明
这个说明是一个同事给整理出来的.他是写过2个接口(因为感觉和我不是一个路子,最后给改了改)在这个系统里面,然后没多久,调去做一个别的新项目了.


## 依赖

- lua5.1 
- [openresty](https://github.com/openresty/openresty)
- [lua web 开发框架](https://github.com/sumory/lor)
- [luasocket lua包管理器](https://github.com/diegonehab/luasocket)
- [luarocks lua包管理器](https://github.com/luarocks/luarocks)
- [lua-resty-nettle](https://github.com/bungle/lua-resty-nettle)
- [Nettle](http://www.lysator.liu.se/~nisse/nettle/nettle.html) [下载地址](http://www.lysator.liu.se/~nisse/nettle/) [ftp](ftp://ftp.gnu.org/gnu/nettle/)
- [ssl](https://github.com/openresty/lua-resty-core)
- 以下依赖采用包管理器安装 `luarocks install pkg-name`
  - luasec
  - luasocket
  - luaxml `ln -s LuaXML.lua LuaXml.lua`
  - dkjson
  - lua-cjson
  - luacurl
  - luasql-mysql(依赖libmysql `sudo apt install libmysqlclient-dev`, `luarocks install luasql-mysql MYSQL_INCDIR=/usr/include/mysql`)
  - luuid(依赖libuuid `sudo apt install uuid-dev`)
  - md5

- [lua-resty-hmac](https://github.com/jkeys089/lua-resty-hmac/tree/master/lib/resty)

  ```
  $ cd /home/service/openresty/lualib/resty
  $ sudo wget https://raw.githubusercontent.com/jkeys089/lua-resty-hmac/master/lib/resty/hmac.lua
  ```

- [lua-resty-rsa](https://github.com/doujiang24/lua-resty-rsa)

  ```
  $ cd /home/service/openresty/lualib/resty
  $ sudo wget https://raw.githubusercontent.com/doujiang24/lua-resty-rsa/master/lib/resty/rsa.lua
  ```

- [lua-resty-http](https://github.com/pintsized/lua-resty-http)

## 命令行执行时的依赖

- imagemagick `sudo apt install imagemagick`
- ffmpeg `sudo apt install ffmpeg`

## nginx配置

### 主配置文件

```conf
# 压缩队列名,命令行下也会用到
env instance_id;

http {
    # soket 读超时设置
    lua_socket_read_timeout 65;
    # 共享内存
    lua_shared_dict fresh_token_limit 20m;

    # lua 相关的配置,按实际情况配置即可
    lua_package_path  "/home/service/openresty/lualib/?.lua;/home/work/dev/p2papi/app2/?.lua;/home/work/dev/p2papi/?.lua;/home/work/local/lor/?.lua;/home/work/local/luarocks/share/lua/5.1/?.lua;/home/service/openresty/lualib/?.lua;./?.lua;;";
    lua_package_cpath "/home/service/openresty/lualib/?.so;/usr/local/lib/lua/5.1/?.so;/home/work/local/luarocks/lib/lua/5.1/?.so;/home/service/openresty/lualib/?.so;./?.so;;";
}
```

### 虚拟主机配置

```conf
# 可选配置,可减少反复改配置文件
set $work_env "dev";

location / {
    default_type  text/html;
    content_by_lua_file /home/work/dev/p2papi/app2/main.lua;
}
```

*请将目录换成真实有效的*

# 定时任务,仅供参考

```sh
0 12 * * *      lua /data/v3-p2papi/app2/cmd/fcm.lua >>/data/v3-p2papi/log/fcm.log
*/5 * * * *     lua /data/v3-p2papi/app2/cmd/sync.lua >>/data/v3-p2papi/log/sync.log
*/10 * * * *    lua /data/v3-p2papi/app2/cmd/google_token.lua >>/data/v3-p2papi/log/google-token.log
*/6 * * * *     sh  /data/v3-p2papi/check-queue.sh >>/data/v3-p2papi/log/check.log
1 2 * * *       sh  /data/v3-p2papi/del_img_video.sh >>/data/v3-p2papi/log/del.log
```

# 我的mac的luarock list,仅作参考
```
Installed rocks:
----------------

ansicolors
   1.0.2-3 (installed) - /usr/local/lib/luarocks/rocks-5.1

date
   2.1.2-1 (installed) - /usr/local/lib/luarocks/rocks-5.1

dkjson
   2.5-2 (installed) - /usr/local/lib/luarocks/rocks-5.1

elasticsearch
   1.0.0-1 (installed) - /usr/local/lib/luarocks/rocks-5.1

etlua
   1.3.0-1 (installed) - /usr/local/lib/luarocks/rocks-5.1

lapis
   1.5.1-1 (installed) - /usr/local/lib/luarocks/rocks-5.1

loadkit
   1.1.0-1 (installed) - /usr/local/lib/luarocks/rocks-5.1

lpeg
   1.0.1-1 (installed) - /usr/local/lib/luarocks/rocks-5.1

lua-cjson
   2.1.0-1 (installed) - /usr/local/lib/luarocks/rocks-5.1

lua-llthreads2
   0.1.4-1 (installed) - /usr/local/lib/luarocks/rocks-5.1

lua-resty-cookie
   0.1.0-1 (installed) - /usr/local/lib/luarocks/rocks-5.1

lua-resty-http
   0.06-0 (installed) - /usr/local/lib/luarocks/rocks-5.1

lua-resty-session
   2.2-1 (installed) - /usr/local/lib/luarocks/rocks-5.1

lua-resty-template
   1.5-1 (installed) - /usr/local/lib/luarocks/rocks-5.1

lua-term
   0.7-1 (installed) - /usr/local/lib/luarocks/rocks-5.1

lua-xmlreader
   0.1-2 (installed) - /usr/local/lib/luarocks/rocks-5.1

lua-zlib
   1.1-0 (installed) - /usr/local/lib/luarocks/rocks-5.1

luabitop
   1.0.2-3 (installed) - /usr/local/lib/luarocks/rocks-5.1

luacrypto
   0.3.2-2 (installed) - /usr/local/lib/luarocks/rocks-5.1

luacurl
   1.2.1-1 (installed) - /usr/local/lib/luarocks/rocks-5.1

luafilesystem
   1.6.3-2 (installed) - /usr/local/lib/luarocks/rocks-5.1

luasec
   0.6-1 (installed) - /usr/local/lib/luarocks/rocks-5.1

luasocket
   3.0rc1-2 (installed) - /usr/local/lib/luarocks/rocks-5.1

luasql-mysql
   2.3.5-1 (installed) - /usr/local/lib/luarocks/rocks-5.1

luaxml
   101012-2 (installed) - /usr/local/lib/luarocks/rocks-5.1

lub
   1.1.0-1 (installed) - /usr/local/lib/luarocks/rocks-5.1

lunitx
   0.8-0 (installed) - /usr/local/lib/luarocks/rocks-5.1

lzmq
   0.4.4-1 (installed) - /usr/local/lib/luarocks/rocks-5.1

magick
   1.3.0-1 (installed) - /usr/local/lib/luarocks/rocks-5.1

md5
   1.2-1 (installed) - /usr/local/lib/luarocks/rocks-5.1

mimetypes
   1.0.0-1 (installed) - /usr/local/lib/luarocks/rocks-5.1

openssl
   scm-1 (installed) - /usr/local/lib/luarocks/rocks-5.1

org.conman.iconv
   2.0.0-1 (installed) - /usr/local/lib/luarocks/rocks-5.1

pgmoon
   1.8.0-1 (installed) - /usr/local/lib/luarocks/rocks-5.1

utf8
   1.2-0 (installed) - /usr/local/lib/luarocks/rocks-5.1

xml
   1.1.3-1 (installed) - /usr/local/lib/luarocks/rocks-5.1
```