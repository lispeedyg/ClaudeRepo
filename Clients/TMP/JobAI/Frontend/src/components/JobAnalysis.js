import React, { useState } from 'react';
import './JobAnalysis.css';

/**
 * JobAnalysis Component
 * 
 * Integrates with Claude AI to provide intelligent analysis
 * of job status, bottlenecks, and recommendations based on
 * the complete traveler data.
 */
const JobAnalysis = ({ jobNumber, travelerData }) => {
  const [analysis, setAnalysis] = useState(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);

  const requestAnalysis = async () => {
    setLoading(true);
    setError(null);

    try {
      const response = await fetch(`http://localhost:5000/api/job-analysis/${jobNumber}`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        }
      });

      if (!response.ok) {
        throw new Error('Failed to get AI analysis');
      }

      const data = await response.json();
      setAnalysis(data.analysis);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="job-analysis">
      {!analysis && !loading && (
        <div className="analysis-prompt">
          <p>Click the button below to get AI-powered insights about this job</p>
          <button 
            className="analyze-button"
            onClick={requestAnalysis}
          >
            🤖 Request AI Analysis
          </button>
        </div>
      )}

      {loading && (
        <div className="analysis-loading">
          <div className="spinner"></div>
          <p>Claude is analyzing the job... This may take a few seconds.</p>
        </div>
      )}

      {error && (
        <div className="analysis-error">
          <strong>Error:</strong> {error}
          <button onClick={requestAnalysis} className="retry-button">
            Retry
          </button>
        </div>
      )}

      {analysis && (
        <div className="analysis-content">
          <div className="analysis-header">
            <h3>AI Analysis Results</h3>
            <button onClick={requestAnalysis} className="refresh-button">
              🔄 Refresh Analysis
            </button>
          </div>
          <div className="analysis-text">
            <pre>{analysis}</pre>
          </div>
        </div>
      )}
    </div>
  );
};

export default JobAnalysis;
