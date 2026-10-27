USE streamteam;

DROP TABLE IF EXISTS TestResult;
CREATE TABLE TestResult (
    test_no      INT AUTO_INCREMENT PRIMARY KEY,
    rule_tested  VARCHAR(20),
    description  VARCHAR(255),
    expected     VARCHAR(10),
    actual       VARCHAR(10),
    message      VARCHAR(255),
    result       VARCHAR(4)
);

DROP PROCEDURE IF EXISTS run_test;

DELIMITER $$

-- runs one insert/update, catches the error if there is one and logs if it did what we expected
CREATE PROCEDURE run_test(IN p_rule VARCHAR(20), IN p_desc VARCHAR(255), IN p_expected VARCHAR(10), IN p_sql TEXT)
BEGIN
    DECLARE failed INT DEFAULT 0;
    DECLARE err_msg VARCHAR(255) DEFAULT '';

    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN
        SET failed = 1;
        GET DIAGNOSTICS CONDITION 1 err_msg = MESSAGE_TEXT;
    END;

    SET @stmt = p_sql;
    PREPARE s FROM @stmt;
    EXECUTE s;
    DEALLOCATE PREPARE s;

    INSERT INTO TestResult (rule_tested, description, expected, actual, message, result)
    VALUES (
        p_rule,
        p_desc,
        p_expected,
        IF(failed = 1, 'reject', 'accept'),
        err_msg,
        IF((failed = 1) = (p_expected = 'reject'), 'PASS', 'FAIL')
    );
END$$

DELIMITER ;

-- setup data, 2 leagues so we can test stuff across leagues
-- league 1 has roster_size 3 and active_slots 2 so the limits are easy to hit
INSERT INTO User (user_id, username, email, password) VALUES
    (1, 'enrique', 'e@test.com',  'pw'),
    (2, 'ethan',   'et@test.com', 'pw'),
    (3, 'sam',     's@test.com',  'pw'),
    (4, 'alex',    'a@test.com',  'pw'),
    (5, 'jordan',  'j@test.com',  'pw'),
    (6, 'casey',   'c@test.com',  'pw');

INSERT INTO League (league_id, user_id, name, roster_size, active_slots, max_teams) VALUES
    (1, 1, 'Test League', 3, 2, 4),
    (2, 5, 'Other League', 8, 5, 4);

INSERT INTO Season (season_id, league_id, season_num, start_date) VALUES
    (1, 1, 1, '2026-11-01'),
    (2, 2, 1, '2026-11-01');

INSERT INTO Draft (draft_id, season_id, draft_date) VALUES (1, 1, '2026-10-30');

INSERT INTO Artist (artist_id, artist_name) VALUES
    (1, 'Artist One'), (2, 'Artist Two'), (3, 'Artist Three'), (4, 'Artist Four'),
    (5, 'Artist Five'), (6, 'Artist Six');

INSERT INTO Team (team_id, league_id, user_id, team_name) VALUES
    (1, 1, 1, 'Team A'),
    (2, 1, 2, 'Team B'),
    (3, 1, 3, 'Team C'),
    (5, 2, 5, 'Other Team');

-- R5 draft order cant be set until the league is full (league 1 only has 3 teams rn)
-- test 1: try setting draft order when only 3 teams are in, should fail
CALL run_test('R5', 'set draft order before league is full', 'reject',
    'INSERT INTO DraftsIn VALUES (1, 1, 1)');

-- R4 league size
-- test 2: add the 4th team, should work
CALL run_test('R4', 'add 4th team to league', 'accept',
    'INSERT INTO Team (team_id, league_id, user_id, team_name) VALUES (4, 1, 4, ''Team D'')');
-- test 3: try adding a 5th team when the league is full, should fail
CALL run_test('R4', 'add 5th team to full league', 'reject',
    'INSERT INTO Team (team_id, league_id, user_id, team_name) VALUES (6, 1, 6, ''Team E'')');
-- test 4: same user tries to make a 2nd team in the same league, should fail
CALL run_test('UNIQUE', 'same user makes 2 teams in one league', 'reject',
    'INSERT INTO Team (team_id, league_id, user_id, team_name) VALUES (7, 2, 5, ''Second Team'')');

-- R5 now the league is full so draft order works
-- test 5: league is full now so setting draft order should work
CALL run_test('R5', 'set draft order once league is full', 'accept',
    'INSERT INTO DraftsIn VALUES (1, 1, 1), (1, 2, 2), (1, 3, 3), (1, 4, 4)');
-- test 6: team from a different league tries to join this draft, should fail
CALL run_test('R5', 'team from another league joins draft', 'reject',
    'INSERT INTO DraftsIn VALUES (1, 5, 5)');

-- R7 draft picks
-- test 7: team A drafts 3 artists, should work
CALL run_test('R7', 'team in the draft picks 3 artists', 'accept',
    'INSERT INTO DraftPick VALUES (1, 1, 1, 1), (1, 2, 1, 2), (1, 3, 1, 3)');
-- test 8: team A tries to draft a 4th when roster_size is 3, should fail
CALL run_test('R7', 'team picks more than roster_size', 'reject',
    'INSERT INTO DraftPick VALUES (1, 4, 1, 4)');
-- test 9: a team thats not in the draft tries to pick, should fail
CALL run_test('R7', 'team not in this draft makes a pick', 'reject',
    'INSERT INTO DraftPick VALUES (1, 5, 5, 5)');
-- test 10: someone tries to draft an artist thats already been picked, should fail
CALL run_test('UNIQUE', 'same artist drafted twice', 'reject',
    'INSERT INTO DraftPick VALUES (1, 6, 2, 1)');

-- R9 rosters
-- test 11: put artist 1 on team A, should work
CALL run_test('R9', 'put artist 1 on team A', 'accept',
    'INSERT INTO Rosters VALUES (1, 1, ''2026-10-30 10:00:00'', NULL, ''draft'')');
-- test 12: put artist 1 on team B too (same league), should fail
CALL run_test('R9', 'put artist 1 on team B in same league', 'reject',
    'INSERT INTO Rosters VALUES (2, 1, ''2026-10-30 10:00:00'', NULL, ''draft'')');
-- test 13: put artist 1 on a team in a different league, should work
CALL run_test('R9', 'put artist 1 on a team in a different league', 'accept',
    'INSERT INTO Rosters VALUES (5, 1, ''2026-10-30 10:00:00'', NULL, ''draft'')');
-- test 14: fill up team A to 3 artists, should work
CALL run_test('R9', 'fill team A roster to roster_size', 'accept',
    'INSERT INTO Rosters VALUES (1, 2, ''2026-10-30 10:00:00'', NULL, ''draft''), (1, 3, ''2026-10-30 10:00:00'', NULL, ''draft'')');
-- test 15: try adding a 4th artist to team A, should fail
CALL run_test('R9', 'add artist to a full roster', 'reject',
    'INSERT INTO Rosters VALUES (1, 4, ''2026-10-30 10:00:00'', NULL, ''draft'')');
-- test 16: released date is before acquired date, should fail
CALL run_test('CHECK', 'released before acquired', 'reject',
    'INSERT INTO Rosters VALUES (3, 5, ''2026-10-30 10:00:00'', ''2026-10-29 10:00:00'', ''draft'')');

-- team A drops artist 1 and team B grabs them
-- test 17: team A releases artist 1, should work
CALL run_test('R9', 'release artist 1 from team A', 'accept',
    'UPDATE Rosters SET released_at = ''2026-11-02 08:00:00'' WHERE team_id = 1 AND artist_id = 1');
-- test 18: team B picks up artist 1 now that theyre free, should work
CALL run_test('R9', 'team B picks up released artist 1', 'accept',
    'INSERT INTO Rosters VALUES (2, 1, ''2026-11-02 09:00:00'', NULL, ''pickup'')');
-- test 19: try putting artist 1 back on team A when team B has them, should fail
CALL run_test('R9', 'un-release artist 1 back onto team A', 'reject',
    'UPDATE Rosters SET released_at = NULL WHERE team_id = 1 AND artist_id = 1');
-- test 20: team A uses the open spot for artist 4, should work
CALL run_test('R9', 'team A fills open spot with artist 4', 'accept',
    'INSERT INTO Rosters VALUES (1, 4, ''2026-11-02 09:00:00'', NULL, ''pickup'')');

-- R10 lineups (team A has artists 2, 3, 4 and active_slots is 2)
-- test 21: team A tries to start artist 1 who isnt on their roster anymore, should fail
CALL run_test('R10', 'start artist not on the roster', 'reject',
    'INSERT INTO Lineup VALUES (1, 1, ''2026-11-03'', TRUE)');
-- test 22: team A starts 2 of their artists, should work
CALL run_test('R10', 'start 2 rostered artists', 'accept',
    'INSERT INTO Lineup VALUES (1, 2, ''2026-11-03'', TRUE), (1, 3, ''2026-11-03'', TRUE)');
-- test 23: team A tries to start a 3rd when active_slots is 2, should fail
CALL run_test('R10', 'start a 3rd artist past active_slots', 'reject',
    'INSERT INTO Lineup VALUES (1, 4, ''2026-11-03'', TRUE)');
-- test 24: put the 3rd artist on the bench instead, should work
CALL run_test('R10', 'put 3rd artist on the bench', 'accept',
    'INSERT INTO Lineup VALUES (1, 4, ''2026-11-03'', FALSE)');
-- test 25: try switching the bench guy to starter when slots are full, should fail
CALL run_test('R10', 'switch bench artist to starter when full', 'reject',
    'UPDATE Lineup SET is_starter = TRUE WHERE team_id = 1 AND artist_id = 4 AND effective_date = ''2026-11-03''');

-- R14 matchups
-- test 26: matchup between team A and team B, should work
CALL run_test('R14', 'matchup between 2 teams in the league', 'accept',
    'INSERT INTO Matchup (season_id, team_id_a, team_id_b, start_date) VALUES (1, 1, 2, ''2026-11-01'')');
-- test 27: matchup with a team from another league, should fail
CALL run_test('R14', 'matchup with a team from another league', 'reject',
    'INSERT INTO Matchup (season_id, team_id_a, team_id_b, start_date) VALUES (1, 1, 5, ''2026-11-01'')');
-- test 28: team plays itself, should fail
CALL run_test('CHECK', 'team plays itself', 'reject',
    'INSERT INTO Matchup (season_id, team_id_a, team_id_b, start_date) VALUES (1, 1, 1, ''2026-11-01'')');

-- R11 pickups (team A has 2, 3, 4 and team B has artist 1)
-- test 29: team A picks up free artist 6 and drops artist 2, should work
CALL run_test('R11', 'add free artist 6 and drop artist 2', 'accept',
    'INSERT INTO PickupRequest (team_id, add_artist_id, drop_artist_id) VALUES (1, 6, 2)');
-- test 30: team A tries to drop artist 1 who isnt on their team, should fail
CALL run_test('R11', 'drop an artist not on your team', 'reject',
    'INSERT INTO PickupRequest (team_id, add_artist_id, drop_artist_id) VALUES (1, 6, 1)');
-- test 31: team A tries to add artist 1 who team B has, should fail
CALL run_test('R11', 'add an artist another team has', 'reject',
    'INSERT INTO PickupRequest (team_id, add_artist_id, drop_artist_id) VALUES (1, 1, 2)');

-- other CHECK constraints
-- test 32: league with more active slots than roster spots, should fail
CALL run_test('CHECK', 'league with more active slots than roster', 'reject',
    'INSERT INTO League (user_id, name, roster_size, active_slots) VALUES (1, ''Bad League'', 3, 5)');
-- test 33: season with a status that isnt allowed, should fail
CALL run_test('CHECK', 'season with a made up status', 'reject',
    'INSERT INTO Season (league_id, season_num, start_date, status) VALUES (1, 2, ''2026-11-01'', ''paused'')');

-- results
SELECT test_no, rule_tested, description, expected, actual, result, message
FROM TestResult
ORDER BY test_no;

SELECT
    COUNT(*) AS total_tests,
    SUM(result = 'PASS') AS passed,
    SUM(result = 'FAIL') AS failed
FROM TestResult;