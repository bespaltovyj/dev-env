# Окружение agent-box

## Git-репозитории
- Все git-репозитории клонировать только в `/repos/<имя-репозитория>` (`$REPOS_DIR`), например
  `git clone https://github.com/org/app.git /repos/app`. Не клонировать в домашнюю папку, `/tmp` и другие места.
- `/repos/orca-worktrees` занят worktree Orca: не клонировать туда и не создавать репозиторий с таким именем.
- `/repos` — папка Windows: имена файлов без учёта регистра, большие `node_modules` и сборки там медленнее.

## PostgreSQL
- PostgreSQL 18 доступен по адресу `postgres:5432`; пользователь, пароль и БД по умолчанию — в переменных
  `$POSTGRES_USER`, `$POSTGRES_PASSWORD`, `$POSTGRES_DB`. Для своих задач создавать отдельные базы
  (`createdb -h postgres -U "$POSTGRES_USER" <имя>`), а не писать в базу по умолчанию.

## Сеть
- Интернет только через прокси с allowlist: доступны GitHub (только https, не ssh), реестры npm, PyPI, Go,
  Maven Central, Gradle, Kubernetes/Helm и Anthropic. Ответ 403 от прокси — домена нет в списке, обходить не пытаться.
