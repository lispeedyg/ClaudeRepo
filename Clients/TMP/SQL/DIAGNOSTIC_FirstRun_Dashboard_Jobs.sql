-- ========================================================================
-- DIAGNOSTIC: Why are specific jobs showing in First Run report?
-- Purpose: Identify why Job 010 and 010-020 appear in dashboard
-- SIMPLIFIED VERSION - No nested aggregates
-- ========================================================================

USE [THURO]
GO

-- ========================================================================
-- PART 1: Direct check - Are these jobs in the view?
-- ========================================================================
SELECT 
    'VIEW OUTPUT CHECK' AS Section,
    Machine,
    Department,
    DeptMachine,
    CustomerPartJob,
    JobDueDtStatus,
    OperationDetails,
    MachineStatus,
    ProgressDisplay,
    RunQty,
    RequiredQty,
    PercentComplete
FROM THURO.dbo.vw_MachineStatus_GG
WHERE 
    -- Look for the specific jobs from your screenshot
    (CustomerPartJob LIKE '%010%' OR CustomerPartJob LIKE '%010-020%')
    -- Only jobs that would show in First Run tab
    AND MachineStatus LIKE '%F%'  -- Has FirstRun indicator
ORDER BY Machine

-- ========================================================================
-- PART 2: Raw data check - What do these jobs look like?
-- ========================================================================
SELECT 
    'RAW JOB DATA' AS Section,
    j.Job,
    j.Part_Number,
    j.Customer,
    j.Status AS Job_Status,
    w.Work_Center AS Machine,
    w.Department AS Dept_Code,
    
    -- Department name mapping (from your view)
    CASE w.Department
        WHEN 'Swiss' THEN '01-Swiss'
        WHEN 'Turning' THEN '02-Turng'
        WHEN 'Milling' THEN '03-Milng'
        WHEN 'Multis' THEN '04-MSpnd'
        WHEN 'Grinding' THEN '05-Grnd'
        WHEN 'Deburring' THEN '06-Dburr'
        WHEN 'Washing' THEN '07-Wshng'
        ELSE w.Department
    END AS Dept_Name_Mapped,
    
    -- Check: Is this department in the allowed list?
    CASE 
        WHEN w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
        THEN 'YES - In allowed dept list'
        ELSE 'NO - Dept: ' + w.Department
    END AS Dept_Filter_Status,
    
    jo.Operation_Service,
    jo.Status AS Op_Status

FROM THURO.dbo.Job j
    INNER JOIN THURO.dbo.Job_Operation jo ON j.Job = jo.Job
    INNER JOIN THURO.dbo.Work_Center w ON jo.Work_Center = w.Work_Center
    
WHERE 
    (j.Job LIKE '%010%' OR j.Job = '010' OR j.Job = '010-020')
    AND j.Status NOT IN ('Complete', 'Closed', 'Shipped')
    AND w.Status = 1 
    AND w.UVText1 = 'MStatusQry'
    
ORDER BY j.Job, jo.Sequence

-- ========================================================================
-- PART 3: FirstRun check - Is it F or O?
-- ========================================================================
SELECT 
    'FIRSTRUN INDICATOR' AS Section,
    j.Job,
    j.Part_Number,
    j.Customer,
    w.Work_Center,
    
    -- Check: FirstRun indicator
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM THURO.dbo.Job j_hist
            INNER JOIN THURO.dbo.Job_Operation jo_hist ON j_hist.Job = jo_hist.Job
            INNER JOIN THURO.dbo.Job_Operation_Time jot_hist ON jo_hist.Job_Operation = jot_hist.Job_Operation
            WHERE j_hist.Part_Number = j.Part_Number
                AND j_hist.Job < j.Job  -- Previous job
                AND jot_hist.Act_Run_Qty > 0  -- Had production
        ) THEN 'O (Repeat/Old) - Will NOT show in First Run'
        ELSE 'F (First Run) - Will show in First Run'
    END AS RunIndicator_Status

FROM THURO.dbo.Job j
    INNER JOIN THURO.dbo.Job_Operation jo ON j.Job = jo.Job
    INNER JOIN THURO.dbo.Work_Center w ON jo.Work_Center = w.Work_Center
    
WHERE 
    (j.Job LIKE '%010%' OR j.Job = '010' OR j.Job = '010-020')
    AND j.Status NOT IN ('Complete', 'Closed', 'Shipped')

ORDER BY j.Job, w.Work_Center

-- ========================================================================
-- PART 4: Activity check - Recent 7 days
-- ========================================================================
SELECT 
    'RECENT ACTIVITY CHECK' AS Section,
    j.Job,
    j.Part_Number,
    w.Work_Center,
    
    -- Would this be excluded by the 7-day activity filter?
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM THURO.dbo.Job_Operation jo_check
            INNER JOIN THURO.dbo.Job_Operation_Time jot_check ON jo_check.Job_Operation = jot_check.Job_Operation
            WHERE jo_check.Job = j.Job
              AND jo_check.Work_Center = w.Work_Center
              AND jot_check.Work_Date >= DATEADD(DAY, -7, GETDATE())
              AND jot_check.Work_Date IS NOT NULL
              AND jot_check.Last_Updated IS NOT NULL
        ) THEN 'YES - Has recent activity (last 7 days)'
        ELSE 'NO - No activity in last 7 days - EXCLUDED'
    END AS Activity_Filter_Status,
    
    -- Show the actual last activity date
    (SELECT MAX(jot.Work_Date)
     FROM THURO.dbo.Job_Operation jo_act
     INNER JOIN THURO.dbo.Job_Operation_Time jot ON jo_act.Job_Operation = jot.Job_Operation
     WHERE jo_act.Job = j.Job
       AND jo_act.Work_Center = w.Work_Center
    ) AS Last_Work_Date

FROM THURO.dbo.Job j
    INNER JOIN THURO.dbo.Job_Operation jo ON j.Job = jo.Job
    INNER JOIN THURO.dbo.Work_Center w ON jo.Work_Center = w.Work_Center
    
WHERE 
    (j.Job LIKE '%010%' OR j.Job = '010' OR j.Job = '010-020')
    AND j.Status NOT IN ('Complete', 'Closed', 'Shipped')

ORDER BY j.Job, w.Work_Center

-- ========================================================================
-- PART 5: Complete Pass/Fail Analysis
-- ========================================================================
SELECT 
    'COMPLETE ANALYSIS' AS Section,
    j.Job,
    j.Part_Number,
    j.Customer,
    w.Work_Center,
    w.Department,
    
    -- Check 1: Department filter
    CASE 
        WHEN w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
        THEN 'PASS'
        ELSE 'FAIL'
    END AS Check1_Dept_Filter,
    
    -- Check 2: Activity in last 7 days
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM THURO.dbo.Job_Operation jo_check
            INNER JOIN THURO.dbo.Job_Operation_Time jot_check ON jo_check.Job_Operation = jot_check.Job_Operation
            WHERE jo_check.Job = j.Job
              AND jo_check.Work_Center = w.Work_Center
              AND jot_check.Work_Date >= DATEADD(DAY, -7, GETDATE())
              AND jot_check.Work_Date IS NOT NULL
              AND jot_check.Last_Updated IS NOT NULL
        ) THEN 'PASS'
        ELSE 'FAIL'
    END AS Check2_Recent_Activity,
    
    -- Check 3: Job status
    CASE 
        WHEN (j.Status NOT IN ('Complete', 'Closed', 'Shipped') 
              OR j.Status_Date >= DATEADD(DAY, -1, GETDATE()))
        THEN 'PASS'
        ELSE 'FAIL'
    END AS Check3_Job_Status,
    
    -- Check 4: FirstRun indicator
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM THURO.dbo.Job j_hist
            INNER JOIN THURO.dbo.Job_Operation jo_hist ON j_hist.Job = jo_hist.Job
            INNER JOIN THURO.dbo.Job_Operation_Time jot_hist ON jo_hist.Job_Operation = jot_hist.Job_Operation
            WHERE j_hist.Part_Number = j.Part_Number
                AND j_hist.Job < j.Job
                AND jot_hist.Act_Run_Qty > 0
        ) THEN 'FAIL (Repeat)'
        ELSE 'PASS (First Run)'
    END AS Check4_FirstRun,
    
    -- Final verdict
    CASE 
        WHEN w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
             AND EXISTS (
                SELECT 1 
                FROM THURO.dbo.Job_Operation jo_check
                INNER JOIN THURO.dbo.Job_Operation_Time jot_check ON jo_check.Job_Operation = jot_check.Job_Operation
                WHERE jo_check.Job = j.Job
                  AND jo_check.Work_Center = w.Work_Center
                  AND jot_check.Work_Date >= DATEADD(DAY, -7, GETDATE())
                  AND jot_check.Work_Date IS NOT NULL
                  AND jot_check.Last_Updated IS NOT NULL
            )
             AND (j.Status NOT IN ('Complete', 'Closed', 'Shipped') 
                  OR j.Status_Date >= DATEADD(DAY, -1, GETDATE()))
             AND NOT EXISTS (
                SELECT 1 
                FROM THURO.dbo.Job j_hist
                INNER JOIN THURO.dbo.Job_Operation jo_hist ON j_hist.Job = jo_hist.Job
                INNER JOIN THURO.dbo.Job_Operation_Time jot_hist ON jo_hist.Job_Operation = jot_hist.Job_Operation
                WHERE j_hist.Part_Number = j.Part_Number
                    AND j_hist.Job < j.Job
                    AND jot_hist.Act_Run_Qty > 0
            )
        THEN 'YES - WILL SHOW in First Run'
        ELSE 'NO - Will not show'
    END AS Final_Verdict

FROM THURO.dbo.Job j
    INNER JOIN THURO.dbo.Job_Operation jo ON j.Job = jo.Job
    INNER JOIN THURO.dbo.Work_Center w ON jo.Work_Center = w.Work_Center

WHERE (j.Job LIKE '%010%' OR j.Job = '010' OR j.Job = '010-020')

ORDER BY j.Job, w.Work_Center

-- ========================================================================
-- PART 6: Previous Production History (if any)
-- ========================================================================
SELECT 
    'PREVIOUS PRODUCTION' AS Section,
    j_curr.Job AS Current_Job,
    j_curr.Part_Number,
    j_prev.Job AS Previous_Job,
    jo_prev.Work_Center,
    jo_prev.Operation_Service,
    jot_prev.Work_Date AS Production_Date,
    jot_prev.Act_Run_Qty AS Qty_Produced,
    DATEDIFF(DAY, jot_prev.Work_Date, GETDATE()) AS Days_Ago

FROM THURO.dbo.Job j_curr
    INNER JOIN THURO.dbo.Job j_prev ON j_prev.Part_Number = j_curr.Part_Number
        AND j_prev.Job < j_curr.Job
    INNER JOIN THURO.dbo.Job_Operation jo_prev ON j_prev.Job = jo_prev.Job
    INNER JOIN THURO.dbo.Job_Operation_Time jot_prev ON jo_prev.Job_Operation = jot_prev.Job_Operation

WHERE (j_curr.Job LIKE '%010%' OR j_curr.Job = '010' OR j_curr.Job = '010-020')
    AND j_curr.Status NOT IN ('Complete', 'Closed', 'Shipped')
    AND jot_prev.Act_Run_Qty > 0

ORDER BY j_curr.Job, j_prev.Job, jot_prev.Work_Date DESC

-- ========================================================================
-- PART 7: Simple Summary Counts (using temp table to avoid aggregates)
-- ========================================================================

-- Create temp table with job flags
SELECT 
    j.Job,
    j.Part_Number,
    w.Work_Center,
    w.Department,
    
    -- Flag 1: Dept filter
    CASE 
        WHEN w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
        THEN 1 ELSE 0
    END AS Passes_Dept_Filter,
    
    -- Flag 2: Recent activity
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM THURO.dbo.Job_Operation jo_check
            INNER JOIN THURO.dbo.Job_Operation_Time jot_check ON jo_check.Job_Operation = jot_check.Job_Operation
            WHERE jo_check.Job = j.Job
              AND jo_check.Work_Center = w.Work_Center
              AND jot_check.Work_Date >= DATEADD(DAY, -7, GETDATE())
              AND jot_check.Work_Date IS NOT NULL
              AND jot_check.Last_Updated IS NOT NULL
        ) THEN 1 ELSE 0
    END AS Has_Recent_Activity,
    
    -- Flag 3: FirstRun
    CASE 
        WHEN NOT EXISTS (
            SELECT 1 
            FROM THURO.dbo.Job j_hist
            INNER JOIN THURO.dbo.Job_Operation jo_hist ON j_hist.Job = jo_hist.Job
            INNER JOIN THURO.dbo.Job_Operation_Time jot_hist ON jo_hist.Job_Operation = jot_hist.Job_Operation
            WHERE j_hist.Part_Number = j.Part_Number
                AND j_hist.Job < j.Job
                AND jot_hist.Act_Run_Qty > 0
        ) THEN 1 ELSE 0
    END AS Is_FirstRun,
    
    -- Flag 4: All pass
    CASE 
        WHEN w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
             AND EXISTS (
                SELECT 1 
                FROM THURO.dbo.Job_Operation jo_check
                INNER JOIN THURO.dbo.Job_Operation_Time jot_check ON jo_check.Job_Operation = jot_check.Job_Operation
                WHERE jo_check.Job = j.Job
                  AND jo_check.Work_Center = w.Work_Center
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
        THEN 1 ELSE 0
    END AS Passes_All_Checks

INTO #JobFlags

FROM THURO.dbo.Job j
    INNER JOIN THURO.dbo.Job_Operation jo ON j.Job = jo.Job
    INNER JOIN THURO.dbo.Work_Center w ON jo.Work_Center = w.Work_Center

WHERE (j.Job LIKE '%010%' OR j.Job = '010' OR j.Job = '010-020')
    AND j.Status NOT IN ('Complete', 'Closed', 'Shipped')

-- Now do simple aggregates on the temp table
SELECT 
    'SUMMARY COUNTS' AS Section,
    COUNT(DISTINCT Job) AS Total_Jobs,
    SUM(Passes_Dept_Filter) AS Passing_Dept_Filter,
    SUM(Has_Recent_Activity) AS With_Recent_Activity,
    SUM(Is_FirstRun) AS Marked_FirstRun,
    SUM(Passes_All_Checks) AS Should_Show_In_Report

FROM #JobFlags

-- Clean up
DROP TABLE #JobFlags

-- ========================================================================
-- INSTRUCTIONS:
-- 1. Run all parts in sequence
-- 2. Part 1: Check if these jobs appear in the view
-- 3. Parts 2-4: Individual filter checks
-- 4. Part 5: Complete pass/fail analysis
-- 5. Part 6: Shows any previous production history
-- 6. Part 7: Summary counts
-- ========================================================================
