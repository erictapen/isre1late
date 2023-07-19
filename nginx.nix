pkgs:
let
  # Nginx is not designed to be run in a development environment -.-
  # So we have to provide some configure flags. Luckily compilation is fast.
  # This will essentially use a local ./.nginx/ directory instead of a global
  # one.
  nginx = pkgs.nginx.overrideAttrs (oldAttrs: rec {
    configureFlags = oldAttrs.configureFlags ++ [
      "--without-http-cache"
      "--http-client-body-temp-path=.nginx/client_body"
      "--http-proxy-temp-path=.nginx/proxy"
      "--http-fastcgi-temp-path=.nginx/fastcgi"
      "--http-uwsgi-temp-path=.nginx/uwsgi"
      "--http-scgi-temp-path=.nginx/scgi"
      "--error-log-path=.nginx/error.log"
    ];
  });
  # Our nginx config is currently just some sane default stuff and one
  # redirect, so / gets mapped to /de (our default language).
  nginxConfig = pkgs.writeText "nginx.conf" ''
    worker_processes  1;

    error_log  stderr;
    pid .nginx/nginx.pid;

    daemon off;

    events {
        worker_connections  1024;
    }


    http {
        keepalive_timeout  65;
        access_log  /dev/stdout combined;

        include ${nginx}/conf/mime.types;

        add_header 'Cache-Control' 'no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0';
        expires off;

        map $http_accept_language $lang {
                default de;
                ~de de;
                ~en en;
        }


        server {
            listen       8080;
            server_name  localhost;
            allow 127.0.0.1;
            deny all;

            location / {
                root   ./.;
                try_files /index.html =404;
            }

            location /assets/ {
                alias ./assets/;
            }

        }

    }

  '';
in
pkgs.writeShellScriptBin "nginx-isre1late" ''
  mkdir -p .nginx
  ${nginx}/bin/nginx -p . -c ${nginxConfig}
''
