# Custom log format including the protocol ($scheme)
log_format custom_format '$remote_addr - $remote_user [$time_local] '
'"$request" $status $body_bytes_sent '
'"$http_referer" "$http_user_agent" "$scheme"';

server {
  listen 80;
  listen [::]:80;
  server_name ${full_domain};
  return 302 https://$server_name$request_uri;

  access_log /var/log/nginx/access.log custom_format;
}
server {
  # SSL configuration

  listen 443 ssl http2;
  listen [::]:443 ssl http2;
  ssl_certificate /etc/ssl/certs/${full_domain}.crt.pem;
  ssl_certificate_key /etc/ssl/private/${full_domain}.key.pem;

  access_log /var/log/nginx/access.log custom_format;

  server_name ${full_domain};

  root /var/www/${full_domain}/html;
  index index.html index.htm index.nginx-debian.html;

  location / {
    try_files $uri $uri/ =404;
  }
}