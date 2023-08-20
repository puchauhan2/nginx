#!/bin/bash
 
# import src utility
if [[ -z $(type -t src) ]]; then
  source <(curl -sL https://www.doublesharp.com/src)
fi
 
src osname
src osversion
 
cat <<REPO > /etc/yum.repos.d/nginx.repo
[nginx]
name=nginx repo
# default repo
#baseurl=http://nginx.org/packages/$(osname)/$(osversion)/\$basearch/
# mainline "dev" repo for http2 support
baseurl=http://nginx.org/packages/mainline/$(osname)/$(osversion)/\$basearch/
gpgcheck=0
enabled=1
REPO
 
#install nginx
yum install -y nginx
 
# turn on for reboots
systemctl enable nginx
 
mkdir -p /etc/nginx/includes
mkdir -p /etc/nginx/sites-enabled
mkdir -p /etc/nginx/sites-available
mkdir -p /etc/nginx/streams-enabled
mkdir -p /etc/nginx/streams-available
 
# use a conf file to include our sites-enabled conf files
cat <<SITESENABLED > /etc/nginx/includes/sites-enabled.conf
include                 /etc/nginx/sites-enabled/*.conf;
SITESENABLED
 
[[ -f "/etc/nginx/conf.d/_.sites-enabled.conf" ]] || ln -s /etc/nginx/includes/sites-enabled.conf /etc/nginx/conf.d/_.sites-enabled.conf
 
# enable httpd in selinux
semanage permissive -a httpd_t
 
cat <<NGINX_CONF > /etc/nginx/nginx.conf
user                    nginx;
worker_processes        auto;
 
error_log               /var/log/nginx/error.log warn;
pid                     /var/run/nginx.pid;
 
worker_rlimit_nofile    100000; 
 
events {
  # determines how much clients will be served per worker
  # max clients = worker_connections * worker_processes
  # max clients is also limited by the number of socket connections available on the system (~64k)
  worker_connections      100000;
 
  # optmized to serve many clients with each thread, essential for linux
  use                     epoll;
 
  # accept as many connections as possible, may flood worker connections if set too low
  multi_accept on;
}
 
# web servers / virtual hosts
http {
  include                 /etc/nginx/mime.types;
  default_type            application/octet-stream;
 
  log_format              main    '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                                  '\$status \$body_bytes_sent "\$http_referer" '
                                  '"\$http_user_agent" "\$http_x_forwarded_for"';
 
  access_log              /var/log/nginx/access.log combined flush=1m buffer=128k;
 
  # cache informations about FDs, frequently accessed files
  # can boost performance, but you need to test those values
  open_file_cache         max=200000 inactive=20s;
  open_file_cache_valid   30s;
  open_file_cache_min_uses 2;
  open_file_cache_errors  on;
 
  # send headers in one peace, its better then sending them one by one
  tcp_nopush              on;
   
  # don't buffer data sent, good for small data bursts in real time
  tcp_nodelay             on;
   
  # server will close connection after this time
  keepalive_timeout       30;
   
  # allow the server to close connection on non responding client, this will free up memory
  reset_timedout_connection on;
   
  # request timed out -- default 60
  client_body_timeout     10;
   
  # if client stop responding, free up memory -- default 60
  send_timeout            2;
   
  # reduce the data that needs to be sent over network
  gzip                    on;
  gzip_min_length         10240;
  gzip_proxied            expired no-cache no-store private auth;
  gzip_types              text/plain text/css text/xml text/javascript application/x-javascript application/xml;
  gzip_disable            "MSIE [1-6]\.";
 
  proxy_buffer_size       128k;
  proxy_buffers           64 256k;
  proxy_busy_buffers_size 256k;
  proxy_ignore_client_abort on;
 
  include                 /etc/nginx/conf.d/*.conf;
}
 
# load balancer streams
stream {
  include                 /etc/nginx/streams-enabled/*.conf;
}
NGINX_CONF
 
 
# create a virtual server conf file that is in sites-available
cat <<NGINX_HOST > /etc/nginx/sites-available/myapp.conf
upstream myapp {
        # our app will be on localhost port 3000, but you can change this here
        server                  127.0.0.1:3000 fail_timeout=0;
}
  
server {
        listen                  80;
        server_name             myapp.example.com;
  
        location / {
                proxy_set_header        Host \$host:\$server_port;
                proxy_set_header        X-Real-IP \$remote_addr;
                proxy_set_header        X-Forwarded-For \$proxy_add_x_forwarded_for;
                proxy_set_header        X-Forwarded-Proto \$scheme;
  
                proxy_pass              http://myapp;
        }
}
NGINX_HOST
  
# link this conf to sites-enabled. it's important to use the full path
#ln -s /etc/nginx/sites-available/myapp.conf /etc/nginx/sites-enabled/myapp.conf
 
nginx -t && (service nginx status > /dev/null && service nginx restart)
