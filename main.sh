#!/usr/bin/env bash
set -euo pipefail

# === НАСТРОЙКИ ===
export TOKEN="token"

# Картинки можно задавать как:
# - путь к файлу (./sell.jpg)
# - URL (https://...)
# - file_id (самый удобный вариант после первой отправки)
PHOTO_SELL="./sell.png"
PHOTO_BUY="./buy.png"
PHOTO_RAKETA="./sminem.png"
PHOTO_VTB="./vtb.png"
PHOTO_PUTIN="./putin.png"

COOLDOWN_SECONDS="${COOLDOWN_SECONDS:-10}"

OFFSET_FILE="${OFFSET_FILE:-./offset.txt}"
COOLDOWN_FILE="${COOLDOWN_FILE:-./cooldowns.txt}"

API="https://api.telegram.org/bot${TOKEN}"

touch "$COOLDOWN_FILE" 2>/dev/null || true

get_last_ts() {
  local chat_id="$1"
  awk -v id="$chat_id" '$1==id{print $2}' "$COOLDOWN_FILE" 2>/dev/null | tail -n1
}

set_last_ts() {
  local chat_id="$1" ts="$2"
  touch "$COOLDOWN_FILE"
  if grep -q "^${chat_id} " "$COOLDOWN_FILE"; then
    awk -v id="$chat_id" -v ts="$ts" '
      $1==id {$2=ts}
      {print}
    ' "$COOLDOWN_FILE" > "${COOLDOWN_FILE}.tmp"
    mv "${COOLDOWN_FILE}.tmp" "$COOLDOWN_FILE"
  else
    printf "%s %s\n" "$chat_id" "$ts" >> "$COOLDOWN_FILE"
  fi
}

send_photo() {
  local chat_id="$1"
  local reply_to="$2"
  local photo="$3"

  if [[ -f "$photo" ]]; then
    curl -sS -X POST "$API/sendPhoto" \
      -F "chat_id=$chat_id" \
      -F "reply_to_message_id=$reply_to" \
      -F "photo=@${photo}" >/dev/null
  else
    curl -sS -X POST "$API/sendPhoto" \
      -d "chat_id=$chat_id" \
      -d "reply_to_message_id=$reply_to" \
      -d "photo=$photo" >/dev/null
  fi
}

OFFSET=0
if [[ -f "$OFFSET_FILE" ]]; then
  OFFSET="$(cat "$OFFSET_FILE" 2>/dev/null || echo 0)"
fi

echo "Bot started. Offset=$OFFSET"
echo "PHOTO_SELL=$PHOTO_SELL"
echo "PHOTO_BUY=$PHOTO_BUY"

while true; do
  # timeout=30 держит запрос “долго”, чтобы не долбить API
  RESP="$(curl -sS "$API/getUpdates" \
    -d "timeout=10" \
    -d "offset=$OFFSET" \
    -d 'allowed_updates=["message"]' || true)"

  # если что-то пошло не так — просто повторим цикл
  if [[ -z "$RESP" ]] || [[ "$(jq -r '.ok // false' <<<"$RESP")" != "true" ]]; then
    continue
  fi

  # перебираем апдейты
  while IFS= read -r upd; do
    update_id="$(jq -r '.update_id' <<<"$upd")"
    # следующий offset = update_id + 1
    OFFSET=$((update_id + 1))

    chat_id="$(jq -r '.message.chat.id // empty' <<<"$upd")"
    msg_id="$(jq -r '.message.message_id // empty' <<<"$upd")"
    text="$(jq -r '.message.text // empty' <<<"$upd")"

    [[ -z "$chat_id" || -z "$msg_id" || -z "$text" ]] && continue

    photo_to_send=""
    # границы слова: не буква/цифра/подчёркивание
    if grep -Eqi '(^|[^[:alnum:]_])(продал|подпродал)([^[:alnum:]_]|$)' <<<"$text"; then
        photo_to_send="$PHOTO_SELL"
    elif grep -Eqi '(^|[^[:alnum:]_])(купил[[:space:]]+втб|втб[[:space:]]+дивы|втб[[:space:]]+дивиденды|дивы[[:space:]]+втб|дивиденды[[:space:]]+втб)([^[:alnum:]_]|$)' <<<"$text"; then
        photo_to_send="$PHOTO_VTB"
    elif grep -Eqi '(^|[^[:alnum:]_])(купил|закупил|подкупил|закупился)([^[:alnum:]_]|$)' <<<"$text"; then
        photo_to_send="$PHOTO_BUY"
    elif grep -Eqi '(^|[^[:alnum:]_])(ракета|ракетит)([^[:alnum:]_]|$)' <<<"$text"; then
        photo_to_send="$PHOTO_RAKETA"
    elif grep -Eqi '(^|[^[:alnum:]_])(как[[:space:]]+по[[:space:]]+нотам)([^[:alnum:]_]|$)' <<<"$text"; then
        photo_to_send="$PHOTO_PUTIN"
    else
      continue
    fi

    now="$(date +%s)"
    last="$(get_last_ts "$chat_id" || echo 0)"
    last="${last:-0}"

    if (( now - last < COOLDOWN_SECONDS )); then
      continue
    fi

    send_photo "$chat_id" "$msg_id" "$photo_to_send"
    set_last_ts "$chat_id" "$now"

  done < <(jq -c '.result[]' <<<"$RESP")

  # сохраняем offset, чтобы после перезапуска не отвечать на старые сообщения
  echo "$OFFSET" > "$OFFSET_FILE"
done
