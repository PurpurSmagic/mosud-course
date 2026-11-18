-- Практическая работа № 4. Соединения отношений и сложные JOIN.
-- Усачев И.А., ИНБО-21-23, вариант 8. Клиенты без отзывов.
-- Клиент определяется по customer_unique_id. Учитываются заказы всех статусов.

BEGIN ISOLATION LEVEL REPEATABLE READ;

-- 1. Основной запрос. Оба LEFT JOIN сохраняют клиента даже без совпадений.
-- customers → orders по customer_id: 1:N; orders → order_reviews: 1:N.
-- У человека может быть несколько customer_id. Проверяем все его заказы вместе.
CREATE TEMP VIEW lab04_clients_without_reviews AS
SELECT c.customer_unique_id,
       count(DISTINCT o.order_id) AS order_count,
       count(r.order_id) AS review_count
FROM olist.customers AS c
LEFT JOIN olist.orders AS o ON o.customer_id = c.customer_id
LEFT JOIN olist.order_reviews AS r ON r.order_id = o.order_id
WHERE c.customer_unique_id IS NOT NULL
GROUP BY c.customer_unique_id
HAVING count(r.order_id) = 0;

-- Первые 10 клиентов и общее число найденных клиентов до LIMIT.
SELECT customer_unique_id, order_count, review_count, count(*) OVER () AS total_clients
FROM lab04_clients_without_reviews
ORDER BY order_count DESC, customer_unique_id
LIMIT 10;

-- 2. Антисоединение. Исключаем человека, если хотя бы у одного его заказа есть отзыв.
CREATE TEMP VIEW lab04_anti AS
SELECT DISTINCT c.customer_unique_id
FROM olist.customers AS c
WHERE c.customer_unique_id IS NOT NULL
  AND NOT EXISTS (
      SELECT 1
      FROM olist.customers AS account
      JOIN olist.orders AS o ON o.customer_id = account.customer_id
      JOIN olist.order_reviews AS r ON r.order_id = o.order_id
      WHERE account.customer_unique_id = c.customer_unique_id
  );

WITH only_left_join AS (
    SELECT customer_unique_id FROM lab04_clients_without_reviews
    EXCEPT
    SELECT customer_unique_id FROM lab04_anti
),
only_not_exists AS (
    SELECT customer_unique_id FROM lab04_anti
    EXCEPT
    SELECT customer_unique_id FROM lab04_clients_without_reviews
)
SELECT (SELECT count(*) FROM lab04_clients_without_reviews) AS left_join_clients,
       (SELECT count(*) FROM lab04_anti) AS not_exists_clients,
       (SELECT count(*) FROM only_left_join) AS only_left_join,
       (SELECT count(*) FROM only_not_exists) AS only_not_exists;

-- У этих людей один заказ без отзыва, а другой с отзывом. Фильтр
-- WHERE r.order_id IS NULL по отдельным заказам ошибочно включил бы их в ответ.
SELECT count(*) AS clients_with_both_kinds_of_orders
FROM (
    SELECT c.customer_unique_id
    FROM olist.customers AS c
    JOIN olist.orders AS o ON o.customer_id = c.customer_id
    LEFT JOIN olist.order_reviews AS r ON r.order_id = o.order_id
    WHERE c.customer_unique_id IS NOT NULL
    GROUP BY c.customer_unique_id
    HAVING bool_or(r.order_id IS NULL) AND bool_or(r.order_id IS NOT NULL)
) AS mixed_clients;

-- 3. Намеренная ошибка. У заказа две независимые связи 1:N:
-- с позициями и с отзывами. JOIN повторяет каждый отзыв для каждой позиции.
CREATE TEMP VIEW lab04_wrong_counts AS
SELECT o.order_id, count(r.order_id) AS review_count
FROM olist.orders AS o
LEFT JOIN olist.order_items AS i ON i.order_id = o.order_id
LEFT JOIN olist.order_reviews AS r ON r.order_id = o.order_id
GROUP BY o.order_id;

-- 4. Исправление. Сначала считаем каждую дочернюю таблицу по ключу заказа.
-- Теперь каждому заказу соответствует максимум одна строка каждой сводки.
CREATE TEMP VIEW lab04_order_counts AS
WITH item_counts AS (
    SELECT order_id, count(*) AS item_count
    FROM olist.order_items
    GROUP BY order_id
),
review_counts AS (
    SELECT order_id, count(*) AS review_count
    FROM olist.order_reviews
    GROUP BY order_id
)
SELECT o.order_id, coalesce(i.item_count, 0) AS item_count,
       coalesce(r.review_count, 0) AS review_count
FROM olist.orders AS o
LEFT JOIN item_counts AS i ON i.order_id = o.order_id
LEFT JOIN review_counts AS r ON r.order_id = o.order_id;

-- Одна строка на заказ с обеих сторон. Примеры с наибольшим завышением.
SELECT c.order_id, c.item_count, w.review_count AS wrong_reviews,
       c.review_count AS actual_reviews
FROM lab04_order_counts AS c
JOIN lab04_wrong_counts AS w ON w.order_id = c.order_id
WHERE w.review_count > c.review_count
ORDER BY (w.review_count - c.review_count) DESC, c.order_id
LIMIT 5;

-- Проверка общих итогов по всем заказам с прямым подсчётом исходных отзывов.
SELECT count(*) FILTER (WHERE w.review_count > c.review_count) AS overstated_orders,
       coalesce(sum(w.review_count), 0) AS wrong_reviews,
       coalesce(sum(c.review_count), 0) AS corrected_reviews,
       (SELECT count(*) FROM olist.order_reviews) AS source_reviews
FROM lab04_order_counts AS c
JOIN lab04_wrong_counts AS w ON w.order_id = c.order_id;

ROLLBACK;
