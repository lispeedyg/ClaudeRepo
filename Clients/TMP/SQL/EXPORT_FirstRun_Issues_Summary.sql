-- ========================================================================
-- EXPORT: Just the relevant First Run issues for analysis
-- Purpose: Extract minimal data needed to diagnose the problem
-- ========================================================================

USE [THURO]
GO

-- ========================================================================
-- OPTION 1: Show ONLY jobs that PASS all checks (appear in First Run)
-- These are the ones showing in your dashboard
-- ========================================================================
SELECT TOP 50  -- Limit to 50 most recent
    'JOBS IN FIRST RUN REPORT' AS Issue_Type,
    j.Job,
    j.Part_Number,
    j.Customer,
    w.Work_Center AS Machine,
    w.Department,
    
    -- When was last activity?
    (SELECT MAX(jot.Work_Date)
     FROM THURO.dbo.Job_Operation jo_act
     INNER JOIN THURO.dbo.Job_Operation_Time jot ON jo_act.Job_Operation = jot.Job_Operation
     WHERE jo_act.Job = j.Job
       AND jo_act.Work_Center = w.Work_Center
    ) AS Last_Activity_Date,
    
    -- Does it have previous production? (This is the KEY question)
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM THURO.dbo.Job j_hist
            INNER JOIN THURO.dbo.Job_Operation jo_hist ON j_hist.Job = jo_hist.Job
            INNER JOIN THURO.dbo.Job_Operation_Time jot_hist ON jo_hist.Job_Operation = jot_hist.Job_Operation
            WHERE j_hist.Part_Number = j.Part_Number
                AND j_hist.Job < j.Job
                AND jot_hist.Act_Run_Qty > 0
        ) THEN 'HAS PREVIOUS - Should be O not F'
        ELSE 'NO PREVIOUS - Correctly F'
    END AS Previous_Production_Status,
    
    -- Show the previous job(s) if they exist
    (SELECT TOP 1 CAST(j_prev.Job AS VARCHAR(20))
     FROM THURO.dbo.Job j_prev
     INNER JOIN THURO.dbo.Job_Operation jo_prev ON j_prev.Job = jo_prev.Job
     INNER JOIN THURO.dbo.Job_Operation_Time jot_prev ON jo_prev.Job_Operation = jot_prev.Job_Operation
     WHERE j_prev.Part_Number = j.Part_Number
       AND j_prev.Job < j.Job
       AND jot_prev.Act_Run_Qty > 0
     ORDER BY j_prev.Job DESC
    ) AS Most_Recent_Previous_Job,
    
    -- How much was produced in previous job?
    (SELECT SUM(jot_prev.Act_Run_Qty)
     FROM THURO.dbo.Job j_prev
     INNER JOIN THURO.dbo.Job_Operation jo_prev ON j_prev.Job = jo_prev.Job
     INNER JOIN THURO.dbo.Job_Operation_Time jot_prev ON jo_prev.Job_Operation = jot_prev.Job_Operation
     WHERE j_prev.Part_Number = j.Part_Number
       AND j_prev.Job < j.Job
    ) AS Total_Previous_Production

FROM THURO.dbo.Job j
    INNER JOIN THURO.dbo.Job_Operation jo ON j.Job = jo.Job
    INNER JOIN THURO.dbo.Work_Center w ON jo.Work_Center = w.Work_Center

WHERE 
    -- Only jobs that PASS all filters (these are showing in First Run report)
    w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
    AND j.Status NOT IN ('Complete', 'Closed', 'Shipped')
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

ORDER BY 
    Last_Activity_Date DESC,
    j.Job DESC

-- ========================================================================
-- OPTION 2: Show jobs with POTENTIAL issues (simplified)
-- Look for common patterns that cause problems
-- ========================================================================
SELECT TOP 50
    'POTENTIAL ISSUE' AS Issue_Type,
    j.Job,
    j.Part_Number,
    j.Customer,
    w.Work_Center AS Machine,
    w.Department,
    
    -- What's the issue?
    CASE 
        -- Issue 1: Previous jobs exist but in wrong department
        WHEN EXISTS (
            SELECT 1 
            FROM THURO.dbo.Job j_prev
            INNER JOIN THURO.dbo.Job_Operation jo_prev ON j_prev.Job = jo_prev.Job
            INNER JOIN THURO.dbo.Job_Operation_Time jot_prev ON jo_prev.Job_Operation = jot_prev.Job_Operation
            INNER JOIN THURO.dbo.Work_Center w_prev ON jo_prev.Work_Center = w_prev.Work_Center
            WHERE j_prev.Part_Number = j.Part_Number
              AND j_prev.Job < j.Job
              AND jot_prev.Act_Run_Qty > 0
              AND w_prev.Department NOT IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
        ) THEN 'Previous production in EXCLUDED department'
        
        -- Issue 2: Previous jobs exist but no recent production
        WHEN EXISTS (
            SELECT 1 
            FROM THURO.dbo.Job j_prev
            INNER JOIN THURO.dbo.Job_Operation jo_prev ON j_prev.Job = jo_prev.Job
            INNER JOIN THURO.dbo.Job_Operation_Time jot_prev ON jo_prev.Job_Operation = jot_prev.Job_Operation
            WHERE j_prev.Part_Number = j.Part_Number
              AND j_prev.Job < j.Job
              AND jot_prev.Act_Run_Qty > 0
              AND jot_prev.Work_Date < DATEADD(DAY, -30, GETDATE())
        ) THEN 'Previous production more than 30 days ago'
        
        ELSE 'Unknown issue'
    END AS Issue_Description,
    
    -- Show previous jobs in excluded departments
    (SELECT TOP 3 
        CAST(j_prev.Job AS VARCHAR(10)) + '(' + w_prev.Department + ')' + ', '
     FROM THURO.dbo.Job j_prev
     INNER JOIN THURO.dbo.Job_Operation jo_prev ON j_prev.Job = jo_prev.Job
     INNER JOIN THURO.dbo.Job_Operation_Time jot_prev ON jo_prev.Job_Operation = jot_prev.Job_Operation
     INNER JOIN THURO.dbo.Work_Center w_prev ON jo_prev.Work_Center = w_prev.Work_Center
     WHERE j_prev.Part_Number = j.Part_Number
       AND j_prev.Job < j.Job
       AND jot_prev.Act_Run_Qty > 0
     ORDER BY j_prev.Job DESC
     FOR XML PATH('')
    ) AS Previous_Jobs_With_Depts

FROM THURO.dbo.Job j
    INNER JOIN THURO.dbo.Job_Operation jo ON j.Job = jo.Job
    INNER JOIN THURO.dbo.Work_Center w ON jo.Work_Center = w.Work_Center

WHERE 
    -- Jobs that pass all filters BUT have potential issues
    w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
    AND j.Status NOT IN ('Complete', 'Closed', 'Shipped')
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
    -- Has some previous production somewhere
    AND EXISTS (
        SELECT 1 
        FROM THURO.dbo.Job j_prev
        INNER JOIN THURO.dbo.Job_Operation jo_prev ON j_prev.Job = jo_prev.Job
        INNER JOIN THURO.dbo.Job_Operation_Time jot_prev ON jo_prev.Job_Operation = jot_prev.Job_Operation
        WHERE j_prev.Part_Number = j.Part_Number
          AND j_prev.Job < j.Job
          AND jot_prev.Act_Run_Qty > 0
    )

ORDER BY j.Job DESC

-- ========================================================================
-- OPTION 3: Specific jobs from your screenshot (010, 010-020)
-- ========================================================================
SELECT 
    'SPECIFIC JOBS FROM SCREENSHOT' AS Issue_Type,
    j.Job,
    j.Part_Number,
    j.Customer,
    w.Work_Center AS Machine,
    w.Department,
    jo.Operation_Service,
    jo.Status AS Op_Status,
    
    -- All the key checks
    CASE 
        WHEN w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
        THEN 'PASS' ELSE 'FAIL'
    END AS Check_Dept,
    
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM THURO.dbo.Job_Operation jo_check
            INNER JOIN THURO.dbo.Job_Operation_Time jot_check ON jo_check.Job_Operation = jot_check.Job_Operation
            WHERE jo_check.Job = j.Job
              AND jot_check.Work_Date >= DATEADD(DAY, -7, GETDATE())
        ) THEN 'PASS' ELSE 'FAIL'
    END AS Check_Activity,
    
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM THURO.dbo.Job j_hist
            INNER JOIN THURO.dbo.Job_Operation jo_hist ON j_hist.Job = jo_hist.Job
            INNER JOIN THURO.dbo.Job_Operation_Time jot_hist ON jo_hist.Job_Operation = jot_hist.Job_Operation
            WHERE j_hist.Part_Number = j.Part_Number
                AND j_hist.Job < j.Job
                AND jot_hist.Act_Run_Qty > 0
        ) THEN 'FAIL (has previous)' ELSE 'PASS (no previous)'
    END AS Check_FirstRun,
    
    -- Show previous jobs for this part
    STUFF((
        SELECT ', ' + CAST(j_prev.Job AS VARCHAR(10))
        FROM THURO.dbo.Job j_prev
        WHERE j_prev.Part_Number = j.Part_Number
          AND j_prev.Job < j.Job
        ORDER BY j_prev.Job
        FOR XML PATH(''), TYPE
    ).value('.', 'NVARCHAR(MAX)'), 1, 2, '') AS All_Previous_Jobs,
    
    -- Which had production?
    STUFF((
        SELECT ', ' + CAST(j_prev.Job AS VARCHAR(10)) + '(' + CAST(SUM(jot_prev.Act_Run_Qty) AS VARCHAR(10)) + ')'
        FROM THURO.dbo.Job j_prev
        INNER JOIN THURO.dbo.Job_Operation jo_prev ON j_prev.Job = jo_prev.Job
        INNER JOIN THURO.dbo.Job_Operation_Time jot_prev ON jo_prev.Job_Operation = jot_prev.Job_Operation
        WHERE j_prev.Part_Number = j.Part_Number
          AND j_prev.Job < j.Job
          AND jot_prev.Act_Run_Qty > 0
        GROUP BY j_prev.Job
        ORDER BY j_prev.Job
        FOR XML PATH(''), TYPE
    ).value('.', 'NVARCHAR(MAX)'), 1, 2, '') AS Previous_Jobs_With_Production

FROM THURO.dbo.Job j
    INNER JOIN THURO.dbo.Job_Operation jo ON j.Job = jo.Job
    INNER JOIN THURO.dbo.Work_Center w ON jo.Work_Center = w.Work_Center

WHERE 
    -- Look for the specific patterns from your screenshot
    (j.Job LIKE '%010%' OR j.Job = '010' OR j.Job = '010-020'
     OR j.Customer LIKE '%CHAMPAERO%' OR j.Customer LIKE '%BAE%')
    AND j.Status NOT IN ('Complete', 'Closed', 'Shipped')

ORDER BY j.Job, jo.Sequence

-- ========================================================================
-- INSTRUCTIONS FOR SHARING DATA:
-- 
-- Run ONE of these three options:
-- 
-- Option 1: Shows all jobs currently in First Run report (top 50)
--           Best for: "These jobs ARE showing but SHOULDN'T be"
-- 
-- Option 2: Shows jobs with potential issues (top 50)
--           Best for: Finding patterns in the data
-- 
-- Option 3: Shows specific jobs from your screenshot
--           Best for: Focused analysis of known problem jobs
-- 
-- TO SHARE WITH ME:
-- 1. Run Option 1 or Option 3 (start with Option 3 for specific jobs)
-- 2. Right-click the results → "Save Results As..." → CSV
-- 3. Or just copy the first 10-20 rows and paste into chat
-- 4. Focus on the columns:
--    - Job, Part_Number, Customer, Machine, Department
--    - Previous_Production_Status
--    - Most_Recent_Previous_Job
--    - The Check_* columns
-- 
-- I need to see:
-- - Which jobs are showing in First Run that have previous production
-- - What departments the previous production was in
-- - The pattern of why FirstRun logic is not detecting the previous work
-- ========================================================================
