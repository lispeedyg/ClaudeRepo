-- ========================================================================
-- SHOW WHAT'S INCLUDED: Departments, Operations, and Machines
-- Based on vw_MachineStatus_GG filters
-- FIXED: Removed Description column references
-- ========================================================================

USE [THURO]
GO

-- ========================================================================
-- PART 1: ALLOWED vs EXCLUDED Departments
-- Shows which departments are included in the view
-- ========================================================================
SELECT 
    'DEPARTMENT FILTER' AS Section,
    w.Department,
    COUNT(DISTINCT w.Work_Center) AS Num_Machines,
    
    -- Is this department in the filter?
    CASE 
        WHEN w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
        THEN '✓ INCLUDED in First Run view'
        ELSE '✗ EXCLUDED from First Run view'
    END AS Filter_Status,
    
    -- Is it a production or support department?
    CASE 
        WHEN w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
        THEN 'Production'
        WHEN w.Department LIKE '%INSPECT%' OR w.Department LIKE '%INSP%'
        THEN 'Inspection'
        WHEN w.Department LIKE '%ASSY%' OR w.Department = 'Assembly'
        THEN 'Assembly'
        WHEN w.Department LIKE '%SETUP%' OR w.Department LIKE '%1ST RUN%' OR w.Department LIKE '%FIRST RUN%'
        THEN 'Setup/First Run'
        WHEN w.Department IS NULL OR w.Department = ''
        THEN 'No Department'
        ELSE 'Support/Other'
    END AS Dept_Type

FROM THURO.dbo.Work_Center w

WHERE w.Status = 1  -- Active work centers only
  AND w.UVText1 = 'MStatusQry'  -- Work centers in machine status query

GROUP BY w.Department

ORDER BY 
    CASE WHEN w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing') THEN 0 ELSE 1 END,
    w.Department

-- ========================================================================
-- PART 2: OPERATION FILTER OVERVIEW
-- Shows which operations are included vs excluded
-- ========================================================================
SELECT 
    'OPERATION FILTER' AS Section,
    jo.Operation_Service,
    w.Work_Center,
    
    -- Is this operation included?
    CASE 
        WHEN w.Work_Center = 'SM SETUPM' 
        THEN '✗ EXCLUDED - Setup operation (SM SETUPM)'
        WHEN w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
        THEN '✓ INCLUDED - Production operation'
        ELSE '✗ EXCLUDED - Not in production dept'
    END AS Filter_Status,
    
    w.Department,
    COUNT(DISTINCT jo.Job) AS Active_Jobs_With_This_Op

FROM THURO.dbo.Job_Operation jo
    INNER JOIN THURO.dbo.Work_Center w ON jo.Work_Center = w.Work_Center
    INNER JOIN THURO.dbo.Job j ON jo.Job = j.Job

WHERE w.Status = 1
  AND w.UVText1 = 'MStatusQry'
  AND j.Status NOT IN ('Complete', 'Closed', 'Shipped')

GROUP BY jo.Operation_Service, w.Work_Center, w.Department

ORDER BY 
    CASE 
        WHEN w.Work_Center = 'SM SETUPM' THEN 2
        WHEN w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing') THEN 0 
        ELSE 1 
    END,
    COUNT(DISTINCT jo.Job) DESC

-- ========================================================================
-- PART 3: INCLUDED OPERATIONS BY DEPARTMENT
-- Shows which operations are used in ALLOWED departments
-- ========================================================================
SELECT 
    'INCLUDED OPERATIONS BY DEPT' AS Section,
    
    CASE w.Department
        WHEN 'Swiss' THEN '01-Swiss'
        WHEN 'Turning' THEN '02-Turng'
        WHEN 'Milling' THEN '03-Milng'
        WHEN 'Multis' THEN '04-MSpnd'
        WHEN 'Grinding' THEN '05-Grnd'
        WHEN 'Deburring' THEN '06-Dburr'
        WHEN 'Washing' THEN '07-Wshng'
    END AS Department_Display,
    
    jo.Operation_Service,
    COUNT(DISTINCT w.Work_Center) AS Num_Machines,
    COUNT(DISTINCT jo.Job) AS Active_Jobs

FROM THURO.dbo.Job_Operation jo
    INNER JOIN THURO.dbo.Work_Center w ON jo.Work_Center = w.Work_Center
    INNER JOIN THURO.dbo.Job j ON jo.Job = j.Job

WHERE w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
  AND w.Status = 1
  AND w.UVText1 = 'MStatusQry'
  AND j.Status NOT IN ('Complete', 'Closed', 'Shipped')
  AND w.Work_Center != 'SM SETUPM'  -- Exclude setup operations

GROUP BY w.Department, jo.Operation_Service

ORDER BY 
    CASE w.Department
        WHEN 'Swiss' THEN 1
        WHEN 'Turning' THEN 2
        WHEN 'Milling' THEN 3
        WHEN 'Multis' THEN 4
        WHEN 'Grinding' THEN 5
        WHEN 'Deburring' THEN 6
        WHEN 'Washing' THEN 7
    END,
    COUNT(DISTINCT jo.Job) DESC

-- ========================================================================
-- PART 4: EXCLUDED OPERATIONS
-- Shows operations that are filtered out
-- ========================================================================
SELECT 
    'EXCLUDED OPERATIONS' AS Section,
    jo.Operation_Service,
    w.Work_Center,
    ISNULL(w.Department, 'NULL') AS Department,
    
    -- Why is it excluded?
    CASE 
        WHEN w.Work_Center = 'SM SETUPM'
        THEN 'Setup operation (explicitly excluded in view)'
        WHEN w.Department IS NULL OR w.Department = ''
        THEN 'No department assigned'
        WHEN w.Department NOT IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
        THEN 'Not in production department list'
        ELSE 'Other'
    END AS Exclusion_Reason,
    
    COUNT(DISTINCT jo.Job) AS Active_Jobs

FROM THURO.dbo.Job_Operation jo
    INNER JOIN THURO.dbo.Work_Center w ON jo.Work_Center = w.Work_Center
    INNER JOIN THURO.dbo.Job j ON jo.Job = j.Job

WHERE w.Status = 1
  AND w.UVText1 = 'MStatusQry'
  AND j.Status NOT IN ('Complete', 'Closed', 'Shipped')
  AND (w.Work_Center = 'SM SETUPM' 
       OR w.Department NOT IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
       OR w.Department IS NULL)

GROUP BY jo.Operation_Service, w.Work_Center, w.Department

ORDER BY 
    CASE WHEN w.Work_Center = 'SM SETUPM' THEN 0 ELSE 1 END,
    COUNT(DISTINCT jo.Job) DESC

-- ========================================================================
-- PART 5: INCLUDED DEPARTMENTS & MACHINES
-- All machines in the ALLOWED departments
-- ========================================================================
SELECT 
    'INCLUDED DEPARTMENTS & MACHINES' AS Section,
    
    -- Department with friendly name
    CASE w.Department
        WHEN 'Swiss' THEN '01-Swiss'
        WHEN 'Turning' THEN '02-Turng'
        WHEN 'Milling' THEN '03-Milng'
        WHEN 'Multis' THEN '04-MSpnd'
        WHEN 'Grinding' THEN '05-Grnd'
        WHEN 'Deburring' THEN '06-Dburr'
        WHEN 'Washing' THEN '07-Wshng'
        ELSE w.Department
    END AS Department_Display,
    
    w.Department AS Raw_Dept_Code,
    w.Work_Center AS Machine,
    
    -- How many active jobs on this machine?
    (SELECT COUNT(DISTINCT jo.Job)
     FROM THURO.dbo.Job_Operation jo
     INNER JOIN THURO.dbo.Job j ON jo.Job = j.Job
     WHERE jo.Work_Center = w.Work_Center
       AND j.Status NOT IN ('Complete', 'Closed', 'Shipped')
    ) AS Active_Jobs,
    
    -- Any recent activity?
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM THURO.dbo.Job_Operation jo
            INNER JOIN THURO.dbo.Job_Operation_Time jot ON jo.Job_Operation = jot.Job_Operation
            WHERE jo.Work_Center = w.Work_Center
              AND jot.Work_Date >= DATEADD(DAY, -7, GETDATE())
        ) THEN 'YES - Recent activity'
        ELSE 'NO - Idle'
    END AS Recent_Activity_7Days

FROM THURO.dbo.Work_Center w

WHERE w.Status = 1
  AND w.UVText1 = 'MStatusQry'
  AND w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
  AND w.Work_Center != 'SM SETUPM'  -- Exclude setup

ORDER BY 
    CASE w.Department
        WHEN 'Swiss' THEN 1
        WHEN 'Turning' THEN 2
        WHEN 'Milling' THEN 3
        WHEN 'Multis' THEN 4
        WHEN 'Grinding' THEN 5
        WHEN 'Deburring' THEN 6
        WHEN 'Washing' THEN 7
        ELSE 99
    END,
    w.Work_Center

-- ========================================================================
-- PART 6: EXCLUDED DEPARTMENTS & MACHINES
-- All machines in the EXCLUDED departments
-- ========================================================================
SELECT 
    'EXCLUDED DEPARTMENTS & MACHINES' AS Section,
    ISNULL(w.Department, 'NULL') AS Department,
    w.Work_Center AS Machine,
    
    -- Why excluded?
    CASE 
        WHEN w.Work_Center = 'SM SETUPM'
        THEN 'Setup machine (explicitly excluded)'
        WHEN w.Department IS NULL OR w.Department = ''
        THEN 'No department assigned'
        WHEN w.Department LIKE '%INSPECT%' OR w.Department LIKE '%INSP%'
        THEN 'Inspection dept'
        WHEN w.Department LIKE '%ASSY%' OR w.Department = 'Assembly'
        THEN 'Assembly dept'
        WHEN w.Department LIKE '%SETUP%' OR w.Department LIKE '%1ST RUN%' OR w.Department LIKE '%FIRST RUN%'
        THEN 'Setup/staging dept'
        WHEN w.Department LIKE '%411 NEW PART%'
        THEN 'New part setup dept'
        ELSE 'Not in production dept list'
    END AS Exclusion_Reason,
    
    -- How many active jobs?
    (SELECT COUNT(DISTINCT jo.Job)
     FROM THURO.dbo.Job_Operation jo
     INNER JOIN THURO.dbo.Job j ON jo.Job = j.Job
     WHERE jo.Work_Center = w.Work_Center
       AND j.Status NOT IN ('Complete', 'Closed', 'Shipped')
    ) AS Active_Jobs

FROM THURO.dbo.Work_Center w

WHERE w.Status = 1
  AND w.UVText1 = 'MStatusQry'
  AND (w.Work_Center = 'SM SETUPM'
       OR w.Department NOT IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
       OR w.Department IS NULL)

ORDER BY 
    CASE WHEN w.Work_Center = 'SM SETUPM' THEN 0 ELSE 1 END,
    ISNULL(w.Department, 'NULL'),
    w.Work_Center

-- ========================================================================
-- PART 7: SUMMARY STATISTICS
-- Quick overview of included vs excluded
-- ========================================================================
SELECT 
    'SUMMARY STATISTICS' AS Section,
    
    -- Work Centers
    COUNT(DISTINCT w.Work_Center) AS Total_Machines,
    SUM(CASE 
        WHEN w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
        AND w.Work_Center != 'SM SETUPM'
        THEN 1 ELSE 0 
    END) AS Machines_Included,
    SUM(CASE 
        WHEN w.Work_Center = 'SM SETUPM'
        OR w.Department NOT IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
        OR w.Department IS NULL
        THEN 1 ELSE 0 
    END) AS Machines_Excluded,
    
    -- Departments
    COUNT(DISTINCT w.Department) AS Total_Departments,
    COUNT(DISTINCT CASE 
        WHEN w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
        THEN w.Department 
    END) AS Depts_Included,
    COUNT(DISTINCT CASE 
        WHEN w.Department NOT IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
        OR w.Department IS NULL
        THEN ISNULL(w.Department, 'NULL')
    END) AS Depts_Excluded

FROM THURO.dbo.Work_Center w

WHERE w.Status = 1
  AND w.UVText1 = 'MStatusQry'

-- ========================================================================
-- PART 8: COMPLETE FILTER DEFINITION
-- Shows the exact filter from vw_MachineStatus_GG
-- ========================================================================
SELECT 
    'COMPLETE FILTER DEFINITION' AS Section,
    '
    ===== INCLUDED DEPARTMENTS (will show in First Run report) =====
    1. Swiss
    2. Turning
    3. Multis (Multi-Spindle)
    4. Milling
    5. Grinding
    6. Deburring
    7. Washing
    
    ===== EXCLUDED OPERATIONS/WORK CENTERS =====
    - SM SETUPM (Setup operations - explicitly excluded in WHERE clause)
    
    ===== ADDITIONAL FILTERS =====
    - Only work centers with Status = 1 (active)
    - Only work centers with UVText1 = ''MStatusQry''
    - Only operations with activity in last 7 days
    - Only jobs NOT in status: Complete, Closed, Shipped
    - Only jobs marked as First Run (F) - no previous production
    
    ===== COMMON EXCLUDED DEPARTMENTS =====
    - NULL (no department assigned)
    - 411 NEW PART (new part setup)
    - Assembly / AS ASSY
    - In Process Insp / R8 INSPECT / RB INSPECT
    - Engineering / ENGRELEA
    - FIRST RUN / 1ST RUN SU (staging)
    - Q8 DEBURR
    - TOOL MAINT
    - DAILY STRT
    - OPER IPS
    
    ===== KEY LOGIC =====
    For a job to appear in First Run report, it must have:
    1. At least one operation in an INCLUDED department (Swiss through Washing)
    2. That operation must NOT be in SM SETUPM work center
    3. That operation must have activity in the last 7 days
    4. The job must be marked as First Run (F) - meaning NO previous 
       production history exists for that part number
    
    If a job ONLY has operations in excluded departments (like 411 NEW PART,
    Assembly, Inspection, etc.), it will NOT appear in the First Run report.
    ' AS Filter_Explanation

-- ========================================================================
-- INSTRUCTIONS:
-- 
-- PART 1: All departments (INCLUDED vs EXCLUDED)
-- PART 2: Operations filter overview (shows Operation_Service)
-- PART 3: Operations by INCLUDED department (shows what ops are in production depts)
-- PART 4: EXCLUDED operations (shows what ops are filtered out)
-- PART 5: Machines in INCLUDED departments
-- PART 6: Machines in EXCLUDED departments
-- PART 7: Summary statistics
-- PART 8: Complete filter definition (reference)
--
-- TO EXPORT TO EXCEL:
-- 1. Run this query
-- 2. For each result table, press Ctrl+A then Ctrl+C
-- 3. Paste into Excel
-- 
-- KEY PARTS FOR UNDERSTANDING FILTERS:
-- - Part 2: Shows which operations are included vs excluded
-- - Part 3: Shows what operations are actually used in production departments
-- - Part 4: Shows what operations are filtered out (like SM SETUPM)
-- - Part 5: Shows all machines that WILL appear in First Run report
-- ========================================================================
