-- ========================================================================
-- COMPARISON: Jobs showing vs not showing in First Run Report
-- 
-- Job 1317611 (Part 4400172) - IS on 1st Run Report
-- Job 1317286 (Part 8605993-1) - IS on 1st Run Report
-- Job 1317538 (Part 8580464-1) - NOT on 1st Run Report
-- 
-- Purpose: Identify why some jobs show and others don't
-- ========================================================================

USE [THURO]
GO

-- ========================================================================
-- PART 1: Side-by-side comparison of the 3 jobs
-- ========================================================================
SELECT 
    'JOB COMPARISON' AS Section,
    j.Job,
    j.Part_Number,
    j.Customer,
    j.Status AS Job_Status,
    
    -- Key Question 1: Do they have operations in ALLOWED departments?
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM THURO.dbo.Job_Operation jo_allowed
            INNER JOIN THURO.dbo.Work_Center w_allowed ON jo_allowed.Work_Center = w_allowed.Work_Center
            WHERE jo_allowed.Job = j.Job
              AND w_allowed.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
              AND w_allowed.Status = 1
              AND w_allowed.UVText1 = 'MStatusQry'
        ) THEN 'YES - Has ops in allowed depts'
        ELSE 'NO - Only in excluded depts'
    END AS Has_Allowed_Dept_Ops,
    
    -- Key Question 2: Do ALLOWED dept operations have recent activity?
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM THURO.dbo.Job_Operation jo_check
            INNER JOIN THURO.dbo.Work_Center w_check ON jo_check.Work_Center = w_check.Work_Center
            INNER JOIN THURO.dbo.Job_Operation_Time jot_check ON jo_check.Job_Operation = jot_check.Job_Operation
            WHERE jo_check.Job = j.Job
              AND w_check.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
              AND jot_check.Work_Date >= DATEADD(DAY, -7, GETDATE())
              AND jot_check.Work_Date IS NOT NULL
              AND jot_check.Last_Updated IS NOT NULL
        ) THEN 'YES - Recent activity in allowed dept'
        ELSE 'NO - No recent activity in allowed dept'
    END AS Allowed_Dept_Has_Recent_Activity,
    
    -- Most recent activity in allowed departments
    (SELECT MAX(jot.Work_Date)
     FROM THURO.dbo.Job_Operation jo
     INNER JOIN THURO.dbo.Work_Center w ON jo.Work_Center = w.Work_Center
     INNER JOIN THURO.dbo.Job_Operation_Time jot ON jo.Job_Operation = jot.Job_Operation
     WHERE jo.Job = j.Job
       AND w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
    ) AS Last_Activity_Allowed_Dept,
    
    -- Most recent activity in ANY department (including excluded)
    (SELECT MAX(jot.Work_Date)
     FROM THURO.dbo.Job_Operation jo
     INNER JOIN THURO.dbo.Job_Operation_Time jot ON jo.Job_Operation = jot.Job_Operation
     WHERE jo.Job = j.Job
    ) AS Last_Activity_Any_Dept,
    
    -- Key Question 3: FirstRun indicator
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM THURO.dbo.Job j_hist
            INNER JOIN THURO.dbo.Job_Operation jo_hist ON j_hist.Job = jo_hist.Job
            INNER JOIN THURO.dbo.Job_Operation_Time jot_hist ON jo_hist.Job_Operation = jot_hist.Job_Operation
            WHERE j_hist.Part_Number = j.Part_Number
                AND j_hist.Job < j.Job
                AND jot_hist.Act_Run_Qty > 0
        ) THEN 'O (Repeat)'
        ELSE 'F (First Run)'
    END AS FirstRun_Indicator,
    
    -- FINAL VERDICT: Should this show in First Run report?
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
        THEN 'YES - Should show in First Run'
        ELSE 'NO - Should NOT show'
    END AS Should_Show_In_FirstRun

FROM THURO.dbo.Job j

WHERE j.Job IN ('1317611', '1317286', '1317538')

-- ========================================================================
-- PART 2: Detailed operation breakdown for each job
-- Show which operations are in allowed vs excluded departments
-- ========================================================================
SELECT 
    'OPERATION DETAILS' AS Section,
    j.Job,
    jo.Sequence,
    jo.Work_Center,
    w.Department,
    jo.Operation_Service,
    jo.Status AS Op_Status,
    
    -- Is this an allowed department?
    CASE 
        WHEN w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
        THEN 'ALLOWED'
        ELSE 'EXCLUDED'
    END AS Dept_Status,
    
    -- Does this operation have recent activity?
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM THURO.dbo.Job_Operation_Time jot_check
            WHERE jot_check.Job_Operation = jo.Job_Operation
              AND jot_check.Work_Date >= DATEADD(DAY, -7, GETDATE())
              AND jot_check.Work_Date IS NOT NULL
              AND jot_check.Last_Updated IS NOT NULL
        ) THEN 'YES'
        ELSE 'NO'
    END AS Has_Recent_Activity,
    
    -- Last activity date
    (SELECT MAX(jot.Work_Date)
     FROM THURO.dbo.Job_Operation_Time jot
     WHERE jot.Job_Operation = jo.Job_Operation
    ) AS Last_Activity_Date,
    
    -- Total quantity produced
    (SELECT SUM(jot.Act_Run_Qty)
     FROM THURO.dbo.Job_Operation_Time jot
     WHERE jot.Job_Operation = jo.Job_Operation
    ) AS Total_Qty_Produced,
    
    -- Would this operation be included in the view?
    CASE 
        WHEN w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
             AND w.Status = 1
             AND w.UVText1 = 'MStatusQry'
             AND EXISTS (
                SELECT 1 
                FROM THURO.dbo.Job_Operation_Time jot_check
                WHERE jot_check.Job_Operation = jo.Job_Operation
                  AND jot_check.Work_Date >= DATEADD(DAY, -7, GETDATE())
                  AND jot_check.Work_Date IS NOT NULL
                  AND jot_check.Last_Updated IS NOT NULL
            )
        THEN 'WOULD BE IN VIEW'
        ELSE 'EXCLUDED FROM VIEW'
    END AS View_Inclusion_Status

FROM THURO.dbo.Job j
    INNER JOIN THURO.dbo.Job_Operation jo ON j.Job = jo.Job
    INNER JOIN THURO.dbo.Work_Center w ON jo.Work_Center = w.Work_Center

WHERE j.Job IN ('1317611', '1317286', '1317538')

ORDER BY j.Job, jo.Sequence

-- ========================================================================
-- PART 3: Check if these jobs are actually in the view
-- ========================================================================
SELECT 
    'VIEW CHECK' AS Section,
    Machine,
    CustomerPartJob,
    MachineStatus,
    Department,
    DeptMachine,
    StatusDuration,
    ProgressDisplay

FROM THURO.dbo.vw_MachineStatus_GG

WHERE CustomerPartJob LIKE '%1317611%'
   OR CustomerPartJob LIKE '%1317286%'
   OR CustomerPartJob LIKE '%1317538%'

-- ========================================================================
-- PART 4: WHY is job 1317538 excluded?
-- Specific analysis for the job that's NOT showing
-- ========================================================================
SELECT 
    'WHY 1317538 EXCLUDED' AS Section,
    
    -- Check 1: Does it have ANY operations in allowed departments?
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM THURO.dbo.Job_Operation jo
            INNER JOIN THURO.dbo.Work_Center w ON jo.Work_Center = w.Work_Center
            WHERE jo.Job = '1317538'
              AND w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
        ) THEN 'PASS - Has operations in allowed departments'
        ELSE 'FAIL - Only has operations in excluded departments'
    END AS Check_Has_Allowed_Dept,
    
    -- Check 2: Do those allowed operations have recent activity?
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM THURO.dbo.Job_Operation jo
            INNER JOIN THURO.dbo.Work_Center w ON jo.Work_Center = w.Work_Center
            INNER JOIN THURO.dbo.Job_Operation_Time jot ON jo.Job_Operation = jot.Job_Operation
            WHERE jo.Job = '1317538'
              AND w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
              AND jot.Work_Date >= DATEADD(DAY, -7, GETDATE())
              AND jot.Work_Date IS NOT NULL
              AND jot.Last_Updated IS NOT NULL
        ) THEN 'PASS - Has recent activity in allowed dept'
        ELSE 'FAIL - No recent activity in allowed dept'
    END AS Check_Recent_Activity_Allowed,
    
    -- THE KEY EXCLUSION REASON
    CASE 
        WHEN NOT EXISTS (
            SELECT 1 FROM THURO.dbo.Job_Operation jo
            INNER JOIN THURO.dbo.Work_Center w ON jo.Work_Center = w.Work_Center
            WHERE jo.Job = '1317538'
              AND w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
        ) THEN 'EXCLUDED: Job has NO operations in allowed departments (Swiss, Turning, Multis, Milling, Grinding, Deburring, Washing)'
        
        WHEN NOT EXISTS (
            SELECT 1 
            FROM THURO.dbo.Job_Operation jo
            INNER JOIN THURO.dbo.Work_Center w ON jo.Work_Center = w.Work_Center
            INNER JOIN THURO.dbo.Job_Operation_Time jot ON jo.Job_Operation = jot.Job_Operation
            WHERE jo.Job = '1317538'
              AND w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
              AND jot.Work_Date >= DATEADD(DAY, -7, GETDATE())
              AND jot.Work_Date IS NOT NULL
              AND jot.Last_Updated IS NOT NULL
        ) THEN 'EXCLUDED: Job has operations in allowed depts but NO RECENT activity (last 7 days) in those depts'
        
        ELSE 'Should be included (has allowed dept + recent activity)'
    END AS Exclusion_Reason

-- ========================================================================
-- PART 5: List of departments used by each job
-- ========================================================================
SELECT 
    'DEPARTMENTS USED' AS Section,
    j.Job,
    w.Department,
    COUNT(DISTINCT jo.Job_Operation) AS Num_Operations,
    
    -- Is this department allowed?
    CASE 
        WHEN w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
        THEN 'ALLOWED'
        ELSE 'EXCLUDED'
    END AS Dept_Status,
    
    -- Recent activity in this department?
    MAX(jot.Work_Date) AS Last_Activity_Date

FROM THURO.dbo.Job j
    INNER JOIN THURO.dbo.Job_Operation jo ON j.Job = jo.Job
    INNER JOIN THURO.dbo.Work_Center w ON jo.Work_Center = w.Work_Center
    LEFT JOIN THURO.dbo.Job_Operation_Time jot ON jo.Job_Operation = jot.Job_Operation

WHERE j.Job IN ('1317611', '1317286', '1317538')

GROUP BY j.Job, w.Department

ORDER BY j.Job, 
    CASE WHEN w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing') THEN 0 ELSE 1 END,
    w.Department

-- ========================================================================
-- PART 6: Summary
-- ========================================================================
SELECT 
    'SUMMARY' AS Section,
    '
    Based on the analysis above:
    
    Jobs 1317611 and 1317286 ARE showing because:
    - They have operations in ALLOWED departments AND
    - Those operations have recent activity (last 7 days)
    
    Job 1317538 is NOT showing because:
    - It only has operations in EXCLUDED departments, OR
    - Its operations in allowed depts have no recent activity
    
    Common excluded departments:
    - NULL
    - 411 NEW PART
    - Assembly
    - Engineering
    - In Process Insp
    - Q8 DEBURR
    - R8 INSPECT
    - TOOL MAINT
    - FIRST RUN
    - 1ST RUN SU
    - AS ASSY
    - DAILY STRT
    - OPER IPS
    
    THE FIX:
    Look at Part 2 and Part 5 to see exactly which departments each job uses.
    If job 1317538 SHOULD be showing, you may need to add its departments
    to the allowed list in the view.
    ' AS Explanation

-- ========================================================================
-- INSTRUCTIONS:
-- 1. Run all 6 parts
-- 2. Part 1: High-level comparison (MOST IMPORTANT - shows yes/no for each check)
-- 3. Part 2: Every operation breakdown
-- 4. Part 3: Are they in the view?
-- 5. Part 4: Why 1317538 is excluded
-- 6. Part 5: Which departments each job uses
-- 7. Part 6: Summary explanation
-- ========================================================================
