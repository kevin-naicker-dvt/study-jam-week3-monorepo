import { useNavigate } from 'react-router-dom';

export default function DashboardPage() {
  const navigate = useNavigate();
  const userStr = localStorage.getItem('user');
  const user = userStr ? JSON.parse(userStr) : null;

  const handleLogout = () => {
    localStorage.removeItem('access_token');
    localStorage.removeItem('user');
    navigate('/login');
  };

  return (
    <div className="dashboard-container">
      <nav className="dashboard-nav">
        <div className="nav-brand">
          <div className="logo-circle small">SJ</div>
          <span>Study Jam Week 3</span>
        </div>
        <button onClick={handleLogout} className="btn-outline">
          Logout
        </button>
      </nav>

      <main className="dashboard-main">
        <div className="welcome-card">
          <div className="welcome-icon">
            {user?.name?.charAt(0).toUpperCase()}
            {user?.surname?.charAt(0).toUpperCase()}
          </div>
          <h1>
            Welcome, {user?.name} {user?.surname}!
          </h1>
          <p className="welcome-email">{user?.email}</p>
          <div className="access-badge">Access Granted</div>
        </div>

        <div className="info-grid">
          <div className="info-card">
            <h3>Backend</h3>
            <p>NestJS + Drizzle ORM</p>
            <span className="tag">REST API</span>
          </div>
          <div className="info-card">
            <h3>Database</h3>
            <p>PostgreSQL on GCP Cloud SQL</p>
            <span className="tag">africa-south1</span>
          </div>
          <div className="info-card">
            <h3>Frontend</h3>
            <p>React + TypeScript + Vite</p>
            <span className="tag">Cloud Run</span>
          </div>
          <div className="info-card">
            <h3>CI/CD</h3>
            <p>GCP Cloud Build + Artifact Registry</p>
            <span className="tag">Automated</span>
          </div>
        </div>
      </main>
    </div>
  );
}
