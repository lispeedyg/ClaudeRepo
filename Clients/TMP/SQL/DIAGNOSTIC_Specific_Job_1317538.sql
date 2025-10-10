-- ========================================================================
-- SPECIFIC JOB CHECK - Diagnose Job 1317538
-- Purpose: Find out why this job isn't being picked up by the FirstRun logic
-- ========================================================================

USE [THURO]
GO

-- Check this specific job
DECLARE @JobNumber VARCHAR(50) = '1317538'

-- What's actually in the database for this job?
SELECT 
    'JOB DATABASE VALUES' AS Section,
    j.Job,
    j.Part_Number,
    LEN(j.Part_Number) AS Part_Number_Length,
    j.Status AS Job_Status,
    j.Status_Date,
    j.Customer,
    j.Order_Date,
    
    -- Check for whitespace issues
    CASE 
        WHEN j.Part_Number LIKE '% %' THEN '⚠ Contains spaces'
        WHEN j.Part_Number LIKE '%	%' THEN '⚠ Contains tabs'
        WHEN j.Part_Number != RTRIM(LTRIM(j.Part_Number)) THEN '⚠ Has leading/trailing whitespace'
        ELSE '✓ No whitespace issues'
    END AS Part_Number_Quality_Check,
    
    -- Show it with quotes so we can see exact value
    '''' + j.Part_Number + '''' AS Part_Number_With_Quotes,
    
    -- Check Status issues
    CASE 
        WHEN j.Status IN ('Complete', 'Closed', 'Shipped') THEN '⚠ Job is Complete/Closed/Shipped - will be EXCLUDED'
        ELSE '✓ Job Status should be included'
    END AS Status_Check,
    
    -- Will it show in FirstRun logic?
    CASE 
        WHEN j.Status IN ('Complete', 'Closed', 'Shipped') THEN 'NO - Job is closed'
        WHEN NOT EXISTS (
            SELECT 1 
            FROM THURO.dbo.Job j_hist with (NoLock)
            INNER JOIN THURO.dbo.Job_Operation jo_hist with (NoLock) ON j_hist.Job = jo_hist.Job
            INNER JOIN THURO.dbo.Job_Operation_Time jot_hist with (NoLock) ON jo_hist.Job_Operation = jot_hist.Job_Operation
            WHERE j_hist.Part_Number = j.Part_Number
                AND j_hist.Job < j.Job
                AND jot_hist.Act_Run_Qty > 0
        ) THEN 'YES - Should show as First Run (F)'
        ELSE 'NO - Will show as Repeat (O) - has previous production'
    END AS FirstRun_Prediction

FROM THURO.dbo.Job j with (NoLock)
WHERE j.Job = @JobNumber

-- ========================================================================
-- Check if there are similar part numbers (typos, extra characters, etc.)
-- ========================================================================
SELECT 
    'SIMILAR PART NUMBERS' AS Section,
    j.Job,
    j.Part_Number,
    j.Status,
    j.Customer,
    
    -- Show similarity
    CASE 
        WHEN j.Part_Number = '858046-1' THEN '✓ EXACT MATCH'
        WHEN REPLACE(REPLACE(REPLACE(j.Part_Number, ' ', ''), CHAR(9), ''), CHAR(13), '') = '858046-1' 
        THEN '⚠ Match after removing whitespace'
        WHEN j.Part_Number LIKE '%858046-1%' THEN '⚠ Contains target part number'
        WHEN j.Part_Number LIKE '%858046%' THEN '~ Similar (contains 858046)'
        ELSE '? Different'
    END AS Similarity
    
FROM THURO.dbo.Job j with (NoLock)
WHERE j.Part_Number LIKE '%858046%'
   OR j.Job = @JobNumber
ORDER BY 
    CASE WHEN j.Job = @JobNumber THEN 0 ELSE 1 END,
    j.Job DESC

-- ========================================================================
-- Show ALL jobs with EXACTLY this part number (cleaned)
-- ========================================================================
SELECT 
    'EXACT PART NUMBER MATCHES' AS Section,
    j.Job,
    j.Part_Number,
    j.Status,
    j.Customer,
    j.Status_Date,
    
    -- Has production?
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM THURO.dbo.Job_Operation jo
            INNER JOIN THURO.dbo.Job_Operation_Time jot ON jo.Job_Operation = jot.Job_Operation
            WHERE jo.Job = j.Job AND jot.Act_Run_Qty > 0
        ) THEN '✓ Has Production'
        ELSE '○ No Production'
    END AS Production_Status

FROM THURO.dbo.Job j with (NoLock)
WHERE RTRIM(LTRIM(j.Part_Number)) = '858046-1'
ORDER BY j.Job

-- ========================================================================
-- SOLUTION: Show what the FirstRun query is actually seeing
-- ========================================================================
SELECT 
    'WHAT FIRSTRUN QUERY SEES' AS Section,
    j.Job,
    j.Part_Number,
    j.Status,
    
    -- This is the exact filter from FirstRunIdentifier CTE
    CASE 
        WHEN j.Status NOT IN ('Complete', 'Closed', 'Shipped') THEN '✓ INCLUDED in FirstRun query'
        ELSE '✗ EXCLUDED from FirstRun query'
    END AS Inclusion_Status,
    
    -- What would the RunIndicator be?
    CASE 
        WHEN j.Status IN ('Complete', 'Closed', 'Shipped') THEN 'N/A - Job excluded'
        WHEN EXISTS (
            SELECT 1 
            FROM THURO.dbo.Job j_hist with (NoLock)
            INNER JOIN THURO.dbo.Job_Operation jo_hist with (NoLock) ON j_hist.Job = jo_hist.Job
            INNER JOIN THURO.dbo.Job_Operation_Time jot_hist with (NoLock) ON jo_hist.Job_Operation = jot_hist.Job_Operation
            WHERE j_hist.Part_Number = j.Part_Number
                AND j_hist.Job < j.Job
                AND jot_hist.Act_Run_Qty > 0
        ) THEN 'O (Repeat)'
        ELSE 'F (First Run)'
    END AS RunIndicator

FROM THURO.dbo.Job j with (NoLock)
WHERE j.Job = @JobNumber
   OR RTRIM(LTRIM(j.Part_Number)) = '858046-1'
ORDER BY j.Job

-- ========================================================================
-- INSTRUCTIONS:
-- This will show you EXACTLY what's in the database for Job 1317538
-- and why it's not showing up in the First Run tab
-- ========================================================================
