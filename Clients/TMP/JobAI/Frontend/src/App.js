import React, { useState } from 'react';
import JobTraveler from './components/JobTraveler';
import JobAnalysis from './components/JobAnalysis';
import './App.css';

function App() {
  const [jobNumber, setJobNumber] = useState('');
  const [currentJob, setCurrentJob] = useState(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);

  const handleSearch = async (e) => {
    e.preventDefault();
    
    if (!jobNumber.trim()) {
      setError('Please enter a job number');
      return;
    }

    setLoading(true);
    setError(null);
    setCurrentJob(null);

    try {
      const response = await fetch(`http://localhost:5000/api/job-traveler/${jobNumber}`);
      
      if (!response.ok) {
        throw new Error(`Job ${jobNumber} not found`);
      }

      const data = await response.json();
      setCurrentJob(data);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="App">
      <header className="App-header">
        <h1>
          <span className="robot-icon">🤖</span>
          JobAI - Intelligent Job Analysis
        </h1>
        <p className="subtitle">AI-Powered Manufacturing Job Insights</p>
      </header>

      <main className="App-main">
        <div className="search-container">
          <form onSubmit={handleSearch} className="search-form">
            <input
              type="text"
              value={jobNumber}
              onChange={(e) => setJobNumber(e.target.value)}
              placeholder="Enter Job Number (e.g., 1317608)"
              className="job-input"
              disabled={loading}
            />
            <button 
              type="submit" 
              className="search-button"
              disabled={loading}
            >
              {loading ? 'Loading...' : 'Search Job'}
            </button>
          </form>

          {error && (
            <div className="error-message">
              <strong>Error:</strong> {error}
            </div>
          )}
        </div>

        {currentJob && (
          <div className="results-container">
            {/* Job Traveler Table - The "Opening Set of Facts" */}
            <section className="traveler-section">
              <h2>Job Traveler - Complete Operation Data</h2>
              <p className="section-description">
                This table shows ALL operations for the job, providing complete context
                for AI analysis and decision-making.
              </p>
              <JobTraveler data={currentJob} />
            </section>

            {/* AI Analysis Section */}
            <section className="analysis-section">
              <h2>AI Analysis & Recommendations</h2>
              <JobAnalysis jobNumber={currentJob.job.jobNumber} travelerData={currentJob} />
            </section>
          </div>
        )}

        {!currentJob && !loading && !error && (
          <div className="welcome-message">
            <h2>Welcome to JobAI</h2>
            <p>Enter a job number above to get started with intelligent job analysis.</p>
            <div className="features">
              <div className="feature">
                <span className="feature-icon">📊</span>
                <h3>Complete Job Overview</h3>
                <p>View all operations, statuses, and time entries in one place</p>
              </div>
              <div className="feature">
                <span className="feature-icon">🤖</span>
                <h3>AI-Powered Insights</h3>
                <p>Get intelligent analysis and recommendations from Claude AI</p>
              </div>
              <div className="feature">
                <span className="feature-icon">⚡</span>
                <h3>Actionable Recommendations</h3>
                <p>Identify bottlenecks and get prioritized action items</p>
              </div>
            </div>
          </div>
        )}
      </main>

      <footer className="App-footer">
        <p>JobAI v1.0.0 | IQ Associates | Powered by Claude AI</p>
      </footer>
    </div>
  );
}

export default App;
