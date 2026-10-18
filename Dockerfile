# Caddy に入口の設定を入れたイメージ (ADR-0001)。設定を VPS に手で写さず、main の Caddyfile をそのまま版付きで出す
FROM caddy:2.11.6
COPY Caddyfile /etc/caddy/Caddyfile
