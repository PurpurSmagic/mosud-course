-- Практическая работа № 6. Подзапросы и логика предикатов.
-- Усачев И.А., группа ИНБО-21-23, вариант 8.
-- Продавцы, у которых средняя стоимость доставки позиции выше общей средней.

BEGIN ISOLATION LEVEL REPEATABLE READ;

-- AVG учитывает известные значения, включая нулевую стоимость доставки.
-- Индекс временной таблицы ускоряет поиск позиций отдельного продавца.
CREATE TEMP TABLE lab06_freight ON COMMIT DROP AS
SELECT seller_id, freight_value
FROM olist.order_items
WHERE freight_value IS NOT NULL;

CREATE INDEX ON lab06_freight (seller_id);
ANALYZE lab06_freight;

-- 1. Первый скалярный подзапрос зависит от продавца внешней строки.
-- Второй вычисляет один общий порог по всем позициям с известной стоимостью.
CREATE TEMP TABLE lab06_main ON COMMIT DROP AS
WITH averages AS MATERIALIZED (
    SELECT s.seller_id,
           (SELECT avg(i.freight_value) FROM lab06_freight AS i
            WHERE i.seller_id = s.seller_id) AS seller_avg,
           (SELECT avg(i.freight_value) FROM lab06_freight AS i) AS overall_avg
    FROM olist.sellers AS s
)
SELECT seller_id, seller_avg, overall_avg
FROM averages
WHERE seller_avg > overall_avg;

-- Первые 10 продавцов по величине средней. Отбор и сортировка до округления.
SELECT seller_id, round(seller_avg, 2) AS seller_avg_freight,
       round(overall_avg, 2) AS overall_avg_freight
FROM lab06_main
ORDER BY seller_avg DESC, seller_id
LIMIT 10;

-- 2. Альтернатива. Один CTE группирует исходные позиции по продавцу,
-- другой считает среднюю по всем позициям. AVG пропускает NULL.
CREATE TEMP TABLE lab06_alternative ON COMMIT DROP AS
WITH per_seller AS (
    SELECT seller_id, avg(freight_value) AS seller_avg
    FROM olist.order_items
    GROUP BY seller_id
),
overall AS (
    SELECT avg(freight_value) AS overall_avg FROM olist.order_items
)
SELECT s.seller_id, p.seller_avg, g.overall_avg
FROM olist.sellers AS s
JOIN per_seller AS p ON p.seller_id = s.seller_id
CROSS JOIN overall AS g
WHERE p.seller_avg > g.overall_avg;

-- 3. Обе разности сравнивают полные строки с неокруглёнными средними.
CREATE TEMP VIEW lab06_comparison AS
WITH only_main AS (
    TABLE lab06_main EXCEPT TABLE lab06_alternative
),
only_alternative AS (
    TABLE lab06_alternative EXCEPT TABLE lab06_main
)
SELECT (SELECT count(*) FROM lab06_main) AS main_sellers,
       (SELECT count(*) FROM lab06_alternative) AS alternative_sellers,
       (SELECT count(*) FROM only_main) AS only_main,
       (SELECT count(*) FROM only_alternative) AS only_alternative;

TABLE lab06_comparison;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM lab06_comparison WHERE only_main <> 0 OR only_alternative <> 0) THEN
        RAISE EXCEPTION 'Результаты основного и альтернативного запросов различаются';
    END IF;
END $$;

-- 4. ANY и ALL. У пяти найденных продавцов сравним каждую известную стоимость
-- с общим порогом. Все пять уже прошли основное условие по средней.
SELECT m.seller_id, round(m.seller_avg, 2) AS seller_avg_freight,
       m.overall_avg < ANY (
           SELECT i.freight_value FROM lab06_freight AS i WHERE i.seller_id = m.seller_id
       ) AS any_item_above,
       m.overall_avg < ALL (
           SELECT i.freight_value FROM lab06_freight AS i WHERE i.seller_id = m.seller_id
       ) AS all_items_above
FROM lab06_main AS m
ORDER BY m.seller_id
LIMIT 5;

-- У пустого набора и набора с NULL разные логические свойства.
-- IS UNKNOWN делает неопределённый результат видимым в выводе psql.
WITH empty_set(value) AS (SELECT 5 WHERE false),
with_null(value) AS (VALUES (5), (NULL::integer))
SELECT 10 > ANY (SELECT value FROM empty_set) AS any_empty,
       10 > ALL (SELECT value FROM empty_set) AS all_empty,
       10 > ANY (SELECT value FROM with_null) AS any_with_null,
       (10 > ALL (SELECT value FROM with_null)) IS UNKNOWN AS all_with_null_is_unknown;

ROLLBACK;
