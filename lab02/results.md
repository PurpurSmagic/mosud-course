# Результаты практической работы № 2

[Описание работы](README.md) · [Полный SQL-скрипт](lab02.sql)

Запросы выполнены на PostgreSQL 17.5 с данными Olist. Вариант 8, штаты MT и MS.

## Подготовка выборок

Временная таблица содержит позиции доставленных заказов для двух штатов. Она удаляется при завершении транзакции.

```sql
BEGIN ISOLATION LEVEL REPEATABLE READ;

-- Одна строка соответствует позиции доставленного заказа.
CREATE TEMP TABLE lab02_purchases ON COMMIT DROP AS
SELECT c.customer_state, i.product_id
FROM olist.customers AS c
JOIN olist.orders AS o ON o.customer_id = c.customer_id
JOIN olist.order_items AS i ON i.order_id = o.order_id
WHERE o.order_status = 'delivered'
  AND c.customer_state IN ('MT', 'MS');
```

## Мощности A и B

```sql
SELECT 'A' AS operand, 'MT' AS customer_state,
       count(*) AS row_count, count(DISTINCT product_id) AS distinct_products
FROM lab02_purchases
WHERE customer_state = 'MT'
UNION ALL
SELECT 'B', 'MS', count(*), count(DISTINCT product_id)
FROM lab02_purchases
WHERE customer_state = 'MS'
ORDER BY operand;
```

| operand | customer_state | row_count | distinct_products |
| --- | --- | ---: | ---: |
| A | MT | 1037 | 841 |
| B | MS | 811 | 647 |

## Операции над множествами

```sql
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
```

Столбец row_count показывает полный размер результата. В sample_product_id приведён один товар из каждой выборки.

| operation | row_count | sample_product_id |
| --- | ---: | --- |
| A EXCEPT B | 748 | 008686d56f4c85b987a4c24a286834c1 |
| A INTERSECT B | 93 | 014a8a503291921f7b004a5215bb3c36 |
| A UNION ALL B | 1848 | 008686d56f4c85b987a4c24a286834c1 |
| A UNION B | 1395 | 008686d56f4c85b987a4c24a286834c1 |
| B EXCEPT A | 554 | 0141015d2469c1c5f9d7d377d1cdb44a |
| EXISTS + DISTINCT | 93 | 014a8a503291921f7b004a5215bb3c36 |

## Проверка коммутативности и эквивалентности

```sql
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
```

Столбцы only_left и only_right считают товары, которые есть только в одном из сравниваемых результатов.

| comparison | only_left | only_right |
| --- | ---: | ---: |
| EXCEPT | 748 | 554 |
| INTERSECT | 0 | 0 |
| INTERSECT / EXISTS | 0 | 0 |
| UNION | 0 | 0 |

## Дубликаты после удаления DISTINCT

```sql
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
```

Найдено 32 товаров с повторами. В таблице показаны первые 10 по убыванию числа повторений.

| product_id | occurrences_in_a | total_products_with_duplicates |
| --- | ---: | ---: |
| 9ecadb84c81da840dbf3564378b586e9 | 6 | 32 |
| d1c427060a0f73f6b889a5c7c61f2ac4 | 6 | 32 |
| 389d119b48cf3043d311335e499d9c6b | 5 | 32 |
| a92930c327948861c015c919a0bcb4a8 | 5 | 32 |
| 36efd30e7c14e8ed3a6557e9104112b3 | 4 | 32 |
| 5a848e4ab52fd5445cdc07aab1c40e48 | 4 | 32 |
| aca2eb7d00ea1a7b8ebd4e68314663af | 4 | 32 |
| 43423cdffde7fda63d0414ed38c11a73 | 3 | 32 |
| 7814c273ab16783d73a9863ebfa8b141 | 3 | 32 |
| 99a4788cb24856965c36a24e339b6058 | 3 | 32 |
