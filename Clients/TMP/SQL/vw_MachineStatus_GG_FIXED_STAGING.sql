USE [THURO]
GO

/****** Object:  View [dbo].[vw_MachineStatus_GG]    Script Date: 10/5/2025 - FIXED STAGING LOGIC ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO





-- Uncomment this line to implement as a view:
--ALTER VIEW [dbo].[vw_MachineStatus_GG] AS

--COMPLETION PREDICTION CTE - ORIGINAL UNCHANGED
WITH 
-- NEW: FirstRun Identifier - Check if part number has been run before
FirstRunIdentifier AS (
    SELECT DISTINCT
        j.Job,
        j.Part_Number,
        CASE 
            WHEN EXISTS (
                SELECT 1 
                FROM THURO.dbo.Job j_hist with (NoLock)
                INNER JOIN THURO.dbo.Job_Operation jo_hist with (NoLock) ON j_hist.Job = jo_hist.Job
                INNER JOIN THURO.dbo.Job_Operation_Time jot_hist with (NoLock) ON jo_hist.Job_Operation = jot_hist.Job_Operation
                WHERE j_hist.Part_Number = j.Part_Number
                    AND j_hist.Job < j.Job  -- Previous job (lower job number)
                    AND jot_hist.Act_Run_Qty > 0  -- Must have actual production
            ) THEN 'O'  -- Old/Repeat
            ELSE 'F'  -- First Run
        END AS RunIndicator
    FROM THURO.dbo.Job j with (NoLock)
    WHERE j.Status NOT IN ('Complete', 'Closed', 'Shipped')
),

JobCompletionPredictions AS (
    SELECT 
        jo.Job_Operation,
        jo.Job,
        jo.Work_Center,
        jo.Operation_Service,
        jo.Est_Required_Qty AS required_qty,
        
        -- Current progress
        ISNULL(SUM(jot.Act_Run_Qty), 0) AS completed_qty,
        CASE 
            WHEN jo.Est_Required_Qty > ISNULL(SUM(jot.Act_Run_Qty), 0)
            THEN jo.Est_Required_Qty - ISNULL(SUM(jot.Act_Run_Qty), 0)
            ELSE 0
        END AS remaining_qty,
        
        -- Current team performance
        current_operator.operator_name,
        current_operator.recent_parts_per_hour,
        current_operator.days_since_work,
        CASE WHEN current_operator.operator_name IS NOT NULL THEN 1 ELSE 0 END AS operator_assigned,
        
        -- Historical performance for this part/operator combination
        historical_perf.historical_parts_per_hour,
        historical_perf.historical_scrap_rate,
        historical_perf.days_of_experience,
        
        -- COMPLETION PREDICTION CALCULATION
        CASE 
            WHEN jo.Est_Required_Qty <= ISNULL(SUM(jot.Act_Run_Qty), 0) THEN 0  -- Already complete
            WHEN historical_perf.historical_parts_per_hour > 0 
            THEN (jo.Est_Required_Qty - ISNULL(SUM(jot.Act_Run_Qty), 0)) / historical_perf.historical_parts_per_hour
            WHEN current_operator.recent_parts_per_hour > 0 
            THEN (jo.Est_Required_Qty - ISNULL(SUM(jot.Act_Run_Qty), 0)) / current_operator.recent_parts_per_hour
            ELSE NULL
        END AS estimated_hours_remaining,
        
        -- PREDICTION QUALITY SCORE (0-100)
        CASE 
            WHEN historical_perf.days_of_experience >= 10 AND historical_perf.historical_scrap_rate <= 1.0 THEN 95
            WHEN historical_perf.days_of_experience >= 5 AND historical_perf.historical_scrap_rate <= 2.0 THEN 85
            WHEN historical_perf.days_of_experience >= 3 THEN 70
            WHEN current_operator.recent_parts_per_hour > 0 THEN 50
            WHEN current_operator.operator_name IS NOT NULL THEN 30
            ELSE 10
        END AS prediction_confidence
        
    FROM THURO.dbo.Job_Operation jo with (NoLock)
        LEFT JOIN THURO.dbo.Job_Operation_Time jot with (NoLock) ON jo.Job_Operation = jot.Job_Operation
        
        -- Get current primary operator
        LEFT JOIN (
            SELECT 
                jot_curr.Job_Operation,
                e.First_Name + ' ' + e.Last_Name AS operator_name,
                AVG(CASE WHEN jot_curr.Act_Run_Hrs > 0 THEN jot_curr.Act_Run_Qty / jot_curr.Act_Run_Hrs ELSE 0 END) AS recent_parts_per_hour,
                DATEDIFF(DAY, MAX(jot_curr.Last_Updated), GETDATE()) AS days_since_work,
                ROW_NUMBER() OVER (PARTITION BY jot_curr.Job_Operation ORDER BY MAX(jot_curr.Last_Updated) DESC, SUM(jot_curr.Act_Run_Qty) DESC) AS operator_rank
            FROM THURO.dbo.Job_Operation_Time jot_curr with (NoLock)
                INNER JOIN THURO.dbo.Employee e ON jot_curr.Employee = e.Employee
            WHERE jot_curr.Last_Updated >= DATEADD(DAY, -30, GETDATE())
                AND jot_curr.Act_Run_Qty > 0
            GROUP BY jot_curr.Job_Operation, jot_curr.Employee, e.First_Name, e.Last_Name
        ) current_operator ON jo.Job_Operation = current_operator.Job_Operation AND current_operator.operator_rank = 1
        
        -- Get historical performance for this part/operator combination
        LEFT JOIN (
            SELECT 
                jo_hist.Job_Operation,
                emp_hist.Employee,
                AVG(CASE WHEN jot_hist.Act_Run_Hrs > 0 THEN jot_hist.Act_Run_Qty / jot_hist.Act_Run_Hrs ELSE 0 END) AS historical_parts_per_hour,
                CASE 
                    WHEN (SUM(jot_hist.Act_Run_Qty) + SUM(jot_hist.Act_Scrap_Qty)) > 0
                    THEN SUM(jot_hist.Act_Scrap_Qty) * 100.0 / (SUM(jot_hist.Act_Run_Qty) + SUM(jot_hist.Act_Scrap_Qty))
                    ELSE 0
                END AS historical_scrap_rate,
                COUNT(DISTINCT CAST(jot_hist.Last_Updated AS DATE)) AS days_of_experience
            FROM THURO.dbo.Job_Operation jo_hist with (NoLock)
                INNER JOIN THURO.dbo.Job j_hist with (NoLock)ON jo_hist.Job = j_hist.Job
                INNER JOIN THURO.dbo.Job_Operation_Time jot_hist with (NoLock)
				ON jo_hist.Job_Operation = jot_hist.Job_Operation
                INNER JOIN THURO.dbo.Employee emp_hist with (NoLock) ON jot_hist.Employee = emp_hist.Employee
            WHERE jot_hist.Last_Updated >= DATEADD(DAY, -180, GETDATE())  -- 6 months history
                AND jot_hist.Act_Run_Qty > 0
            GROUP BY jo_hist.Job_Operation, emp_hist.Employee, j_hist.Part_Number, jo_hist.Work_Center
        ) historical_perf ON jo.Job_Operation = historical_perf.Job_Operation 
                          AND current_operator.operator_name = (SELECT e.First_Name + ' ' + e.Last_Name FROM THURO.dbo.Employee e WHERE e.Employee = historical_perf.Employee)
    
    WHERE jo.Status NOT IN ('Complete', 'Closed')
        AND jo.Est_Required_Qty > 0
        AND jo.Work_Center != 'SM SETUPM'  -- ONLY ADDITION: Exclude setup operations
    
    GROUP BY jo.Job_Operation, jo.Job, jo.Work_Center, jo.Operation_Service, jo.Est_Required_Qty,
             current_operator.operator_name, current_operator.recent_parts_per_hour, current_operator.days_since_work,
             historical_perf.historical_parts_per_hour, historical_perf.historical_scrap_rate, historical_perf.days_of_experience
),

MachineStatusCTE AS (
    -- PART 1: FIXED STAGING LOGIC + FIRSTRUN INDICATOR + DATA QUALITY FLAGS
    SELECT DISTINCT
            -- Machine/Work Center Info - ORIGINAL UNCHANGED
            w.Work_Center AS Machine,
            ISNULL(dept_names.DeptName, w.Department) AS Department,
            -- ENHANCED: Added operation number to DeptMachine field with leading zeros (no sort prefix in display)
            CONCAT(
                CASE 
                    WHEN dept_names.DeptName IS NOT NULL 
                    THEN SUBSTRING(dept_names.DeptName, 4, LEN(dept_names.DeptName))  -- Remove "01-" prefix for display
                    ELSE w.Department 
                END, 
                ' | ', w.Work_Center, 
                CASE 
                    WHEN current_op.Status = 'C' OR current_op.Operation_Service IS NULL THEN ''
                    ELSE CONCAT(' | ', current_op.Operation_Service)
                END
            ) AS DeptMachine,
            
            -- FIXED: Show STAGING only for machines truly waiting, not completed jobs
            CASE 
                WHEN current_op.Status = 'C' THEN 
                    CASE 
                        -- If job is complete and there's stale setup, show it's complete
                        WHEN job_setup.setup_operator IS NOT NULL THEN
                            CONCAT('COMPLETE: ', j.Customer, ' | ', j.Part_Number, ' | ', j.Job, ' | ⚠CLEANUP')
                        ELSE CONCAT('COMPLETE: ', j.Customer, ' | ', j.Part_Number, ' | ', j.Job)
                    END
                WHEN j.Job IS NULL THEN 
                    CASE 
                        WHEN setup_for_machine.Job IS NOT NULL 
                             AND setup_for_machine.setup_status IN ('ACTIVE SUP', 'SUP IDLE')
                             AND setup_for_machine.setup_start >= DATEADD(DAY, -7, GETDATE())
                        THEN CONCAT('STAGING: ', setup_for_machine.Customer, ' | ', setup_for_machine.Part_Number, ' | ', setup_for_machine.Job)
                        ELSE 'WAITING for new JOB'
                    END
                ELSE CONCAT(ISNULL(j.Customer,''), ' | ', ISNULL(j.Part_Number,''), ' | ', ISNULL(j.Job,''))
            END AS CustomerPartJob,
            
            -- FIXED: Job Due Date/Status
            CASE 
                WHEN current_op.Status = 'C' THEN 
                    CONCAT('Complete | ', ISNULL(CAST(j.Status_Date AS VARCHAR),''))
                WHEN j.Job IS NULL THEN 
                    CASE 
                        WHEN setup_for_machine.setup_status IS NOT NULL 
                             AND setup_for_machine.setup_start >= DATEADD(DAY, -7, GETDATE())
                        THEN CONCAT(ISNULL(setup_for_machine.setup_status,''), ' | ', ISNULL(setup_for_machine.setup_duration,''))
                        ELSE ''
                    END
                ELSE CONCAT(ISNULL(CAST(ISNULL(ship_dates.Promised_Date, j.Sched_End) AS VARCHAR),''), ' | ', ISNULL(j.Status,''))
            END AS JobDueDtStatus,
            
            -- FIXED: Operation Details
            CASE 
                WHEN current_op.Status = 'C' THEN 
                    'Operation Complete - Ready for next job'
                WHEN current_op.Job_Operation IS NULL THEN 
                    CASE 
                        WHEN setup_for_machine.setup_status IS NOT NULL 
                             AND setup_for_machine.setup_start >= DATEADD(DAY, -7, GETDATE())
                        THEN CONCAT('SUP: ', ISNULL(setup_for_machine.setup_status,''), ' | ', ISNULL(setup_for_machine.setup_duration,''))
                        ELSE 'READY for new operation'
                    END
                ELSE CONCAT(
                    ISNULL(current_op.Operation_Service,''), ' | ', ISNULL(current_op.Description,''), ' | ', ISNULL(current_op.Status,''),
                    -- ADD COMPLETION PREDICTION
                    CASE 
                        WHEN job_predictions.estimated_hours_remaining IS NOT NULL AND job_predictions.estimated_hours_remaining > 0
                        THEN CONCAT(' | ETA:', 
                            CASE 
                                WHEN job_predictions.estimated_hours_remaining <= 8 THEN CONCAT(CAST(CEILING(job_predictions.estimated_hours_remaining) AS VARCHAR), 'h')
                                WHEN job_predictions.estimated_hours_remaining <= 24 THEN '1d'
                                ELSE CONCAT(CAST(CEILING(job_predictions.estimated_hours_remaining / 8) AS VARCHAR), 'd')
                            END)
                        WHEN job_predictions.remaining_qty = 0 THEN ' | COMPLETE'
                        WHEN job_predictions.operator_assigned = 0 THEN ' | NO-OP'
                        ELSE ' | UNK'
                    END
                )
            END AS OperationDetails,
            
            -- FIXED: Employee Info with Data Quality Warnings
            CASE 
                WHEN current_op.Status = 'C' THEN 
                    CASE 
                        -- Show cleanup warning if there's stale setup data
                        WHEN job_setup.setup_operator IS NOT NULL
                        THEN CONCAT('⚠ CLEANUP: Setup ', ISNULL(job_setup.setup_operator,''), ' still open from SM-', 
                                  CAST(ISNULL(job_setup.setup_hours, 0) AS VARCHAR), 'h')
                        WHEN latest_activity.Operator IS NOT NULL
                        THEN CONCAT('LAST: ', ISNULL(latest_activity.Operator,''), ' | ', ISNULL(CAST(latest_activity.Work_Date AS VARCHAR),''))
                        ELSE ''
                    END
                WHEN latest_activity.Operator IS NULL THEN 
                    CASE 
                        WHEN setup_for_machine.setup_operator IS NOT NULL 
                             AND setup_for_machine.setup_start >= DATEADD(DAY, -7, GETDATE())
                        THEN CONCAT('SETUP: ', ISNULL(setup_for_machine.setup_operator,''), ' | SM-', 
                                  CAST(ISNULL(setup_for_machine.setup_hours, 0) AS VARCHAR), 'h')
                        ELSE ''
                    END
                ELSE 
                    CASE 
                        -- Show both production and setup operator if setup exists for this job
                        WHEN job_setup.setup_operator IS NOT NULL
                        THEN CONCAT(ISNULL(latest_activity.Operator,''), ' | ', ISNULL(CAST(latest_activity.Work_Date AS VARCHAR),''), 
                                  ' | ⚠SUP: ', ISNULL(job_setup.setup_operator,''), ' | SM-', 
                                  CAST(ISNULL(job_setup.setup_hours, 0) AS VARCHAR), 'h open')
                        ELSE CONCAT(ISNULL(latest_activity.Operator,''), ' | ', ISNULL(CAST(latest_activity.Work_Date AS VARCHAR),''))
                    END
            END AS OperatorActivity,
            
            -- Timing Information - ORIGINAL UNCHANGED
            latest_activity.Last_Updated AS LastUpdated,
            
            -- FIXED StatusDuration - Complete jobs show OFFLINE
            CONCAT(
                CASE 
                    -- PRIORITY 1: If operation is complete, machine is OFFLINE
                    WHEN current_op.Status = 'C' THEN 
                        CASE 
                            WHEN job_setup.setup_operator IS NOT NULL THEN 'OFFLINE | ⚠'
                            ELSE 'OFFLINE'
                        END
                    
                    -- PRIORITY 2: Check if no operation assigned
                    WHEN current_op.Job_Operation IS NULL THEN 
                        CASE 
                            WHEN setup_for_machine.setup_status = 'ACTIVE SUP' 
                                 AND setup_for_machine.setup_start >= DATEADD(DAY, -7, GETDATE())
                            THEN 'STAGING'
                            WHEN setup_for_machine.setup_status IN ('SUP IDLE', 'SUP STALLED')
                                 AND setup_for_machine.setup_start >= DATEADD(DAY, -7, GETDATE())
                            THEN 'STAGING-IDLE'
                            ELSE 'OFFLINE'
                        END
                    
                    -- PRIORITY 3: Check if over plan
                    WHEN current_op.Est_Required_Qty > 0 AND op_totals.Total_Run_Qty >= current_op.Est_Required_Qty
                    THEN 'OverPlan'
                    
                    -- PRIORITY 4: Check for recent activity (ACTIVE)
                    WHEN latest_activity.Last_Updated IS NOT NULL
                         AND latest_activity.Last_Updated >= DATEADD(HOUR, -8, GETDATE())
                    THEN 'ACTIVE'
                    
                    -- PRIORITY 5: Has activity but not recent (IDLE)
                    WHEN latest_activity.Last_Updated IS NOT NULL
                    THEN 'IDLE'
                    
                    -- PRIORITY 6: No activity at all
                    ELSE 'OFFLINE'
                END,
                ' | ',
                -- Duration calculation
                CASE 
                    WHEN current_op.Status = 'C' THEN 
                        CASE 
                            WHEN latest_activity.Work_Date IS NOT NULL
                            THEN CONCAT(DATEDIFF(DAY, latest_activity.Work_Date, GETDATE()), 'd')
                            ELSE 'N/A'
                        END
                    WHEN current_op.Job_Operation IS NULL THEN '0h'
                    WHEN latest_activity.Last_Updated IS NULL THEN '7d+'
                    WHEN current_op.Est_Required_Qty > 0 AND op_totals.Total_Run_Qty >= current_op.Est_Required_Qty
                    THEN 
                        CASE 
                            WHEN prod_timeline.DaysInProduction IS NOT NULL AND prod_timeline.TotalMachineHours IS NOT NULL
                            THEN CONCAT(
                                CAST(prod_timeline.DaysInProduction AS VARCHAR(10)), 'd-',
                                CAST(CAST(prod_timeline.TotalMachineHours AS INT) AS VARCHAR(10)), 'Mh'
                            )
                            WHEN latest_activity.Work_Date IS NOT NULL AND latest_activity.Work_Date >= DATEADD(DAY, -30, GETDATE())
                            THEN 
                                CASE 
                                    WHEN DATEDIFF(DAY, latest_activity.Work_Date, GETDATE()) >= 1
                                    THEN CONCAT(DATEDIFF(DAY, latest_activity.Work_Date, GETDATE()), 'd')
                                    ELSE CONCAT(DATEDIFF(HOUR, latest_activity.Work_Date, GETDATE()), 'h')
                                END
                            ELSE 'Active'
                        END
                    WHEN latest_activity.Work_Date IS NOT NULL
                         AND latest_activity.Work_Date >= DATEADD(DAY, -30, GETDATE())
                    THEN 
                        CASE 
                            WHEN prod_timeline.DaysInProduction IS NOT NULL AND prod_timeline.TotalMachineHours IS NOT NULL
                            THEN CONCAT(
                                CAST(prod_timeline.DaysInProduction AS VARCHAR(10)), 'd-',
                                CAST(CAST(prod_timeline.TotalMachineHours AS INT) AS VARCHAR(10)), 'Mh',
                                CASE 
                                    WHEN job_predictions.estimated_hours_remaining IS NOT NULL AND job_predictions.estimated_hours_remaining > 0
                                    THEN CONCAT('→',
                                        CASE 
                                            WHEN job_predictions.estimated_hours_remaining <= 8 THEN CONCAT(CAST(CEILING(job_predictions.estimated_hours_remaining) AS VARCHAR), 'h')
                                            WHEN job_predictions.estimated_hours_remaining <= 24 THEN '1d'
                                            ELSE CONCAT(CAST(CEILING(job_predictions.estimated_hours_remaining / 8) AS VARCHAR), 'd')
                                        END)
                                    ELSE ''
                                END
                            )
                            ELSE
                                CASE 
                                    WHEN (DATEDIFF(DAY, latest_activity.Work_Date, GETDATE()) 
                                        - (DATEDIFF(WEEK, latest_activity.Work_Date, GETDATE()) * 2)
                                        - CASE WHEN DATEPART(WEEKDAY, latest_activity.Work_Date) = 1 THEN 1 ELSE 0 END
                                        - CASE WHEN DATEPART(WEEKDAY, GETDATE()) = 7 THEN 1 ELSE 0 END) >= 1
                                    THEN CONCAT(
                                        DATEDIFF(DAY, latest_activity.Work_Date, GETDATE()) 
                                        - (DATEDIFF(WEEK, latest_activity.Work_Date, GETDATE()) * 2)
                                        - CASE WHEN DATEPART(WEEKDAY, latest_activity.Work_Date) = 1 THEN 1 ELSE 0 END
                                        - CASE WHEN DATEPART(WEEKDAY, GETDATE()) = 7 THEN 1 ELSE 0 END,
                                        'd',
                                        CASE 
                                            WHEN DATEPART(WEEKDAY, GETDATE()) BETWEEN 2 AND 6
                                            THEN DATEPART(HOUR, GETDATE())
                                            ELSE 0
                                        END, 'h'
                                    )
                                    ELSE 
                                        CASE 
                                            WHEN DATEPART(WEEKDAY, GETDATE()) BETWEEN 2 AND 6
                                            THEN CONCAT(CASE WHEN DATEDIFF(HOUR, latest_activity.Work_Date, GETDATE()) > 0 
                                                            THEN DATEDIFF(HOUR, latest_activity.Work_Date, GETDATE()) 
                                                            ELSE 0 END, 'h')
                                            ELSE '0h'
                                        END
                                END
                        END
                    WHEN latest_activity.Work_Date IS NOT NULL
                    THEN 
                        CASE 
                            WHEN prod_timeline.DaysInProduction IS NOT NULL AND prod_timeline.TotalMachineHours IS NOT NULL
                            THEN CONCAT(
                                CAST(prod_timeline.DaysInProduction AS VARCHAR(10)), 'd-',
                                CAST(CAST(prod_timeline.TotalMachineHours AS INT) AS VARCHAR(10)), 'Mh'
                            )
                            ELSE '999d+'
                        END
                    ELSE 'N/A'
                END
            ) AS StatusDuration,
            
            -- FIXED: Individual Status Fields with FirstRun Indicator
            CONCAT(
                CASE 
                    -- PRIORITY 1: Complete operations are OFFLINE
                    WHEN current_op.Status = 'C' THEN 
                        CASE 
                            WHEN job_setup.setup_operator IS NOT NULL THEN 'OFFLINE | ⚠'
                            ELSE 'OFFLINE'
                        END
                    
                    -- PRIORITY 2: No operation assigned
                    WHEN current_op.Job_Operation IS NULL THEN 
                        CASE 
                            WHEN setup_for_machine.setup_status = 'ACTIVE SUP'
                                 AND setup_for_machine.setup_start >= DATEADD(DAY, -7, GETDATE())
                            THEN 'STAGING'
                            WHEN setup_for_machine.setup_status IN ('SUP IDLE', 'SUP STALLED')
                                 AND setup_for_machine.setup_start >= DATEADD(DAY, -7, GETDATE())
                            THEN 'STAGING-IDLE'
                            ELSE 'OFFLINE'
                        END
                    
                    -- PRIORITY 3: Over plan
                    WHEN current_op.Est_Required_Qty > 0 AND op_totals.Total_Run_Qty >= current_op.Est_Required_Qty
                    THEN 'OverPlan'
                    
                    -- PRIORITY 4: Active (recent activity within 8 hours)
                    WHEN latest_activity.Last_Updated IS NOT NULL
                         AND latest_activity.Last_Updated >= DATEADD(HOUR, -8, GETDATE())
                    THEN 'ACTIVE'
                    
                    -- PRIORITY 5: Idle (has activity but not recent)
                    WHEN latest_activity.Last_Updated IS NOT NULL
                    THEN 'IDLE'
                    
                    ELSE 'OFFLINE'
                END,
                ' | ',
                ISNULL(first_run.RunIndicator, 'O')  -- Add FirstRun indicator (F or O)
            ) AS MachineStatus,
            
            -- Progress Display
            CASE 
                WHEN current_op.Status = 'C' THEN 
                    'Operation Complete'
                WHEN current_op.Job_Operation IS NULL THEN 
                    CASE 
                        WHEN setup_for_machine.Job IS NOT NULL
                             AND setup_for_machine.setup_start >= DATEADD(DAY, -7, GETDATE())
                        THEN CONCAT('STAGING for ', setup_for_machine.Job)
                        ELSE 'READY for new job'
                    END
                ELSE CONCAT(
                    ISNULL(current_op.Operation_Service,''), ': ',
                    ISNULL(op_totals.Total_Run_Qty, 0), 
                    ' / ', 
                    ISNULL(current_op.Est_Required_Qty, 0), 
                    ' | ', 
                    CASE 
                        WHEN current_op.Est_Required_Qty IS NULL OR current_op.Est_Required_Qty = 0 THEN '0'
                        WHEN op_totals.Total_Run_Qty IS NULL THEN '0'
                        WHEN op_totals.Total_Run_Qty > 999999 OR current_op.Est_Required_Qty > 999999 THEN '999+'
                        WHEN op_totals.Total_Run_Qty > current_op.Est_Required_Qty * 10 THEN '999+'
                        ELSE CAST(ROUND((CAST(op_totals.Total_Run_Qty AS FLOAT) / CAST(current_op.Est_Required_Qty AS FLOAT)) * 100, 1) AS VARCHAR(20))
                    END, 
                    '%'
                )
            END AS ProgressDisplay,
            
            -- Individual Metrics - ORIGINAL UNCHANGED
            CASE WHEN current_op.Status = 'C' OR current_op.Job_Operation IS NULL THEN 0 ELSE ISNULL(op_totals.Total_Run_Qty,0) END AS RunQty,
            CASE WHEN current_op.Status = 'C' OR current_op.Job_Operation IS NULL THEN 0 ELSE ISNULL(op_totals.Total_Scrap_Qty,0) END AS ScrapQty,
            CASE WHEN current_op.Status = 'C' OR current_op.Job_Operation IS NULL THEN 0 ELSE ISNULL(current_op.Est_Required_Qty,0) END AS RequiredQty,
            
            -- Progress Indicator - ORIGINAL UNCHANGED
            CASE 
                WHEN current_op.Status = 'C' OR current_op.Job_Operation IS NULL THEN 0.0
                WHEN current_op.Est_Required_Qty IS NULL OR current_op.Est_Required_Qty = 0 THEN 0.0
                WHEN op_totals.Total_Run_Qty IS NULL THEN 0.0
                WHEN op_totals.Total_Run_Qty > 999999 OR current_op.Est_Required_Qty > 999999 THEN 999.9
                WHEN op_totals.Total_Run_Qty > current_op.Est_Required_Qty * 10 THEN 999.9
                ELSE ROUND((CAST(ISNULL(op_totals.Total_Run_Qty,0) AS FLOAT) / CAST(ISNULL(current_op.Est_Required_Qty,1) AS FLOAT)) * 100, 1)
            END AS PercentComplete,

            -- ERROR DETECTION: Count multiple jobs per machine - ORIGINAL UNCHANGED
            COUNT(*) OVER (PARTITION BY w.Work_Center) AS jobs_on_machine,

            -- DEDUPLICATION: Rank to pick best record per machine - ORIGINAL LOGIC
            ROW_NUMBER() OVER (
                PARTITION BY w.Work_Center 
                ORDER BY 
                    CASE 
                        WHEN latest_activity.Work_Date >= DATEADD(DAY, -7, GETDATE()) 
                             AND current_op.Status NOT IN ('Complete', 'Closed', 'C')
                             AND j.Status NOT IN ('Complete', 'Closed', 'Shipped')
                        THEN 1
                        WHEN latest_activity.Work_Date >= DATEADD(DAY, -7, GETDATE())
                        THEN 2
                        WHEN setup_for_machine.Job IS NOT NULL OR job_setup.Job IS NOT NULL
                        THEN 3
                        ELSE 4
                    END,
                    ISNULL(latest_activity.Last_Updated, '1900-01-01') DESC,
                    ISNULL(j.Job,0) DESC
            ) AS machine_rank

        FROM THURO.dbo.Job j with (NoLock)
            INNER JOIN THURO.dbo.Work_Center w with (NoLock) ON EXISTS (
                SELECT 1 FROM THURO.dbo.Job_Operation jo_exists with (NoLock)
                WHERE jo_exists.Job = j.Job AND jo_exists.Work_Center = w.Work_Center
            )
            
            -- Department name mapping - ORIGINAL UNCHANGED
            LEFT JOIN (
                SELECT RTRIM(LTRIM('Swiss')) AS Department, '01-Swiss' AS DeptName UNION ALL
                SELECT RTRIM(LTRIM('Turning')), '02-Turng' UNION ALL
                SELECT RTRIM(LTRIM('Milling')), '03-Milng' UNION ALL
                SELECT RTRIM(LTRIM('Multis')), '04-MSpnd' UNION ALL
                SELECT RTRIM(LTRIM('Grinding')), '05-Grnd' UNION ALL
                SELECT RTRIM(LTRIM('Deburring')), '06-Dburr' UNION ALL
                SELECT RTRIM(LTRIM('Washing')), '07-Wshng'
            ) dept_names ON RTRIM(LTRIM(dept_names.Department)) = RTRIM(LTRIM(w.Department))
            
            -- Get the CURRENT operation - ORIGINAL UNCHANGED EXCEPT EXCLUDE SETUP
            INNER JOIN (
                SELECT 
                    jo.Job, jo.Work_Center, jo.Job_Operation, jo.Operation_Service, jo.Description, jo.Status, jo.Est_Required_Qty,
                    ROW_NUMBER() OVER (
                        PARTITION BY jo.Job, jo.Work_Center 
                        ORDER BY 
                            CASE 
                                WHEN EXISTS (
                                    SELECT 1 FROM THURO.dbo.Job_Operation_Time jot_check with (NoLock)
                                    WHERE jot_check.Job_Operation = jo.Job_Operation
                                        AND jot_check.Work_Date >= DATEADD(DAY, -7, GETDATE())
                                        AND jot_check.Work_Date IS NOT NULL
                                ) THEN 0
                                ELSE 1
                            END,
                            CASE WHEN jo.Status IN ('Complete', 'Closed') THEN 1 ELSE 0 END,
                            CASE 
                                WHEN jo.Status = 'S' THEN 0
                                WHEN jo.Status = 'R' THEN 1
                                WHEN jo.Status = 'O' THEN 2
                                ELSE 3
                            END,
                            jo.Sequence DESC,
                            jo.Job_Operation DESC
                    ) AS rn
                FROM THURO.dbo.Job_Operation jo with (NoLock)
                WHERE (jo.Status NOT IN ('Complete', 'Closed')
                   OR jo.Job_Operation IN (
                       SELECT DISTINCT jot.Job_Operation 
                       FROM THURO.dbo.Job_Operation_Time jot with (NoLock)
                       WHERE jot.Work_Date >= DATEADD(DAY, (-2), GETDATE())
                   ))
                   AND jo.Work_Center != 'SM SETUPM'
            ) current_op ON current_op.Job = j.Job AND current_op.Work_Center = w.Work_Center AND current_op.rn = 1
            
            -- Get the most recent time entry - ORIGINAL UNCHANGED
            LEFT JOIN (
                SELECT 
                    jot.Job_Operation,
                    jot.Work_Date,
                    jot.Last_Updated,
                    jot.Operation_Complete,
                    UPPER(LEFT(e.First_Name, 1)) + LOWER(SUBSTRING(e.First_Name, 2, LEN(e.First_Name))) + '_' + 
                    UPPER(LEFT(e.Last_Name, 1)) AS Operator,
                    ROW_NUMBER() OVER (PARTITION BY jot.Job_Operation ORDER BY jot.Last_Updated DESC, jot.Work_Date DESC) AS rn
                FROM THURO.dbo.Job_Operation_Time jot with (NoLock)
                INNER JOIN THURO.dbo.Employee e ON jot.Employee = e.Employee
                WHERE jot.Work_Date >= DATEADD(DAY, (-30), GETDATE())
                AND jot.Work_Date IS NOT NULL AND jot.Last_Updated IS NOT NULL
            ) latest_activity ON latest_activity.Job_Operation = current_op.Job_Operation AND latest_activity.rn = 1
            
            -- Get TOTAL quantities - ORIGINAL UNCHANGED
            LEFT JOIN (
                SELECT 
                    jot.Job_Operation,
                    SUM(ISNULL(jot.Act_Run_Qty, 0)) AS Total_Run_Qty,
                    SUM(ISNULL(jot.Act_Scrap_Qty, 0)) AS Total_Scrap_Qty
                FROM THURO.dbo.Job_Operation_Time jot with (NoLock)
                WHERE jot.Work_Date >= DATEADD(DAY, (-365), GETDATE())
                AND jot.Work_Date IS NOT NULL
                GROUP BY jot.Job_Operation
            ) op_totals ON op_totals.Job_Operation = current_op.Job_Operation
            
            -- Production timeline data - ORIGINAL UNCHANGED EXCEPT EXCLUDE SETUP
            LEFT JOIN (
                SELECT 
                    current_jobs.Job,
                    current_jobs.Work_Center,
                    current_jobs.Operation_Service,
                    DATEDIFF(DAY, MIN(CAST(jot_timeline.Last_Updated AS DATE)), GETDATE()) AS DaysInProduction,
                    SUM(ISNULL(jot_timeline.Act_Run_Hrs, 0)) AS TotalMachineHours,
                    DATEDIFF(DAY, MAX(CAST(jot_timeline.Last_Updated AS DATE)), GETDATE()) AS DaysSinceLastWork,
                    SUM(ISNULL(jot_timeline.Act_Run_Qty, 0)) AS TotalPartsProduced
                FROM (
                    SELECT DISTINCT 
                        jo_current.Job, 
                        jo_current.Work_Center, 
                        jo_current.Operation_Service
                    FROM THURO.dbo.Job_Operation jo_current with (NoLock)
                    WHERE jo_current.Status NOT IN ('Complete', 'Closed')
                        AND jo_current.Work_Center != 'SM SETUPM'
                ) current_jobs
                INNER JOIN THURO.dbo.Job_Operation jo_timeline with (NoLock)
                    ON current_jobs.Job = jo_timeline.Job 
                    AND current_jobs.Work_Center = jo_timeline.Work_Center
                    AND current_jobs.Operation_Service = jo_timeline.Operation_Service
                INNER JOIN THURO.dbo.Job_Operation_Time jot_timeline with (NoLock)
                    ON jo_timeline.Job_Operation = jot_timeline.Job_Operation
                WHERE (jot_timeline.Act_Run_Qty > 0 OR jot_timeline.Act_Run_Hrs > 0)
                    AND jot_timeline.Last_Updated >= DATEADD(DAY, -365, GETDATE())
                GROUP BY current_jobs.Job, current_jobs.Work_Center, current_jobs.Operation_Service
            ) prod_timeline ON prod_timeline.Job = j.Job 
                            AND prod_timeline.Work_Center = w.Work_Center 
                            AND prod_timeline.Operation_Service = current_op.Operation_Service
            
            -- Completion predictions - ORIGINAL UNCHANGED
            LEFT JOIN JobCompletionPredictions job_predictions ON current_op.Job_Operation = job_predictions.Job_Operation
            
            -- MODIFIED: Setup data for current job - now includes Actual_Start for age checking
            LEFT JOIN (
                SELECT 
                    jo_setup.Job,
                    jo_setup.Actual_Start AS setup_start,
                    SUM(jot_setup.Act_Run_Hrs) AS setup_hours,
                    (SELECT TOP 1 
                        UPPER(LEFT(e_setup.First_Name, 1)) + LOWER(SUBSTRING(e_setup.First_Name, 2, LEN(e_setup.First_Name))) + '_' + 
                        UPPER(LEFT(e_setup.Last_Name, 1))
                     FROM THURO.dbo.Job_Operation_Time jot_recent with (NoLock)
                        INNER JOIN THURO.dbo.Employee e_setup with (NoLock) ON jot_recent.Employee = e_setup.Employee
                     WHERE jot_recent.Job_Operation = jo_setup.Job_Operation
                        AND jot_recent.Act_Run_Hrs > 0
                        AND jot_recent.Work_Date >= DATEADD(DAY, -90, GETDATE())
                     ORDER BY jot_recent.Work_Date DESC
                    ) AS setup_operator
                FROM THURO.dbo.Job_Operation jo_setup with (NoLock)
                    LEFT JOIN THURO.dbo.Job_Operation_Time jot_setup with (NoLock) ON jo_setup.Job_Operation = jot_setup.Job_Operation
                        AND jot_setup.Work_Date >= DATEADD(DAY, -90, GETDATE())
                WHERE jo_setup.Work_Center = 'SM SETUPM'
                    AND jo_setup.Status NOT IN ('Complete', 'Closed')
                GROUP BY jo_setup.Job, jo_setup.Job_Operation, jo_setup.Actual_Start
            ) job_setup ON job_setup.Job = j.Job
            
            -- Setup data for machines (upcoming jobs being staged)
            LEFT JOIN (
                SELECT 
                    target_work_center, Job, Customer, Part_Number, setup_hours, setup_operator, setup_status, setup_duration, setup_start,
                    ROW_NUMBER() OVER (PARTITION BY target_work_center ORDER BY setup_start DESC) AS rn
                FROM (
                    SELECT 
                        (SELECT TOP 1 jo_prod.Work_Center
                         FROM THURO.dbo.Job_Operation jo_prod with (NoLock)
                            INNER JOIN THURO.dbo.Work_Center w_prod with (NoLock) ON jo_prod.Work_Center = w_prod.Work_Center
                         WHERE jo_prod.Job = jo_setup.Job
                            AND jo_prod.Work_Center != 'SM SETUPM'
                            AND jo_prod.Status NOT IN ('Complete', 'Closed')
                            AND w_prod.Status = 1 AND w_prod.UVText1 = 'MStatusQry'
                         ORDER BY jo_prod.Sequence
                        ) AS target_work_center,
                        jo_setup.Job,
                        j_setup.Customer,
                        j_setup.Part_Number,
                        jo_setup.Actual_Start AS setup_start,
                        SUM(jot_setup.Act_Run_Hrs) AS setup_hours,
                        MAX(jot_setup.Work_Date) AS last_setup_activity,
                        (SELECT TOP 1 
                            UPPER(LEFT(e_setup.First_Name, 1)) + LOWER(SUBSTRING(e_setup.First_Name, 2, LEN(e_setup.First_Name))) + '_' + 
                            UPPER(LEFT(e_setup.Last_Name, 1))
                         FROM THURO.dbo.Job_Operation_Time jot_recent_setup with (NoLock)
                            INNER JOIN THURO.dbo.Employee e_setup ON jot_recent_setup.Employee = e_setup.Employee
                         WHERE jot_recent_setup.Job_Operation = jo_setup.Job_Operation
                            AND jot_recent_setup.Act_Run_Hrs > 0
                            AND jot_recent_setup.Work_Date >= DATEADD(DAY, -14, GETDATE())
                         ORDER BY jot_recent_setup.Work_Date DESC
                        ) AS setup_operator,
                        CASE 
                            WHEN MAX(jot_setup.Work_Date) >= DATEADD(HOUR, -8, GETDATE()) AND SUM(jot_setup.Act_Run_Hrs) > 0
                            THEN 'ACTIVE SUP'
                            WHEN MAX(jot_setup.Work_Date) >= DATEADD(HOUR, -24, GETDATE()) AND SUM(jot_setup.Act_Run_Hrs) > 0
                            THEN 'SUP IDLE'
                            WHEN jo_setup.Actual_Start IS NOT NULL
                                 AND (MAX(jot_setup.Work_Date) IS NULL OR MAX(jot_setup.Work_Date) < DATEADD(HOUR, -24, GETDATE()))
                            THEN 'SUP STALLED'
                            ELSE 'SUP SCHEDULED'
                        END AS setup_status,
                        CASE 
                            WHEN jo_setup.Actual_Start IS NOT NULL
                            THEN CASE 
                                    WHEN DATEDIFF(HOUR, jo_setup.Actual_Start, GETDATE()) >= 24
                                    THEN CONCAT(DATEDIFF(DAY, jo_setup.Actual_Start, GETDATE()), 'd')
                                    ELSE CONCAT(DATEDIFF(HOUR, jo_setup.Actual_Start, GETDATE()), 'h')
                                 END
                            ELSE '0h'
                        END AS setup_duration
                    FROM THURO.dbo.Job_Operation jo_setup with (NoLock)
                        INNER JOIN THURO.dbo.Job j_setup  with (NoLock) ON jo_setup.Job = j_setup.Job
                        LEFT JOIN THURO.dbo.Job_Operation_Time jot_setup with (NoLock) ON jo_setup.Job_Operation = jot_setup.Job_Operation
                            AND jot_setup.Work_Date >= DATEADD(DAY, -14, GETDATE())
                    WHERE jo_setup.Work_Center = 'SM SETUPM'
                        AND jo_setup.Status NOT IN ('Complete', 'Closed')
                        AND j_setup.Status NOT IN ('Complete', 'Closed', 'Shipped')
                    GROUP BY jo_setup.Job, jo_setup.Job_Operation, jo_setup.Actual_Start, j_setup.Customer, j_setup.Part_Number
                ) setup_with_targets
                WHERE target_work_center IS NOT NULL
            ) setup_for_machine ON setup_for_machine.target_work_center = w.Work_Center AND setup_for_machine.rn = 1
            
            -- Get promised dates - ORIGINAL UNCHANGED
            LEFT JOIN (
                SELECT 
                    JobSO,
                    MIN(Promised_Date) AS Promised_Date
                FROM THURO.dbo.vw_shipments 
                WHERE Promised_Date IS NOT NULL
                GROUP BY JobSO
            ) ship_dates ON ship_dates.JobSO = j.Job
            
            -- Join FirstRun indicator
            LEFT JOIN FirstRunIdentifier first_run ON first_run.Job = j.Job

        WHERE 
            latest_activity.Work_Date >= DATEADD(DAY, (-7), GETDATE())
            AND latest_activity.Work_Date IS NOT NULL
            AND latest_activity.Last_Updated IS NOT NULL
            AND (j.Status NOT IN ('Complete', 'Closed', 'Shipped') 
                 OR j.Status_Date >= DATEADD(DAY, (-1), GETDATE()))
            AND (current_op.Est_Required_Qty IS NULL OR current_op.Est_Required_Qty >= 0)
            AND (op_totals.Total_Run_Qty IS NULL OR op_totals.Total_Run_Qty >= 0)
            AND w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')

        UNION ALL

        -- PART 2: ORIGINAL MISSING MACHINES LOGIC (UNCHANGED)
        SELECT 
            w.Work_Center AS Machine,
            ISNULL(dept_names.DeptName, w.Department) AS Department,
            CONCAT(
                CASE 
                    WHEN dept_names.DeptName IS NOT NULL 
                    THEN SUBSTRING(dept_names.DeptName, 4, LEN(dept_names.DeptName))
                    ELSE w.Department 
                END, 
                ' | ', w.Work_Center
            ) AS DeptMachine,
            CASE 
                WHEN setup_for_missing.Job IS NOT NULL
                     AND setup_for_missing.setup_start >= DATEADD(DAY, -7, GETDATE())
                THEN CONCAT('STAGING: ', ISNULL(setup_for_missing.Customer,''), ' | ', ISNULL(setup_for_missing.Part_Number,''), ' | ', ISNULL(setup_for_missing.Job,''))
                WHEN last_job.Job IS NOT NULL 
                THEN CONCAT('LAST: ', ISNULL(last_job.Customer,''), ' | ', ISNULL(last_job.Part_Number,''), ' | ', ISNULL(last_job.Job,''))
                ELSE 'WAITING for new JOB'
            END AS CustomerPartJob,
            CASE 
                WHEN setup_for_missing.setup_status IS NOT NULL
                     AND setup_for_missing.setup_start >= DATEADD(DAY, -7, GETDATE())
                THEN CONCAT(ISNULL(setup_for_missing.setup_status,''), ' | ', ISNULL(setup_for_missing.setup_duration,''))
                WHEN last_activity_historical.Last_Updated IS NOT NULL 
                THEN CONCAT(DATEDIFF(DAY, last_activity_historical.Last_Updated, GETDATE()), ' days ago')
                ELSE ''
            END AS JobDueDtStatus,
            CASE 
                WHEN setup_for_missing.setup_status IS NOT NULL
                     AND setup_for_missing.setup_start >= DATEADD(DAY, -7, GETDATE())
                THEN CONCAT('SUP: ', ISNULL(setup_for_missing.setup_status,''), ' | ', ISNULL(setup_for_missing.setup_duration,''))
                WHEN last_job_op.Operation_Service IS NOT NULL 
                THEN CONCAT('LAST: ', ISNULL(last_job_op.Operation_Service,''), ' | ', ISNULL(last_job_op.Description,''))
                ELSE 'READY for new operation'
            END AS OperationDetails,
            CASE 
                WHEN setup_for_missing.setup_operator IS NOT NULL
                     AND setup_for_missing.setup_start >= DATEADD(DAY, -7, GETDATE())
                THEN CONCAT('SUP: ', ISNULL(setup_for_missing.setup_operator,''), ' | SM-', 
                          CAST(ISNULL(setup_for_missing.setup_hours, 0) AS VARCHAR), 'h')
                WHEN last_activity_historical.Operator IS NOT NULL 
                THEN CONCAT('LAST: ', ISNULL(last_activity_historical.Operator,''), ' | ', ISNULL(CAST(last_activity_historical.Work_Date AS VARCHAR),''))
                ELSE ''
            END AS OperatorActivity,
            last_activity_historical.Last_Updated AS LastUpdated,
            CASE 
                WHEN setup_for_missing.setup_status = 'ACTIVE SUP' 
                     AND setup_for_missing.setup_start >= DATEADD(DAY, -7, GETDATE())
                THEN 'STAGING | ' + ISNULL(setup_for_missing.setup_duration,'')
                WHEN setup_for_missing.setup_status IN ('SUP IDLE', 'SUP STALLED')
                     AND setup_for_missing.setup_start >= DATEADD(DAY, -7, GETDATE())
                THEN 'STAGING-IDLE | ' + ISNULL(setup_for_missing.setup_duration,'')
                WHEN last_activity_historical.Last_Updated IS NOT NULL 
                THEN CONCAT('OFFLINE | ', DATEDIFF(DAY, last_activity_historical.Last_Updated, GETDATE()), 'd ago')
                ELSE 'OFFLINE | No recent activity'
            END AS StatusDuration,
            CASE 
                WHEN setup_for_missing.setup_status = 'ACTIVE SUP'
                     AND setup_for_missing.setup_start >= DATEADD(DAY, -7, GETDATE())
                THEN 'STAGING'
                WHEN setup_for_missing.setup_status IN ('SUP IDLE', 'SUP STALLED')
                     AND setup_for_missing.setup_start >= DATEADD(DAY, -7, GETDATE())
                THEN 'STAGING-IDLE'
                ELSE 'OFFLINE'
            END AS MachineStatus,
            CASE 
                WHEN setup_for_missing.Job IS NOT NULL
                     AND setup_for_missing.setup_start >= DATEADD(DAY, -7, GETDATE())
                THEN CONCAT('STAGING for ', ISNULL(setup_for_missing.Job,''))
                ELSE 'READY for new job'
            END AS ProgressDisplay,
            0 AS RunQty, 0 AS ScrapQty, 0 AS RequiredQty, 0.0 AS PercentComplete,
            1 AS jobs_on_machine, 1 AS machine_rank
        FROM THURO.dbo.Work_Center w with (NoLock)
            LEFT JOIN (
                SELECT RTRIM(LTRIM('Swiss')) AS Department, '01-Swiss' AS DeptName UNION ALL
                SELECT RTRIM(LTRIM('Turning')), '02-Turng' UNION ALL
                SELECT RTRIM(LTRIM('Milling')), '03-Milng' UNION ALL
                SELECT RTRIM(LTRIM('Multis')), '04-MSpnd' UNION ALL
                SELECT RTRIM(LTRIM('Grinding')), '05-Grnd' UNION ALL
                SELECT RTRIM(LTRIM('Deburring')), '06-Dburr' UNION ALL
                SELECT RTRIM(LTRIM('Washing')), '07-Wshng'
            ) dept_names ON RTRIM(LTRIM(dept_names.Department)) = RTRIM(LTRIM(w.Department))
            LEFT JOIN (
                SELECT 
                    target_work_center, Job, Customer, Part_Number, setup_hours, setup_operator, setup_status, setup_duration, setup_start,
                    ROW_NUMBER() OVER (PARTITION BY target_work_center ORDER BY setup_start DESC) AS rn
                FROM (
                    SELECT 
                        (SELECT TOP 1 jo_prod.Work_Center
                         FROM THURO.dbo.Job_Operation jo_prod with (NoLock)
                            INNER JOIN THURO.dbo.Work_Center w_prod with (NoLock) ON jo_prod.Work_Center = w_prod.Work_Center
                         WHERE jo_prod.Job = jo_setup.Job
                            AND jo_prod.Work_Center != 'SM SETUPM'
                            AND jo_prod.Status NOT IN ('Complete', 'Closed')
                            AND w_prod.Status = 1 AND w_prod.UVText1 = 'MStatusQry'
                         ORDER BY jo_prod.Sequence
                        ) AS target_work_center,
                        jo_setup.Job, j_setup.Customer, j_setup.Part_Number, jo_setup.Actual_Start AS setup_start,
                        SUM(jot_setup.Act_Run_Hrs) AS setup_hours, MAX(jot_setup.Work_Date) AS last_setup_activity,
                        (SELECT TOP 1 
                            UPPER(LEFT(e_setup.First_Name, 1)) + LOWER(SUBSTRING(e_setup.First_Name, 2, LEN(e_setup.First_Name))) + '_' + 
                            UPPER(LEFT(e_setup.Last_Name, 1))
                         FROM THURO.dbo.Job_Operation_Time jot_recent_setup with (NoLock)
                            INNER JOIN THURO.dbo.Employee e_setup ON jot_recent_setup.Employee = e_setup.Employee
                         WHERE jot_recent_setup.Job_Operation = jo_setup.Job_Operation
                            AND jot_recent_setup.Act_Run_Hrs > 0 AND jot_recent_setup.Work_Date >= DATEADD(DAY, -14, GETDATE())
                         ORDER BY jot_recent_setup.Work_Date DESC
                        ) AS setup_operator,
                        CASE 
                            WHEN MAX(jot_setup.Work_Date) >= DATEADD(HOUR, -8, GETDATE()) AND SUM(jot_setup.Act_Run_Hrs) > 0 THEN 'ACTIVE SUP'
                            WHEN MAX(jot_setup.Work_Date) >= DATEADD(HOUR, -24, GETDATE()) AND SUM(jot_setup.Act_Run_Hrs) > 0 THEN 'SUP IDLE'
                            WHEN jo_setup.Actual_Start IS NOT NULL AND (MAX(jot_setup.Work_Date) IS NULL OR MAX(jot_setup.Work_Date) < DATEADD(HOUR, -24, GETDATE())) THEN 'SUP STALLED'
                            ELSE 'SUP SCHEDULED'
                        END AS setup_status,
                        CASE 
                            WHEN jo_setup.Actual_Start IS NOT NULL
                            THEN CASE WHEN DATEDIFF(HOUR, jo_setup.Actual_Start, GETDATE()) >= 24
                                     THEN CONCAT(DATEDIFF(DAY, jo_setup.Actual_Start, GETDATE()), 'd')
                                     ELSE CONCAT(DATEDIFF(HOUR, jo_setup.Actual_Start, GETDATE()), 'h') END
                            ELSE '0h'
                        END AS setup_duration
                    FROM THURO.dbo.Job_Operation jo_setup with (NoLock)
                        INNER JOIN THURO.dbo.Job j_setup with (NoLock) ON jo_setup.Job = j_setup.Job
                        LEFT JOIN THURO.dbo.Job_Operation_Time jot_setup with (NoLock) ON jo_setup.Job_Operation = jot_setup.Job_Operation
                            AND jot_setup.Work_Date >= DATEADD(DAY, -14, GETDATE())
                    WHERE jo_setup.Work_Center = 'SM SETUPM' AND jo_setup.Status NOT IN ('Complete', 'Closed')
                        AND j_setup.Status NOT IN ('Complete', 'Closed', 'Shipped')
                    GROUP BY jo_setup.Job, jo_setup.Job_Operation, jo_setup.Actual_Start, j_setup.Customer, j_setup.Part_Number
                ) setup_with_targets WHERE target_work_center IS NOT NULL
            ) setup_for_missing ON setup_for_missing.target_work_center = w.Work_Center AND setup_for_missing.rn = 1
            LEFT JOIN (
                SELECT 
                    jo_hist.Work_Center, j_hist.Job, j_hist.Customer, j_hist.Part_Number, j_hist.Status,
                    ROW_NUMBER() OVER (PARTITION BY jo_hist.Work_Center ORDER BY 
                        CASE WHEN j_hist.Status NOT IN ('Complete', 'Closed', 'Shipped') THEN 0 ELSE 1 END,
                        j_hist.Status_Date DESC, j_hist.Job DESC) AS rn
                FROM THURO.dbo.Job_Operation jo_hist with (NoLock)
                INNER JOIN THURO.dbo.Job j_hist with (NoLock) ON jo_hist.Job = j_hist.Job
                WHERE j_hist.Status_Date >= DATEADD(DAY, -90, GETDATE())
                   OR j_hist.Status NOT IN ('Complete', 'Closed', 'Shipped')
            ) last_job ON last_job.Work_Center = w.Work_Center AND last_job.rn = 1
            LEFT JOIN (
                SELECT 
                    jo_op_hist.Work_Center, jo_op_hist.Operation_Service, jo_op_hist.Description, jo_op_hist.Status,
                    ROW_NUMBER() OVER (PARTITION BY jo_op_hist.Work_Center ORDER BY jo_op_hist.Job_Operation DESC) AS rn
                FROM THURO.dbo.Job_Operation jo_op_hist with (NoLock)
                INNER JOIN THURO.dbo.Job j_op_hist with (NoLock) ON jo_op_hist.Job = j_op_hist.Job
                WHERE j_op_hist.Status_Date >= DATEADD(DAY, -90, GETDATE())
                   OR j_op_hist.Status NOT IN ('Complete', 'Closed', 'Shipped')
            ) last_job_op ON last_job_op.Work_Center = w.Work_Center AND last_job_op.rn = 1
            LEFT JOIN (
                SELECT 
                    jo_act_hist.Work_Center, jot_hist.Work_Date, jot_hist.Last_Updated,
                    UPPER(LEFT(e_hist.First_Name, 1)) + LOWER(SUBSTRING(e_hist.First_Name, 2, LEN(e_hist.First_Name))) + '_' + 
                    UPPER(LEFT(e_hist.Last_Name, 1)) AS Operator,
                    ROW_NUMBER() OVER (PARTITION BY jo_act_hist.Work_Center ORDER BY jot_hist.Last_Updated DESC, jot_hist.Work_Date DESC) AS rn
                FROM THURO.dbo.Job_Operation jo_act_hist with (NoLock)
                INNER JOIN THURO.dbo.Job_Operation_Time jot_hist with (NoLock) ON jo_act_hist.Job_Operation = jot_hist.Job_Operation
                INNER JOIN THURO.dbo.Employee e_hist ON jot_hist.Employee = e_hist.Employee
                WHERE jot_hist.Work_Date >= DATEADD(DAY, -90, GETDATE())
                AND jot_hist.Work_Date IS NOT NULL AND jot_hist.Last_Updated IS NOT NULL
            ) last_activity_historical ON last_activity_historical.Work_Center = w.Work_Center AND last_activity_historical.rn = 1
        WHERE w.Status = 1 AND w.UVText1 = 'MStatusQry' AND w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
          AND w.Work_Center NOT IN (
              SELECT DISTINCT w_existing.Work_Center
              FROM THURO.dbo.Job j_existing with (NoLock)
              INNER JOIN THURO.dbo.Work_Center w_existing with (NoLock) ON EXISTS (
                  SELECT 1 FROM THURO.dbo.Job_Operation jo_exists with (NoLock)
                  WHERE jo_exists.Job = j_existing.Job AND jo_exists.Work_Center = w_existing.Work_Center
              )
              INNER JOIN (
                  SELECT 
                      jo.Job, jo.Work_Center, jo.Job_Operation,
                      ROW_NUMBER() OVER (PARTITION BY jo.Job, jo.Work_Center ORDER BY 
                          CASE WHEN jo.Status IN ('Complete', 'Closed') THEN 1 ELSE 0 END,
                          jo.Sequence DESC, jo.Job_Operation DESC) AS rn
                  FROM THURO.dbo.Job_Operation jo with (NoLock)
                  WHERE (jo.Status NOT IN ('Complete', 'Closed')
                     OR jo.Job_Operation IN (
                         SELECT DISTINCT jot.Job_Operation 
                         FROM THURO.dbo.Job_Operation_Time jot  with (NoLock)
                         WHERE jot.Work_Date >= DATEADD(DAY, (-2), GETDATE())
                     )) AND jo.Work_Center != 'SM SETUPM'
              ) current_op_existing ON current_op_existing.Job = j_existing.Job 
                                    AND current_op_existing.Work_Center = w_existing.Work_Center 
                                    AND current_op_existing.rn = 1
              LEFT JOIN (
                  SELECT jot.Job_Operation, jot.Work_Date, jot.Last_Updated,
                      ROW_NUMBER() OVER (PARTITION BY jot.Job_Operation ORDER BY jot.Last_Updated DESC, jot.Work_Date DESC) AS rn
                  FROM THURO.dbo.Job_Operation_Time jot with (NoLock)
                  WHERE jot.Work_Date >= DATEADD(DAY, (-30), GETDATE())
                  AND jot.Work_Date IS NOT NULL AND jot.Last_Updated IS NOT NULL
              ) latest_activity_existing ON latest_activity_existing.Job_Operation = current_op_existing.Job_Operation 
                                         AND latest_activity_existing.rn = 1
              WHERE latest_activity_existing.Work_Date >= DATEADD(DAY, (-7), GETDATE())
                  AND latest_activity_existing.Work_Date IS NOT NULL
                  AND latest_activity_existing.Last_Updated IS NOT NULL
                  AND (j_existing.Status NOT IN ('Complete', 'Closed', 'Shipped') 
                       OR j_existing.Status_Date >= DATEADD(DAY, (-1), GETDATE()))
                  AND w_existing.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
          )
)

-- ORIGINAL DEDUPLICATION - One record per machine using machine_rank - NULL-SAFE OUTPUTS
SELECT 
    ISNULL(Machine, '') AS Machine, 
    ISNULL(Department, '') AS Department, 
    ISNULL(DeptMachine, '') AS DeptMachine, 
    ISNULL(CustomerPartJob, '') AS CustomerPartJob, 
    ISNULL(JobDueDtStatus, '') AS JobDueDtStatus,
    ISNULL(OperationDetails, '') AS OperationDetails, 
    ISNULL(OperatorActivity, '') AS OperatorActivity, 
    ISNULL(LastUpdated, '1900-01-01') AS LastUpdated,
    -- ERROR DETECTION: Add "??" flag when multiple jobs detected
    ISNULL(CASE 
        WHEN jobs_on_machine > 1 AND LEFT(MachineStatus, CHARINDEX(' | ', MachineStatus + ' | ') - 1) IN ('ACTIVE', 'IDLE', 'OverPlan', 'STAGING', 'STAGING-IDLE', 'STAGED')
        THEN REPLACE(StatusDuration, LEFT(MachineStatus, CHARINDEX(' | ', MachineStatus + ' | ') - 1), LEFT(MachineStatus, CHARINDEX(' | ', MachineStatus + ' | ') - 1) + '??')
        ELSE StatusDuration
    END, '') AS StatusDuration,
    -- ERROR DETECTION: Add "??" flag to individual status too
    ISNULL(CASE 
        WHEN jobs_on_machine > 1 AND LEFT(MachineStatus, CHARINDEX(' | ', MachineStatus + ' | ') - 1) IN ('ACTIVE', 'IDLE', 'OverPlan', 'STAGING', 'STAGING-IDLE', 'STAGED')
        THEN REPLACE(MachineStatus, LEFT(MachineStatus, CHARINDEX(' | ', MachineStatus + ' | ') - 1), LEFT(MachineStatus, CHARINDEX(' | ', MachineStatus + ' | ') - 1) + '??')
        ELSE MachineStatus
    END, '') AS MachineStatus,
    ISNULL(ProgressDisplay, '') AS ProgressDisplay, 
    ISNULL(RunQty, 0) AS RunQty, 
    ISNULL(ScrapQty, 0) AS ScrapQty, 
    ISNULL(RequiredQty, 0) AS RequiredQty, 
    ISNULL(PercentComplete, 0.0) AS PercentComplete
FROM (
    SELECT *,
        MAX(CASE WHEN LEFT(MachineStatus, CHARINDEX(' | ', MachineStatus + ' | ') - 1) IN ('ACTIVE', 'IDLE', 'OverPlan', 'STAGING', 'STAGING-IDLE', 'STAGED') THEN 1 ELSE 0 END) 
            OVER (PARTITION BY Machine) AS has_active_work,
        ROW_NUMBER() OVER (
            PARTITION BY Machine, CASE WHEN LEFT(MachineStatus, CHARINDEX(' | ', MachineStatus + ' | ') - 1) = 'OFFLINE' THEN 1 ELSE 0 END
            ORDER BY LastUpdated DESC, RunQty DESC
        ) AS offline_rank
    FROM MachineStatusCTE
) filtered
WHERE machine_rank = 1
     
--ORDER BY Department, Machine
GO
