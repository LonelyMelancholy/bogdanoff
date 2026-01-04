#!/usr/bin/env bash
set -euo pipefail

# source secret file with bot token
readonly ENV_FILE="./secrets.env"
source "$ENV_FILE"

# check token from secret file
[[ -z "$BOT_TOKEN" ]] && { echo "❌ Error: Telegram bot token is missing in '$ENV_FILE', exit"; exit 1; }

# file path
PHOTO_SELL="pic/sell.png"
PHOTO_BUY="pic/buy.png"
PHOTO_RAKETA="pic/sminem.png"
PHOTO_VTB="pic/vtb.png"
PHOTO_PUTIN="pic/putin.png"
PHOTO_NALOG="pic/nalog.jpg"
PHOTO_KALIBR="pic/svo.webp"
PHOTO_PIPA="pic/pipa.mp4"
PHOTO_DIVI="pic/divi.jpg"
PHOTO_DOGOVOR="pic/dogovor.mp4"
PHOTO_ZEL1="pic/zel1.jpg"
PHOTO_ZEL2="pic/zel2.jpg"
PHOTO_ZEL3="pic/zel3.jpg"
ZELE=( "$PHOTO_ZEL1" "$PHOTO_ZEL2" "$PHOTO_ZEL3")
PHOTO_TEHANAL="pic/tehanal.jpg"
PHOTO_BUFFET="pic/buffet.jpg"

COOLDOWN_SECONDS="10"
OFFSET_FILE="${OFFSET_FILE:-./offset.txt}"
COOLDOWN_FILE="${COOLDOWN_FILE:-./cooldowns.txt}"

API="https://api.telegram.org/bot${BOT_TOKEN}"

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

send_media() {
  local chat_id="$1"
  local reply_to="$2"
  local media="$3"

  # Принудительный тип через префикс:
  # photo:..., video:..., anim:... (или animation:...), doc:... (или document:...)
  local forced=""
  case "$media" in
    photo:*)     forced="photo";     media="${media#photo:}" ;;
    video:*)     forced="video";     media="${media#video:}" ;;
    anim:*)      forced="animation"; media="${media#anim:}" ;;
    animation:*) forced="animation"; media="${media#animation:}" ;;
    doc:*)       forced="document";  media="${media#doc:}" ;;
    document:*)  forced="document";  media="${media#document:}" ;;
  esac

  local kind="$forced"

  # Определяем тип, если не задан принудительно
  if [[ -z "$kind" ]]; then
    if [[ -f "$media" ]]; then
      # Локальный файл: определяем по mime (надежнее)
      local mime ext
      mime="$(file -b --mime-type "$media" 2>/dev/null || true)"
      ext="${media##*.}"; ext="${ext,,}"

      if [[ "$mime" == video/* ]]; then
        kind="video"
      elif [[ "$mime" == image/gif ]] || [[ "$ext" == "gif" ]]; then
        kind="animation"
      elif [[ "$mime" == image/* ]]; then
        kind="photo"
      else
        kind="document"
      fi
    else
      # URL или file_id: mime не узнать -> пытаемся по расширению (для URL)
      local base ext
      base="${media%%\?*}"        # убираем query-string
      ext="${base##*.}"; ext="${ext,,}"

      case "$ext" in
        jpg|jpeg|png|webp|bmp|tif|tiff) kind="photo" ;;
        gif)                           kind="animation" ;;
        mp4|mov|mkv|webm)              kind="video" ;;
        *)                             kind="document" ;;  # file_id без расширения попадёт сюда
      esac
    fi
  fi

  # Маппинг тип -> метод и имя поля
  local method field
  case "$kind" in
    photo)     method="sendPhoto";     field="photo" ;;
    video)     method="sendVideo";     field="video" ;;
    animation) method="sendAnimation"; field="animation" ;;
    document)  method="sendDocument";  field="document" ;;
    *)         method="sendDocument";  field="document" ;;
  esac

  # Отправка
  if [[ -f "$media" ]]; then
    curl -sS -X POST "$API/$method" \
      -F "chat_id=$chat_id" \
      -F "reply_to_message_id=$reply_to" \
      -F "$field=@${media}" >/dev/null
  else
    curl -sS -X POST "$API/$method" \
      -d "chat_id=$chat_id" \
      -d "reply_to_message_id=$reply_to" \
      -d "$field=$media" >/dev/null
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

    media_to_send=""
    # границы слова: не буква/цифра/подчёркивание
    if grep -Eqi '(^|[^[:alnum:]_])(продал|подпродал)([^[:alnum:]_]|$)' <<<"$text"; then
        media_to_send="$PHOTO_SELL"
    elif grep -Eqi '(^|[^[:alnum:]_])(купил|закупил|подкупил|закупился|докупил)([^[:alnum:]_]|$)' <<<"$text"; then
        media_to_send="$PHOTO_BUY"
    elif grep -Eqi '(^|[^[:alnum:]_])(втб)([^[:alnum:]_]|$)' <<<"$text"; then
        media_to_send="$PHOTO_VTB"
    elif grep -Eqi '(^|[^[:alnum:]_])(ракет[[:alpha:]]*)([^[:alnum:]_]|$)' <<<"$text"; then
        media_to_send="$PHOTO_RAKETA"
    elif grep -Eqi '(^|[^[:alnum:]_])(как[[:space:]]+по[[:space:]]+нотам|многоходовочка|хитрый[[:space:]]+план)([^[:alnum:]_]|$)' <<<"$text"; then
        media_to_send="$PHOTO_PUTIN"
    elif grep -Eqi '(^|[^[:alnum:]_])(ндс|налог[[:alpha:]]*)([^[:alnum:]_]|$)' <<<"$text"; then
        media_to_send="$PHOTO_NALOG"
    elif grep -Eqi '(^|[^[:alnum:]_])(втруху|бахнем)([^[:alnum:]_]|$)' <<<"$text"; then
        media_to_send="$PHOTO_KALIBR"
    elif grep -Eqi '(^|[^[:alnum:]_])(путин[[:alpha:]]*)([^[:alnum:]_]|$)' <<<"$text"; then
        media_to_send="$PHOTO_PIPA"
    elif grep -Eqi '(^|[^[:alnum:]_])(дивиденд[[:alpha:]]*)([^[:alnum:]_]|$)' <<<"$text"; then
        media_to_send="$PHOTO_DIVI"
    elif grep -Eqi '(^|[^[:alnum:]_])(договорня[[:alpha:]]*)([^[:alnum:]_]|$)' <<<"$text"; then
        media_to_send="$PHOTO_DOGOVOR"
    elif grep -Eqi '(^|[^[:alnum:]_])(зеленский|зеленского|зеленском|зеля|зелю|зелик)([^[:alnum:]_]|$)' <<<"$text"; then
        media_to_send=""${ZELE[RANDOM % ${#ZELE[@]}]}""
    elif grep -Eqi '(^|[^[:alnum:]_])(теханал[[:alpha:]]*)([^[:alnum:]_]|$)' <<<"$text"; then
        media_to_send="$PHOTO_TEHANAL"
    elif grep -Eqi '(^|[^[:alnum:]_])(баффет[[:alpha:]]*|бафет[[:alpha:]]*)([^[:alnum:]_]|$)' <<<"$text"; then
        media_to_send="$PHOTO_BUFFET"
    else
      continue
    fi

    now="$(date +%s)"
    last="$(get_last_ts "$chat_id" || echo 0)"
    last="${last:-0}"

    if (( now - last < COOLDOWN_SECONDS )); then
      continue
    fi

    send_media "$chat_id" "$msg_id" "$media_to_send"
    set_last_ts "$chat_id" "$now"

  done < <(jq -c '.result[]' <<<"$RESP")

  # сохраняем offset, чтобы после перезапуска не отвечать на старые сообщения
  echo "$OFFSET" > "$OFFSET_FILE"
done
