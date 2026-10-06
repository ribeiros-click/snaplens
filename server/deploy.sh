#!/bin/bash
# Publica server/public_html (site + API de links) em lens.ribeiros.click via API da Hostinger.
# Token: variável HOSTINGER_API_TOKEN ou arquivo .hostinger/token na raiz do projeto.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
DOMAIN=${DOMAIN:-lens.ribeiros.click}
ORDER_ID=${ORDER_ID:-1009319767}
USERNAME=${HOSTING_USERNAME:-u456578053}
API=https://developers.hostinger.com/api
TOKEN=${HOSTINGER_API_TOKEN:-$(cat "$ROOT/.hostinger/token" 2>/dev/null || true)}
[ -n "$TOKEN" ] || { echo "Defina HOSTINGER_API_TOKEN ou crie .hostinger/token"; exit 1; }
auth=(-H "Authorization: Bearer $TOKEN")
api() { curl -sS "${auth[@]}" -H "Content-Type: application/json" "$@"; }

# 1. config.php (gera a chave de upload na primeira vez; fica fora do git)
CFG=server/public_html/config.php
if [ ! -f "$CFG" ]; then
  KEY=$(openssl rand -hex 24)
  sed "s/'upload_key' => ''/'upload_key' => '$KEY'/" server/public_html/config.example.php > "$CFG"
  chmod 600 "$CFG"
  echo "Chave de upload gerada em $CFG — cole-a em SnapLens → Ajustes → Compartilhar."
fi

# 2. Site existe?
if ! api "$API/hosting/v1/websites" | grep -q "\"domain\":\"$DOMAIN\""; then
  echo "Criando site $DOMAIN…"
  api -X POST "$API/hosting/v1/websites" -d "{\"domain\":\"$DOMAIN\",\"order_id\":$ORDER_ID}"; echo
  for i in $(seq 1 30); do
    sleep 10
    api "$API/hosting/v1/websites" | grep -q "\"domain\":\"$DOMAIN\"" && break
  done
fi

# 3. DNS: a Hostinger cria o registro sozinha ao criar o site; só intervém se o nome não resolver
SUB=${DOMAIN%%.*}; ZONE=${DOMAIN#*.}
HOST_IP=$(dig +short languages.ribeiros.click A | head -1)
if [ -z "$(dig +short "$DOMAIN" A)" ]; then
  echo "Criando DNS $SUB.$ZONE -> $HOST_IP"
  api -X PUT "$API/dns/v1/zones/$ZONE" -d "{\"overwrite\":false,\"zone\":[{\"name\":\"$SUB\",\"type\":\"A\",\"ttl\":300,\"records\":[{\"content\":\"$HOST_IP\"}]}]}"; echo
fi

# 4. Prints + DMG mais recente dentro do pacote
mkdir -p server/public_html/assets/img server/public_html/download
[ -f SnapLens.dmg ] && cp SnapLens.dmg server/public_html/download/SnapLens.dmg
[ -f .build/icon/icon_1024.png ] && sips -z 256 256 .build/icon/icon_1024.png --out server/public_html/assets/icon.png >/dev/null

# 5. Zip (inclui .htaccess) e upload via TUS
STAMP=$(date +%Y%m%d_%H%M%S); ZIP=$ROOT/.build/site_$STAMP.zip
( cd server/public_html && rm -f "$ZIP" && zip -qr "$ZIP" . -x "_data/*" -x "config.example.php" )
UP=$(api -X POST "$API/hosting/v1/files/upload-urls" -d "{\"username\":\"$USERNAME\",\"domain\":\"$DOMAIN\"}")
URL=$(echo "$UP" | python3 -c "import json,sys; print(json.load(sys.stdin)['url'])")
AK=$(echo "$UP" | python3 -c "import json,sys; print(json.load(sys.stdin)['auth_key'])")
RK=$(echo "$UP" | python3 -c "import json,sys; print(json.load(sys.stdin)['rest_auth_key'])")
SIZE=$(wc -c < "$ZIP" | tr -d ' ')
curl -sS -o /dev/null -w "upload create: %{http_code}\n" -X POST "$URL/site.zip?override=true" -H "X-Auth: $AK" -H "X-Auth-Rest: $RK" -H "Tus-Resumable: 1.0.0" -H "Upload-Length: $SIZE" -H "Upload-Offset: 0"
curl -sS -o /dev/null -w "upload data:   %{http_code}\n" -X PATCH "$URL/site.zip?override=true" -H "X-Auth: $AK" -H "X-Auth-Rest: $RK" -H "Tus-Resumable: 1.0.0" -H "Content-Type: application/offset+octet-stream" -H "Upload-Offset: 0" --data-binary "@$ZIP"

# 6. Deploy do arquivo (extrai em public_html)
api -X POST "$API/hosting/v1/accounts/$USERNAME/websites/$DOMAIN/deploy" -d '{"archive_path":"site.zip"}'; echo

# 7. SSL + redirecionamento HTTPS (idempotente)
api -X POST "$API/hosting/v1/accounts/$USERNAME/websites/$DOMAIN/ssl/setup" -d '{}' >/dev/null || true
api -X PATCH "$API/hosting/v1/accounts/$USERNAME/websites/$DOMAIN/ssl/https-redirect/toggle" -d '{"is_enabled":true}' >/dev/null || true

# 8. Cron diário de limpeza de links expirados
# A listagem devolve as barras escapadas (\/), por isso a comparação ignora barras.
if ! api "$API/hosting/v1/accounts/$USERNAME/cron-jobs" | tr -d '\\/' | grep -q "${DOMAIN}public_htmlcleanup.php"; then
  api -X POST "$API/hosting/v1/accounts/$USERNAME/cron-jobs" -d "{\"command\":\"php /home/$USERNAME/domains/$DOMAIN/public_html/cleanup.php\",\"time\":\"0 3 * * *\"}" || true; echo
fi

api -X DELETE "$API/hosting/v1/accounts/$USERNAME/websites/$DOMAIN/cache/clear" -d '{"directory":"/"}' >/dev/null || true
mkdir -p .hostinger && echo "{\"domain\":\"$DOMAIN\",\"username\":\"$USERNAME\",\"type\":\"php\"}" > .hostinger/site.json
echo "Publicado: https://$DOMAIN/"
