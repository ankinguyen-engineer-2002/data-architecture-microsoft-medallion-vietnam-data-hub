"""
Query Watchdog for Fabric Warehouse
Monitors running queries and kills long-running ad-hoc queries to prevent CU burn.
"""
from __future__ import annotations

import os
import sys
import time
import urllib.parse
import urllib.request
import json
from datetime import datetime
from typing import Optional

try:
    import pyodbc
except ImportError:
    print("ERROR: pyodbc not installed. Run: pip install pyodbc")
    sys.exit(1)

try:
    import yaml
except ImportError:
    print("ERROR: pyyaml not installed. Run: pip install pyyaml")
    sys.exit(1)


class QueryWatchdog:
    def __init__(self, config_path: str = "config.yaml"):
        """Initialize watchdog with config"""
        with open(config_path) as f:
            self.config = yaml.safe_load(f)
        
        # Load settings from config
        self.threshold_seconds = self.config['kill_threshold_seconds']
        self.warehouses = self.config['warehouses']
        self.iterations = self.config['iterations']
        self.interval = self.config['interval_seconds']
        
        # Exclusion rules
        self.excluded_procedures = self.config['exclusions']['procedure_patterns']
        self.excluded_keywords = self.config['exclusions']['etl_keywords']
        self.excluded_logins = self.config['exclusions']['login_names']
        self.excluded_wait_types = self.config['excluded_wait_types']
        
        # Connection settings
        self.tenant_id = os.getenv('FABRIC_TENANT_ID', '5a9d9cfd-c32e-4ac1-a9ed-fe83df4f9e4d')
        self.client_id = os.getenv('FABRIC_CLIENT_ID')
        self.client_secret = os.getenv('FABRIC_CLIENT_SECRET')
        self.sql_server = os.getenv('FABRIC_SQL_SERVER', 
            '7woj2wroypauvkpn72b56t46ju-qp6ntsfwdaou5atebne65u3p4a.datawarehouse.fabric.microsoft.com')
        
        if not self.client_id or not self.client_secret:
            raise RuntimeError("Missing FABRIC_CLIENT_ID or FABRIC_CLIENT_SECRET environment variables")
        
        self.token = None
        self.token_expiry = None
    
    def get_token(self) -> str:
        """Get access token for SQL authentication using Service Principal"""
        # Check if token is still valid (refresh 5 min before expiry)
        if self.token and self.token_expiry:
            from datetime import datetime, timedelta
            if datetime.utcnow() < self.token_expiry - timedelta(minutes=5):
                return self.token
        
        # Request new token
        body = urllib.parse.urlencode({
            "grant_type": "client_credentials",
            "client_id": self.client_id,
            "client_secret": self.client_secret,
            "scope": "https://database.windows.net/.default"
        }).encode("utf-8")
        
        req = urllib.request.Request(
            f"https://login.microsoftonline.com/{self.tenant_id}/oauth2/v2.0/token",
            data=body,
            method="POST",
            headers={"Content-Type": "application/x-www-form-urlencoded"}
        )
        
        with urllib.request.urlopen(req, timeout=60) as resp:
            result = json.loads(resp.read().decode("utf-8"))
            self.token = result["access_token"]
            # Token typically valid for 1 hour
            from datetime import datetime, timedelta
            self.token_expiry = datetime.utcnow() + timedelta(seconds=result.get('expires_in', 3600))
            return self.token
    
    def get_connection(self, database: str) -> pyodbc.Connection:
        """Create connection to Fabric Warehouse"""
        token = self.get_token()
        
        conn_str = (
            f"Driver={{ODBC Driver 18 for SQL Server}};"
            f"Server={self.sql_server};"
            f"Database={database};"
            f"Encrypt=yes;"
            f"TrustServerCertificate=no;"
            f"Connection Timeout=30;"
        )
        
        # SQL_COPT_SS_ACCESS_TOKEN = 1256
        conn = pyodbc.connect(conn_str, attrs_before={1256: token.encode('utf-16-le')})
        return conn
    
    def should_exclude_query(self, command: str, login_name: str, wait_type: Optional[str], 
                            blocking_session_id: Optional[int]) -> tuple[bool, str]:
        """
        Check if query should be excluded from killing.
        Returns: (should_exclude, reason)
        """
        if not command:
            return True, "No command text"
        
        # Check stored procedures
        for pattern in self.excluded_procedures:
            if pattern in command:
                return True, f"Stored procedure ({pattern})"
        
        # Check ETL keywords
        command_upper = command.upper()
        for keyword in self.excluded_keywords:
            if keyword in command_upper:
                return True, f"ETL workload ({keyword})"
        
        # Check login names
        if login_name in self.excluded_logins:
            return True, f"Excluded user ({login_name})"
        
        # Check if blocked by another session
        if blocking_session_id is not None and blocking_session_id > 0:
            return True, f"Blocked by session {blocking_session_id}"
        
        # Check wait types (query waiting, not consuming CU)
        if wait_type and wait_type in self.excluded_wait_types:
            return True, f"Waiting ({wait_type})"
        
        return False, ""
    
    def check_and_kill_queries(self, warehouse: str) -> dict:
        """
        Check running queries in warehouse and kill long-running ad-hoc queries.
        Returns: stats dict
        """
        stats = {
            'warehouse': warehouse,
            'checked': 0,
            'excluded': 0,
            'killed': 0,
            'errors': 0
        }
        
        try:
            conn = self.get_connection(warehouse)
            cursor = conn.cursor()
            
            # Query DMVs for running queries
            cursor.execute("""
                SELECT 
                    r.session_id,
                    r.start_time,
                    r.total_elapsed_time,
                    r.command,
                    r.status,
                    r.wait_type,
                    r.blocking_session_id,
                    s.login_name
                FROM sys.dm_exec_requests r
                JOIN sys.dm_exec_sessions s ON r.session_id = s.session_id
                WHERE r.status = 'running'
                  AND r.session_id != @@SPID  -- Don't kill ourselves
                ORDER BY r.total_elapsed_time DESC
            """)
            
            rows = cursor.fetchall()
            stats['checked'] = len(rows)
            
            print(f"  [{warehouse}] Found {len(rows)} running queries")
            
            for row in rows:
                session_id = row.session_id
                start_time = row.start_time
                elapsed_ms = row.total_elapsed_time
                command = row.command or ""
                wait_type = row.wait_type
                blocking_session_id = row.blocking_session_id
                login_name = row.login_name or ""
                
                elapsed_seconds = elapsed_ms / 1000 if elapsed_ms else 0
                
                # Check if query exceeds threshold
                if elapsed_seconds <= self.threshold_seconds:
                    continue
                
                # Check exclusion rules
                should_exclude, reason = self.should_exclude_query(
                    command, login_name, wait_type, blocking_session_id
                )
                
                if should_exclude:
                    print(f"    [SKIP] Session {session_id}: {reason}")
                    stats['excluded'] += 1
                    continue
                
                # Kill query
                print(f"    [KILL] Session {session_id}:")
                print(f"           User: {login_name}")
                print(f"           Elapsed: {elapsed_seconds:.0f}s (threshold: {self.threshold_seconds}s)")
                print(f"           Query: {command[:200]}...")
                
                try:
                    # Note: In Fabric, KILL uses string session_id
                    cursor.execute(f"KILL '{session_id}'")
                    stats['killed'] += 1
                    print(f"           ✓ Killed successfully")
                    
                    # Log to audit table (if exists)
                    try:
                        cursor.execute("""
                            IF OBJECT_ID('Meta.QueryGovernorLog', 'U') IS NOT NULL
                            BEGIN
                                INSERT INTO Meta.QueryGovernorLog 
                                (WarehouseName, SessionId, LoginName, QueryStartTime, 
                                 ElapsedSeconds, Action, QueryText, KillSuccess)
                                VALUES (?, ?, ?, ?, ?, 'KILL', ?, 1)
                            END
                        """, warehouse, str(session_id), login_name, start_time,
                            int(elapsed_seconds), command[:4000])
                        conn.commit()
                    except Exception as log_err:
                        print(f"           Warning: Could not log to audit table: {log_err}")
                
                except Exception as e:
                    error_msg = str(e)
                    stats['errors'] += 1
                    print(f"           ✗ Error: {error_msg}")
                    
                    # Try to log error
                    try:
                        cursor.execute("""
                            IF OBJECT_ID('Meta.QueryGovernorLog', 'U') IS NOT NULL
                            BEGIN
                                INSERT INTO Meta.QueryGovernorLog 
                                (WarehouseName, SessionId, LoginName, QueryStartTime, 
                                 ElapsedSeconds, Action, QueryText, KillSuccess, ErrorMessage)
                                VALUES (?, ?, ?, ?, ?, 'KILL', ?, 0, ?)
                            END
                        """, warehouse, str(session_id), login_name, start_time,
                            int(elapsed_seconds), command[:4000], error_msg[:1000])
                        conn.commit()
                    except:
                        pass
            
            cursor.close()
            conn.close()
            
        except Exception as e:
            print(f"  [ERROR] {warehouse}: {e}")
            stats['errors'] += 1
        
        return stats
    
    def run(self):
        """Main loop: run iterations with interval"""
        print(f"=== Query Watchdog Started at {datetime.utcnow().isoformat()}Z ===")
        print(f"Configuration:")
        print(f"  - Kill threshold: {self.threshold_seconds}s")
        print(f"  - Warehouses: {', '.join(self.warehouses)}")
        print(f"  - Iterations: {self.iterations}")
        print(f"  - Interval: {self.interval}s")
        print()
        
        total_stats = {
            'checked': 0,
            'excluded': 0,
            'killed': 0,
            'errors': 0
        }
        
        for iteration in range(1, self.iterations + 1):
            print(f"--- Iteration {iteration}/{self.iterations} at {datetime.utcnow().strftime('%H:%M:%S')}Z ---")
            
            for warehouse in self.warehouses:
                stats = self.check_and_kill_queries(warehouse)
                total_stats['checked'] += stats['checked']
                total_stats['excluded'] += stats['excluded']
                total_stats['killed'] += stats['killed']
                total_stats['errors'] += stats['errors']
            
            # Sleep between iterations (except last one)
            if iteration < self.iterations:
                print(f"  Sleeping {self.interval}s...")
                time.sleep(self.interval)
            
            print()
        
        print(f"=== Query Watchdog Completed at {datetime.utcnow().isoformat()}Z ===")
        print(f"Summary:")
        print(f"  - Queries checked: {total_stats['checked']}")
        print(f"  - Queries excluded: {total_stats['excluded']}")
        print(f"  - Queries killed: {total_stats['killed']}")
        print(f"  - Errors: {total_stats['errors']}")


def main():
    """Entry point"""
    try:
        watchdog = QueryWatchdog()
        watchdog.run()
    except Exception as e:
        print(f"FATAL ERROR: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
