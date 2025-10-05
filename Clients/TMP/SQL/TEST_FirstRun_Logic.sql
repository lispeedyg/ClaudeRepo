-- TEST QUERY: FirstRun Part Number Detection
-- Purpose: Verify FirstRun logic before integrating into main view
-- Test this query first to ensure it correctly identifies first-run vs repeat parts

USE [THURO]
GO

-- Test the FirstRun indicator logic
SELECT TOP 100
    j.Job,
    j.Part_Number,
    j.Customer,
    j.Status,
    j.Status_Date,
    
    -- FirstRun Check Logic
    CASE 
        WHEN j.Part_Number IS NULL OR LTRIM(RTRIM(j.Part_Number)) = '' 
        THEN 'O'  -- No part number = treat as Old
        
        WHEN EXISTS (
            SELECT 1 
            FROM THURO.dbo.Job j_prev with (NoLock)
            WHERE j_prev.Part_Number = j.Part_Number
              AND j_prev.Job < j.Job  -- Previous job (lower job number)
              AND j_prev.Status IN ('Complete', 'Closed', 'Shipped')  -- Only count completed previous jobs
        ) 
        THEN 'O'  -- Old part (has been run before)
        
        ELSE 'F'  -- FirstRun part (never completed before)
    END AS FirstRunFlag,
    
    -- Show count of previous jobs for verification
    (SELECT COUNT(*)
     FROM THURO.dbo.Job j_prev with (NoLock)
     WHERE j_prev.Part_Number = j.Part_Number
       AND j_prev.Job < j.Job
       AND j_prev.Status IN ('Complete', 'Closed', 'Shipped')
    ) AS PreviousCompletedJobCount
    
FROM THURO.dbo.Job j with (NoLock)
WHERE j.Status NOT IN ('Complete', 'Closed', 'Shipped')  -- Current active jobs
  AND j.Part_Number IS NOT NULL
ORDER BY j.Job DESC

-- VERIFICATION QUERIES:
-- =====================

-- 1. Show some examples of FirstRun parts
SELECT TOP 10
    'FirstRun Examples' AS QueryType,
    j.Job,
    j.Part_Number,
    j.Customer,
    j.Status
FROM THURO.dbo.Job j with (NoLock)
WHERE j.Status NOT IN ('Complete', 'Closed', 'Shipped')
  AND j.Part_Number IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 
      FROM THURO.dbo.Job j_prev with (NoLock)
      WHERE j_prev.Part_Number = j.Part_Number
        AND j_prev.Job < j.Job
        AND j_prev.Status IN ('Complete', 'Closed', 'Shipped')
  )
ORDER BY j.Job DESC

UNION ALL

-- 2. Show some examples of Repeat parts
SELECT TOP 10
    'Repeat Part Examples' AS QueryType,
    j.Job,
    j.Part_Number,
    j.Customer,
    j.Status
FROM THURO.dbo.Job j with (NoLock)
WHERE j.Status NOT IN ('Complete', 'Closed', 'Shipped')
  AND j.Part_Number IS NOT NULL
  AND EXISTS (
      SELECT 1 
      FROM THURO.dbo.Job j_prev with (NoLock)
      WHERE j_prev.Part_Number = j.Part_Number
        AND j_prev.Job < j.Job
        AND j_prev.Status IN ('Complete', 'Closed', 'Shipped')
  )
ORDER BY j.Job DESC

GO
