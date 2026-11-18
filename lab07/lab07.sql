-- Практическая работа № 7. NULL, трёхзначная логика и качество данных.
-- Усачев И.А., группа ИНБО-21-23. Вариант по курсу 8, задание общее.

BEGIN ISOLATION LEVEL REPEATABLE READ;

-- 1. Все столбцы трёх таблиц, допускающие NULL по фактической схеме.
CREATE TEMP TABLE lab07_null_profile (
    table_name text, column_name text, ordinal_position integer,
    total_rows bigint, null_rows bigint
) ON COMMIT DROP;

DO $$
DECLARE
    col record;
BEGIN
    FOR col IN
        SELECT table_schema, table_name, column_name, ordinal_position
        FROM information_schema.columns
        WHERE table_schema = 'olist' AND is_nullable = 'YES'
          AND table_name IN ('orders', 'products', 'order_reviews')
    LOOP
        EXECUTE format(
            'INSERT INTO lab07_null_profile
             SELECT $1, $2, $3, count(*), count(*) - count(%I) FROM %I.%I',
            col.column_name, col.table_schema, col.table_name
        ) USING col.table_name, col.column_name, col.ordinal_position;
    END LOOP;
END $$;

SELECT table_name, column_name, total_rows, null_rows,
       round(100.0 * null_rows / nullif(total_rows, 0), 2) AS null_pct
FROM lab07_null_profile
ORDER BY table_name, ordinal_position;

-- 2. COUNT(*) считает заказы; COUNT(date) — только заполненные даты доставки.
SELECT count(*) AS all_orders,
       count(order_delivered_customer_date) AS known_dates,
       count(*) - count(order_delivered_customer_date) AS missing_dates
FROM olist.orders;

-- 3. Стандартные сравнения с NULL дают UNKNOWN. FILTER учитывает только TRUE.
SET LOCAL transform_null_equals = off;
SELECT count(*) FILTER (WHERE order_delivered_customer_date = NULL) AS equals_null,
       count(*) FILTER (WHERE order_delivered_customer_date <> NULL) AS differs_from_null,
       count(*) FILTER (WHERE order_delivered_customer_date IS NULL) AS is_null,
       count(*) FILTER (WHERE order_delivered_customer_date IS NOT NULL) AS is_not_null
FROM olist.orders;

-- 4. Обычное равенство и два сравнения, которые определены даже для NULL.
WITH pairs(n, a, b) AS (
    VALUES (1, 'SP', 'SP'), (2, 'SP', 'RJ'), (3, 'SP', NULL), (4, NULL, NULL)
)
SELECT coalesce(a, '(NULL)') AS a_value, coalesce(b, '(NULL)') AS b_value,
       coalesce((a = b)::text, 'UNKNOWN') AS ordinary_equality,
       a IS DISTINCT FROM b AS is_distinct,
       a IS NOT DISTINCT FROM b AS is_not_distinct
FROM pairs
ORDER BY n;

-- 5. Во временный набор добавляем один существующий ключ заказа и NULL.
CREATE TEMP TABLE temp_ids (id text) ON COMMIT DROP;
INSERT INTO temp_ids SELECT order_id FROM olist.orders ORDER BY order_id LIMIT 1;
INSERT INTO temp_ids VALUES (NULL);
SELECT coalesce(id, '(NULL)') AS temp_id FROM temp_ids ORDER BY id NULLS LAST;

SELECT count(*) FILTER (WHERE o.order_id NOT IN (SELECT id FROM temp_ids)) AS not_in,
       count(*) FILTER (WHERE NOT EXISTS (
           SELECT 1 FROM temp_ids AS t WHERE t.id = o.order_id
       )) AS not_exists,
       count(*) FILTER (WHERE o.order_id NOT IN (
           SELECT id FROM temp_ids WHERE id IS NOT NULL
       )) AS not_in_without_null
FROM olist.orders AS o;

-- 6. Число строк соединения и число уникальных заказов при двух положениях фильтра.
SELECT 'ON' AS filter_location, count(*) AS joined_rows, count(DISTINCT o.order_id) AS orders
FROM olist.orders AS o
LEFT JOIN olist.order_reviews AS r ON r.order_id = o.order_id AND r.review_score >= 4
UNION ALL
SELECT 'WHERE', count(*), count(DISTINCT o.order_id)
FROM olist.orders AS o
LEFT JOIN olist.order_reviews AS r ON r.order_id = o.order_id
WHERE r.review_score >= 4
ORDER BY filter_location;

-- 7. COALESCE на двух реальных отзывах. Текст сокращён только для вывода.
WITH examples AS (
    (SELECT order_id, review_comment_message FROM olist.order_reviews
     WHERE review_comment_message IS NULL ORDER BY order_id, review_id LIMIT 1)
    UNION ALL
    (SELECT order_id, review_comment_message FROM olist.order_reviews
     WHERE review_comment_message ~ '[^[:space:]]' ORDER BY order_id, review_id LIMIT 1)
)
SELECT order_id, review_comment_message IS NULL AS was_null,
       left(coalesce(review_comment_message, 'Комментарий отсутствует'), 100) AS displayed_comment
FROM examples
ORDER BY was_null DESC;

SELECT count(*) FILTER (WHERE review_comment_message IS NULL) AS null_comments,
       count(*) FILTER (WHERE review_comment_message = '') AS empty_strings,
       count(*) FILTER (WHERE review_comment_message ~ '^[[:space:]]+$') AS whitespace_only
FROM olist.order_reviews;

-- NULLIF заменяет нулевой знаменатель на NULL. Для пустой выборки доля не определена.
WITH samples(missing, total) AS (VALUES (1, 4), (0, 0))
SELECT missing, total, round(100.0 * missing / nullif(total, 0), 2) AS missing_pct,
       (100.0 * missing / nullif(total, 0)) IS NULL AS undefined_pct
FROM samples
ORDER BY total DESC;

-- 8. Мини-профиль. В каждой строке знаменатель — размер соответствующей таблицы.
WITH metrics(n, metric, table_name, column_name) AS (
    VALUES (1, 'orders_without_delivery_date', 'orders', 'order_delivered_customer_date'),
           (2, 'products_without_category', 'products', 'product_category_name'),
           (3, 'reviews_without_text', 'order_reviews', 'review_comment_message')
)
SELECT m.metric, p.total_rows, p.null_rows AS missing_rows,
       round(100.0 * p.null_rows / nullif(p.total_rows, 0), 2) AS missing_pct
FROM metrics AS m
JOIN lab07_null_profile AS p USING (table_name, column_name)
ORDER BY m.n;

-- 9. Пропуск текста допустим при выставленной оценке. Для даты важен статус заказа:
-- у заказа в пути дата ещё не известна, у доставленного пропуск требует проверки.
SELECT order_status, count(*) AS orders,
       count(*) FILTER (WHERE order_delivered_customer_date IS NULL) AS missing_dates,
       min(order_id) FILTER (WHERE order_delivered_customer_date IS NULL) AS example_order_without_date
FROM olist.orders
GROUP BY order_status
ORDER BY order_status;

ROLLBACK;
