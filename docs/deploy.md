# Деплой Beaver v2

Приложение живёт на том же VPS и на том же gateway (nginx на `:8000`), что и
priority-lists, и пользуется той же базой Supabase. Отдельный контейнер не нужен:
Beaver — это статическая web-сборка в подпути `/beaver/` плюс свои таблицы в
существующей базе.

## 1. Секреты

```bash
cp .env.json.example .env.json
# вписать SUPABASE_ANON_KEY (тот же anon key, что у priority-lists)
```

`.env.json` в git не попадает — он в `.gitignore`. Все сборки запускаются с
`--dart-define-from-file=.env.json`.

## 2. Миграция базы

```bash
scripts/apply_migration.sh                     # 001_beaver_schema.sql
scripts/apply_migration.sh supabase/migrations/002_....sql
```

Скрипт копирует файл на VPS и подаёт его в `psql` внутри контейнера `db`
(наружу порт базы не открыт). Миграции идемпотентны, повторный запуск безопасен.

После миграции PostgREST нужно попросить перечитать схему, иначе новые таблицы
для REST API не существуют:

```bash
ssh -i ~/.ssh/priority-deploy root@65.21.0.66 \
  "cd /opt/priority-lists/supabase && \
   docker compose exec -T db psql -U postgres -d postgres \
     -c \"NOTIFY pgrst, 'reload schema';\""
```

## 3. Web-сборка

```bash
scripts/deploy_web.sh
```

Собирает с `--base-href /beaver/` и заливает `build/web/` в `/opt/beaver/web`
на VPS.

## 4. Правки в репозитории priority-lists (один раз)

Gateway и compose-файл лежат в репозитории priority-lists, поэтому два изменения
нужно внести там, а не здесь.

> **Статус:** обе правки уже применены — и в рабочей копии
> `/home/ngoriachev/Develop/priority-lists`, и на VPS (gateway пересоздан,
> `http://65.21.0.66:8000/beaver/` отвечает). Но в priority-lists они **не
> закоммичены**: пока их не закоммитить, CI-шный `rsync --delete` каталога
> `supabase/` вернёт на VPS старые файлы и `/beaver/` перестанет открываться.

### 4.1. `supabase/volumes/nginx/nginx.conf`

Добавить блок **до** `location /` (иначе его перехватит корневой `try_files`
priority-lists):

```nginx
    # Web app Beaver (Flutter web build, подпуть /beaver/)
    location /beaver/ {
        alias /usr/share/nginx/beaver/;
        index index.html;
        # Flutter web — SPA: неизвестные пути отдаём index.html, а не 404.
        try_files $uri $uri/ /beaver/index.html;
    }
```

### 4.2. `supabase/docker-compose.yml`, сервис `gateway`

Добавить монтирование рядом с существующим:

```yaml
      # Flutter web build Beaver; абсолютный путь, чтобы CI rsync --delete
      # каталога supabase/ его не затронул
      - /opt/beaver/web:/usr/share/nginx/beaver:ro
```

### 4.3. Применить

Из репозитория priority-lists:

```bash
scripts/deploy_web.sh   # синхронизирует nginx.conf и docker-compose.yml
                        # и пересоздаёт только gateway
```

`docker compose down` здесь запускать нельзя — база должна продолжать работать.
Скрипт priority-lists поднимает только `gateway`.

## Проверка

- `http://65.21.0.66:8000/` — priority-lists
- `http://65.21.0.66:8000/beaver/` — Beaver

## Android

```bash
flutter build apk --release --dart-define-from-file=.env.json
```

APK оказывается в `build/app/outputs/flutter-apk/app-release.apk`. Gateway
работает по HTTP, поэтому в `AndroidManifest.xml` включён
`android:usesCleartextTraffic="true"`.
