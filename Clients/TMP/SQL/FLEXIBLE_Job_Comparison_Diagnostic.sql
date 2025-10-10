-- ========================================================================
-- FLEXIBLE JOB COMPARISON: Enter Any Job Numbers
-- Compare multiple jobs to see why some show in First Run and others don't
-- ========================================================================

USE [THURO]
GO

-- ========================================================================
-- ⭐ ENTER YOUR JOB NUMBERS HERE ⭐
-- Just change the numbers in the SELECT statements below
-- ========================================================================
DECLARE @JobsToCheck TABLE (Job VARCHAR(50))

INSERT INTO @JobsToCheck (Job)
SELECT '1317611' UNION ALL  -- Change these to your job numbers
SELECT '1317286' UNION ALL  -- Add or remove lines as needed
SELECT '1317538' UNION ALL  -- Just copy the pattern
SELECT '1317620'            -- Last one has no UNION ALL

-- You can add more jobs by copying this line:
-- SELECT 'XXXXXXX' UNION ALL

-- ========================================================================
-- PART 1: QUICK SUMMARY - Which jobs show and which don't?
-- ========================================================================
SELECT 
    'QUICK SUMMARY' AS Section,
    j.Job,
    j.Part_Number,
    j.Customer,
    
    -- Final verdict
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM THURO.dbo.Job_Operation jo_check
            INNER JOIN THURO.dbo.Work_Center w_check ON jo_check.Work_Center = w_check.Work_Center
            INNER JOIN THURO.dbo.Job_Operation_Time jot_check ON jo_check.Job_Operation = jot_check.Job_Operation
            WHERE jo_check.Job = j.Job
              AND w_check.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
              AND w_check.Status = 1
              AND w_check.UVText1 = 'MStatusQry'
              AND w_check.Work_Center != 'SM SETUPM'
              AND jot_check.Work_Date >= DATEADD(DAY, -7, GETDATE())
              AND jot_check.Work_Date IS NOT NULL
              AND jot_check.Last_Updated IS NOT NULL
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
        THEN '✓✓✓ WILL SHOW in First Run'
        ELSE '✗✗✗ Will NOT show'
    END AS Shows_In_FirstRun,
    
    -- Quick reason why
    CASE 
        WHEN NOT EXISTS (
            SELECT 1 FROM THURO.dbo.Job_Operation jo
            INNER JOIN THURO.dbo.Work_Center w ON jo.Work_Center = w.Work_Center
            WHERE jo.Job = j.Job
              AND w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
              AND w.Work_Center != 'SM SETUPM'
        ) THEN 'No ops in allowed depts'
        
        WHEN NOT EXISTS (
            SELECT 1 
            FROM THURO.dbo.Job_Operation jo
            INNER JOIN THURO.dbo.Work_Center w ON jo.Work_Center = w.Work_Center
            INNER JOIN THURO.dbo.Job_Operation_Time jot ON jo.Job_Operation = jot.Job_Operation
            WHERE jo.Job = j.Job
              AND w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
              AND w.Work_Center != 'SM SETUPM'
              AND jot.Work_Date >= DATEADD(DAY, -7, GETDATE())
        ) THEN 'No recent activity in allowed depts'
        
        WHEN EXISTS (
            SELECT 1 
            FROM THURO.dbo.Job j_hist
            INNER JOIN THURO.dbo.Job_Operation jo_hist ON j_hist.Job = jo_hist.Job
            INNER JOIN THURO.dbo.Job_Operation_Time jot_hist ON jo_hist.Job_Operation = jot_hist.Job_Operation
            WHERE j_hist.Part_Number = j.Part_Number
                AND j_hist.Job < j.Job
                AND jot_hist.Act_Run_Qty > 0
        ) THEN 'Has previous production (not first run)'
        
        ELSE 'Passes all checks'
    END AS Primary_Reason

FROM THURO.dbo.Job j
    INNER JOIN @JobsToCheck jtc ON j.Job = jtc.Job

ORDER BY 
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM THURO.dbo.Job_Operation jo_check
            INNER JOIN THURO.dbo.Work_Center w_check ON jo_check.Work_Center = w_check.Work_Center
            INNER JOIN THURO.dbo.Job_Operation_Time jot_check ON jo_check.Job_Operation = jot_check.Job_Operation
            WHERE jo_check.Job = j.Job
              AND w_check.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
              AND w_check.Status = 1
              AND w_check.Work_Center != 'SM SETUPM'
              AND jot_check.Work_Date >= DATEADD(DAY, -7, GETDATE())
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
        THEN 0 ELSE 1 
    END,
    j.Job

-- ========================================================================
-- PART 2: DETAILED FILTER CHECK - Pass/Fail for each job
-- ========================================================================
SELECT 
    'DETAILED CHECK' AS Section,
    j.Job,
    j.Part_Number,
    j.Customer,
    j.Status AS Job_Status,
    
    -- CHECK 1: Has operations in allowed departments?
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM THURO.dbo.Job_Operation jo_allowed
            INNER JOIN THURO.dbo.Work_Center w_allowed ON jo_allowed.Work_Center = w_allowed.Work_Center
            WHERE jo_allowed.Job = j.Job
              AND w_allowed.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
              AND w_allowed.Status = 1
              AND w_allowed.UVText1 = 'MStatusQry'
              AND w_allowed.Work_Center != 'SM SETUPM'
        ) THEN '✓ PASS'
        ELSE '✗ FAIL'
    END AS Check1_Has_Allowed_Ops,
    
    -- CHECK 2: Recent activity in allowed departments?
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM THURO.dbo.Job_Operation jo_check
            INNER JOIN THURO.dbo.Work_Center w_check ON jo_check.Work_Center = w_check.Work_Center
            INNER JOIN THURO.dbo.Job_Operation_Time jot_check ON jo_check.Job_Operation = jot_check.Job_Operation
            WHERE jo_check.Job = j.Job
              AND w_check.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
              AND w_check.Work_Center != 'SM SETUPM'
              AND jot_check.Work_Date >= DATEADD(DAY, -7, GETDATE())
              AND jot_check.Work_Date IS NOT NULL
              AND jot_check.Last_Updated IS NOT NULL
        ) THEN '✓ PASS'
        ELSE '✗ FAIL'
    END AS Check2_Recent_Activity,
    
    -- Show last activity date
    CONVERT(VARCHAR(10), (
        SELECT MAX(jot.Work_Date)
        FROM THURO.dbo.Job_Operation jo
        INNER JOIN THURO.dbo.Work_Center w ON jo.Work_Center = w.Work_Center
        INNER JOIN THURO.dbo.Job_Operation_Time jot ON jo.Job_Operation = jot.Job_Operation
        WHERE jo.Job = j.Job
          AND w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
          AND w.Work_Center != 'SM SETUPM'
    ), 101) AS Last_Activity_Allowed_Dept,
    
    -- CHECK 3: Job status
    CASE 
        WHEN (j.Status NOT IN ('Complete', 'Closed', 'Shipped') 
              OR j.Status_Date >= DATEADD(DAY, -1, GETDATE()))
        THEN '✓ PASS'
        ELSE '✗ FAIL'
    END AS Check3_Job_Status,
    
    -- CHECK 4: FirstRun indicator
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM THURO.dbo.Job j_hist
            INNER JOIN THURO.dbo.Job_Operation jo_hist ON j_hist.Job = jo_hist.Job
            INNER JOIN THURO.dbo.Job_Operation_Time jot_hist ON jo_hist.Job_Operation = jot_hist.Job_Operation
            WHERE j_hist.Part_Number = j.Part_Number
                AND j_hist.Job < j.Job
                AND jot_hist.Act_Run_Qty > 0
        ) THEN '✗ FAIL (Repeat)'
        ELSE '✓ PASS (First Run)'
    END AS Check4_FirstRun

FROM THURO.dbo.Job j
    INNER JOIN @JobsToCheck jtc ON j.Job = jtc.Job

ORDER BY j.Job

-- ========================================================================
-- PART 3: DEPARTMENTS USED - What departments does each job use?
-- ========================================================================
SELECT 
    'DEPARTMENTS USED' AS Section,
    j.Job,
    w.Department,
    COUNT(DISTINCT jo.Job_Operation) AS Num_Operations,
    
    -- Is this department allowed?
    CASE 
        WHEN w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
        THEN '✓ ALLOWED'
        ELSE '✗ EXCLUDED'
    END AS Dept_Status,
    
    -- Recent activity?
    CONVERT(VARCHAR(10), MAX(jot.Work_Date), 101) AS Last_Activity_Date,
    
    CASE 
        WHEN MAX(jot.Work_Date) >= DATEADD(DAY, -7, GETDATE())
        THEN '✓ Recent'
        WHEN MAX(jot.Work_Date) IS NULL
        THEN '- No activity'
        ELSE '✗ Old'
    END AS Activity_Status

FROM @JobsToCheck jtc
    INNER JOIN THURO.dbo.Job j ON jtc.Job = j.Job
    INNER JOIN THURO.dbo.Job_Operation jo ON j.Job = jo.Job
    INNER JOIN THURO.dbo.Work_Center w ON jo.Work_Center = w.Work_Center
    LEFT JOIN THURO.dbo.Job_Operation_Time jot ON jo.Job_Operation = jot.Job_Operation

GROUP BY j.Job, w.Department

ORDER BY 
    j.Job,
    CASE WHEN w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing') THEN 0 ELSE 1 END,
    w.Department

-- ========================================================================
-- PART 4: OPERATION DETAILS - Every operation for each job
-- ========================================================================
SELECT 
    'OPERATION DETAILS' AS Section,
    j.Job,
    jo.Sequence AS Op_Seq,
    jo.Work_Center AS Machine,
    w.Department,
    jo.Operation_Service,
    jo.Status AS Op_Status,
    
    -- Would this operation be included?
    CASE 
        WHEN w.Work_Center = 'SM SETUPM'
        THEN '✗ EXCLUDED (Setup)'
        WHEN w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
        THEN '✓ ALLOWED DEPT'
        ELSE '✗ EXCLUDED DEPT'
    END AS Dept_Status,
    
    -- Recent activity?
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM THURO.dbo.Job_Operation_Time jot_check
            WHERE jot_check.Job_Operation = jo.Job_Operation
              AND jot_check.Work_Date >= DATEADD(DAY, -7, GETDATE())
        ) THEN '✓ YES'
        ELSE '✗ NO'
    END AS Recent_Activity,
    
    CONVERT(VARCHAR(10), (
        SELECT MAX(jot.Work_Date)
        FROM THURO.dbo.Job_Operation_Time jot
        WHERE jot.Job_Operation = jo.Job_Operation
    ), 101) AS Last_Activity_Date,
    
    -- Would this op show in view?
    CASE 
        WHEN w.Work_Center = 'SM SETUPM'
        THEN '✗ NO - Setup excluded'
        WHEN w.Department NOT IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
        THEN '✗ NO - Excluded dept'
        WHEN NOT EXISTS (
            SELECT 1 
            FROM THURO.dbo.Job_Operation_Time jot_check
            WHERE jot_check.Job_Operation = jo.Job_Operation
              AND jot_check.Work_Date >= DATEADD(DAY, -7, GETDATE())
        ) THEN '✗ NO - No recent activity'
        ELSE '✓ YES - Would show in view'
    END AS Would_Show_In_View

FROM @JobsToCheck jtc
    INNER JOIN THURO.dbo.Job j ON jtc.Job = j.Job
    INNER JOIN THURO.dbo.Job_Operation jo ON j.Job = jo.Job
    INNER JOIN THURO.dbo.Work_Center w ON jo.Work_Center = w.Work_Center

ORDER BY j.Job, jo.Sequence

-- ========================================================================
-- PART 5: PREVIOUS PRODUCTION HISTORY - Why marked as Repeat vs First Run
-- ========================================================================
SELECT 
    'PREVIOUS PRODUCTION' AS Section,
    j_curr.Job AS Current_Job,
    j_curr.Part_Number,
    
    -- Previous jobs exist?
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM THURO.dbo.Job j_prev
            WHERE j_prev.Part_Number = j_curr.Part_Number
              AND j_prev.Job < j_curr.Job
        ) THEN 'YES - Has previous jobs'
        ELSE 'NO - This is truly first job for this part'
    END AS Has_Previous_Jobs,
    
    -- Previous production exists?
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM THURO.dbo.Job j_prev
            INNER JOIN THURO.dbo.Job_Operation jo_prev ON j_prev.Job = jo_prev.Job
            INNER JOIN THURO.dbo.Job_Operation_Time jot_prev ON jo_prev.Job_Operation = jot_prev.Job_Operation
            WHERE j_prev.Part_Number = j_curr.Part_Number
              AND j_prev.Job < j_curr.Job
              AND jot_prev.Act_Run_Qty > 0
        ) THEN 'YES - Previous production exists (Repeat)'
        ELSE 'NO - No previous production (First Run)'
    END AS Has_Previous_Production,
    
    -- List previous jobs
    (SELECT TOP 5 CAST(j_prev.Job AS VARCHAR(10)) + ', '
     FROM THURO.dbo.Job j_prev
     WHERE j_prev.Part_Number = j_curr.Part_Number
       AND j_prev.Job < j_curr.Job
     ORDER BY j_prev.Job DESC
     FOR XML PATH(''), TYPE
    ).value('.', 'NVARCHAR(MAX)') AS Previous_Jobs_List,
    
    -- List previous jobs WITH production
    (SELECT TOP 5 CAST(j_prev.Job AS VARCHAR(10)) + '(' + CAST(SUM(jot_prev.Act_Run_Qty) AS VARCHAR(10)) + '), '
     FROM THURO.dbo.Job j_prev
     INNER JOIN THURO.dbo.Job_Operation jo_prev ON j_prev.Job = jo_prev.Job
     INNER JOIN THURO.dbo.Job_Operation_Time jot_prev ON jo_prev.Job_Operation = jot_prev.Job_Operation
     WHERE j_prev.Part_Number = j_curr.Part_Number
       AND j_prev.Job < j_curr.Job
       AND jot_prev.Act_Run_Qty > 0
     GROUP BY j_prev.Job
     ORDER BY j_prev.Job DESC
     FOR XML PATH(''), TYPE
    ).value('.', 'NVARCHAR(MAX)') AS Previous_Jobs_With_Production

FROM @JobsToCheck jtc
    INNER JOIN THURO.dbo.Job j_curr ON jtc.Job = j_curr.Job

ORDER BY j_curr.Job

-- ========================================================================
-- PART 6: SIDE-BY-SIDE COMPARISON
-- Easy visual comparison of all jobs
-- ========================================================================
SELECT 
    'SIDE-BY-SIDE COMPARISON' AS Section,
    j.Job,
    
    -- Allowed dept ops?
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM THURO.dbo.Job_Operation jo
            INNER JOIN THURO.dbo.Work_Center w ON jo.Work_Center = w.Work_Center
            WHERE jo.Job = j.Job
              AND w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
              AND w.Work_Center != 'SM SETUPM'
        ) THEN 'YES'
        ELSE 'NO'
    END AS Has_Allowed_Ops,
    
    -- Recent activity?
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
        ) THEN 'YES'
        ELSE 'NO'
    END AS Has_Recent_Activity,
    
    -- Previous production?
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM THURO.dbo.Job j_hist
            INNER JOIN THURO.dbo.Job_Operation jo_hist ON j_hist.Job = jo_hist.Job
            INNER JOIN THURO.dbo.Job_Operation_Time jot_hist ON jo_hist.Job_Operation = jot_hist.Job_Operation
            WHERE j_hist.Part_Number = j.Part_Number
                AND j_hist.Job < j.Job
                AND jot_hist.Act_Run_Qty > 0
        ) THEN 'YES (Repeat)'
        ELSE 'NO (First Run)'
    END AS Previous_Production,
    
    -- Final result
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM THURO.dbo.Job_Operation jo_check
            INNER JOIN THURO.dbo.Work_Center w_check ON jo_check.Work_Center = w_check.Work_Center
            INNER JOIN THURO.dbo.Job_Operation_Time jot_check ON jo_check.Job_Operation = jot_check.Job_Operation
            WHERE jo_check.Job = j.Job
              AND w_check.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
              AND w_check.Work_Center != 'SM SETUPM'
              AND jot_check.Work_Date >= DATEADD(DAY, -7, GETDATE())
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
-- INSTRUCTIONS:
-- 
-- 1. ENTER YOUR JOB NUMBERS at the top (lines 14-18)
-- 2. Run the entire query
-- 3. Look at the results in order:
--    - Part 1: Quick summary (shows which show, which don't, and why)
--    - Part 2: Detailed pass/fail for each check
--    - Part 3: What departments each job uses
--    - Part 4: Every operation detail
--    - Part 5: Previous production history
--    - Part 6: Side-by-side comparison (easy to see differences)
--
-- MOST USEFUL PARTS:
-- - Part 1: Quick answer to "why is this job not showing?"
-- - Part 3: See which departments are ALLOWED vs EXCLUDED
-- - Part 6: Easy visual comparison of YES/NO for each filter
--
-- TO ADD MORE JOBS:
-- Just add more SELECT statements at the top:
-- SELECT 'JOBNUM' UNION ALL
-- ========================================================================
