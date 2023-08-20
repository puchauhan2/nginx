#!/bin/bash
 
# import src utility

 

cat <<REPO > /etc/yum.repos.d/nginx.repo
[nginx]
name=nginx repo
baseurl=http://nginx.org/packages/centos/7/x86_64/
gpgcheck=0
enabled=1
REPO
 
#install nginx
yum install -y nginx
 
# turn on for reboots
systemctl enable nginx 
 
# create a virtual server conf file that is in sites-available
cat <<EOF> /etc/nginx/conf.d/petboox.conf
map $sent_http_content_type $expires {
    default    off;

    # Images expires in 2 weeks
    image/png 2w;
    image/gif 2w;
    image/jpg 2w;
    image/jpeg 2w;
    image/ico 2w;
    image/x-icon 2w;
    image/vnd.microsoft.icon 2w;
    image/svg+xml 2w;
   application/x-font-woff 2w;
application/font-woff2 4w;
video/mp4 4w;
    text/css 2w;
    text/javascript 2w;
    application/javascript 2w;
application/x-javascript 2w;
etag on;
}

server {
client_max_body_size 400M;
gzip on;
gzip_disable "msie6";

gzip_comp_level 6;
gzip_min_length 1100;
gzip_buffers 16 8k;
gzip_proxied any;
gzip_types
        text/plain
    text/css
    text/js
    text/xml
    text/javascript
    application/javascript
    application/x-javascript
    application/json
    application/xml
    application/xml+rss;


expires $expires;
    server_name petbooxdemo.brainvire.net;

 location / {
                proxy_pass http://localhost:4200;
                add_header X-Frame-Options DENY;
                proxy_hide_header X-Powered-By;

}
 location /admin {
                proxy_pass http://localhost:4300;
                add_header X-Frame-Options DENY;
                proxy_hide_header X-Powered-By;

}


 location /api {

                proxy_pass http://localhost:8000;
                add_header X-Frame-Options DENY;
                proxy_hide_header X-Powered-By;

}

}
EOF
# link this conf to sites-enabled. it's important to use the full path
#ln -s /etc/nginx/sites-available/myapp.conf /etc/nginx/sites-enabled/myapp.conf
 
nginx -t && (service nginx status > /dev/null && service nginx restart)
