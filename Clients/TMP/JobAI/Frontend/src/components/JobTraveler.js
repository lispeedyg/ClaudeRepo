import React, { useState } from 'react';
import './JobTraveler.css';

/**
 * JobTraveler Component
 * 
 * Displays the complete "opening set of facts" for a job.
 * Shows ALL operations in a comprehensive table format, providing
 * the foundational context for AI analysis and user understanding.
 */
const JobTraveler = ({ data }) => {
  const [expandedRows, setExpandedRows] = useState(new Set());

  if (!data) return null;

  const { job, operations, summary } = data;

  const toggleRow = (sequence) => {
    const newExpanded = new Set(expandedRows);
    if (newExpanded.has(sequence)) {
      newExpanded.delete(sequence);
    } else {
      newExpanded.add(sequence);
    }
    setExpandedRows(newExpanded);
  };

  const getStatusClass = (statusCode) => {
    switch (statusCode) {
      case 'C': return 'status-complete';
      case 'S': return 'status-started';
      case 'O': return 'status-open';
      case 'H': return 'status-hold';
      default: return 'status-other';
    }
  };

  const getActionClass = (actionNeeded) => {
    if (actionNeeded.includes('CLEANUP NEEDED')) return 'action-critical';
    if (actionNeeded.includes('No action needed')) return 'action-none';
    return 'action-info';
  };

  return (
    <div className="job-traveler">
      {/* Job Header Card */}
      <div className="job-header-card">
        <div className="job-header-grid">
          <div className="job-header-item">
            <label>Job Number:</label>
            <strong>{job.jobNumber}</strong>
          </div>
          <div className="job-header-item">
            <label>Customer:</label>
            <strong>{job.customer}</strong>
          </div>
          <div className="job-header-item">
            <label>Part Number:</label>
            <strong>{job.partNumber}</strong>
          </div>
          <div className="job-header-item">
            <label>Job Status:</label>
            <span className={`status-badge ${getStatusClass(job.status)}`}>
              {job.status}
            </span>
          </div>
        </div>

        {/* Summary Stats */}
        <div className="summary-stats">
          <div className="stat">
            <span className="stat-value">{summary.totalOperations}</span>
            <span className="stat-label">Total Operations</span>
          </div>
          <div className="stat">
            <span className="stat-value">{summary.completeOperations}</span>
            <span className="stat-label">Complete</span>
          </div>
          <div className="stat">
            <span className="stat-value">{summary.activeOperations}</span>
            <span className="stat-label">Active</span>
          </div>
          <div className="stat">
            <span className="stat-value">{summary.openOperations}</span>
            <span className="stat-label">Open</span>
          </div>
        </div>
      </div>

      {/* Operations Table */}
      <div className="operations-table-container">
        <table className="operations-table">
          <thead>
            <tr>
              <th className="col-expand"></th>
              <th className="col-sequence">Seq</th>
              <th className="col-workcenter">Work Center</th>
              <th className="col-description">Description</th>
              <th className="col-status">Status</th>
              <th className="col-hours">Hours</th>
              <th className="col-qty">Qty Produced</th>
              <th className="col-operator">Latest Operator</th>
              <th className="col-action">Action Needed</th>
            </tr>
          </thead>
          <tbody>
            {operations.map((op, index) => (
              <React.Fragment key={index}>
                <tr 
                  className={`operation-row ${expandedRows.has(op.sequence) ? 'expanded' : ''}`}
                  onClick={() => toggleRow(op.sequence)}
                >
                  <td className="col-expand">
                    <span className="expand-icon">
                      {expandedRows.has(op.sequence) ? '▼' : '▶'}
                    </span>
                  </td>
                  <td className="col-sequence">
                    <strong>{op.sequence}</strong>
                  </td>
                  <td className="col-workcenter">
                    <span className="workcenter-badge">{op.workCenter}</span>
                  </td>
                  <td className="col-description">
                    {op.description}
                  </td>
                  <td className="col-status">
                    <span className={`status-badge ${getStatusClass(op.statusCode)}`}>
                      {op.statusMeaning}
                    </span>
                  </td>
                  <td className="col-hours">
                    {op.totalHours ? op.totalHours.toFixed(2) : '0.00'}
                  </td>
                  <td className="col-qty">
                    {op.qtyProduced || 0} / {op.requiredQty || 0}
                  </td>
                  <td className="col-operator">
                    {op.latestOperator || '-'}
                  </td>
                  <td className="col-action">
                    <span className={`action-badge ${getActionClass(op.actionNeeded)}`}>
                      {op.actionNeeded}
                    </span>
                  </td>
                </tr>
                
                {/* Expanded Details Row */}
                {expandedRows.has(op.sequence) && (
                  <tr className="details-row">
                    <td colSpan="9">
                      <div className="operation-details">
                        <div className="detail-grid">
                          <div className="detail-item">
                            <label>Job Operation:</label>
                            <span>{op.jobOperation}</span>
                          </div>
                          <div className="detail-item">
                            <label>Operation Service:</label>
                            <span>{op.operationService}</span>
                          </div>
                          <div className="detail-item">
                            <label>Actual Start:</label>
                            <span>{op.actualStart ? new Date(op.actualStart).toLocaleDateString() : 'Not Started'}</span>
                          </div>
                          <div className="detail-item">
                            <label>Last Work Date:</label>
                            <span>
                              {op.lastWorkDate 
                                ? `${new Date(op.lastWorkDate).toLocaleDateString()} (${op.daysSinceLastWork} days ago)`
                                : 'No activity yet'}
                            </span>
                          </div>
                          <div className="detail-item">
                            <label>Status Check:</label>
                            <span>{op.statusCheck}</span>
                          </div>
                          <div className="detail-item full-width">
                            <label>Required Quantity:</label>
                            <span>{op.requiredQty || 'N/A'}</span>
                          </div>
                        </div>
                      </div>
                    </td>
                  </tr>
                )}
              </React.Fragment>
            ))}
          </tbody>
        </table>
      </div>

      {/* Legend */}
      <div className="table-legend">
        <h4>Status Legend:</h4>
        <div className="legend-items">
          <span className="legend-item">
            <span className="status-badge status-complete">Complete</span>
            Operation finished
          </span>
          <span className="legend-item">
            <span className="status-badge status-started">Started</span>
            Work in progress
          </span>
          <span className="legend-item">
            <span className="status-badge status-open">Open</span>
            Ready to start
          </span>
          <span className="legend-item">
            <span className="status-badge status-hold">On Hold</span>
            Temporarily paused
          </span>
        </div>
      </div>
    </div>
  );
};

export default JobTraveler;
