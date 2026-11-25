#!/usr/bin/env bash
# アクセスログの確かめ (ADR-0002)。イメージ edge-caddy:ci を本物の Caddy で動かし、次を見る。
#
# 1. Cloudflare から届いた要求は、CF-Connecting-IP の値を client_ip として残す
# 2. Cookie・認証ヘッダー・クエリ文字列 (OAuth の code など) をログに残さない
# 3. 上流 (各サービス) へ渡す X-Forwarded-For は Cloudflare の IP だけで、利用者が送った値を混ぜない
# 4. Cloudflare 以外から届いた要求は 403 で、CF-Connecting-IP を偽っても client_ip にならない
#
# 手元の docker のネットワークは Cloudflare の IP ではないので、1〜3 は Caddyfile の Cloudflare の
# IP 一覧をテスト用のネットワークに差し替えて動かす。4 は差し替えない Caddyfile で動かす。
#
#   docker build -t edge-caddy:ci . && test/access-log.sh
set -euo pipefail

IMAGE="${IMAGE:-edge-caddy:ci}"
NET="edge-access-log-test"
SUBNET="172.31.250.0/24"
CADDY_IP="172.31.250.10"
CLIENT_IP="172.31.250.20"
SPOOFED="198.51.100.9"
REAL="203.0.113.7"
SECRET="do-not-log-$RANDOM"
WORK="$(mktemp -d)"

cleanup() {
  docker rm -f edge-test-caddy edge-test-upstream >/dev/null 2>&1 || true
  docker network rm "$NET" >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

fail() {
  echo "NG: $*" >&2
  echo "--- access.log" >&2
  docker exec edge-test-caddy cat /var/log/caddy/access.log >&2 || true
  exit 1
}

mkdir -p "$WORK/certs"
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 1 \
  -subj "/CN=*.lumorphia.com" -keyout "$WORK/certs/origin.key" -out "$WORK/certs/origin.pem" 2>/dev/null
chmod 644 "$WORK/certs/origin.key"

docker network create --subnet "$SUBNET" "$NET" >/dev/null
# 上流の代わり。受け取った X-Forwarded-For をそのまま返す
docker run -d --name edge-test-upstream --network "$NET" --network-alias prismtone-web \
  caddy:2.11.9 caddy respond --listen :3000 --body '{http.request.header.X-Forwarded-For}' >/dev/null

# Caddyfile の Cloudflare の IP 一覧 (1 行) を取り出す
CF_LIST="$(docker run --rm "$IMAGE" sed -n 's/^[[:space:]]*@direct not remote_ip //p' /etc/caddy/Caddyfile)"
[ -n "$CF_LIST" ] || fail "Caddyfile から Cloudflare の IP 一覧を取り出せない"
# 一覧は cloudflare_only と trusted_proxies の 2 か所にある。同じでなければならない
TRUSTED="$(docker run --rm "$IMAGE" sed -n 's/^[[:space:]]*trusted_proxies static //p' /etc/caddy/Caddyfile)"
[ "$CF_LIST" = "$TRUSTED" ] || fail "cloudflare_only と trusted_proxies の IP 一覧が違う"

run_caddy() {
  local caddyfile="$1"
  docker rm -f edge-test-caddy >/dev/null 2>&1 || true
  docker run -d --name edge-test-caddy --network "$NET" --ip "$CADDY_IP" \
    -v "$WORK/certs:/etc/caddy/certs:ro" -v "$caddyfile:/etc/caddy/Caddyfile:ro" "$IMAGE" >/dev/null
  for _ in $(seq 1 30); do
    docker logs edge-test-caddy 2>&1 | grep -q '"serving initial configuration"' && return 0
    sleep 0.5
  done
  fail "Caddy が起動しない"
}

request() {
  docker run --rm --network "$NET" --ip "$CLIENT_IP" curlimages/curl:8.17.0 -sk \
    --resolve "prismtone.lumorphia.com:443:$CADDY_IP" \
    -H "CF-Connecting-IP: $REAL" -H "X-Forwarded-For: $SPOOFED" \
    -H "Cookie: session=$SECRET" -H "Authorization: Bearer $SECRET" -H "Referer: https://example.com/?t=$SECRET" \
    -A "edge-test-agent" -w '\n%{http_code}' \
    "https://prismtone.lumorphia.com/api/lumorphia/callback?code=$SECRET&state=$SECRET"
}

last_log() {
  for _ in $(seq 1 20); do
    if docker exec edge-test-caddy test -s /var/log/caddy/access.log; then
      docker exec edge-test-caddy tail -n 1 /var/log/caddy/access.log
      return 0
    fi
    sleep 0.5
  done
  fail "アクセスログが書かれない"
}

field() {
  python3 -c 'import json,sys; d=json.loads(sys.argv[1]); [d:=d.get(k,{}) if isinstance(d,dict) else {} for k in sys.argv[2].split(".")]; print(d if d!={} else "")' "$1" "$2"
}

# --- 1〜3: Cloudflare から届いた要求 (一覧をテスト用のネットワークに差し替える)
docker run --rm "$IMAGE" cat /etc/caddy/Caddyfile | sed "s#$CF_LIST#$SUBNET#g" >"$WORK/Caddyfile.trusted"
run_caddy "$WORK/Caddyfile.trusted"
out="$(request)"
status="$(tail -n 1 <<<"$out")"
body="$(head -n 1 <<<"$out")"
[ "$status" = 200 ] || fail "Cloudflare からの要求が $status"
[ "$body" = "$CLIENT_IP" ] || fail "上流の X-Forwarded-For が '$body' (Cloudflare の IP '$CLIENT_IP' だけであるべき)"

line="$(last_log)"
[ "$(field "$line" request.client_ip)" = "$REAL" ] || fail "client_ip が CF-Connecting-IP ではない"
[ "$(field "$line" request.uri)" = "/api/lumorphia/callback" ] || fail "uri にクエリが残っている"
[ "$(field "$line" user_agent)" = "edge-test-agent" ] || fail "user_agent が残っていない"
[ "$(field "$line" request.host)" = "prismtone.lumorphia.com" ] || fail "host が残っていない"
[ "$(field "$line" status)" = 200 ] || fail "status が残っていない"
if docker exec edge-test-caddy cat /var/log/caddy/access.log | grep -q "$SECRET"; then
  fail "Cookie・認証ヘッダー・Referer・クエリの値がログに残っている"
fi
if docker exec edge-test-caddy cat /var/log/caddy/access.log | grep -q "$SPOOFED"; then
  fail "利用者が送った X-Forwarded-For がログに残っている"
fi
if docker logs edge-test-caddy 2>&1 | grep -q "$SECRET"; then
  fail "コンテナの標準出力にアクセスログが出ている"
fi
echo "ok: Cloudflare からの要求"

# --- 4: Cloudflare 以外から届いた要求 (差し替えない)
docker run --rm "$IMAGE" cat /etc/caddy/Caddyfile >"$WORK/Caddyfile.real"
run_caddy "$WORK/Caddyfile.real"
out="$(request)"
status="$(tail -n 1 <<<"$out")"
[ "$status" = 403 ] || fail "Cloudflare 以外からの要求が $status (403 であるべき)"
line="$(last_log)"
[ "$(field "$line" request.client_ip)" = "$CLIENT_IP" ] || fail "Cloudflare 以外からの CF-Connecting-IP を信じている"
echo "ok: Cloudflare 以外からの要求"
