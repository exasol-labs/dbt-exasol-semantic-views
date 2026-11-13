-- The governed answers equal the same numbers computed by hand from the seeds,
-- at grains coarser than the adopted views. Re-adding the views' rows would
-- not: customer 1 has orders in two statuses, so North's distinct customers
-- are not the sum over its statuses, and the overall average order is not the
-- average of the regions' averages.
WITH expected AS (
  SELECT c.region,
         SUM(o.net_amount) AS total_revenue,
         COUNT(o.net_amount) AS order_count,
         COUNT(DISTINCT o.customer_key) AS customers,
         SUM(CASE WHEN o.order_status = 'delivered' THEN o.net_amount END) AS delivered_revenue
  FROM {{ ref('it_orders') }} o
  JOIN {{ ref('it_customers') }} c ON c.customer_key = o.customer_key
  GROUP BY c.region
), overall AS (
  SELECT AVG(net_amount) AS avg_order_value, MAX(net_amount) AS largest_order
  FROM {{ ref('it_orders') }}
)
SELECT e.region AS failing
FROM expected e
LEFT JOIN {{ ref('it_revenue_by_region') }} r ON r.customer_region = e.region
LEFT JOIN {{ ref('it_delivered_by_region') }} d ON d.customer_region = e.region
WHERE r.total_revenue IS NULL OR r.total_revenue <> e.total_revenue
   OR r.order_count <> e.order_count OR r.customers <> e.customers
   OR d.delivered_revenue IS NULL OR d.delivered_revenue <> e.delivered_revenue
UNION ALL
SELECT 'overall'
FROM overall o, {{ ref('it_order_size_overall') }} g
WHERE ROUND(g.avg_order_value, 6) <> ROUND(o.avg_order_value, 6)
   OR g.largest_order <> o.largest_order
