--Verifica os processos com LOCK
SELECT 
     SessionID = s.Session_id,
     resource_type,   
     DatabaseName = DB_NAME(resource_database_id),
     request_mode,
     request_type,
     login_time,
     host_name,
     program_name,
     client_interface_name,
     login_name,
     nt_domain,
     nt_user_name,
     s.status,
     last_request_start_time,
     last_request_end_time,
     s.logical_reads,
     s.reads,
     request_status,
     request_owner_type,
     objectid,
     dbid,
     a.number,
     a.encrypted ,
     a.blocking_session_id,
     a.text       
 FROM   
     sys.dm_tran_locks l
     JOIN sys.dm_exec_sessions s ON l.request_session_id = s.session_id
     LEFT JOIN   
     (
         SELECT  *
         FROM    sys.dm_exec_requests r
         CROSS APPLY sys.dm_exec_sql_text(sql_handle)
     ) a ON s.session_id = a.session_id
 WHERE  
     s.session_id > 50;

--Matar o processo pelo session_id	 
Kill 51