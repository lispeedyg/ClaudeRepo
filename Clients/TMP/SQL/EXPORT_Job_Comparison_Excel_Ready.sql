-- ========================================================================
-- EXCEL-READY EXPORT: Job Comparison Results
-- All results formatted for easy export to Excel/CSV
-- ========================================================================

USE [THURO]
GO

SET NOCOUNT ON

-- ========================================================================
-- TABLE 1: Job Comparison Summary (Main Results)
-- Copy this directly to Excel
-- ========================================================================
SELECT 
    j.Job,
    j.Part_Number,
    j.Customer,
    j.Status AS Job_Status,
    
    -- Check 1: Has operations in allowed departments?
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM THURO.dbo.Job_Operation jo_allowed
            INNER JOIN THURO.dbo.Work_Center w_allowed ON jo_allowed.Work_Center = w_allowed.Work_Center
            WHERE jo_allowed.Job = j.Job
              AND w_allowed.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
              AND w_allowed.Status = 1
              AND w_allowed.UVText1 = 'MStatusQry'
        ) THEN 'YES'
        ELSE 'NO'
    END AS Has_Allowed_Dept_Ops,
    
    -- Check 2: Recent activity in allowed departments?
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
        ) THEN 'YES'
        ELSE 'NO'
    END AS Has_Recent_Activity,
    
    -- Last activity in allowed departments
    CONVERT(VARCHAR(10), (
        SELECT MAX(jot.Work_Date)
        FROM THURO.dbo.Job_Operation jo
        INNER JOIN THURO.dbo.Work_Center w ON jo.Work_Center = w.Work_Center
        INNER JOIN THURO.dbo.Job_Operation_Time jot ON jo.Job_Operation = jot.Job_Operation
        WHERE jo.Job = j.Job
          AND w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
    ), 101) AS Last_Activity_Allowed,
    
    -- Last activity in any department
    CONVERT(VARCHAR(10), (
        SELECT MAX(jot.Work_Date)
        FROM THURO.dbo.Job_Operation jo
        INNER JOIN THURO.dbo.Job_Operation_Time jot ON jo.Job_Operation = jot.Job_Operation
        WHERE jo.Job = j.Job
    ), 101) AS Last_Activity_Any,
    
    -- Check 3: FirstRun indicator
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM THURO.dbo.Job j_hist
            INNER JOIN THURO.dbo.Job_Operation jo_hist ON j_hist.Job = jo_hist.Job
            INNER JOIN THURO.dbo.Job_Operation_Time jot_hist ON jo_hist.Job_Operation = jot_hist.Job_Operation
            WHERE j_hist.Part_Number = j.Part_Number
                AND j_hist.Job < j.Job
                AND jot_hist.Act_Run_Qty > 0
        ) THEN 'O-Repeat'
        ELSE 'F-FirstRun'
    END AS FirstRun_Status,
    
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
        THEN 'SHOULD SHOW'
        ELSE 'SHOULD NOT SHOW'
    END AS Shows_In_FirstRun

FROM THURO.dbo.Job j
WHERE j.Job IN ('1317611', '1317286', '1317538')
ORDER BY j.Job

-- ========================================================================
-- TABLE 2: Departments Used by Each Job
-- Shows which departments are ALLOWED vs EXCLUDED
-- ========================================================================
SELECT 
    j.Job,
    j.Part_Number,
    w.Department,
    COUNT(DISTINCT jo.Job_Operation) AS Num_Operations,
    
    CASE 
        WHEN w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
        THEN 'ALLOWED'
        ELSE 'EXCLUDED'
    END AS Dept_Filter_Status,
    
    CONVERT(VARCHAR(10), MAX(jot.Work_Date), 101) AS Last_Activity

FROM THURO.dbo.Job j
    INNER JOIN THURO.dbo.Job_Operation jo ON j.Job = jo.Job
    INNER JOIN THURO.dbo.Work_Center w ON jo.Work_Center = w.Work_Center
    LEFT JOIN THURO.dbo.Job_Operation_Time jot ON jo.Job_Operation = jot.Job_Operation

WHERE j.Job IN ('1317611', '1317286', '1317538')

GROUP BY j.Job, j.Part_Number, w.Department

ORDER BY 
    j.Job,
    CASE WHEN w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing') THEN 0 ELSE 1 END,
    w.Department

-- ========================================================================
-- TABLE 3: Operation-Level Detail
-- Every operation for each job
-- ========================================================================
SELECT 
    j.Job,
    jo.Sequence AS Op_Seq,
    jo.Work_Center AS Machine,
    w.Department,
    jo.Operation_Service,
    jo.Status AS Op_Status,
    
    CASE 
        WHEN w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
        THEN 'ALLOWED'
        ELSE 'EXCLUDED'
    END AS Dept_Status,
    
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM THURO.dbo.Job_Operation_Time jot_check
            WHERE jot_check.Job_Operation = jo.Job_Operation
              AND jot_check.Work_Date >= DATEADD(DAY, -7, GETDATE())
              AND jot_check.Work_Date IS NOT NULL
        ) THEN 'YES'
        ELSE 'NO'
    END AS Recent_Activity,
    
    CONVERT(VARCHAR(10), (
        SELECT MAX(jot.Work_Date)
        FROM THURO.dbo.Job_Operation_Time jot
        WHERE jot.Job_Operation = jo.Job_Operation
    ), 101) AS Last_Activity_Date,
    
    (SELECT SUM(jot.Act_Run_Qty)
     FROM THURO.dbo.Job_Operation_Time jot
     WHERE jot.Job_Operation = jo.Job_Operation
    ) AS Total_Qty_Produced

FROM THURO.dbo.Job j
    INNER JOIN THURO.dbo.Job_Operation jo ON j.Job = jo.Job
    INNER JOIN THURO.dbo.Work_Center w ON jo.Work_Center = w.Work_Center

WHERE j.Job IN ('1317611', '1317286', '1317538')

ORDER BY j.Job, jo.Sequence

-- ========================================================================
-- TABLE 4: Quick Summary - Why Each Job Shows or Doesn't Show
-- ========================================================================
SELECT 
    j.Job,
    j.Part_Number,
    
    CASE 
        WHEN NOT EXISTS (
            SELECT 1 FROM THURO.dbo.Job_Operation jo
            INNER JOIN THURO.dbo.Work_Center w ON jo.Work_Center = w.Work_Center
            WHERE jo.Job = j.Job
              AND w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
        ) THEN 'No operations in allowed departments'
        
        WHEN NOT EXISTS (
            SELECT 1 
            FROM THURO.dbo.Job_Operation jo
            INNER JOIN THURO.dbo.Work_Center w ON jo.Work_Center = w.Work_Center
            INNER JOIN THURO.dbo.Job_Operation_Time jot ON jo.Job_Operation = jot.Job_Operation
            WHERE jo.Job = j.Job
              AND w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
              AND jot.Work_Date >= DATEADD(DAY, -7, GETDATE())
        ) THEN 'Has allowed dept ops but no recent activity'
        
        WHEN EXISTS (
            SELECT 1 
            FROM THURO.dbo.Job j_hist
            INNER JOIN THURO.dbo.Job_Operation jo_hist ON j_hist.Job = jo_hist.Job
            INNER JOIN THURO.dbo.Job_Operation_Time jot_hist ON jo_hist.Job_Operation = jot_hist.Job_Operation
            WHERE j_hist.Part_Number = j.Part_Number
                AND j_hist.Job < j.Job
                AND jot_hist.Act_Run_Qty > 0
        ) THEN 'Has previous production - not a first run'
        
        ELSE 'Passes all checks - should show'
    END AS Reason

FROM THURO.dbo.Job j
WHERE j.Job IN ('1317611', '1317286', '1317538')
ORDER BY j.Job

-- ========================================================================
-- INSTRUCTIONS FOR EXPORTING TO EXCEL:
-- 
-- METHOD 1 - Direct Copy (Recommended):
-- 1. Run this entire query
-- 2. Click on the first result grid (Table 1)
-- 3. Press Ctrl+A (select all)
-- 4. Press Ctrl+C (copy)
-- 5. Open Excel
-- 6. Press Ctrl+V (paste)
-- 7. Repeat for each table/result grid
--
-- METHOD 2 - Save As CSV:
-- 1. Run the query
-- 2. Right-click on each result grid
-- 3. Select "Save Results As..."
-- 4. Save as .csv
-- 5. Open in Excel
--
-- METHOD 3 - Export to Single File:
-- 1. In SSMS, go to: Query → Results To → Results to File
-- 2. Run the query
-- 3. Choose location and filename
-- 4. Opens as grid format file (.rpt)
-- 5. Can open in Notepad and format as needed
--
-- TIPS:
-- - Table 1 is the MAIN summary - this is what you want to focus on
-- - Table 2 shows which departments each job uses
-- - Table 3 shows every single operation
-- - Table 4 is a simple plain-English explanation
-- 
-- For a document/report, copy Table 1 and Table 4 - they tell the story!
-- ========================================================================
