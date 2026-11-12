-- Практическая работа № 2. Множества и мультимножества в SQL.
-- ФИО: Усачев И.А.
-- Группа: ИНБО-21-23
-- Вариант: 8 (X = MT, Y = MS).

BEGIN ISOLATION LEVEL REPEATABLE READ;

-- Одна строка соответствует позиции доставленного заказа.
CREATE TEMP TABLE lab02_purchases ON COMMIT DROP AS
SELECT c.customer_state, i.product_id
FROM olist.customers AS c
JOIN olist.orders AS o ON o.customer_id = c.customer_id
JOIN olist.order_items AS i ON i.order_id = o.order_id
WHERE o.order_status = 'delivered'
  AND c.customer_state IN ('MT', 'MS');

-- 1. Мощности A и B с учётом повторов и после их удаления.
SELECT 'A' AS operand, 'MT' AS customer_state,
       count(*) AS row_count, count(DISTINCT product_id) AS distinct_products
FROM lab02_purchases
WHERE customer_state = 'MT'
UNION ALL
SELECT 'B', 'MS', count(*), count(DISTINCT product_id)
FROM lab02_purchases
WHERE customer_state = 'MS'
ORDER BY operand;

-- 2. Объединение, пересечение, обе разности и пересечение через EXISTS.
WITH a AS (
    SELECT product_id FROM lab02_purchases WHERE customer_state = 'MT'
),
b AS (
    SELECT product_id FROM lab02_purchases WHERE customer_state = 'MS'
),
union_distinct AS (
    SELECT product_id FROM a
    UNION
    SELECT product_id FROM b
),
union_all AS (
    SELECT product_id FROM a
    UNION ALL
    SELECT product_id FROM b
),
intersection AS (
    SELECT product_id FROM a
    INTERSECT
    SELECT product_id FROM b
),
a_minus_b AS (
    SELECT product_id FROM a
    EXCEPT
    SELECT product_id FROM b
),
b_minus_a AS (
    SELECT product_id FROM b
    EXCEPT
    SELECT product_id FROM a
),
intersection_exists AS (
    SELECT DISTINCT a.product_id
    FROM a
    WHERE EXISTS (SELECT 1 FROM b WHERE b.product_id = a.product_id)
)
SELECT 'A UNION B' AS operation, count(*) AS row_count, min(product_id) AS sample_product_id
FROM union_distinct
UNION ALL
SELECT 'A UNION ALL B', count(*), min(product_id) FROM union_all
UNION ALL
SELECT 'A INTERSECT B', count(*), min(product_id) FROM intersection
UNION ALL
SELECT 'A EXCEPT B', count(*), min(product_id) FROM a_minus_b
UNION ALL
SELECT 'B EXCEPT A', count(*), min(product_id) FROM b_minus_a
UNION ALL
SELECT 'EXISTS + DISTINCT', count(*), min(product_id) FROM intersection_exists
ORDER BY operation;

-- 3. Проверка коммутативности и эквивалентности по самим product_id.
-- Метка сравнения позволяет проверить все пары одним EXCEPT в каждом направлении.
WITH a AS (
    SELECT product_id FROM lab02_purchases WHERE customer_state = 'MT'
),
b AS (
    SELECT product_id FROM lab02_purchases WHERE customer_state = 'MS'
),
ab_intersection AS (
    SELECT product_id FROM a
    INTERSECT
    SELECT product_id FROM b
),
left_results (comparison, product_id) AS (
    SELECT 'UNION', product_id
    FROM (SELECT product_id FROM a UNION SELECT product_id FROM b) AS ab_union
    UNION ALL
    SELECT 'INTERSECT', product_id FROM ab_intersection
    UNION ALL
    SELECT 'EXCEPT', product_id
    FROM (SELECT product_id FROM a EXCEPT SELECT product_id FROM b) AS ab_difference
    UNION ALL
    SELECT 'INTERSECT / EXISTS', product_id FROM ab_intersection
),
right_results (comparison, product_id) AS (
    SELECT 'UNION', product_id
    FROM (SELECT product_id FROM b UNION SELECT product_id FROM a) AS ba_union
    UNION ALL
    SELECT 'INTERSECT', product_id
    FROM (SELECT product_id FROM b INTERSECT SELECT product_id FROM a) AS ba_intersection
    UNION ALL
    SELECT 'EXCEPT', product_id
    FROM (SELECT product_id FROM b EXCEPT SELECT product_id FROM a) AS ba_difference
    UNION ALL
    SELECT DISTINCT 'INTERSECT / EXISTS', a.product_id
    FROM a
    WHERE EXISTS (SELECT 1 FROM b WHERE b.product_id = a.product_id)
),
left_only AS (
    SELECT comparison, product_id FROM left_results
    EXCEPT
    SELECT comparison, product_id FROM right_results
),
right_only AS (
    SELECT comparison, product_id FROM right_results
    EXCEPT
    SELECT comparison, product_id FROM left_results
)
SELECT pairs.comparison,
       (SELECT count(*) FROM left_only WHERE left_only.comparison = pairs.comparison) AS only_left,
       (SELECT count(*) FROM right_only WHERE right_only.comparison = pairs.comparison) AS only_right
FROM (VALUES ('UNION'), ('INTERSECT'), ('EXCEPT'), ('INTERSECT / EXISTS')) AS pairs (comparison)
ORDER BY pairs.comparison;

-- 4. Пересечение через EXISTS без DISTINCT. Десять товаров с наибольшей кратностью.
WITH a AS (
    SELECT product_id FROM lab02_purchases WHERE customer_state = 'MT'
),
b AS (
    SELECT product_id FROM lab02_purchases WHERE customer_state = 'MS'
)
SELECT a.product_id, count(*) AS occurrences_in_a,
       count(*) OVER () AS total_products_with_duplicates
FROM a
WHERE EXISTS (SELECT 1 FROM b WHERE b.product_id = a.product_id)
GROUP BY a.product_id
HAVING count(*) > 1
ORDER BY occurrences_in_a DESC, a.product_id
LIMIT 10;

-- 5. Обычные UNION, INTERSECT и EXCEPT возвращают множества.
-- UNION ALL, INTERSECT ALL, EXCEPT ALL и SELECT без DISTINCT допускают повторы.

COMMIT;
