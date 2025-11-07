sudo -u postgres createdb metabase_sample
sudo -u postgres psql -d metabase_sample <<'SQL'
-- Limpa objetos se rodar mais de uma vez
DROP TABLE IF EXISTS order_events;
DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS customers;

-- =========================
-- Tabela de clientes
-- =========================
CREATE TABLE customers (
    id              serial PRIMARY KEY,
    full_name       text NOT NULL,
    email           text NOT NULL,
    city            text,
    state           text,
    created_at      timestamp NOT NULL
);

INSERT INTO customers (full_name, email, city, state, created_at)
SELECT
    'Cliente ' || gs,
    'cliente' || gs || '@exemplo.com',
    (ARRAY['São Paulo','Rio de Janeiro','Fortaleza','Salvador','Belo Horizonte','Curitiba','Porto Alegre','Recife'])[floor(random()*8)::int + 1],
    (ARRAY['SP','RJ','CE','BA','MG','PR','RS','PE'])[floor(random()*8)::int + 1],
    now() - (random()*365 || ' days')::interval
FROM generate_series(1, 500) AS gs;

-- =========================
-- Tabela de produtos
-- =========================
CREATE TABLE products (
    id          serial PRIMARY KEY,
    name        text NOT NULL,
    category    text NOT NULL,
    price       numeric(10,2) NOT NULL
);

INSERT INTO products (name, category, price)
SELECT
    'Produto ' || gs,
    (ARRAY['Eletrônicos','Casa','Roupas','Mercado','Beleza','Livros'])[floor(random()*6)::int + 1],
    round((random()*900 + 10)::numeric, 2)
FROM generate_series(1, 80) AS gs;

-- =========================
-- Tabela de pedidos
-- =========================
CREATE TABLE orders (
    id              bigserial PRIMARY KEY,
    customer_id     int NOT NULL REFERENCES customers(id),
    created_at      timestamp NOT NULL,
    status          text NOT NULL,
    payment_method  text NOT NULL,
    total_amount    numeric(12,2) NOT NULL
);

INSERT INTO orders (customer_id, created_at, status, payment_method, total_amount)
SELECT
    (SELECT id FROM customers ORDER BY random() LIMIT 1),
    now() - (random()*90 || ' days')::interval,
    (ARRAY['paid','pending','canceled'])[floor(random()*3)::int + 1],
    (ARRAY['credit_card','pix','boleto','debit_card'])[floor(random()*4)::int + 1],
    0
FROM generate_series(1, 5000);

-- =========================
-- Itens do pedido
-- =========================
CREATE TABLE order_items (
    id          bigserial PRIMARY KEY,
    order_id    bigint NOT NULL REFERENCES orders(id),
    product_id  int NOT NULL REFERENCES products(id),
    quantity    int NOT NULL,
    unit_price  numeric(10,2) NOT NULL,
    total_price numeric(12,2) NOT NULL
);

INSERT INTO order_items (order_id, product_id, quantity, unit_price, total_price)
SELECT
    o.id,
    p.id,
    q.qty,
    p.price,
    p.price * q.qty
FROM orders o
CROSS JOIN LATERAL (
    SELECT (1 + floor(random()*5)::int) AS items_count
) c
CROSS JOIN LATERAL (
    SELECT id, price
    FROM products
    ORDER BY random()
    LIMIT c.items_count
) p
CROSS JOIN LATERAL (
    SELECT (1 + floor(random()*4)::int) AS qty
) q;

-- Atualiza total do pedido com base nos itens
UPDATE orders o
SET total_amount = sub.sum_total
FROM (
    SELECT order_id, sum(total_price) AS sum_total
    FROM order_items
    GROUP BY order_id
) sub
WHERE sub.order_id = o.id;

-- =========================
-- Eventos do pedido (funil)
-- =========================
CREATE TABLE order_events (
    id          bigserial PRIMARY KEY,
    order_id    bigint NOT NULL REFERENCES orders(id),
    event_type  text NOT NULL,
    event_time  timestamp NOT NULL
);

INSERT INTO order_events (order_id, event_type, event_time)
SELECT
    o.id,
    e.event_type,
    o.created_at + (e.offset_minutes || ' minutes')::interval
FROM orders o
CROSS JOIN LATERAL (
    VALUES
        ('cart_view', -5),
        ('checkout_start', -2),
        ('payment_attempt', 0),
        ('order_created', 1)
) e(event_type, offset_minutes)
WHERE random() < 0.8;

-- =========================
-- Índices básicos
-- =========================
CREATE INDEX idx_orders_created_at ON orders(created_at);
CREATE INDEX idx_orders_customer_id ON orders(customer_id);
CREATE INDEX idx_items_order_id ON order_items(order_id);
CREATE INDEX idx_events_order_id ON order_events(order_id);

SQL
