SELECT jobid, schedule, command, nodename, nodeport, database, username, active
FROM cron.job
ORDER BY jobid;
