USE tele_com;
-- check duplicates
SELECT CustomerID, Gender, SeniorCitizen, Has_Partner, Has_Dependents, 
		TenureMonths, Has_PhoneService, Has_MultipleLines, InternetServiceType, Has_OnlineSecurity,
        Has_OnlineBackup, Has_DeviceProtection, Has_TechSupport, Has_StreamingTV, Has_StreamingMovies,
        ContractType, PaperlessBilling, PaymentMethodType, MonthlyCharges, TotalCharges, Churned
FROM telecom_churn
GROUP BY CustomerID, Gender, SeniorCitizen, Has_Partner, Has_Dependents, 
		TenureMonths, Has_PhoneService, Has_MultipleLines, InternetServiceType, Has_OnlineSecurity,
        Has_OnlineBackup, Has_DeviceProtection, Has_TechSupport, Has_StreamingTV, Has_StreamingMovies,
        ContractType, PaperlessBilling, PaymentMethodType, MonthlyCharges, TotalCharges, Churned
HAVING COUNT(*) > 1;

-- CHECK FOR NULL VALUES
SELECT *
FROM telecom_churn
WHERE CustomerID IS NULL
OR  Gender IS NULL
OR SeniorCitizen IS NULL
OR Has_Partner IS NULL
OR Has_Dependents IS NULL 
OR TenureMonths IS NULL
OR Has_PhoneService IS NULL
OR Has_MultipleLines IS NULL
OR InternetServiceType IS NULL
OR Has_OnlineSecurity IS NULL
OR Has_OnlineBackup IS NULL
OR Has_DeviceProtection IS NULL
OR Has_TechSupport IS NULL
OR  Has_StreamingTV IS NULL
OR Has_StreamingMovies IS NULL
OR	ContractType IS NULL
OR PaperlessBilling IS NULL
OR PaymentMethodType IS NULL
OR MonthlyCharges IS NULL
OR TotalCharges IS NULL
OR Churned IS NULL;

-- exploratory data analysis
-- total users
SELECT COUNT(CustomerID)
FROM telecom_churn;
-- current users
SELECT COUNT(CustomerID) AS current_users
FROM telecom_churn
WHERE Churned = 'No';
-- total revenue 
SELECT ROUND(SUM(TotalCharges), 2) AS total_revenue
FROM telecom_churn;
-- revenue by internet service type
SELECT InternetServiceType, ROUND(SUM(TotalCharges), 2) AS revenue
FROM telecom_churn
GROUP BY 1
ORDER BY 2;
-- revenue by internet service type and contract type
SELECT 
InternetServiceType,
ContractType,
COUNT(*) AS total_customers,
SUM(Churned) AS churn_count
FROM telecom_churn
GROUP BY 1, 2
ORDER BY 1;
-- average tenure by internet service type
SELECT InternetServiceType, ROUND(AVG(TenureMonths), 2)
FROM telecom_churn
GROUP BY 1;
-- MARKETING SEGMENTS
CREATE TABLE existing_users
AS 
SELECT *
FROM telecom_churn
WHERE Churned = 0;
-- view table
SELECT *
FROM existing_users;
-- arpu
SELECT ROUND(AVG(MonthlyCharges), 2) AS arpu
FROM existing_users;
-- calculate the clv and add column
ALTER TABLE existing_users
ADD COLUMN clv FLOAT;
SET SQL_SAFE_UPDATES = 0;
UPDATE existing_users
SET clv = MonthlyCharges * TenureMonths;
-- view column
SELECT CustomerID, clv
FROM existing_users
GROUP BY 1, 2;
-- clv segments
ALTER TABLE existing_users
ADD COLUMN clv_score NUMERIC(10, 2);
UPDATE existing_users
SET clv_score = 
				(0.4 * MonthlyCharges) +
                (0.3 * TenureMonths) +
                (0.1 * CASE WHEN Has_StreamingTV = 'Yes' THEN 1 ELSE 0 END) +
                (0.1 *  CASE WHEN Has_StreamingMovies = 'Yes' THEN 1 ELSE 0 END) +
                (0.1 * CASE WHEN InternetServiceType = 'Fiber optic'
                THEN 1 ELSE 0 END);
-- VIEW COLUMN
SELECT CustomerID, clv_score
FROM existing_users;
-- add clv segment
ALTER TABLE existing_users
ADD COLUMN clv_segments VARCHAR(2000);
UPDATE existing_users
SET clv_segments = CASE WHEN clv_score > (SELECT AVG(clv_score)
								FROM (SELECT clv_score, NTILE(100) OVER (ORDER BY clv_score) AS percentile
                                FROM existing_users) AS subquery
                                WHERE percentile = 85)
                                THEN 'HIGH'
		 WHEN clv_score >=  (SELECT AVG(clv_score)
								FROM (SELECT clv_score, NTILE(100) OVER (ORDER BY clv_score) AS percentile
                                FROM existing_users) AS subquery
                                WHERE percentile = 50)
                                THEN 'MODERATE VALUE'
		WHEN clv_score >= 	(SELECT AVG(clv_score)
								FROM (SELECT clv_score, NTILE(100) OVER (ORDER BY clv_score) AS percentile
                                FROM existing_users) AS subquery
                                WHERE percentile = 25)
                                THEN 'LOW'
		ELSE 'churn risk'
        END;
-- view segments
SELECT CustomerID, clv, clv_score, clv_segments
FROM existing_users; 
-- analyzing the segments
-- avg bill and tenure per segments
SELECT clv_segments,
		ROUND(AVG(MonthlyCharges), 2) AS avg_monthly_charges,
		ROUND(AVG(TenureMonths), 2) AS avg_tenure
FROM existing_users
GROUP BY 1;
-- churn risk of users based on their payment method
SELECT clv_segments,
PaymentMethodType,
COUNT(CustomerID)
FROM existing_users
GROUP BY 1, 2;
-- count of tech support, mulitiple lines...... across each segments
SELECT clv_segments,
	ROUND(AVG(CASE WHEN Has_TechSupport = 'Yes' THEN 1 ELSE 0 END), 2) AS tech_support_pct,
    ROUND(AVG(CASE WHEN Has_MultipleLines = 'Yes' THEN 1 ELSE 0 END), 2) AS multiple_lines_pct,
    ROUND(AVG(CASE WHEN Has_OnlineBackup = 'Yes' THEN 1 ELSE 0 END), 2) AS backup_pct,
    ROUND(AVG(CASE WHEN Has_OnlineSecurity = 'Yes' THEN 1 ELSE 0 END), 2) AS onlinesec_pct,
    ROUND(AVG(CASE WHEN Has_DeviceProtection = 'Yes' THEN 1 ELSE 0 END), 2) AS device_protection,
    ROUND(AVG(CASE WHEN Has_PhoneService = 'Yes' THEN 1 ELSE 0 END), 2) AS phoneService_pct
FROM existing_users
GROUP BY 1;
-- revenue per segments
SELECT clv_segments,
 COUNT(CustomerID),
 SUM(MonthlyCharges * TenureMonths) AS total_revenue
FROM existing_users
GROUP BY 1;
-- offering internet to users with no internet service
SELECT CustomerID
FROM existing_users
WHERE InternetServiceType = 'No'
AND (clv_segments = 'LOW' OR clv_segments ='churn risk');
-- cross selling and up selling for senior citizens who do not have tech support
SELECT CustomerID
FROM existing_users
WHERE (Has_Partner = 'No' OR Has_Dependents = 'No')
AND (InternetServiceType = 'DSL' OR InternetServiceType = 'Fiber optic')
AND SeniorCitizen = 1
AND Has_TechSupport = 'No'
AND (clv_segments = 'LOW' OR clv_segments = 'churn risk');
-- offering phone servIce to users with no phone service
SELECT CustomerID
FROM existing_users
WHERE Has_PhoneService = 'No'
AND (clv_segments = 'LOW' OR clv_segments ='churn risk');
-- cross selling of multiple lines for users with partners and dependents
SELECT CustomerID
FROM existing_users
WHERE
Has_PhoneService = 'Yes'
AND Has_MultipleLines = 'No'
AND (Has_Partner = 'Yes' OR Has_Dependents = 'Yes')
AND (clv_segments = 'LOW' OR clv_segments = 'churn risk');
-- enlighten users who use traditional method of payment to reduce churn risk
SELECT CustomerID
FROM existing_users
WHERE PaperlessBilling = 'No'
AND Has_TechSupport = 'No'
AND (clv_segments = 'LOW' OR clv_segments = 'churn risk'); 
-- offer great features to users with  fast internet service
SELECT CustomerID
FROM existing_users
WHERE InternetServiceType = 'Fiber optic'
AND Has_OnlineSecurity = 'No'
AND Has_OnlineBackup = 'No'
AND Has_DeviceProtection = 'No'
AND Has_StreamingTV = 'No'
AND Has_StreamingMovies = 'No'
AND (clv_segments = 'LOW' OR clv_segments = 'churn risk');
-- upgrade basic internet users on premium features to premium internet service at a cheaper rate for longer lock in period
SELECT CustomerID,
clv_segments,
MonthlyCharges
FROM existing_users
WHERE InternetServiceType = 'DSL'
AND Has_OnlineSecurity = 'Yes'
AND Has_OnlineBackup = 'Yes'
AND Has_DeviceProtection = 'Yes'
AND Has_StreamingTV = 'Yes'
AND Has_StreamingMovies = 'Yes'
AND (clv_segments = 'HIGH' OR clv_segments = 'MODERATE VALUE')

-- creating stored procedures
-- users who will be offered internet service
DELIMITER //
CREATE PROCEDURE
internet_service_offer()
BEGIN
SELECT eu.CustomerID
FROM existing_users eu
WHERE eu.InternetServiceType = 'No'
AND eu.clv_segments IN('LOW','churn risk');
END //
DELIMITER ;

-- tech support for senior citizens
DELIMITER //
CREATE PROCEDURE
tech_suppprt_senior_citizen()
BEGIN
SELECT eu.CustomerID
FROM existing_users eu
WHERE (eu.Has_Partner = 'No' OR eu.Has_Dependents = 'No')
AND eu.InternetServiceType IN('DSL', 'Fiber optic')
AND eu.SeniorCitizen = 1
AND eu.Has_TechSupport = 'No'
AND eu.clv_segments IN ('LOW','churn risk');
END //
DELIMITER ;

-- phone service offer
DELIMITER //
CREATE PROCEDURE
phone_service_offer()
BEGIN
SELECT eu.CustomerID
FROM existing_users eu
WHERE eu.Has_PhoneService = 'No'
AND eu.clv_segments IN ('LOW', 'churn risk');
END //
DELIMITER ;
-- mulitple lines offer
DELIMITER //
CREATE PROCEDURE
multiple_lines_offer()
BEGIN
SELECT eu.CustomerID
FROM existing_users eu
WHERE
eu.Has_PhoneService = 'Yes'
AND eu.Has_MultipleLines = 'No'
AND (eu.Has_Partner = 'Yes' OR eu.Has_Dependents = 'Yes')
AND eu.clv_segments IN ('LOW','churn risk');
END //
DELIMITER ;
-- enlightening offer
DELIMITER //
CREATE PROCEDURE
enlightening_offer()
BEGIN
SELECT eu.CustomerID
FROM existing_users eu
WHERE eu.PaperlessBilling = 'No'
AND eu.Has_TechSupport = 'No'
AND eu.clv_segments IN ('LOW','churn risk'); 
END //
DELIMITER ;
-- premium features for fast internet users
DELIMITER //
CREATE PROCEDURE
premium_fast_internet_users()
BEGIN
SELECT eu.CustomerID
FROM existing_users eu
WHERE eu.InternetServiceType = 'Fiber optic'
AND eu.Has_OnlineSecurity = 'No'
AND eu.Has_OnlineBackup = 'No'
AND eu.Has_DeviceProtection = 'No'
AND eu.Has_StreamingTV = 'No'
AND eu.Has_StreamingMovies = 'No'
AND eu.clv_segments IN ('LOW','churn risk');
END //
DELIMITER ;
-- basic longer lock in
DELIMITER //
CREATE PROCEDURE 
basic_longer_lock_in()
BEGIN
SELECT eu.CustomerID
FROM existing_users eu
WHERE eu.InternetServiceType = 'DSL'
AND eu.Has_OnlineSecurity = 'Yes'
AND eu.Has_OnlineBackup = 'Yes'
AND eu.Has_DeviceProtection = 'Yes'
AND eu.Has_StreamingTV = 'Yes'
AND eu.Has_StreamingMovies = 'Yes'
AND eu.clv_segments IN ('HIGH','MODERATE VALUE');
END //
DELIMITER ;
-- use procedures
-- internet service offer
CALL internet_service_offer();
-- tech support
CALL tech_suppprt_senior_citizen();
-- phone service
CALL phone_service_offer();
-- multiple lines
CALL multiple_lines_offer();
-- enlightening offer
CALL enlightening_offer();
-- premium fast internet
CALL premium_fast_internet_users();
-- basic longer lock in
CALL basic_longer_lock_in();
























 

