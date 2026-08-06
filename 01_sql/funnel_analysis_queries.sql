-- ============================================
-- 1. DATABASE & TABLE CREATION
-- ============================================
CREATE DATABASE ecomerce_funnel;

CREATE TABLE events (
    timestamp_mp BIGINT,
    visitorid INTEGER,
    event VARCHAR(20),
    itemid INTEGER,
    transactionid INTEGER
);

CREATE TABLE category_tree (
    categoryid INTEGER,
    parentid INTEGER
);

CREATE TABLE item_properties (
    timestamp_ms BIGINT,
    itemid INTEGER,
    property VARCHAR(50),
    value TEXT
);

-- Data imported via DBeaver Import Data (GUI), not COPY command

-- ============================================
-- 2. VERIFY IMPORT COUNTS
-- ============================================
SELECT COUNT(*) FROM events;
SELECT COUNT(*) FROM category_tree;
SELECT COUNT(*) FROM item_properties;

-- ============================================
-- 3. BASIC FUNNEL COUNTS
-- ============================================
SELECT event, COUNT(*) AS total_count
FROM events e
GROUP BY event
ORDER BY total_count DESC;

SELECT
    event,
    COUNT(DISTINCT visitorid) AS unique_visitor
FROM events e
GROUP BY event
ORDER BY unique_visitor DESC;

-- ============================================
-- 4. FUNNEL WITH CONVERSION & DROPOFF RATES
-- ============================================
WITH funnel AS (
    SELECT
        COUNT(DISTINCT visitorid) FILTER (WHERE event = 'view') AS viewers,
        COUNT(DISTINCT visitorid) FILTER (WHERE event = 'addtocart') AS add_to_cart,
        COUNT(DISTINCT visitorid) FILTER (WHERE event = 'transaction') AS purchasers
    FROM events
)
SELECT
    viewers, add_to_cart, purchasers,
    ROUND(add_to_cart::numeric / viewers * 100, 2) AS view_to_cart_rate,
    ROUND(purchasers::numeric / add_to_cart * 100, 2) AS cart_to_purchase_rate,
    ROUND(purchasers::numeric / viewers * 100, 2) AS overall_conversion_rate,
    ROUND(100 - (add_to_cart::numeric / viewers * 100), 2) AS view_to_cart_dropoff,
    ROUND(100 - (purchasers::numeric / add_to_cart * 100), 2) AS cart_to_purchase_dropoff
FROM funnel;

SELECT 'View' AS stage, COUNT(DISTINCT visitorid) AS visitors
FROM events WHERE event = 'view'
UNION ALL
SELECT 'Add to Cart', COUNT(DISTINCT visitorid)
FROM events WHERE event = 'addtocart'
UNION ALL
SELECT 'Purchase', COUNT(DISTINCT visitorid)
FROM events WHERE event = 'transaction';

-- ============================================
-- 5. CATEGORY SEGMENTATION
-- ============================================
CREATE TABLE item_category AS
SELECT DISTINCT ON (itemid)
    itemid,
    value AS categoryid
FROM item_properties
WHERE property = 'categoryid'
ORDER BY itemid, timestamp_ms DESC;

SELECT COUNT(*) FROM item_category;

SELECT
    ic.categoryid,
    COUNT(DISTINCT e.visitorid) FILTER (WHERE e.event = 'view') AS viewers,
    COUNT(DISTINCT e.visitorid) FILTER (WHERE e.event = 'addtocart') AS add_to_cart,
    COUNT(DISTINCT e.visitorid) FILTER (WHERE e.event = 'transaction') AS purchasers,
    ROUND(
        COUNT(DISTINCT e.visitorid) FILTER (WHERE e.event = 'transaction')::numeric
        / NULLIF(COUNT(DISTINCT e.visitorid) FILTER (WHERE e.event = 'view'), 0) * 100, 2
    ) AS overall_conversion_rate
FROM events e
JOIN item_category ic ON e.itemid = ic.itemid
GROUP BY ic.categoryid
ORDER BY viewers DESC
LIMIT 10;

SELECT
    ic.categoryid,
    COUNT(DISTINCT e.visitorid) FILTER (WHERE e.event = 'view') AS viewers,
    COUNT(DISTINCT e.visitorid) FILTER (WHERE e.event = 'transaction') AS purchasers,
    ROUND(
        COUNT(DISTINCT e.visitorid) FILTER (WHERE e.event = 'transaction')::numeric
        / NULLIF(COUNT(DISTINCT e.visitorid) FILTER (WHERE e.event = 'view'), 0) * 100, 2
    ) AS conversion_rate
FROM events e
JOIN item_category ic ON e.itemid = ic.itemid
GROUP BY ic.categoryid
HAVING COUNT(DISTINCT e.visitorid) FILTER (WHERE e.event = 'view') >= 500
ORDER BY conversion_rate DESC
LIMIT 10;
-- ============================================
-- 6. DEDUPLICATION & TIME-BASED ANALYSIS
-- ============================================
SELECT timestamp_mp, visitorid, event, itemid, transactionid, COUNT(*)
FROM events
GROUP BY timestamp_mp, visitorid, event, itemid, transactionid
HAVING COUNT(*) > 1;

CREATE TABLE events_clean AS
SELECT DISTINCT * FROM events;

SELECT COUNT(*) FROM events_clean;

ALTER TABLE events_clean ADD COLUMN event_datetime TIMESTAMP;
UPDATE events_clean SET event_datetime = TO_TIMESTAMP(timestamp_mp / 1000.0);

SELECT
    TO_CHAR(event_datetime, 'Day') AS day_of_week,
    COUNT(DISTINCT visitorid) FILTER (WHERE event = 'view') AS viewers,
    COUNT(DISTINCT visitorid) FILTER (WHERE event = 'addtocart') AS add_to_cart,
    COUNT(DISTINCT visitorid) FILTER (WHERE event = 'transaction') AS purchasers,
    ROUND(
        COUNT(DISTINCT visitorid) FILTER (WHERE event = 'transaction')::numeric
        / NULLIF(COUNT(DISTINCT visitorid) FILTER (WHERE event = 'view'), 0) * 100, 2
    ) AS conversion_rate
FROM events_clean
GROUP BY TO_CHAR(event_datetime, 'Day'), EXTRACT(DOW FROM event_datetime)
ORDER BY EXTRACT(DOW FROM event_datetime);

SELECT
    EXTRACT(HOUR FROM event_datetime) AS hour_of_day,
    COUNT(DISTINCT visitorid) FILTER (WHERE event = 'view') AS viewers,
    COUNT(DISTINCT visitorid) FILTER (WHERE event = 'transaction') AS purchasers,
    ROUND(
        COUNT(DISTINCT visitorid) FILTER (WHERE event = 'transaction')::numeric
        / NULLIF(COUNT(DISTINCT visitorid) FILTER (WHERE event = 'view'), 0) * 100, 2
    ) AS conversion_rate
FROM events_clean
GROUP BY EXTRACT(HOUR FROM event_datetime)
ORDER BY hour_of_day;

-- ============================================
-- 7. FINAL VIEW FOR POWER BI EXPORT
-- ============================================
CREATE VIEW funnel_by_category AS
SELECT
    ic.categoryid,
    e.event,
    e.visitorid,
    e.event_datetime
FROM events_clean e
JOIN item_category ic ON e.itemid = ic.itemid;

-- ============================================
-- 8. FINAL VERIFICATION
-- ============================================
SELECT COUNT(*) FROM events_clean;
SELECT COUNT(*) FROM item_category;
SELECT COUNT(*) FROM funnel_by_category;
