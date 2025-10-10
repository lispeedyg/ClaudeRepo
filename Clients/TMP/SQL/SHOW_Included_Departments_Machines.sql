-- ========================================================================
-- SHOW WHAT'S INCLUDED: Departments, Operations, and Machines
-- Based on vw_MachineStatus_GG filters
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
-- PART 2: INCLUDED Departments Detail
-- All machines in the ALLOWED departments
-- ========================================================================
SELECT 
    'INCLUDED DEPARTMENTS' AS Section,
    
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
    w.Description AS Machine_Description,
    
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
-- PART 3: EXCLUDED Departments Detail
-- All machines in the EXCLUDED departments
-- ========================================================================
SELECT 
    'EXCLUDED DEPARTMENTS' AS Section,
    ISNULL(w.Department, 'NULL') AS Department,
    w.Work_Center AS Machine,
    w.Description AS Machine_Description,
    
    -- Why excluded?
    CASE 
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
  AND (w.Department NOT IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
       OR w.Department IS NULL)

ORDER BY 
    ISNULL(w.Department, 'NULL'),
    w.Work_Center

-- ========================================================================
-- PART 4: Operation Types by Department
-- Shows what kind of operations happen in each department
-- ========================================================================
SELECT 
    'OPERATION TYPES' AS Section,
    w.Department,
    
    CASE 
        WHEN w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
        THEN 'INCLUDED'
        ELSE 'EXCLUDED'
    END AS Filter_Status,
    
    jo.Operation_Service,
    COUNT(DISTINCT jo.Job_Operation) AS Num_Operations,
    COUNT(DISTINCT jo.Job) AS Num_Jobs

FROM THURO.dbo.Job_Operation jo
    INNER JOIN THURO.dbo.Work_Center w ON jo.Work_Center = w.Work_Center
    INNER JOIN THURO.dbo.Job j ON jo.Job = j.Job

WHERE w.Status = 1
  AND w.UVText1 = 'MStatusQry'
  AND j.Status NOT IN ('Complete', 'Closed', 'Shipped')

GROUP BY w.Department, jo.Operation_Service

ORDER BY 
    CASE WHEN w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing') THEN 0 ELSE 1 END,
    w.Department,
    COUNT(DISTINCT jo.Job_Operation) DESC

-- ========================================================================
-- PART 5: Summary Statistics
-- Quick overview of included vs excluded
-- ========================================================================
SELECT 
    'SUMMARY' AS Section,
    
    -- Total work centers
    COUNT(DISTINCT w.Work_Center) AS Total_Machines,
    
    -- Included work centers
    SUM(CASE 
        WHEN w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
        THEN 1 ELSE 0 
    END) AS Machines_Included,
    
    -- Excluded work centers
    SUM(CASE 
        WHEN w.Department NOT IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
        OR w.Department IS NULL
        THEN 1 ELSE 0 
    END) AS Machines_Excluded,
    
    -- Unique departments
    COUNT(DISTINCT w.Department) AS Total_Departments,
    
    -- Included departments
    COUNT(DISTINCT CASE 
        WHEN w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
        THEN w.Department 
    END) AS Depts_Included,
    
    -- Excluded departments
    COUNT(DISTINCT CASE 
        WHEN w.Department NOT IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
        OR w.Department IS NULL
        THEN ISNULL(w.Department, 'NULL')
    END) AS Depts_Excluded

FROM THURO.dbo.Work_Center w

WHERE w.Status = 1
  AND w.UVText1 = 'MStatusQry'

-- ========================================================================
-- PART 6: The Filter Definition (for reference)
-- Shows the exact filter from vw_MachineStatus_GG
-- ========================================================================
SELECT 
    'FILTER DEFINITION' AS Section,
    '
    ===== INCLUDED DEPARTMENTS (will show in First Run report) =====
    1. Swiss
    2. Turning
    3. Multis (Multi-Spindle)
    4. Milling
    5. Grinding
    6. Deburring
    7. Washing
    
    ===== ADDITIONAL FILTERS =====
    - Only work centers with Status = 1 (active)
    - Only work centers with UVText1 = ''MStatusQry''
    - Only jobs with activity in last 7 days
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
    
    These excluded departments are typically support operations,
    not primary production departments.
    ' AS Filter_Explanation

-- ========================================================================
-- INSTRUCTIONS:
-- 
-- PART 1: Shows all departments (INCLUDED vs EXCLUDED)
-- PART 2: Lists all machines in INCLUDED departments
-- PART 3: Lists all machines in EXCLUDED departments  
-- PART 4: Shows operation types in each department
-- PART 5: Summary statistics
-- PART 6: The actual filter definition (reference)
--
-- TO EXPORT TO EXCEL:
-- 1. Run this query
-- 2. For each result table, press Ctrl+A then Ctrl+C
-- 3. Paste into Excel
-- 4. Part 2 shows what WILL appear in First Run
-- 5. Part 3 shows what WON'T appear in First Run
-- ========================================================================
