# ADR-0002: アクセスログに利用者の IP を残し、30 日で消す

| 項目     | 内容       |
| -------- | ---------- |
| Status   | Accepted   |
| Date     | 2026-11-25 |
| Deciders | t1nyb0x    |

## Context

2026-11-25 時点で、どこにも利用者の IP のアクセスログが無かった。

- edge の Caddy は `log` を設定しておらず、アクセスログを出していない
- Prismtone のリクエストのログ (`remoteAddress`) は Fastify の `req.ip` で、X-Forwarded-For の先頭、つまり Cloudflare のエッジの IP になる
- accounts は本番でリクエストのログを出していない (`disableRequestLogging`)
- 利用者の IP (`CF-Connecting-IP`) は、各サービスのレート制限とセッションの記録にだけ使っている

不正なアクセスや障害を調べるとき、誰からの要求かをさかのぼれない。相棒が利用者の IP を残すことに決めた。

## Decision

- **edge の Caddy で全サイトのアクセスログを残す**。サービスごとに作らず、入口の 1 か所にまとめる
- 利用者の IP は `CF-Connecting-IP` から取る (`servers { trusted_proxies static <Cloudflare の IP>; client_ip_headers Cf-Connecting-Ip }`)。信じるのは Cloudflare から届いた要求だけで、ほかから届いたものは直接つないできた IP を残す (そもそも 403)
- **残すもの**: 時刻、利用者の IP、直接つないできた IP (Cloudflare)、プロトコル、メソッド、ホスト、パス、状態、大きさ、所要時間、User-Agent
- **残さないもの**: リクエストとレスポンスのヘッダー (Cookie、Authorization、Referer を含む)、クエリ文字列 (OAuth の `code` や `state` が入る)、TLS の情報、送信元ポート
- **30 日で消す**。Caddy がファイルに書き (`/var/log/caddy`、ボリューム `caddy_logs`)、1 日ごとに分け (`roll_interval 24h`)、720 時間を過ぎたものを消す (`roll_keep_for`)。Docker のログは大きさで回るので期間を約束できず、使わない。30 日は DB のバックアップと Sentry に揃えた (相棒の判断)
- 上流へ渡す X-Forwarded-For は、直接つないできた Cloudflare の IP に固定する (`header_up X-Forwarded-For {remote_host}`)。`trusted_proxies` を設定すると、Caddy は届いた X-Forwarded-For (利用者が自由に書ける) に足して渡すようになり、各サービスの `req.ip` (Fastify の `trustProxy: true` は先頭を取る) を偽装できてしまう。今までと同じ値を渡す
- 各サービスのプライバシーポリシーに、アクセスログの中身・目的・30 日を書く (マイナー改定で告知。相棒の判断)。**ポリシーの公開より前に、この変更を main に入れない** (main に入ると数分で本番に当たる)

## Consequences

### 良い点

- 不正なアクセスや障害を、利用者の IP でさかのぼれる
- 全サービスで同じ形のログになり、サービスを足しても edge の `import lumorphia_site` だけで残る
- 残さないものを `test/access-log.sh` (CI) が本物の Caddy で確かめる

### 悪い点・注意

- 個人情報 (IP) を 30 日持つ。ポリシーに書いた目的以外に使わない。ログを会話や Issue に貼るときは IP を伏せる
- Cloudflare の IP の一覧が `cloudflare_only` と `trusted_proxies` の 2 か所になる。同じであることを `test/access-log.sh` が確かめる
- `trusted_proxies` が古いと、新しい Cloudflare の IP から届いた要求では、利用者の IP の代わりに Cloudflare の IP が残る
- パスに利用者を指すもの (`/users/<handle>` など) は残る。公開のページの URL なので残してよいとした
