# 入口の運用

## 1. 置き場所

| ホストのパス | 中身 |
| --- | --- |
| `~/srv/edge/compose.yaml` | main の `compose.yaml` (doco-cd を登録したあとは doco-cd が取ってくる) |
| `~/srv/edge/certs/origin.pem`・`origin.key` | Cloudflare Origin CA の証明書 1 枚 (`lumorphia.com` と `*.lumorphia.com`)。鍵は `600` |
| `~/srv/doco-cd-edge/compose.yaml` | edge 専用の doco-cd |

共有のネットワーク `lumorphia-edge` は `docker network create lumorphia-edge` で作ったもの (2026-10 の accounts のときに作った)。各サービスの web は、ここに固有の別名で出る。

Prismtone の proxy からの切り替えは [cutover.md](cutover.md) (1 回だけ)。

## 2. doco-cd

edge 専用の doco-cd が main を 5 分ごとに見て、`compose.yaml` の変更か `latest` の digest の変化で入れ替える。

1. `doco-cd/compose.yaml` を `~/srv/doco-cd-edge/compose.yaml` に写し、「ホスト」と書いたパス (`EDGE_CERTS_DIR`、GHCR の認証の `docker-config.json`) を実際の場所に書き換える
2. `docker compose -f ~/srv/doco-cd-edge/compose.yaml up -d`、`docker logs -f doco-cd-edge` で `job completed successfully` を待つ
3. 外から各ドメインの health を確かめる

env を変えたら doco-cd を作り直す (起動したときの値を使う)。

## 3. 更新

`Caddyfile` か Caddy の版を変える PR を develop に入れ、develop → main をマージする。CI がイメージを作り、doco-cd が数分で入れ替える。Caddy が作り直されるので、全ドメインが数秒止まる。入れ替わったら、外から各ドメインの health を確かめる。

いま動いている設定は、`docker inspect edge-caddy-1 --format '{{.Image}}'` と GHCR の `sha-<コミット>` で確かめる。

## 4. サービスを足す

1. サービスの compose で、web を `lumorphia-edge` に固有の別名 (`<サービス>-web`) で出す。サービス名の `web` を上流に使わない
2. edge の `Caddyfile` にサイトを足す (`import lumorphia_site` と `reverse_proxy <サービス>-web:<ポート>`)。上流が起動する前でも設定は通る (届かない間は 502)
3. Cloudflare の DNS を proxy (オレンジ) で VPS に向け、SSL を Full (strict) にする。証明書は今の 1 枚 (`*.lumorphia.com`) で足りる
4. 公開前なら Cloudflare Access の内側に置く (サービスの runbook に従う)

## 5. 戻し方

前のイメージに戻すときは、`EDGE_TAG=sha-<戻したいコミット>` を doco-cd の environment に足して doco-cd を作り直す。直したものが main に入ったら外して、もう一度作り直す。急ぐときは `docker compose -p edge -f ~/srv/edge/compose.yaml` で手で入れ替えてもよい (doco-cd が次の回に main の状態へ戻すので、先に doco-cd を止める)。
