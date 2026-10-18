# Prismtone の proxy から edge への切り替え (1 回だけ)

ADR-0001。入口が止まるのは、Prismtone の proxy を止めてから edge の Caddy が起きるまでの数秒。運営者が VPS で行う。秘密 (証明書の鍵、`.env.*`) を会話や PR に貼らない。

## 前に済ませること

1. edge の最初のイメージがある: edge の develop → main をマージし、CI の `publish` が `ghcr.io/lumorphia/edge-caddy:latest` を出したこと。VPS から取れること (lumorphia/accounts の deploy.md §4 の 1 と同じ `manifest inspect` を `edge-caddy` で)
2. いま Prismtone の Caddy が載せているサイトが、全部 edge の `Caddyfile` にあること

   ```sh
   ls ~/srv/caddy-sites/            # accounts.caddy のほかにあれば、先に edge に足す
   ```

3. 証明書を edge の置き場所に写す (Prismtone の `PRISMTONE_CERTS_DIR` にある Origin CA の 1 枚)

   ```sh
   mkdir -p ~/srv/edge/certs
   cp ~/srv/prismtone/docker/certs/origin.pem ~/srv/prismtone/docker/certs/origin.key ~/srv/edge/certs/
   chmod 600 ~/srv/edge/certs/origin.key
   ```

4. edge の `compose.yaml` を `~/srv/edge/compose.yaml` に置く (main のもの)
5. **Prismtone の PR (web を `lumorphia-edge` に `prismtone-web` で出し、compose から proxy を外す) が main に入り、doco-cd が当てたこと**。Prismtone の doco-cd は `remove_orphans: false` なので、compose から外れた proxy は動いたまま残る。確かめる:

   ```sh
   docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' prismtone-web-1   # lumorphia-edge を含む
   docker ps --filter name=prismtone-proxy-1 --format '{{.Names}} {{.Status}}'                       # まだ Up
   ```

6. edge のイメージを先に取っておく (切り替えの数秒を短くする)

   ```sh
   EDGE_CERTS_DIR=$HOME/srv/edge/certs docker compose -p edge -f ~/srv/edge/compose.yaml pull
   ```

## 切り替え

```sh
docker stop prismtone-proxy-1 \
  && EDGE_CERTS_DIR=$HOME/srv/edge/certs docker compose -p edge -f ~/srv/edge/compose.yaml up -d
```

project の名前 (`edge`) は doco-cd の `.doco-cd.yml` と同じにする。あとで doco-cd がこのコンテナを引き継ぐ。

## 確かめる

外から (Cloudflare を通して):

```sh
for u in https://prismtone.lumorphia.com/api/health https://accounts.lumorphia.com/api/health; do
  curl -s -o /dev/null -w "%{http_code} $u\n" "$u"
done
```

両方 200。Uptime Kuma も緑に戻ること。Scenote はまだ起動していなければ 502 (公開前は Access の内側)。

## 戻し方

何かおかしければ、すぐ戻す。

```sh
EDGE_CERTS_DIR=$HOME/srv/edge/certs docker compose -p edge -f ~/srv/edge/compose.yaml stop \
  && docker start prismtone-proxy-1
```

`down -v` は使わない。

## 落ち着いたら (1 日ほど様子を見てから)

1. 残った Prismtone の proxy を消す: `docker rm prismtone-proxy-1`。Caddy のボリューム (`prismtone_caddy_data`・`prismtone_caddy_config`) も消してよい (証明書は Origin CA のファイルで、Caddy の自動の証明書は使っていない)
2. Prismtone の `.env.production` から `CADDY_SITES_DIR`・`PRISMTONE_CERTS_DIR`・`SITE_ADDRESS` を消し、`~/srv/caddy-sites` を片付ける。Prismtone の doco-cd の env も直したら、doco-cd を作り直す (env はコンテナを作ったときにしか読まない)
3. edge の doco-cd を登録する ([deploy.md](deploy.md) §2)
