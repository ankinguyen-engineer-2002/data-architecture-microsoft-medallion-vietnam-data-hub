CREATE   PROCEDURE Meta.usp_LogPipelineRun
    @pipeline_run_id VARCHAR(128), @pipeline_name VARCHAR(256), @status VARCHAR(80),
    @tables_succeeded INT = NULL, @tables_failed INT = NULL, @notes VARCHAR(2000) = NULL,
    @project VARCHAR(128) = NULL
AS
BEGIN
    DECLARE @now DATETIME2(6) = CAST(GETUTCDATE() AS DATETIME2(6));
    IF @status = 'running'
        INSERT INTO Meta.PipelineRunLog (pipeline_run_id, pipeline_name, project, status, start_time_utc, trigger_type)
        VALUES (@pipeline_run_id, @pipeline_name, @project, 'running', @now, 'Manual');
    ELSE
        UPDATE Meta.PipelineRunLog
        SET project = COALESCE(@project, project),
            status = @status,
            end_time_utc = @now,
            error_message = @notes
        WHERE pipeline_run_id = @pipeline_run_id;
END;
