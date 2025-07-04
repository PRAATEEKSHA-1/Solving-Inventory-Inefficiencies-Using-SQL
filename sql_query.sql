-- 1. Stock Level Calculations across Stores and Warehouse
SELECT 
    s.store_id,
    s.region,
    s.product_id,
    SUM(i.inventory_level) AS total_stock_level
FROM 
    inventory_analysis_db.stores s
JOIN 
    inventory_analysis_db.inventory i ON s.inventory_id = i.inventory_id
GROUP BY 
    s.store_id,s.region, s.product_id
ORDER BY 
    total_stock_level DESC;


# 2. Low Inventory Detection Based on Reorder Point
-- First calculate reorder point per product using 3-day lead time
WITH reorder_point AS (
    SELECT 
        s.product_id,
        ROUND((AVG(i.units_sold) * 3) + STDDEV(i.units_sold), 2) AS reorder_point
    FROM 
        inventory_analysis_db.stores s
    JOIN 
        inventory_analysis_db.inventory i ON s.inventory_id = i.inventory_id
    GROUP BY 
        s.product_id
)

-- Show all products with inventory status
SELECT 
    s.store_id,
    s.product_id,
    i.inventory_level,
    r.reorder_point,
    CASE 
        WHEN i.inventory_level < r.reorder_point THEN 'Low Stock'
        ELSE 'Available'
    END AS status
FROM 
    inventory_analysis_db.stores s
JOIN 
    inventory_analysis_db.inventory i ON s.inventory_id = i.inventory_id
JOIN 
    reorder_point r ON s.product_id = r.product_id
ORDER BY 
    status ASC;


-- 3. Reorder Point Estimation Using Historical Trends
SELECT 
    s.store_id,
    s.product_id,
    ROUND((AVG(i.units_sold) * 3) + STDDEV(i.units_sold), 2) AS estimated_reorder_point
FROM 
    inventory_analysis_db.stores s
JOIN 
    inventory_analysis_db.inventory i ON s.inventory_id = i.inventory_id
GROUP BY 
    s.store_id, s.product_id
ORDER BY 
    estimated_reorder_point DESC;


-- 4. Inventory Turnover Analysis
SELECT 
    s.store_id,
    s.product_id,
    DATE_FORMAT(s.date, '%Y-%m') AS month,
    SUM(i.units_sold) AS total_units_sold,
    ROUND(AVG(i.inventory_level), 2) AS avg_inventory_level,
    ROUND(SUM(i.units_sold) / NULLIF(AVG(i.inventory_level), 0), 2) AS inventory_turnover
FROM 
    inventory_analysis_db.stores s
JOIN 
    inventory_analysis_db.inventory i ON s.inventory_id = i.inventory_id
GROUP BY 
    s.store_id, s.product_id, month
ORDER BY 
    inventory_turnover DESC;

    
-- 5. Summary Report with KPIs
-- 1. Stockout Rate
WITH reorder_point AS (
    SELECT 
        s.product_id,
        ef.season_id,
        ROUND(AVG(i.units_sold) * 3 + STDDEV(i.units_sold), 2) AS reorder_point
    FROM 
        inventory_analysis_db.stores s
    JOIN inventory_analysis_db.inventory i ON s.inventory_id = i.inventory_id
    JOIN inventory_analysis_db.external_factor ef ON s.inventory_id = ef.inventory_id
    GROUP BY 
        s.product_id, ef.season_id
),
stock_status AS (
    SELECT 
        s.store_id,
        s.product_id,
        sa.season,
        w.weather,
        i.inventory_level,
        rp.reorder_point,
        CASE 
            WHEN i.inventory_level < rp.reorder_point THEN 1
            ELSE 0
        END AS is_stockout
    FROM 
        inventory_analysis_db.stores s
    JOIN inventory_analysis_db.inventory i ON s.inventory_id = i.inventory_id
    JOIN inventory_analysis_db.external_factor ef ON s.inventory_id = ef.inventory_id
    JOIN inventory_analysis_db.seasonality sa ON ef.season_id = sa.season_id
    JOIN inventory_analysis_db.weather w ON ef.weather_id = w.weather_id
    JOIN reorder_point rp 
        ON s.product_id = rp.product_id 
        AND ef.season_id = rp.season_id
)
SELECT
    store_id,
    product_id,
    season,
    weather,
    COUNT(*) AS total_records,
    SUM(is_stockout) AS stockout_count,
    ROUND(SUM(is_stockout) * 100.0 / COUNT(*), 2) AS stockout_rate_percent
FROM 
    stock_status
GROUP BY 
    store_id, product_id, season, weather
ORDER BY 
    stockout_rate_percent asc;

--  2. Average Inventory Age
SELECT 
    s.store_id,
    s.product_id,
    ROUND(AVG(DATEDIFF(CURDATE(), s.date)), 2) AS avg_inventory_age_days
FROM 
    inventory_analysis_db.stores s
JOIN 
    inventory_analysis_db.inventory i ON s.inventory_id = i.inventory_id
WHERE 
    i.inventory_level > 0
GROUP BY 
    s.store_id, s.product_id
ORDER BY 
    avg_inventory_age_days DESC;

-- 3. Average Stock Level
SELECT 
    s.store_id,
    s.product_id,
    sa.season AS season,
    w.weather AS weather,
    ROUND(AVG(i.inventory_level), 2) AS avg_stock_level
FROM 
    inventory_analysis_db.stores s
JOIN 
    inventory_analysis_db.inventory i ON s.inventory_id = i.inventory_id
JOIN 
    inventory_analysis_db.external_factor ef ON s.inventory_id = ef.inventory_id
JOIN 
    inventory_analysis_db.seasonality sa ON ef.season_id = sa.season_id
JOIN 
    inventory_analysis_db.weather w ON ef.weather_id = w.weather_id
GROUP BY 
    s.store_id, s.product_id, sa.season, w.weather;

-- Analytical outputs
-- Identify fast-selling vs slow-moving products
SELECT
	c.category,
    s.product_id,
    ROUND(SUM(i.units_sold) / COUNT(DISTINCT s.date), 2) AS avg_daily_units_sold,
    CASE
        WHEN (SUM(i.units_sold) / COUNT(DISTINCT s.date)) >= 
             (SELECT ROUND(AVG(daily_avg),2)
              FROM (
                  SELECT 
                      SUM(i2.units_sold)/COUNT(DISTINCT s2.date) AS daily_avg
                  FROM 
                      inventory_analysis_db.stores s2
                  JOIN 
                      inventory_analysis_db.inventory i2 
                      ON s2.inventory_id = i2.inventory_id
                  GROUP BY 
                      s2.product_id
              ) sub) THEN 'Fast-Selling'
        ELSE 'Slow-Moving'
    END AS product_type
FROM 
    inventory_analysis_db.stores s
JOIN 
    inventory_analysis_db.inventory i 
    ON s.inventory_id = i.inventory_id
JOIN
    inventory_analysis_db.category c
    ON s.category_id = c.category_id
GROUP BY 
    s.product_id, c.category;

-- Forecast Demand Trends by Season
SELECT 
    se.season,
    s.product_id,
    ROUND(AVG(i.demand_forecast), 2) AS avg_seasonal_demand
FROM 
    stores s
JOIN 
    inventory i ON s.inventory_id = i.inventory_id
JOIN 
    external_factor ef ON ef.inventory_id = i.inventory_id
JOIN 
    seasonality se ON ef.season_id = se.season_id
GROUP BY 
    se.season, s.product_id
ORDER BY 
    se.season, avg_seasonal_demand DESC;

-- overstock days and stockout days
WITH product_stats AS (
    SELECT 
        s.product_id,
        ROUND((AVG(i.units_sold) * 3) + STDDEV(i.units_sold), 2) AS reorder_point,
        ROUND(AVG(i.inventory_level), 2) AS avg_inventory_level
    FROM 
        inventory_analysis_db.stores s
    JOIN 
        inventory_analysis_db.inventory i 
        ON s.inventory_id = i.inventory_id
    GROUP BY 
        s.product_id
),

multiplier_calc AS (
    SELECT
        product_id,
        reorder_point,
        avg_inventory_level,
        ROUND(avg_inventory_level / reorder_point, 2) AS overstock_multiplier
    FROM
        product_stats
),

stock_status AS (
    SELECT 
        s.store_id,
        s.product_id,
        s.date,
        i.inventory_level,
        mc.reorder_point,
        mc.overstock_multiplier,
        CASE 
            WHEN i.inventory_level < mc.reorder_point THEN 1
            ELSE 0
        END AS is_stockout,
        CASE
            WHEN i.inventory_level > mc.reorder_point * mc.overstock_multiplier THEN 1
            ELSE 0
        END AS is_overstock
    FROM 
        inventory_analysis_db.stores s
    JOIN 
        inventory_analysis_db.inventory i 
        ON s.inventory_id = i.inventory_id
    JOIN 
        multiplier_calc mc 
        ON s.product_id = mc.product_id
)

SELECT
    store_id,
    product_id,
    COUNT(DISTINCT CASE WHEN is_stockout = 1 THEN date END) AS stockout_days,
    COUNT(DISTINCT CASE WHEN is_overstock = 1 THEN date END) AS overstock_days
FROM
    stock_status
GROUP BY 
    store_id, product_id
ORDER BY 
    stockout_days DESC, overstock_days DESC;

-- Calculate forecasted demand vs actual units sold by season using schema
SELECT
    sa.season,
    s.product_id,
    c.category,
    ROUND(SUM(i.demand_forecast), 2) AS total_forecasted_demand,
    SUM(i.units_sold) AS total_actual_demand
FROM 
    inventory_analysis_db.stores s
JOIN 
    inventory_analysis_db.inventory i 
    ON s.inventory_id = i.inventory_id
JOIN 
    inventory_analysis_db.external_factor ef 
    ON s.inventory_id = ef.inventory_id
JOIN 
    inventory_analysis_db.seasonality sa 
    ON ef.season_id = sa.season_id
JOIN 
    inventory_analysis_db.category c 
    ON s.category_id = c.category_id
GROUP BY 
    sa.season, s.product_id, c.category
ORDER BY 
    sa.season, total_forecasted_demand DESC;
