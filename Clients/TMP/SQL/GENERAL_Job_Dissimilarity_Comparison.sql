-- ========================================================================
-- GENERAL JOB COMPARISON: Find Dissimilarities Between Jobs
-- NOW WITH EXECUTIVE SUMMARY - Main reason shown first!
-- ========================================================================

USE [THURO]
GO

-- ========================================================================
-- ⭐ ENTER YOUR PARAMETERS HERE ⭐
-- ========================================================================
DECLARE @JobsToCheck TABLE (Job VARCHAR(50))
DECLARE @FilterDepartment VARCHAR(50) = NULL  -- Set to dept name or leave NULL for all
-- Examples: 'Deburring', 'Swiss', 'Turning', 'Milling', NULL

INSERT INTO @JobsToCheck (Job)
SELECT '1317611' UNION ALL  -- ⭐ Change these to your job numbers
SELECT '1317286' UNION ALL
SELECT '1317538' UNION ALL
SELECT '1317620'

-- ========================================================================
-- PART 0: EXECUTIVE SUMMARY ⭐⭐⭐ START HERE ⭐⭐⭐
-- Main reason why each job is different - ONE CLEAR ANSWER
-- ========================================================================
SELECT 
    '⭐ EXECUTIVE SUMMARY ⭐' AS Section,
    j.Job,
    j.Part_Number,
    j.Customer,
    
    -- THE MAIN REASON (in priority order)
    CASE 
        -- Priority 1: Job status issues
        WHEN j.Status IN ('Complete', 'Closed', 'Shipped')
        THEN '❌ Job is ' + j.Status + ' (closed jobs excluded from view)'
        
        -- Priority 2: No operations in allowed departments
        WHEN NOT EXISTS (
            SELECT 1 FROM THURO.dbo.Job_Operation jo
            INNER JOIN THURO.dbo.Work_Center w ON jo.Work_Center = w.Work_Center
            WHERE jo.Job = j.Job
              AND w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
              AND w.Status = 1
              AND w.UVText1 = 'MStatusQry'
              AND w.Work_Center != 'SM SETUPM'
              AND (@FilterDepartment IS NULL OR w.Department = @FilterDepartment)
        ) THEN '❌ Only has operations in EXCLUDED departments: ' + 
               STUFF((SELECT DISTINCT ', ' + ISNULL(w.Department, 'NULL')
                     FROM THURO.dbo.Job_Operation jo
                     INNER JOIN THURO.dbo.Work_Center w ON jo.Work_Center = w.Work_Center
                     WHERE jo.Job = j.Job
                     FOR XML PATH('')), 1, 2, '')
        
        -- Priority 3: No recent activity in allowed departments
        WHEN NOT EXISTS (
            SELECT 1 
            FROM THURO.dbo.Job_Operation jo
            INNER JOIN THURO.dbo.Work_Center w ON jo.Work_Center = w.Work_Center
            INNER JOIN THURO.dbo.Job_Operation_Time jot ON jo.Job_Operation = jot.Job_Operation
            WHERE jo.Job = j.Job
              AND w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
              AND w.Work_Center != 'SM SETUPM'
              AND jot.Work_Date >= DATEADD(DAY, -7, GETDATE())
              AND jot.Work_Date IS NOT NULL
              AND (@FilterDepartment IS NULL OR w.Department = @FilterDepartment)
        ) THEN '❌ No recent activity (last 7 days). Last activity: ' + 
               ISNULL(CONVERT(VARCHAR(10), (
                   SELECT MAX(jot.Work_Date)
                   FROM THURO.dbo.Job_Operation jo
                   INNER JOIN THURO.dbo.Work_Center w ON jo.Work_Center = w.Work_Center
                   INNER JOIN THURO.dbo.Job_Operation_Time jot ON jo.Job_Operation = jot.Job_Operation
                   WHERE jo.Job = j.Job
                     AND w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
                     AND (@FilterDepartment IS NULL OR w.Department = @FilterDepartment)
               ), 101) + ' (' + CAST(DATEDIFF(DAY, (
                   SELECT MAX(jot.Work_Date)
                   FROM THURO.dbo.Job_Operation jo
                   INNER JOIN THURO.dbo.Work_Center w ON jo.Work_Center = w.Work_Center
                   INNER JOIN THURO.dbo.Job_Operation_Time jot ON jo.Job_Operation = jot.Job_Operation
                   WHERE jo.Job = j.Job
                     AND w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
                     AND (@FilterDepartment IS NULL OR w.Department = @FilterDepartment)
               ), GETDATE()) AS VARCHAR) + ' days ago)', 'Never')
        
        -- Priority 4: Has previous production (for First Run context)
        WHEN EXISTS (
            SELECT 1 
            FROM THURO.dbo.Job j_hist
            INNER JOIN THURO.dbo.Job_Operation jo_hist ON j_hist.Job = jo_hist.Job
            INNER JOIN THURO.dbo.Job_Operation_Time jot_hist ON jo_hist.Job_Operation = jot_hist.Job_Operation
            WHERE j_hist.Part_Number = j.Part_Number
                AND j_hist.Job < j.Job
                AND jot_hist.Act_Run_Qty > 0
        ) THEN '⚠️ Not a First Run - Previous production exists in job(s): ' + 
               STUFF((SELECT TOP 3 ', ' + CAST(j_prev.Job AS VARCHAR(10))
                     FROM THURO.dbo.Job j_prev
                     INNER JOIN THURO.dbo.Job_Operation jo_prev ON j_prev.Job = jo_prev.Job
                     INNER JOIN THURO.dbo.Job_Operation_Time jot_prev ON jo_prev.Job_Operation = jot_prev.Job_Operation
                     WHERE j_prev.Part_Number = j.Part_Number
                       AND j_prev.Job < j.Job
                       AND jot_prev.Act_Run_Qty > 0
                     ORDER BY j_prev.Job DESC
                     FOR XML PATH('')), 1, 2, '')
        
        -- All checks pass
        ELSE '✅ SHOULD SHOW - Passes all filters (allowed dept + recent activity + first run)'
    END AS PRIMARY_REASON,
    
    -- Quick status indicator
    CASE 
        WHEN j.Status IN ('Complete', 'Closed', 'Shipped') THEN '❌ EXCLUDED'
        WHEN NOT EXISTS (
            SELECT 1 FROM THURO.dbo.Job_Operation jo
            INNER JOIN THURO.dbo.Work_Center w ON jo.Work_Center = w.Work_Center
            WHERE jo.Job = j.Job
              AND w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
              AND w.Work_Center != 'SM SETUPM'
              AND (@FilterDepartment IS NULL OR w.Department = @FilterDepartment)
        ) THEN '❌ EXCLUDED'
        WHEN NOT EXISTS (
            SELECT 1 
            FROM THURO.dbo.Job_Operation jo
            INNER JOIN THURO.dbo.Work_Center w ON jo.Work_Center = w.Work_Center
            INNER JOIN THURO.dbo.Job_Operation_Time jot ON jo.Job_Operation = jot.Job_Operation
            WHERE jo.Job = j.Job
              AND w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
              AND w.Work_Center != 'SM SETUPM'
              AND jot.Work_Date >= DATEADD(DAY, -7, GETDATE())
              AND (@FilterDepartment IS NULL OR w.Department = @FilterDepartment)
        ) THEN '❌ EXCLUDED'
        WHEN EXISTS (
            SELECT 1 
            FROM THURO.dbo.Job j_hist
            INNER JOIN THURO.dbo.Job_Operation jo_hist ON j_hist.Job = jo_hist.Job
            INNER JOIN THURO.dbo.Job_Operation_Time jot_hist ON jo_hist.Job_Operation = jot_hist.Job_Operation
            WHERE j_hist.Part_Number = j.Part_Number
                AND j_hist.Job < j.Job
                AND jot_hist.Act_Run_Qty > 0
        ) THEN '⚠️ NOT FIRST RUN'
        ELSE '✅ INCLUDED'
    END AS Status_Indicator

FROM @JobsToCheck jtc
    INNER JOIN THURO.dbo.Job j ON jtc.Job = j.Job

ORDER BY 
    CASE 
        WHEN j.Status IN ('Complete', 'Closed', 'Shipped') THEN 3
        WHEN NOT EXISTS (
            SELECT 1 FROM THURO.dbo.Job_Operation jo
            INNER JOIN THURO.dbo.Work_Center w ON jo.Work_Center = w.Work_Center
            WHERE jo.Job = j.Job
              AND w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
              AND w.Work_Center != 'SM SETUPM'
        ) THEN 2
        WHEN NOT EXISTS (
            SELECT 1 
            FROM THURO.dbo.Job_Operation jo
            INNER JOIN THURO.dbo.Work_Center w ON jo.Work_Center = w.Work_Center
            INNER JOIN THURO.dbo.Job_Operation_Time jot ON jo.Job_Operation = jot.Job_Operation
            WHERE jo.Job = j.Job
              AND w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
              AND w.Work_Center != 'SM SETUPM'
              AND jot.Work_Date >= DATEADD(DAY, -7, GETDATE())
        ) THEN 1
        ELSE 0
    END,
    j.Job

-- ========================================================================
-- PART 1: QUICK COMPARISON MATRIX
-- Side-by-side YES/NO for each filter
-- ========================================================================
SELECT 
    'COMPARISON MATRIX' AS Section,
    j.Job,
    
    -- Column 1: Has allowed dept ops?
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM THURO.dbo.Job_Operation jo
            INNER JOIN THURO.dbo.Work_Center w ON jo.Work_Center = w.Work_Center
            WHERE jo.Job = j.Job
              AND w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
              AND w.Work_Center != 'SM SETUPM'
              AND (@FilterDepartment IS NULL OR w.Department = @FilterDepartment)
        ) THEN 'YES'
        ELSE 'NO'
    END AS Has_Allowed_Ops,
    
    -- Column 2: Recent activity?
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM THURO.dbo.Job_Operation jo
            INNER JOIN THURO.dbo.Work_Center w ON jo.Work_Center = w.Work_Center
            INNER JOIN THURO.dbo.Job_Operation_Time jot ON jo.Job_Operation = jot.Job_Operation
            WHERE jo.Job = j.Job
              AND w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
              AND w.Work_Center != 'SM SETUPM'
              AND jot.Work_Date >= DATEADD(DAY, -7, GETDATE())
              AND (@FilterDepartment IS NULL OR w.Department = @FilterDepartment)
        ) THEN 'YES'
        ELSE 'NO'
    END AS Recent_Activity,
    
    -- Column 3: Job status OK?
    CASE 
        WHEN j.Status NOT IN ('Complete', 'Closed', 'Shipped') THEN 'YES'
        ELSE 'NO'
    END AS Status_OK,
    
    -- Column 4: First Run?
    CASE 
        WHEN NOT EXISTS (
            SELECT 1 
            FROM THURO.dbo.Job j_hist
            INNER JOIN THURO.dbo.Job_Operation jo_hist ON j_hist.Job = jo_hist.Job
            INNER JOIN THURO.dbo.Job_Operation_Time jot_hist ON jo_hist.Job_Operation = jot_hist.Job_Operation
            WHERE j_hist.Part_Number = j.Part_Number
                AND j_hist.Job < j.Job
                AND jot_hist.Act_Run_Qty > 0
        ) THEN 'YES'
        ELSE 'NO'
    END AS Is_First_Run,
    
    -- Final Result
    CASE 
        WHEN j.Status NOT IN ('Complete', 'Closed', 'Shipped')
             AND EXISTS (
                SELECT 1 FROM THURO.dbo.Job_Operation jo
                INNER JOIN THURO.dbo.Work_Center w ON jo.Work_Center = w.Work_Center
                INNER JOIN THURO.dbo.Job_Operation_Time jot ON jo.Job_Operation = jot.Job_Operation
                WHERE jo.Job = j.Job
                  AND w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
                  AND w.Work_Center != 'SM SETUPM'
                  AND jot.Work_Date >= DATEADD(DAY, -7, GETDATE())
                  AND (@FilterDepartment IS NULL OR w.Department = @FilterDepartment)
             )
             AND NOT EXISTS (
                SELECT 1 
                FROM THURO.dbo.Job j_hist
                INNER JOIN THURO.dbo.Job_Operation jo_hist ON j_hist.Job = jo_hist.Job
                INNER JOIN THURO.dbo.Job_Operation_Time jot_hist ON jo_hist.Job_Operation = jot_hist.Job_Operation
                WHERE j_hist.Part_Number = j.Part_Number
                    AND j_hist.Job < j.Job
                    AND jot_hist.Act_Run_Qty > 0
             )
        THEN 'SHOWS'
        ELSE 'HIDDEN'
    END AS Result

FROM @JobsToCheck jtc
    INNER JOIN THURO.dbo.Job j ON jtc.Job = j.Job

ORDER BY j.Job

-- ========================================================================
-- PART 2: DEPARTMENTS COMPARISON
-- Which departments does each job use?
-- ========================================================================
SELECT 
    'DEPARTMENTS BY JOB' AS Section,
    j.Job,
    w.Department,
    COUNT(DISTINCT jo.Job_Operation) AS Num_Operations,
    
    CASE 
        WHEN w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
        THEN '✓ ALLOWED'
        ELSE '✗ EXCLUDED'
    END AS Dept_Status,
    
    CONVERT(VARCHAR(10), MAX(jot.Work_Date), 101) AS Last_Activity,
    
    CASE 
        WHEN MAX(jot.Work_Date) >= DATEADD(DAY, -7, GETDATE()) THEN '✓ Recent'
        WHEN MAX(jot.Work_Date) IS NULL THEN '- None'
        ELSE '✗ Old'
    END AS Activity_Status

FROM @JobsToCheck jtc
    INNER JOIN THURO.dbo.Job j ON jtc.Job = j.Job
    INNER JOIN THURO.dbo.Job_Operation jo ON j.Job = jo.Job
    INNER JOIN THURO.dbo.Work_Center w ON jo.Work_Center = w.Work_Center
    LEFT JOIN THURO.dbo.Job_Operation_Time jot ON jo.Job_Operation = jot.Job_Operation

WHERE (@FilterDepartment IS NULL OR w.Department = @FilterDepartment)

GROUP BY j.Job, w.Department

ORDER BY j.Job, 
    CASE WHEN w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing') THEN 0 ELSE 1 END,
    w.Department

-- ========================================================================
-- PART 3: OPERATION DETAILS (Condensed)
-- Key operations only
-- ========================================================================
SELECT 
    'OPERATION DETAILS' AS Section,
    j.Job,
    jo.Sequence,
    w.Work_Center AS Machine,
    w.Department,
    jo.Operation_Service,
    jo.Status AS Op_Status,
    
    CASE 
        WHEN w.Work_Center = 'SM SETUPM' THEN '✗ Setup (excluded)'
        WHEN w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
        THEN '✓ Allowed'
        ELSE '✗ Excluded'
    END AS Dept_Status,
    
    CONVERT(VARCHAR(10), (
        SELECT MAX(jot.Work_Date)
        FROM THURO.dbo.Job_Operation_Time jot
        WHERE jot.Job_Operation = jo.Job_Operation
    ), 101) AS Last_Activity,
    
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM THURO.dbo.Job_Operation_Time jot
            WHERE jot.Job_Operation = jo.Job_Operation
              AND jot.Work_Date >= DATEADD(DAY, -7, GETDATE())
        ) THEN '✓ Recent'
        ELSE '✗ Old/None'
    END AS Activity_Status

FROM @JobsToCheck jtc
    INNER JOIN THURO.dbo.Job j ON jtc.Job = j.Job
    INNER JOIN THURO.dbo.Job_Operation jo ON j.Job = jo.Job
    INNER JOIN THURO.dbo.Work_Center w ON jo.Work_Center = w.Work_Center

WHERE (@FilterDepartment IS NULL OR w.Department = @FilterDepartment)

ORDER BY j.Job, jo.Sequence

-- ========================================================================
-- INSTRUCTIONS:
-- 
-- ⭐⭐⭐ LOOK AT PART 0 FIRST ⭐⭐⭐
-- 
-- PART 0: EXECUTIVE SUMMARY - THE MAIN REASON
--   Shows ONE clear explanation for each job
--   ✅ INCLUDED = Will show in view
--   ❌ EXCLUDED = Won't show (with specific reason)
--   ⚠️ NOT FIRST RUN = Has previous production
--
-- PART 1: COMPARISON MATRIX
--   Quick YES/NO comparison
--   Easy to spot differences
--
-- PART 2: DEPARTMENTS
--   Which depts each job uses
--
-- PART 3: OPERATIONS
--   Detailed operation breakdown
--
-- HOW TO USE:
-- 1. Set job numbers (line 14-18)
-- 2. Set department filter (line 12) - optional
-- 3. Run query
-- 4. Read Part 0 - that's your answer!
-- 5. Use other parts only if you need more detail
--
-- EXAMPLES OF PART 0 OUTPUT:
-- Job 1317538: "❌ Only has operations in EXCLUDED departments: NULL, 411 NEW PART, Assembly"
-- Job 1317611: "✅ SHOULD SHOW - Passes all filters"
-- Job 1317620: "❌ No recent activity (last 7 days). Last activity: 09/15/2025 (25 days ago)"
-- ========================================================================
