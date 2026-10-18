# AGENTS.md

lumorphia/edge: Lumorphia の全サービスの入口 (Caddy)。80/443 を持つのはこれだけで、`lumorphia-edge` の各サービスの web に流す。**このリポジトリは public**。弱点は [SECURITY.md](SECURITY.md) に従い、Issue や公開の PR に書かない。

## 決まり

- 上流は**サービスごとに固有の別名** (`prismtone-web:3000`・`accounts-web:3100`・`scenote-web:3200`) で指す。サービス名の `web` は、つながるすべてのネットワークで名前になるので使わない (2026-10-11 の 502)
- 全サイトに `import lumorphia_site` (Cloudflare の IP だけを受け、Origin CA の証明書を使う)。外すと、各サービスが信じる `CF-Connecting-IP` を偽装できてしまう
- 秘密 (Origin CA の鍵) を置かない。証明書は VPS の `EDGE_CERTS_DIR` だけ
- Caddy の版は `Dockerfile` で固定し、Renovate の PR で上げる
- **main に入るとすぐ本番に当たる** (CI がイメージを作り、doco-cd が数分で入れ替える)。Caddy が作り直されるので、全ドメインが数秒止まる。develop → main は運営者がマージする

## 作業の流れ

1. `develop` から `feat/<topic>` を切る。`develop` と `main` に直接コミットしない
2. `Caddyfile` を直したら、手元で確かめる (CI と同じ):

   ```sh
   docker build -t edge-caddy:local . \
     && mkdir -p .ci-certs \
     && openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 1 -subj "/CN=*.lumorphia.com" -keyout .ci-certs/origin.key -out .ci-certs/origin.pem \
     && docker run --rm -v "$PWD/.ci-certs:/etc/caddy/certs:ro" edge-caddy:local caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile \
     && docker run --rm edge-caddy:local caddy fmt /etc/caddy/Caddyfile | diff -u Caddyfile -
   ```

3. `develop` 向けに PR を作り、CI が緑になってからマージする (Rebase and merge)。`develop` → `main` はマージコミット
4. サービスを足すときは [docs/runbook/deploy.md](docs/runbook/deploy.md) の「サービスを足す」

コミットは Conventional Commits、本文は日本語。設計の判断を変えるときは `docs/adr/` に ADR を足す。
