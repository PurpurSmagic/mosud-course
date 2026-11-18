-- Практическая работа № 3. Выборка, проекция и переименование.
-- ФИО: Усачев И.А.
-- Группа: ИНБО-21-23
-- Вариант: 8.
-- Исходное отношение: olist.geolocation.
-- Предикат: geolocation_state = 'RJ' и -23 <= geolocation_lat <= -22.
-- Диапазон широт выбран для работы, обе границы включены.
-- Проекция: ZIP-префикс, широта, долгота, город.
-- Сокращённые имена результата: zip_prefix, lat, lng, city.

BEGIN ISOLATION LEVEL REPEATABLE READ;

-- 1. Исходный запрос. WHERE выполняет выборку, SELECT задаёт проекцию,
-- AS переименовывает атрибуты. Повторы сохраняются для исследования.
CREATE TEMP TABLE lab03_original ON COMMIT DROP AS
SELECT geolocation_zip_code_prefix AS zip_prefix,
       geolocation_lat AS lat,
       geolocation_lng AS lng,
       geolocation_city AS city
FROM olist.geolocation
WHERE geolocation_state = 'RJ'
  AND geolocation_lat BETWEEN -23 AND -22;

-- 2. Две последовательные выборки. Сначала штат, затем диапазон широт.
CREATE TEMP TABLE lab03_sequential ON COMMIT DROP AS
WITH state_filtered AS (
    SELECT *
    FROM olist.geolocation
    WHERE geolocation_state = 'RJ'
)
SELECT geolocation_zip_code_prefix AS zip_prefix,
       geolocation_lat AS lat,
       geolocation_lng AS lng,
       geolocation_city AS city
FROM state_filtered
WHERE geolocation_lat BETWEEN -23 AND -22;

-- 3. Ранняя проекция. После отбора по штату его столбец уже можно исключить.
-- Широта остаётся в промежуточной выборке для следующего фильтра.
-- Это логический порядок операций, физический план выбирает PostgreSQL.
CREATE TEMP TABLE lab03_early_projection ON COMMIT DROP AS
WITH projected AS (
    SELECT geolocation_zip_code_prefix AS zip_prefix,
           geolocation_lat AS lat,
           geolocation_lng AS lng,
           geolocation_city AS city
    FROM olist.geolocation
    WHERE geolocation_state = 'RJ'
)
SELECT zip_prefix, lat, lng, city
FROM projected
WHERE lat BETWEEN -23 AND -22;

-- 4. Число строк каждого варианта и сравнение SELECT с SELECT DISTINCT.
SELECT 'original SELECT' AS query_variant, count(*) AS row_count
FROM lab03_original
UNION ALL
SELECT 'sequential SELECT', count(*) FROM lab03_sequential
UNION ALL
SELECT 'early projection SELECT', count(*) FROM lab03_early_projection
UNION ALL
SELECT 'SELECT DISTINCT', count(*)
FROM (
    SELECT DISTINCT zip_prefix, lat, lng, city
    FROM lab03_original
) AS distinct_projection
ORDER BY query_variant;

-- 5. EXCEPT ALL проверяет состав и кратность строк в обоих направлениях.
WITH original_only_sequential AS (
    SELECT * FROM lab03_original
    EXCEPT ALL
    SELECT * FROM lab03_sequential
),
sequential_only_original AS (
    SELECT * FROM lab03_sequential
    EXCEPT ALL
    SELECT * FROM lab03_original
),
original_only_early AS (
    SELECT * FROM lab03_original
    EXCEPT ALL
    SELECT * FROM lab03_early_projection
),
early_only_original AS (
    SELECT * FROM lab03_early_projection
    EXCEPT ALL
    SELECT * FROM lab03_original
)
SELECT 'original / sequential' AS comparison,
       (SELECT count(*) FROM original_only_sequential) AS only_original,
       (SELECT count(*) FROM sequential_only_original) AS only_alternative
UNION ALL
SELECT 'original / early projection',
       (SELECT count(*) FROM original_only_early),
       (SELECT count(*) FROM early_only_original)
ORDER BY comparison;

-- 6. Математическая проекция устраняет дубликаты.
-- Первые 10 уникальных строк. Полная мощность выведена в пункте 4.
SELECT DISTINCT zip_prefix, lat, lng, city
FROM lab03_original
ORDER BY zip_prefix, lat, lng, city
LIMIT 10;

-- 7. Кратность одинаковых кортежей из четырёх столбцов проекции.
-- В таблице показаны первые 10 групп, total_duplicate_groups считает все группы.
SELECT zip_prefix, lat, lng, city, count(*) AS occurrences,
       count(*) OVER () AS total_duplicate_groups
FROM lab03_original
GROUP BY zip_prefix, lat, lng, city
HAVING count(*) > 1
ORDER BY occurrences DESC, zip_prefix, lat, lng, city
LIMIT 10;

COMMIT;
