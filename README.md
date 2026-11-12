# Практикум МОСУД

- [Практика № 1 — развёртывание PostgreSQL и загрузка Olist](lab01/README.md)
- [Практика № 2 — множества и мультимножества в SQL](lab02/README.md)

## Автоматическое выполнение практик

При изменении SQL в ветке `main` GitHub Actions создаёт временную базу PostgreSQL, загружает CSV Olist и выполняет `lab01/check.sql` и скрипты вида `lab02/lab02.sql`. Во вкладке **Summary** последнего запуска показаны запросы, таблицы из вывода `psql` и коммит, из которого взят код. Для повторного запуска доступна кнопка **Run workflow**. [Результаты SQL в GitHub Actions](https://github.com/PurpurSmagic/mosud-course/actions/workflows/sql-results.yml)

## Подключение к готовой базе

В DBeaver создай подключение PostgreSQL со следующими параметрами.

| Поле | Значение |
| --- | --- |
| Хост | `127.0.0.1` |
| Порт | `55432` |
| База данных | `olist` |
| Пользователь | `postgres` |

Пароль находится в локальном файле `.local/postgres-password.txt`. Каталоги `.local` и `data` исключены из Git.

Чтобы повторно запустить экземпляр PostgreSQL после перезагрузки, открой PowerShell в корне репозитория и выполни:

```powershell
$pgBin = 'C:\Program Files\PostgreSQL\17\bin'
& "$pgBin\pg_ctl.exe" -D .local/pgdata -l .local/postgres.log -o '-p 55432 -h 127.0.0.1' -w start
```

## Воспроизведение на другом сервере

Скачай [архив Olist на Kaggle](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) и распакуй девять CSV в `data/olist`. На целевом сервере PostgreSQL 17 создай пустую базу `olist`. Из корня репозитория выполни команды ниже с адресом, портом и пользователем целевого сервера. `psql` запросит пароль.

```powershell
$pgBin = 'C:\Program Files\PostgreSQL\17\bin'
& "$pgBin\psql.exe" -X -h 127.0.0.1 -p 55432 -U postgres -d olist -v ON_ERROR_STOP=1 -f lab01/schema.sql
& "$pgBin\psql.exe" -X -h 127.0.0.1 -p 55432 -U postgres -d olist -v ON_ERROR_STOP=1 -f lab01/check.sql
```

`schema.sql` выполняется через `psql`, поскольку использует команду клиента `\copy`. Для готовой базы достаточно запустить `check.sql` в DBeaver или `psql`.
