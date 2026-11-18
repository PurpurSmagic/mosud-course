-- Практическая работа № 8. ER-модель комплектов товаров.
-- Усачев И.А., ИНБО-21-23, вариант 8. База Olist из практики № 1.

BEGIN;

CREATE TABLE IF NOT EXISTS lab.bundles (
    bundle_id bigint GENERATED ALWAYS AS IDENTITY,
    seller_id text NOT NULL,
    bundle_code text NOT NULL,
    name text NOT NULL,
    CONSTRAINT pk_bundles PRIMARY KEY (bundle_id),
    CONSTRAINT fk_bundles_seller FOREIGN KEY (seller_id) REFERENCES olist.sellers (seller_id),
    CONSTRAINT uq_bundles_seller_code UNIQUE (seller_id, bundle_code),
    CONSTRAINT ck_bundles_code CHECK (bundle_code ~ '^[A-Z0-9]+(-[A-Z0-9]+)*$'),
    CONSTRAINT ck_bundles_name CHECK (name ~ '[^[:space:]]')
);

CREATE TABLE IF NOT EXISTS lab.bundle_items (
    bundle_id bigint NOT NULL,
    product_id text NOT NULL,
    quantity integer NOT NULL,
    CONSTRAINT pk_bundle_items PRIMARY KEY (bundle_id, product_id),
    CONSTRAINT fk_bundle_items_bundle FOREIGN KEY (bundle_id)
        REFERENCES lab.bundles (bundle_id) ON DELETE CASCADE,
    CONSTRAINT fk_bundle_items_product FOREIGN KEY (product_id) REFERENCES olist.products (product_id),
    CONSTRAINT ck_bundle_items_quantity CHECK (quantity > 0)
);

-- Цена действует с valid_from до следующей записи того же комплекта.
CREATE TABLE IF NOT EXISTS lab.bundle_prices (
    bundle_id bigint NOT NULL,
    valid_from date NOT NULL,
    price_brl numeric(10,2) NOT NULL,
    CONSTRAINT pk_bundle_prices PRIMARY KEY (bundle_id, valid_from),
    CONSTRAINT fk_bundle_prices_bundle FOREIGN KEY (bundle_id)
        REFERENCES lab.bundles (bundle_id) ON DELETE CASCADE,
    CONSTRAINT ck_bundle_prices_amount CHECK (price_brl > 0 AND price_brl <> 'NaN'::numeric)
);

-- Учебные позиции. Берём пять товаров, которые действительно продавал один продавец.
CREATE TEMP TABLE lab08_sample ON COMMIT DROP AS
WITH sample_seller AS (
    SELECT seller_id FROM olist.order_items
    GROUP BY seller_id
    HAVING count(DISTINCT product_id) >= 5
    ORDER BY seller_id LIMIT 1
),
five_products AS (
    SELECT DISTINCT i.seller_id, i.product_id
    FROM olist.order_items AS i
    JOIN sample_seller AS s USING (seller_id)
    ORDER BY i.product_id LIMIT 5
),
numbered AS (
    SELECT row_number() OVER (ORDER BY product_id) AS n, seller_id, product_id
    FROM five_products
)
SELECT n, seller_id, product_id, 'L08-0' || n AS bundle_code FROM numbered;

DO $$
BEGIN
    IF (SELECT count(*) FROM lab08_sample) <> 5 THEN
        RAISE EXCEPTION 'Для примеров нужен продавец Olist как минимум с пятью разными товарами';
    END IF;
END $$;

INSERT INTO lab.bundles (seller_id, bundle_code, name)
SELECT seller_id, bundle_code, 'Учебный комплект ' || n FROM lab08_sample ORDER BY n
ON CONFLICT ON CONSTRAINT uq_bundles_seller_code DO NOTHING;

CREATE TEMP TABLE lab08_examples ON COMMIT DROP AS
SELECT s.n, b.bundle_id, b.bundle_code
FROM lab08_sample AS s
JOIN lab.bundles AS b USING (seller_id, bundle_code);

-- По два разных товара в комплекте. Соседние комплекты используют общий товар.
INSERT INTO lab.bundle_items (bundle_id, product_id, quantity)
SELECT b.bundle_id, p.product_id, CASE WHEN p.n = b.n THEN 1 ELSE 2 END
FROM lab08_examples AS b
JOIN lab08_sample AS p ON p.n IN (b.n, (b.n % 5) + 1)
ON CONFLICT ON CONSTRAINT pk_bundle_items DO NOTHING;

WITH prices(n, valid_from, price_brl) AS (
    VALUES (1, DATE '2026-01-01', 99.90), (1, DATE '2026-02-01', 109.90),
           (2, DATE '2026-01-01', 79.90), (3, DATE '2026-01-01', 119.90),
           (4, DATE '2026-01-01', 89.90), (5, DATE '2026-01-01', 149.90)
)
INSERT INTO lab.bundle_prices (bundle_id, valid_from, price_brl)
SELECT b.bundle_id, p.valid_from, p.price_brl
FROM prices AS p JOIN lab08_examples AS b USING (n)
ON CONFLICT ON CONSTRAINT pk_bundle_prices DO NOTHING;

-- Проверка структуры. PostgreSQL возвращает определения ключей и проверок.
SELECT rel.relname AS table_name, con.conname AS constraint_name,
       pg_get_constraintdef(con.oid) AS definition
FROM pg_constraint AS con
JOIN pg_class AS rel ON rel.oid = con.conrelid
WHERE rel.relnamespace = 'lab'::regnamespace
  AND rel.relname IN ('bundles', 'bundle_items', 'bundle_prices')
ORDER BY table_name, constraint_name;

SELECT table_name, column_name, data_type, is_nullable, is_identity
FROM information_schema.columns
WHERE table_schema = 'lab' AND table_name IN ('bundles', 'bundle_items', 'bundle_prices')
ORDER BY table_name, ordinal_position;

-- Число записей по учебным комплектам и их фактический состав.
SELECT (SELECT count(*) FROM lab08_examples) AS bundles,
       (SELECT count(*) FROM lab.bundle_items JOIN lab08_examples USING (bundle_id)) AS item_rows,
       (SELECT count(*) FROM lab.bundle_prices JOIN lab08_examples USING (bundle_id)) AS price_rows;

SELECT b.bundle_code, i.product_id, p.product_category_name, i.quantity
FROM lab08_examples AS b
JOIN lab.bundle_items AS i USING (bundle_id)
JOIN olist.products AS p USING (product_id)
ORDER BY b.bundle_code, i.product_id;

-- Цена на дату. До первой записи цена неизвестна. Новая цена действует с первого дня.
WITH dates(as_of) AS (VALUES (DATE '2025-12-31'), (DATE '2026-01-31'), (DATE '2026-02-01'))
SELECT b.bundle_code, d.as_of, active.price_brl
FROM lab08_examples AS b
CROSS JOIN dates AS d
LEFT JOIN LATERAL (
    SELECT p.price_brl FROM lab.bundle_prices AS p
    WHERE p.bundle_id = b.bundle_id AND p.valid_from <= d.as_of
    ORDER BY p.valid_from DESC LIMIT 1
) AS active ON true
WHERE b.n = 1 ORDER BY d.as_of;

-- Ошибочные изменения для проверки по одному на заполненной схеме.
-- 1. Нулевое количество нарушает ck_bundle_items_quantity.
-- UPDATE lab.bundle_items SET quantity = 0
-- WHERE (bundle_id, product_id) = (SELECT bundle_id, product_id FROM lab.bundle_items LIMIT 1);
-- 2. Повтор той же даты у комплекта нарушает pk_bundle_prices.
-- INSERT INTO lab.bundle_prices (bundle_id, valid_from, price_brl)
-- SELECT bundle_id, valid_from, price_brl FROM lab.bundle_prices LIMIT 1;
-- 3. Неизвестный товар нарушает fk_bundle_items_product.
-- INSERT INTO lab.bundle_items (bundle_id, product_id, quantity)
-- SELECT bundle_id, 'L08-MISSING-PRODUCT', 1 FROM lab.bundles LIMIT 1;
-- 4. Повтор кода у того же продавца нарушает uq_bundles_seller_code.
-- INSERT INTO lab.bundles (seller_id, bundle_code, name)
-- SELECT seller_id, bundle_code, name FROM lab.bundles LIMIT 1;

COMMIT;
