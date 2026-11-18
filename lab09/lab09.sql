-- Практическая работа № 9. Функциональные зависимости и нормализация.
-- Усачев И.А., ИНБО-21-23, вариант 8. Исходное отношение bundle_flat.

BEGIN ISOLATION LEVEL REPEATABLE READ;

-- Пять позиций трёх учебных комплектов. Категории берём из каталога Olist.
CREATE TEMP TABLE lab09_flat ON COMMIT DROP AS
WITH sample_products(product_no, product_id) AS (
    VALUES (1, '08574b074924071f4e201e151b152b4e'),
           (2, '0da9ffd92214425d880de3f94e74ce39'),
           (3, '21fecd254a3103704126b28478ea7980')
),
positions(bundle_id, bundle_name, product_no, qty, price_rule_code, price_rule_name) AS (
    VALUES ('KIT-01', 'Садовый набор',       1, 1, 'BASE',   'Базовая цена'),
           ('KIT-01', 'Садовый набор',       2, 2, 'BASE',   'Базовая цена'),
           ('KIT-02', 'Набор для мастерской', 2, 1, 'BASE',   'Базовая цена'),
           ('KIT-02', 'Набор для мастерской', 3, 3, 'BASE',   'Базовая цена'),
           ('KIT-03', 'Сезонный набор',      1, 2, 'SEASON', 'Сезонная цена')
)
SELECT s.bundle_id, s.bundle_name, p.product_id, p.product_category_name AS category_name,
       s.qty, s.price_rule_code, s.price_rule_name
FROM positions AS s
JOIN sample_products AS k USING (product_no)
JOIN olist.products AS p ON p.product_id = k.product_id;

DO $$
BEGIN
    IF (SELECT count(*) FROM lab09_flat) <> 5 THEN
        RAISE EXCEPTION 'Для пяти тестовых позиций нужны все три выбранных товара Olist';
    END IF;
END $$;

SELECT * FROM lab09_flat ORDER BY bundle_id, product_id;

-- Итоговая декомпозиция. В каждой таблице детерминант ФЗ является ключом.
CREATE TABLE IF NOT EXISTS lab.nf_8_price_rules (
    price_rule_code text CONSTRAINT pk_nf_8_price_rules PRIMARY KEY,
    price_rule_name text NOT NULL
);

CREATE TABLE IF NOT EXISTS lab.nf_8_bundles (
    bundle_id text CONSTRAINT pk_nf_8_bundles PRIMARY KEY,
    bundle_name text NOT NULL,
    price_rule_code text NOT NULL,
    CONSTRAINT fk_nf_8_bundles_rule FOREIGN KEY (price_rule_code)
        REFERENCES lab.nf_8_price_rules (price_rule_code)
);

CREATE TABLE IF NOT EXISTS lab.nf_8_products (
    product_id text CONSTRAINT pk_nf_8_products PRIMARY KEY,
    category_name text NOT NULL,
    CONSTRAINT fk_nf_8_products_olist FOREIGN KEY (product_id)
        REFERENCES olist.products (product_id)
);

CREATE TABLE IF NOT EXISTS lab.nf_8_bundle_items (
    item_id bigint GENERATED ALWAYS AS IDENTITY CONSTRAINT pk_nf_8_bundle_items PRIMARY KEY,
    bundle_id text NOT NULL,
    product_id text NOT NULL,
    qty integer NOT NULL,
    CONSTRAINT uq_nf_8_bundle_product UNIQUE (bundle_id, product_id),
    CONSTRAINT fk_nf_8_items_bundle FOREIGN KEY (bundle_id) REFERENCES lab.nf_8_bundles (bundle_id),
    CONSTRAINT fk_nf_8_items_product FOREIGN KEY (product_id) REFERENCES lab.nf_8_products (product_id),
    CONSTRAINT ck_nf_8_items_qty CHECK (qty > 0)
);

-- Проекции исходных строк. Конфликты по ключам возможны при повторном запуске.
INSERT INTO lab.nf_8_price_rules (price_rule_code, price_rule_name)
SELECT DISTINCT price_rule_code, price_rule_name FROM lab09_flat
ON CONFLICT (price_rule_code) DO NOTHING;

INSERT INTO lab.nf_8_products (product_id, category_name)
SELECT DISTINCT product_id, category_name FROM lab09_flat
ON CONFLICT (product_id) DO NOTHING;

INSERT INTO lab.nf_8_bundles (bundle_id, bundle_name, price_rule_code)
SELECT DISTINCT bundle_id, bundle_name, price_rule_code FROM lab09_flat
ON CONFLICT (bundle_id) DO NOTHING;

INSERT INTO lab.nf_8_bundle_items (bundle_id, product_id, qty)
SELECT bundle_id, product_id, qty FROM lab09_flat ORDER BY bundle_id, product_id
ON CONFLICT (bundle_id, product_id) DO NOTHING;

-- Восстанавливаем все позиции тестовых комплектов по PK/FK.
CREATE TEMP TABLE lab09_restored ON COMMIT DROP AS
SELECT b.bundle_id, b.bundle_name, p.product_id, p.category_name,
       i.qty, r.price_rule_code, r.price_rule_name
FROM lab.nf_8_bundle_items AS i
JOIN lab.nf_8_bundles AS b USING (bundle_id)
JOIN lab.nf_8_products AS p USING (product_id)
JOIN lab.nf_8_price_rules AS r ON r.price_rule_code = b.price_rule_code
WHERE b.bundle_id IN (SELECT bundle_id FROM lab09_flat);

SELECT * FROM lab09_restored ORDER BY bundle_id, product_id;

-- Две разности по всем семи атрибутам учитывают также число вхождений строки.
CREATE TEMP TABLE lab09_comparison ON COMMIT DROP AS
WITH missing AS (
    TABLE lab09_flat EXCEPT ALL TABLE lab09_restored
),
extra AS (
    TABLE lab09_restored EXCEPT ALL TABLE lab09_flat
)
SELECT (SELECT count(*) FROM lab09_flat) AS flat_rows,
       (SELECT count(*) FROM lab09_restored) AS restored_rows,
       (SELECT count(*) FROM missing) AS missing_rows,
       (SELECT count(*) FROM extra) AS extra_rows;

TABLE lab09_comparison;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM lab09_comparison WHERE missing_rows > 0 OR extra_rows > 0) THEN
        RAISE EXCEPTION 'Восстановленное отношение отличается от пяти исходных строк';
    END IF;
END $$;

-- Сколько раз название правила записано в плоской таблице и в справочнике.
SELECT f.price_rule_code, f.price_rule_name, count(*) AS copies_in_flat,
       (SELECT count(*) FROM lab.nf_8_price_rules AS r
        WHERE r.price_rule_code = f.price_rule_code) AS copies_in_dictionary
FROM lab09_flat AS f
GROUP BY f.price_rule_code, f.price_rule_name
ORDER BY f.price_rule_code;

SELECT (SELECT count(*) FROM lab.nf_8_price_rules) AS price_rules,
       (SELECT count(*) FROM lab.nf_8_bundles) AS bundles,
       (SELECT count(*) FROM lab.nf_8_products) AS products,
       (SELECT count(*) FROM lab.nf_8_bundle_items) AS bundle_items;

SELECT rel.relname AS table_name, con.conname AS constraint_name,
       pg_get_constraintdef(con.oid) AS definition
FROM pg_constraint AS con
JOIN pg_class AS rel ON rel.oid = con.conrelid
WHERE rel.relnamespace = 'lab'::regnamespace
  AND rel.relname IN ('nf_8_price_rules', 'nf_8_bundles', 'nf_8_products', 'nf_8_bundle_items')
ORDER BY table_name, constraint_name;

COMMIT;
