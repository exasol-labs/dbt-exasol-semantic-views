{{ config(
    materialized='exasol_semantic_model',
    meta={'exasol_semantic_views': {
        'published_schema': 'ESV_IT_SALES',
        'description': 'Integration-test sales model',
    }}
) }}

-- The graph: entities over dbt models, their keys, the object, the join.
EXECUTE SCRIPT SEMANTIC_ADMIN.ADD_ENTITY('esv_it_sales', 'customer',
  {{ exasol_semantic_views.relation_args(ref('it_customers_silver')) }},
  'c', 'c.CUSTOMER_KEY', 'One row per customer', 'Customers');
EXECUTE SCRIPT SEMANTIC_ADMIN.ADD_UNIQUE_KEY('esv_it_sales', 'customer', 'customer_pk', 'PRIMARY',
  'Customer identity', 'NATIVE');
EXECUTE SCRIPT SEMANTIC_ADMIN.ADD_UNIQUE_KEY_COLUMN('esv_it_sales', 'customer', 'customer_pk',
  'CUSTOMER_KEY', NULL, 1);

EXECUTE SCRIPT SEMANTIC_ADMIN.ADD_ENTITY('esv_it_sales', 'order',
  {{ exasol_semantic_views.relation_args(ref('it_orders_silver')) }},
  'o', 'o.ORDER_KEY', 'One row per order', 'Orders');
EXECUTE SCRIPT SEMANTIC_ADMIN.ADD_UNIQUE_KEY('esv_it_sales', 'order', 'order_pk', 'PRIMARY',
  'Order identity', 'NATIVE');
EXECUTE SCRIPT SEMANTIC_ADMIN.ADD_UNIQUE_KEY_COLUMN('esv_it_sales', 'order', 'order_pk',
  'ORDER_KEY', NULL, 1);

EXECUTE SCRIPT SEMANTIC_ADMIN.ADD_SEMANTIC_OBJECT('esv_it_sales', 'ORDERS', 'order',
  'Orders and their customers');
EXECUTE SCRIPT SEMANTIC_ADMIN.ADD_RELATIONSHIP('esv_it_sales', 'order_to_customer', 'order',
  'customer', 'o.CUSTOMER_KEY = c.CUSTOMER_KEY', 'MANY_TO_ONE', 'LEFT', NULL);
EXECUTE SCRIPT SEMANTIC_ADMIN.ADD_RELATIONSHIP_KEY_MAPPING('esv_it_sales', 'order_to_customer',
  'CUSTOMER_KEY', NULL, 'CUSTOMER_KEY', NULL, 1);

/* The interior of the object, in Semantic DDL; a semicolon inside a
   string -- 'a;b' -- does not end the statement. */
ALTER SEMANTIC VIEW esv_it_sales.ORDERS
REPLACE DIMENSIONS (
  DIMENSION customer_region ON ENTITY customer AS c.REGION
    RETURNS VARCHAR(20) DISPLAY 'Region' COMMENT 'Region; of the customer' PUBLIC CERTIFIED,
  DIMENSION order_status ON ENTITY "order" AS o.ORDER_STATUS
    RETURNS VARCHAR(20) DISPLAY 'Status' COMMENT 'Lifecycle status' PUBLIC CERTIFIED
)
REPLACE FACTS (
  FACT net_amount ON ENTITY "order" AS o.NET_AMOUNT
    RETURNS DECIMAL(18,2) ADDITIVE DISPLAY 'Net Amount' COMMENT 'Net order value' PUBLIC CERTIFIED
)
REPLACE METRICS (
  METRIC total_revenue AS SUM(net_amount) ON ENTITY "order"
    RETURNS DECIMAL(18,2) DISPLAY 'Total Revenue' COMMENT 'Net value of all orders'
    ADDITIVE PUBLIC CERTIFIED,
  METRIC delivered_revenue AS SUM(net_amount) ON ENTITY "order"
    FILTER (WHERE order_status = 'delivered')
    RETURNS DECIMAL(18,2) DISPLAY 'Delivered Revenue' COMMENT 'Net value of delivered orders'
    ADDITIVE PUBLIC CERTIFIED,
  METRIC order_count AS COUNT(net_amount) ON ENTITY "order"
    RETURNS DECIMAL(18,0) DISPLAY 'Orders' COMMENT 'Number of orders' ADDITIVE PUBLIC CERTIFIED
);
