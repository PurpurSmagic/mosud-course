# Результаты практической работы № 1

[Описание работы](README.md) · [Скрипт загрузки](schema.sql) · [Скрипт проверок](check.sql)

Запросы из `check.sql` выполнены на базе `olist` в PostgreSQL 17.5. Под каждым запросом приведён его фактический вывод.

## Сверка числа строк

```sql
WITH row_counts (table_name, actual_rows, expected_rows) AS (
    SELECT 'customers', count(*), 99441 FROM olist.customers
    UNION ALL
    SELECT 'geolocation', count(*), 1000163 FROM olist.geolocation
    UNION ALL
    SELECT 'orders', count(*), 99441 FROM olist.orders
    UNION ALL
    SELECT 'order_items', count(*), 112650 FROM olist.order_items
    UNION ALL
    SELECT 'order_payments', count(*), 103886 FROM olist.order_payments
    UNION ALL
    SELECT 'order_reviews', count(*), 99224 FROM olist.order_reviews
    UNION ALL
    SELECT 'products', count(*), 32951 FROM olist.products
    UNION ALL
    SELECT 'sellers', count(*), 3095 FROM olist.sellers
    UNION ALL
    SELECT 'product_category_name_translation', count(*), 71
    FROM olist.product_category_name_translation
)
SELECT table_name, actual_rows, expected_rows, actual_rows - expected_rows AS difference
FROM row_counts
ORDER BY table_name;
```

| table_name | actual_rows | expected_rows | difference |
| :--- | ---: | ---: | ---: |
| customers | 99441 | 99441 | 0 |
| geolocation | 1000163 | 1000163 | 0 |
| order_items | 112650 | 112650 | 0 |
| order_payments | 103886 | 103886 | 0 |
| order_reviews | 99224 | 99224 | 0 |
| orders | 99441 | 99441 | 0 |
| product_category_name_translation | 71 | 71 | 0 |
| products | 32951 | 32951 | 0 |
| sellers | 3095 | 3095 | 0 |

## NULL в ключевых полях

```sql
WITH key_nulls (table_name, column_name, null_count) AS (
    SELECT 'customers', 'customer_id', count(*) - count(customer_id) FROM olist.customers
    UNION ALL
    SELECT 'orders', 'order_id', count(*) - count(order_id) FROM olist.orders
    UNION ALL
    SELECT 'orders', 'customer_id', count(*) - count(customer_id) FROM olist.orders
    UNION ALL
    SELECT 'order_items', 'order_id', count(*) - count(order_id) FROM olist.order_items
    UNION ALL
    SELECT 'order_items', 'order_item_id', count(*) - count(order_item_id) FROM olist.order_items
    UNION ALL
    SELECT 'order_items', 'product_id', count(*) - count(product_id) FROM olist.order_items
    UNION ALL
    SELECT 'order_items', 'seller_id', count(*) - count(seller_id) FROM olist.order_items
    UNION ALL
    SELECT 'order_payments', 'order_id', count(*) - count(order_id) FROM olist.order_payments
    UNION ALL
    SELECT 'order_payments', 'payment_sequential', count(*) - count(payment_sequential)
    FROM olist.order_payments
    UNION ALL
    SELECT 'order_reviews', 'review_id', count(*) - count(review_id) FROM olist.order_reviews
    UNION ALL
    SELECT 'order_reviews', 'order_id', count(*) - count(order_id) FROM olist.order_reviews
    UNION ALL
    SELECT 'products', 'product_id', count(*) - count(product_id) FROM olist.products
    UNION ALL
    SELECT 'sellers', 'seller_id', count(*) - count(seller_id) FROM olist.sellers
    UNION ALL
    SELECT 'product_category_name_translation', 'product_category_name',
           count(*) - count(product_category_name)
    FROM olist.product_category_name_translation
)
SELECT table_name, column_name, null_count
FROM key_nulls
ORDER BY table_name, column_name;
```

| table_name | column_name | null_count |
| :--- | :--- | ---: |
| customers | customer_id | 0 |
| order_items | order_id | 0 |
| order_items | order_item_id | 0 |
| order_items | product_id | 0 |
| order_items | seller_id | 0 |
| order_payments | order_id | 0 |
| order_payments | payment_sequential | 0 |
| order_reviews | order_id | 0 |
| order_reviews | review_id | 0 |
| orders | customer_id | 0 |
| orders | order_id | 0 |
| product_category_name_translation | product_category_name | 0 |
| products | product_id | 0 |
| sellers | seller_id | 0 |

## Ссылки без родительских записей

```sql
WITH orphan_counts (foreign_key, orphan_count) AS (
    SELECT 'fk_orders_customer', count(*)
    FROM olist.orders AS orders
    LEFT JOIN olist.customers AS customers USING (customer_id)
    WHERE orders.customer_id IS NOT NULL AND customers.customer_id IS NULL
    UNION ALL
    SELECT 'fk_items_order', count(*)
    FROM olist.order_items AS items
    LEFT JOIN olist.orders AS orders USING (order_id)
    WHERE items.order_id IS NOT NULL AND orders.order_id IS NULL
    UNION ALL
    SELECT 'fk_items_product', count(*)
    FROM olist.order_items AS items
    LEFT JOIN olist.products AS products USING (product_id)
    WHERE items.product_id IS NOT NULL AND products.product_id IS NULL
    UNION ALL
    SELECT 'fk_items_seller', count(*)
    FROM olist.order_items AS items
    LEFT JOIN olist.sellers AS sellers USING (seller_id)
    WHERE items.seller_id IS NOT NULL AND sellers.seller_id IS NULL
    UNION ALL
    SELECT 'fk_payments_order', count(*)
    FROM olist.order_payments AS payments
    LEFT JOIN olist.orders AS orders USING (order_id)
    WHERE payments.order_id IS NOT NULL AND orders.order_id IS NULL
    UNION ALL
    SELECT 'fk_reviews_order', count(*)
    FROM olist.order_reviews AS reviews
    LEFT JOIN olist.orders AS orders USING (order_id)
    WHERE reviews.order_id IS NOT NULL AND orders.order_id IS NULL
)
SELECT foreign_key, orphan_count
FROM orphan_counts
ORDER BY foreign_key;
```

| foreign_key | orphan_count |
| :--- | ---: |
| fk_items_order | 0 |
| fk_items_product | 0 |
| fk_items_seller | 0 |
| fk_orders_customer | 0 |
| fk_payments_order | 0 |
| fk_reviews_order | 0 |
