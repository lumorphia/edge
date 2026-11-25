# Cloudflare の IP の一覧を更新する

`Caddyfile` の `cloudflare_only` は、Cloudflare の IP からの通信だけを受ける。一覧が古いと、新しい Cloudflare の IP からの正しい通信を 403 で拒んでしまう。

1. https://www.cloudflare.com/ips-v4 と https://www.cloudflare.com/ips-v6 を取る
2. `Caddyfile` の `remote_ip` (cloudflare_only) と `trusted_proxies` の 2 か所を同じ一覧に差し替え、冒頭のコメントの取得日を直す。2 か所が違うと `test/access-log.sh` (CI) が落ちる
3. PR を develop に入れ、develop → main で本番に当てる

`trusted_proxies` が古いと、新しい Cloudflare の IP から届いた要求のアクセスログで、利用者の IP の代わりに Cloudflare の IP が残る。

公開しているサービスで、利用者から 403 の知らせがあったときにも、ここを疑う。
