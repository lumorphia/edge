# lumorphia/edge

Lumorphia の入口。同じ VPS で動く全サービス ([prismtone](https://github.com/lumorphia/prismtone)・[accounts](https://github.com/lumorphia/accounts)・[scenote](https://github.com/lumorphia/scenote)) の 80/443 を、1 つの Caddy で受けて、共有のネットワーク `lumorphia-edge` の各サービスの web へ流す。

- `Caddyfile`: 全ドメインのサイトと、Cloudflare の IP だけを受ける決まり
- `Dockerfile`: Caddy に `Caddyfile` を入れたイメージ (`ghcr.io/lumorphia/edge-caddy`)
- `compose.yaml`: VPS で動かす Caddy。どのサービスの起動も待たない
- `doco-cd/`: edge 専用の doco-cd

なぜ分けたかは [docs/adr/0001-edge.md](docs/adr/0001-edge.md)、手順は [docs/runbook/](docs/runbook/)、弱点の知らせ方は [SECURITY.md](SECURITY.md)。

## ライセンス

[AGPL-3.0-only](LICENSE)
