-- ========================================================================
-- SPECIFIC COMPARISON: Jobs 1317286 vs 1317620
-- Both in Q8 DEBURR - why does only one show?
-- ========================================================================

USE [THURO]
GO

-- ========================================================================
-- PART 1: THE KEY DIFFERENCE - What's different between these jobs?
-- ========================================================================
SELECT 
    '⭐ KEY DIFFERENCE ⭐' AS Section,
    j.Job,
    j.Part_Number,
    j.Customer,
    
    -- Check 1: What is the ACTUAL department name?
    (SELECT DISTINCT w.Department
     FROM THURO.dbo.Job_Operation jo
     INNER JOIN THURO.dbo.Work_Center w ON jo.Work_Center = w.Work_Center
     WHERE jo.Job = j.Job
       AND w.Work_Center = 'Q8 DEBURR'
    ) AS Q8_DEBURR_Department_Name,
    
    -- Check 2: Is this department in the ALLOWED list?
    CASE 
        WHEN (SELECT DISTINCT w.Department
              FROM THURO.dbo.Job_Operation jo
              INNER JOIN THURO.dbo.Work_Center w ON jo.Work_Center = w.Work_Center
              WHERE jo.Job = j.Job AND w.Work_Center = 'Q8 DEBURR'
             ) IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
        THEN '✓ YES - In allowed list'
        ELSE '✗ NO - NOT in allowed list'
    END AS Is_Q8_Department_Allowed,
    
    -- Check 3: Does it have operations in OTHER allowed departments?
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM THURO.dbo.Job_Operation jo
            INNER JOIN THURO.dbo.Work_Center w ON jo.Work_Center = w.Work_Center
            WHERE jo.Job = j.Job
              AND w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
              AND w.Work_Center != 'SM SETUPM'
              AND w.Work_Center != 'Q8 DEBURR'  -- Exclude Q8 DEBURR
        ) THEN '✓ YES - Has OTHER allowed dept operations'
        ELSE '✗ NO - Q8 DEBURR is ONLY operation'
    END AS Has_Other_Allowed_Dept_Ops,
    
    -- Check 4: Recent activity on Q8 DEBURR?
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM THURO.dbo.Job_Operation jo
            INNER JOIN THURO.dbo.Job_Operation_Time jot ON jo.Job_Operation = jot.Job_Operation
            WHERE jo.Job = j.Job
              AND jo.Work_Center = 'Q8 DEBURR'
              AND jot.Work_Date >= DATEADD(DAY, -7, GETDATE())
        ) THEN '✓ YES - Recent activity on Q8 DEBURR'
        ELSE '✗ NO - No recent activity on Q8 DEBURR'
    END AS Q8_Recent_Activity,
    
    -- Last activity on Q8 DEBURR
    CONVERT(VARCHAR(10), (
        SELECT MAX(jot.Work_Date)
        FROM THURO.dbo.Job_Operation jo
        INNER JOIN THURO.dbo.Job_Operation_Time jot ON jo.Job_Operation = jot.Job_Operation
        WHERE jo.Job = j.Job
          AND jo.Work_Center = 'Q8 DEBURR'
    ), 101) AS Last_Activity_Q8_DEBURR,
    
    -- Check 5: Recent activity on OTHER allowed departments?
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM THURO.dbo.Job_Operation jo
            INNER JOIN THURO.dbo.Work_Center w ON jo.Work_Center = w.Work_Center
            INNER JOIN THURO.dbo.Job_Operation_Time jot ON jo.Job_Operation = jot.Job_Operation
            WHERE jo.Job = j.Job
              AND w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
              AND w.Work_Center != 'SM SETUPM'
              AND w.Work_Center != 'Q8 DEBURR'
              AND jot.Work_Date >= DATEADD(DAY, -7, GETDATE())
        ) THEN '✓ YES - Recent activity in OTHER allowed depts'
        ELSE '✗ NO - No recent activity in other allowed depts'
    END AS Other_Dept_Recent_Activity,
    
    -- THE MAIN REASON
    CASE 
        WHEN NOT EXISTS (
            SELECT 1 FROM THURO.dbo.Job_Operation jo
            INNER JOIN THURO.dbo.Work_Center w ON jo.Work_Center = w.Work_Center
            WHERE jo.Job = j.Job
              AND w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
              AND w.Work_Center != 'SM SETUPM'
        ) THEN '❌ Has NO operations in allowed departments (Q8 DEBURR dept name is not "Deburring")'
        
        WHEN NOT EXISTS (
            SELECT 1 
            FROM THURO.dbo.Job_Operation jo
            INNER JOIN THURO.dbo.Work_Center w ON jo.Work_Center = w.Work_Center
            INNER JOIN THURO.dbo.Job_Operation_Time jot ON jo.Job_Operation = jot.Job_Operation
            WHERE jo.Job = j.Job
              AND w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
              AND w.Work_Center != 'SM SETUPM'
              AND jot.Work_Date >= DATEADD(DAY, -7, GETDATE())
        ) THEN '❌ No recent activity (last 7 days) in allowed departments'
        
        ELSE '✅ Should show - has allowed dept ops with recent activity'
    END AS MAIN_REASON

FROM THURO.dbo.Job j
WHERE j.Job IN ('1317286', '1317620')

ORDER BY j.Job

-- ========================================================================
-- PART 2: ALL DEPARTMENTS - What departments does each job touch?
-- ========================================================================
SELECT 
    'ALL DEPARTMENTS' AS Section,
    j.Job,
    w.Department,
    w.Work_Center,
    
    CASE 
        WHEN w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
        THEN '✓ ALLOWED'
        ELSE '✗ EXCLUDED'
    END AS Filter_Status,
    
    COUNT(DISTINCT jo.Job_Operation) AS Num_Operations,
    CONVERT(VARCHAR(10), MAX(jot.Work_Date), 101) AS Last_Activity,
    
    CASE 
        WHEN MAX(jot.Work_Date) >= DATEADD(DAY, -7, GETDATE()) THEN '✓ Recent (last 7 days)'
        WHEN MAX(jot.Work_Date) IS NULL THEN '- No activity'
        ELSE '✗ Old (> 7 days ago)'
    END AS Activity_Status

FROM THURO.dbo.Job j
    INNER JOIN THURO.dbo.Job_Operation jo ON j.Job = jo.Job
    INNER JOIN THURO.dbo.Work_Center w ON jo.Work_Center = w.Work_Center
    LEFT JOIN THURO.dbo.Job_Operation_Time jot ON jo.Job_Operation = jot.Job_Operation

WHERE j.Job IN ('1317286', '1317620')

GROUP BY j.Job, w.Department, w.Work_Center

ORDER BY j.Job, w.Work_Center

-- ========================================================================
-- PART 3: Q8 DEBURR SPECIFIC - What's the Work_Center configuration?
-- ========================================================================
SELECT 
    'Q8 DEBURR CONFIG' AS Section,
    w.Work_Center,
    w.Department,
    w.Status,
    w.UVText1,
    
    CASE 
        WHEN w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
        THEN '✓ Department IS in allowed list'
        ELSE '✗ Department NOT in allowed list: "' + ISNULL(w.Department, 'NULL') + '" != "Deburring"'
    END AS Department_Check

FROM THURO.dbo.Work_Center w
WHERE w.Work_Center = 'Q8 DEBURR'

-- ========================================================================
-- PART 4: OPERATION TIMELINE - When did work happen?
-- ========================================================================
SELECT 
    'ACTIVITY TIMELINE' AS Section,
    j.Job,
    w.Work_Center,
    w.Department,
    jo.Operation_Service,
    jo.Status AS Op_Status,
    
    CONVERT(VARCHAR(10), MIN(jot.Work_Date), 101) AS First_Activity,
    CONVERT(VARCHAR(10), MAX(jot.Work_Date), 101) AS Last_Activity,
    DATEDIFF(DAY, MAX(jot.Work_Date), GETDATE()) AS Days_Since_Last,
    
    SUM(jot.Act_Run_Qty) AS Total_Qty,
    SUM(jot.Act_Run_Hrs) AS Total_Hours,
    
    CASE 
        WHEN MAX(jot.Work_Date) >= DATEADD(DAY, -7, GETDATE()) THEN '✓ Within last 7 days'
        WHEN MAX(jot.Work_Date) >= DATEADD(DAY, -30, GETDATE()) THEN '⚠️ 7-30 days ago'
        ELSE '✗ > 30 days ago'
    END AS Activity_Age

FROM THURO.dbo.Job j
    INNER JOIN THURO.dbo.Job_Operation jo ON j.Job = jo.Job
    INNER JOIN THURO.dbo.Work_Center w ON jo.Work_Center = w.Work_Center
    INNER JOIN THURO.dbo.Job_Operation_Time jot ON jo.Job_Operation = jot.Job_Operation

WHERE j.Job IN ('1317286', '1317620')
  AND jot.Work_Date IS NOT NULL

GROUP BY j.Job, w.Work_Center, w.Department, jo.Operation_Service, jo.Status

ORDER BY j.Job, MAX(jot.Work_Date) DESC

-- ========================================================================
-- PART 5: THE VERDICT - Why does 1317286 show but 1317620 doesn't?
-- ========================================================================
SELECT 
    'THE VERDICT' AS Section,
    '
    ========================================================================
    ANALYSIS: Jobs 1317286 vs 1317620 in Q8 DEBURR
    ========================================================================
    
    LIKELY ISSUE:
    The work center "Q8 DEBURR" has a Department value that is NOT "Deburring"
    
    The view filter looks for:
    w.Department IN (''Swiss'',''Turning'',''Multis'',''Milling'',''Grinding'',''Deburring'',''Washing'')
    
    But Q8 DEBURR might have Department = "Q8 DEBURR" or something else,
    not the exact string "Deburring"
    
    SCENARIOS:
    
    1. If Q8 DEBURR Department = "Q8 DEBURR" (NOT "Deburring"):
       - Jobs ONLY in Q8 DEBURR will be EXCLUDED
       - Jobs that ALSO have operations in other allowed depts will SHOW
       
    2. Job 1317286 shows because:
       - It likely has operations in OTHER allowed departments (Milling, Turning, etc.)
       - Those operations have recent activity
       
    3. Job 1317620 does NOT show because:
       - It ONLY has Q8 DEBURR operation (excluded dept)
       - OR: It has no recent activity in any allowed departments
    
    SOLUTION:
    Look at Part 3 above to see Q8 DEBURR''s actual Department value
    Look at Part 2 to see what OTHER departments each job uses
    
    If Q8 DEBURR should be included, you need to either:
    A) Add its Department value to the allowed list in the view, OR
    B) Change Q8 DEBURR''s Department field to "Deburring"
    ========================================================================
    ' AS Explanation

-- ========================================================================
-- INSTRUCTIONS:
-- 
-- 1. Run this query
-- 2. Look at PART 1 first - it shows the key differences
-- 3. Look at PART 3 - this shows Q8 DEBURR's actual Department value
-- 4. Look at PART 2 - this shows if jobs have OTHER department operations
--
-- KEY QUESTION TO ANSWER:
-- Does Job 1317286 have operations in OTHER allowed departments besides Q8 DEBURR?
-- Does Job 1317620 ONLY have Q8 DEBURR (and no other allowed dept operations)?
--
-- That's likely the difference!
-- ========================================================================
