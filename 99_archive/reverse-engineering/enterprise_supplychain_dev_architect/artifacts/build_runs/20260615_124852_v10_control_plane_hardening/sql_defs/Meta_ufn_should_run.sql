CREATE FUNCTION Meta.ufn_should_run(@asset_id VARCHAR(128))
    RETURNS INT
    AS
    BEGIN
        DECLARE @result INT = 0;
        SELECT @result = CASE
            WHEN is_active = 0 THEN 0
            WHEN next_run_time IS NOT NULL AND next_run_time <= GETUTCDATE() THEN 1
            WHEN next_run_time IS NULL AND (cron_expression IS NULL OR LTRIM(RTRIM(cron_expression)) = '') THEN 1
            WHEN next_run_time IS NULL THEN Meta.ufn_cron_is_due(cron_expression)
            ELSE 0
        END
        FROM Meta.AssetRegistry WHERE asset_id = @asset_id;
        RETURN ISNULL(@result, 0);
    END
