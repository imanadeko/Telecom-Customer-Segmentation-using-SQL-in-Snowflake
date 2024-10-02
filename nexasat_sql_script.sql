-- Exploratory Data Analysis
-- Create another table for existing customers
CREATE OR REPLACE TABLE existing_customers AS
SELECT *
FROM nexa_sat
WHERE churn = 0;

-- Churn count by plan_type and plan_level
SELECT plan_type,
        plan_level,
        SUM(churn) AS churn_count
FROM nexa_sat
GROUP BY ALL
ORDER BY churn_count DESC;

-- Average Tenure by plan_type
SELECT plan_type,
        ROUND(AVG(tenure_months)) AS avg_tenure_months
FROM nexa_sat
GROUP BY ALL
ORDER BY avg_tenure_months;

--Average tenure by plan_level
SELECT plan_level,
        ROUND(AVG(tenure_months)) AS avg_tenure_months
FROM nexa_sat
GROUP BY ALL
ORDER BY avg_tenure_months;

-- Total existing customers and total monthly revenue
SELECT COUNT(customer_id) AS existing_customers,
        ROUND(SUM(monthly_bill_amount)) AS monthly_revenue
FROM existing_customers;

-- Number of existing customers by plan_type and plan_level
SELECT plan_type,
        plan_level,
        COUNT(customer_id) AS customer_count
FROM existing_customers
GROUP BY ALL;


-- Total revenue by plan_type and plan_level
SELECT plan_type, plan_level, ROUND(SUM(monthly_bill_amount)) AS monthly_revenue
FROM existing_customers
GROUP BY ALL
ORDER BY monthly_revenue;

-- Average Revenue per User (ARPU) for existing customers
SELECT ROUND(AVG(monthly_bill_amount)) AS ARPU
FROM existing_customers;

-- Feature engineering

-- Create and update clv: monthly_bill_amount * tenure_months
ALTER TABLE existing_customers
ADD COLUMN clv NUMBER(10, 2);

UPDATE existing_customers
SET clv = monthly_bill_amount * tenure_months;

-- View customers and their clv
SELECT customer_id, clv
FROM existing_customers
LIMIT 5;

/*
CLV scores is calculated using a weighted approach
monthly_bill = 40%
tenure = 30%
call_duration = 10%
data_usage = 10%
premium customer status = 10%
*/
-- Create and update clv_score
ALTER TABLE existing_customers
ADD COLUMN clv_score NUMBER(10, 2);

UPDATE existing_customers
SET clv_score = 
        (0.4 * monthly_bill_amount) +
        (0.3 * tenure_months) +
        (0.1 * call_duration) +
        (0.1 * data_usage) +
        (0.1 * CASE WHEN plan_level = 'Premium'
                THEN 1
                ELSE 0
                END);

-- View customers and their clv and clv scores
SELECT customer_id,
        clv,
        clv_score
FROM existing_customers
LIMIT 5;

/*
Segmentation

Customers are segmented by clv_scores based on the following conditions
High Value: CLV score > 85th percentile
Moderate Value: CLV score >= 50th percentile
Low Value: CLV score >= 25th percentile
Churn Risk: CLV score < 25th percentile
*/

-- Create and update clv_segment
ALTER TABLE existing_customers
ADD COLUMN clv_segment VARCHAR(20);

UPDATE existing_customers
SET clv_segment =
    CASE WHEN clv_score > (
                SELECT PERCENTILE_CONT(0.85)
                        WITHIN GROUP (ORDER BY clv_score)
                FROM existing_customers
                        )
            THEN 'High Value'
        WHEN clv_score >= (
                SELECT PERCENTILE_CONT(0.5)
                        WITHIN GROUP (ORDER BY clv_score)
                FROM existing_customers
                        )
            THEN 'Moderate Value'
        WHEN clv_score >= (
                SELECT PERCENTILE_CONT(0.25)
                        WITHIN GROUP (ORDER BY clv_score)
                FROM existing_customers
                        )
            THEN 'Low Value'
        ELSE 'Churn Risk'
    END;

-- View customers and their clv segments
SELECT customer_id,
        clv_segment
FROM existing_customers
LIMIT 5;

-- Segment Profiling

-- Percentage of customers in each segment
SELECT clv_segment,
        ROUND(
            COUNT(customer_id) / (
            SELECT COUNT(*)
            FROM existing_customers),
                2
            ) AS percentage
FROM existing_customers
GROUP BY clv_segment
ORDER BY percentage;


-- Avg monthly bill and tenure by segment
SELECT clv_segment,
        ROUND(AVG(monthly_bill_amount)) AS avg_monthly_bill,
        ROUND(AVG(tenure_months)) AS avg_tenure
FROM existing_customers
GROUP BY clv_segment
ORDER BY avg_monthly_bill;

-- Tech support and multiple lines percentage by segment
SELECT clv_segment,
        ROUND(AVG(
                CASE WHEN tech_support = 'Yes'
                        THEN 1
                        ELSE 0 END), 2) AS perc_tech_support,
        ROUND(AVG(
                CASE WHEN multiple_lines = 'Yes'
                        THEN 1
                        ELSE 0 END), 2) AS perc_multiple_lines
FROM existing_customers
GROUP BY clv_segment
ORDER BY perc_tech_support;


-- Identifying Opportunities for Cross-selling and Up-selling

-- Cross-selling tech support to senior citizens
SELECT customer_id
FROM existing_customers
WHERE senior_citizen = 1              -- Senior citizens
    AND dependents = 'No'             -- Without dependents
    AND tech_support = 'No';          -- Don't have tech support


-- Cross-selling multiple lines to customers with partners and dependents
SELECT customer_id
FROM existing_customers
WHERE multiple_lines = 'No'            -- Don't have multiple lines
    AND(
        dependents = 'Yes' OR          -- Have dependents
        partner = 'Yes'                -- Have a partner
        );

-- Upselling discounted premium plans to basic customers
SELECT customer_id
FROM existing_customers
WHERE plan_level = 'Basic'
    AND(
        clv_segment = 'Low Value' OR
        clv_segment = 'Churn Risk'
    );


-- Upselling premium plans to high value basic customers
SELECT customer_id
FROM existing_customers
WHERE plan_level = 'Basic'
    AND clv_segment = 'High Value';


-- Percentage of customers identified for cross-selling and upselling opportunities
SELECT ROUND(
        COUNT(customer_id) / (
            SELECT COUNT(customer_id)
            FROM existing_customers
                ),
                2
            ) AS perc_potential_customers
FROM(
    SELECT customer_id
    FROM existing_customers
    WHERE senior_citizen = 1             
        AND dependents = 'No'  
        AND tech_support = 'No'
    UNION
    SELECT customer_id
    FROM existing_customers
    WHERE multiple_lines = 'No'  
        AND(
            dependents = 'Yes' OR       
            partner = 'Yes'
            )
    UNION
    SELECT customer_id
    FROM existing_customers
    WHERE plan_level = 'Basic'
        AND(
            clv_segment = 'Low Value' OR
            clv_segment = 'Churn Risk'
        )   
    UNION
    SELECT customer_id
    FROM existing_customers
    WHERE plan_level = 'Basic'
        AND clv_segment = 'High Value'
    );
