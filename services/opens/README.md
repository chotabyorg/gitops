# OpenSI

Источник: https://github.com/chotabyorg/opens. Production: https://opensi.by, `www` перенаправляется на основной домен. Статическая заглушка без базы данных, форм и секретов приложения.

`prod` содержит Deployment, Service и локальные Traefik IngressRoute/Middleware. TLS выпускает существующий resolver `le`. Используется существующий `ghcr-pull-secret` для приватного контейнера. Kustomize фиксирует полный SHA и digest образа.

Не применять устаревший `platform/argocd/prod.yaml`: актуальная документация платформы описывает живой генератор `services/*/prod`. После merge проверить появление `opens-prod` и ответ `/release.json` с SHA выпущенного образа.

Проверки: `kubectl kustomize services/opens/prod`, `kubectl kustomize services/opens/dev`. GitHub Actions исходного репозитория проверяет контейнер с read-only filesystem и лимитом 64 MiB перед публикацией образа. Push исходников публикует образ; production выпускается отдельным изменением GitOps.

Первый запуск: DNS A `opensi.by` → `153.80.244.178`, CNAME `www.opensi.by` → `opensi.by`, DNS-only. Cloudflare Tunnel не используется.

Откат первого запуска: удалить только `services/opens` отдельным GitOps commit и только созданные для OpenSI DNS-записи. Для последующих выпусков вернуть предыдущий SHA/digest. Существующие сервисы и платформенные ApplicationSet не менять.
