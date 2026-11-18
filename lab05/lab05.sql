-- Практическая работа № 5. Кванторы, EXISTS и реляционное деление.
-- Усачев И.А., ИНБО-21-23, вариант 8. Штаты покупателей: MS, MT, GO.

BEGIN ISOLATION LEVEL REPEATABLE READ;

-- 1. Делитель S и исходные продажи. Штат берём из записи покупателя.
CREATE TEMP TABLE lab05_target ON COMMIT DROP AS
WITH target_states(customer_state) AS (VALUES ('MS'), ('MT'), ('GO'))
SELECT customer_state FROM target_states;

CREATE TEMP TABLE lab05_sales ON COMMIT DROP AS
SELECT o.order_id, c.customer_state, i.seller_id, p.product_category_name AS category
FROM olist.orders AS o
JOIN olist.customers AS c ON c.customer_id = o.customer_id
JOIN olist.order_items AS i ON i.order_id = o.order_id
JOIN olist.products AS p ON p.product_id = i.product_id
WHERE o.order_status = 'delivered';

-- R — уникальные пары (категория, штат) по всем штатам, U — их категории.
CREATE TEMP TABLE lab05_category_states ON COMMIT DROP AS
SELECT DISTINCT category, customer_state
FROM lab05_sales
WHERE category IS NOT NULL AND customer_state IS NOT NULL;

CREATE TEMP VIEW lab05_candidates AS
SELECT DISTINCT category FROM lab05_category_states;

-- 2. Нет обязательного штата, в котором отсутствуют продажи категории.
CREATE TEMP VIEW lab05_by_exists AS
SELECT c.category
FROM lab05_candidates AS c
WHERE NOT EXISTS (
    SELECT 1 FROM lab05_target AS t
    WHERE NOT EXISTS (
        SELECT 1 FROM lab05_category_states AS r
        WHERE r.category = c.category AND r.customer_state = t.customer_state
    )
);

-- 3. Считаем только совпавшие штаты. LEFT JOIN сохраняет группы при пустом S.
CREATE TEMP VIEW lab05_by_count AS
SELECT r.category
FROM lab05_category_states AS r
LEFT JOIN lab05_target AS t ON t.customer_state = r.customer_state
GROUP BY r.category
HAVING count(DISTINCT t.customer_state) = (SELECT count(*) FROM lab05_target);

-- 4. Разность «обязательные штаты минус штаты продаж категории» пуста.
CREATE TEMP VIEW lab05_by_except AS
SELECT c.category
FROM lab05_candidates AS c
WHERE NOT EXISTS (
    SELECT customer_state FROM lab05_target
    EXCEPT
    SELECT customer_state FROM lab05_category_states AS r WHERE r.category = c.category
);

-- Полный список категорий для варианта 8.
SELECT category FROM lab05_by_exists ORDER BY category COLLATE "C";

-- 5. Число категорий и все шесть попарных разностей множеств.
CREATE TEMP VIEW lab05_totals AS
SELECT (SELECT count(*) FROM lab05_target) AS required_states,
       (SELECT count(*) FROM lab05_candidates) AS candidates,
       (SELECT count(*) FROM lab05_by_exists) AS double_not_exists,
       (SELECT count(*) FROM lab05_by_count) AS group_by_count,
       (SELECT count(*) FROM lab05_by_except) AS except_not_exists;

CREATE TEMP VIEW lab05_results AS
SELECT 'double_not_exists' AS method, category FROM lab05_by_exists
UNION ALL
SELECT 'group_by_count', category FROM lab05_by_count
UNION ALL
SELECT 'except_not_exists', category FROM lab05_by_except;

CREATE TEMP VIEW lab05_differences AS
WITH methods(method) AS (
    VALUES ('double_not_exists'), ('group_by_count'), ('except_not_exists')
)
SELECT a.method AS first_method, b.method AS second_method,
       (SELECT count(*)
        FROM (
            SELECT category FROM lab05_results WHERE method = a.method
            EXCEPT
            SELECT category FROM lab05_results WHERE method = b.method
        ) AS only_in_first) AS difference_rows
FROM methods AS a CROSS JOIN methods AS b
WHERE a.method <> b.method;

TABLE lab05_totals;
SELECT * FROM lab05_differences ORDER BY first_method, second_method;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM lab05_differences WHERE difference_rows <> 0) THEN
        RAISE EXCEPTION 'Результаты трёх методов деления различаются';
    END IF;
END $$;

-- 6. Для первой найденной категории показываем число отдельных заказов в каждом штате.
WITH first_category AS (
    SELECT category FROM lab05_by_exists ORDER BY category COLLATE "C" LIMIT 1
)
SELECT f.category, t.customer_state, count(DISTINCT s.order_id) AS delivered_orders
FROM first_category AS f
CROSS JOIN lab05_target AS t
LEFT JOIN lab05_sales AS s ON s.category = f.category AND s.customer_state = t.customer_state
GROUP BY f.category, t.customer_state
ORDER BY t.customer_state;

-- 7. Пустой делитель. Повторяем те же три запроса на том же универсуме U.
SAVEPOINT before_empty_target;
DELETE FROM lab05_target;
TABLE lab05_totals;

-- Все три результата по построению являются подмножествами U.
-- Равенство их мощностей мощности U при пустом S означает равенство множеств.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM lab05_totals
        WHERE double_not_exists <> candidates OR group_by_count <> candidates
           OR except_not_exists <> candidates
    ) THEN
        RAISE EXCEPTION 'При пустом делителе ожидались все категории-кандидаты';
    END IF;
END $$;

-- Для сравнения: обычный JOIN с пустым S не создаёт ни одной группы.
SELECT count(*) AS categories_with_inner_join
FROM (
    SELECT r.category FROM lab05_category_states AS r
    JOIN lab05_target AS t ON t.customer_state = r.customer_state
    GROUP BY r.category
    HAVING count(DISTINCT t.customer_state) = (SELECT count(*) FROM lab05_target)
) AS grouped;
ROLLBACK TO SAVEPOINT before_empty_target;

-- 8. Дополнительно: продавцы с доставленными заказами покупателей MS, MT и GO.
-- Здесь учитываются все товары продавца, включая позиции с неизвестной категорией.
SELECT s.seller_id, count(*) OVER () AS total_sellers
FROM lab05_sales AS s
JOIN lab05_target AS t ON t.customer_state = s.customer_state
GROUP BY s.seller_id
HAVING count(DISTINCT t.customer_state) = (SELECT count(*) FROM lab05_target)
ORDER BY s.seller_id;

ROLLBACK;
