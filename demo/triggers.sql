USE streamteam;

DROP TRIGGER IF EXISTS team_before_insert;
DROP TRIGGER IF EXISTS draftsin_before_insert;
DROP TRIGGER IF EXISTS draftpick_before_insert;
DROP TRIGGER IF EXISTS rosters_before_insert;
DROP TRIGGER IF EXISTS rosters_before_update;
DROP TRIGGER IF EXISTS lineup_before_insert;
DROP TRIGGER IF EXISTS lineup_before_update;
DROP TRIGGER IF EXISTS pickuprequest_before_insert;
DROP TRIGGER IF EXISTS matchup_before_insert;

DELIMITER $$

-- R4: stops a team from joining if the league already has max_teams
CREATE TRIGGER team_before_insert
BEFORE INSERT ON Team
FOR EACH ROW
BEGIN
    DECLARE team_count INT;
    DECLARE league_max INT;

    SELECT COUNT(*) INTO team_count
    FROM Team
    WHERE league_id = NEW.league_id;

    SELECT max_teams INTO league_max
    FROM League
    WHERE league_id = NEW.league_id;

    IF team_count >= league_max THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'League is full';
    END IF;
END$$

-- R5: cant set draft order until the league is full, and the team has to be in that league
CREATE TRIGGER draftsin_before_insert
BEFORE INSERT ON DraftsIn
FOR EACH ROW
BEGIN
    DECLARE draft_league INT;
    DECLARE team_league INT;
    DECLARE team_count INT;
    DECLARE league_max INT;

    SELECT s.league_id INTO draft_league
    FROM Draft d
    JOIN Season s ON d.season_id = s.season_id
    WHERE d.draft_id = NEW.draft_id;

    SELECT league_id INTO team_league
    FROM Team
    WHERE team_id = NEW.team_id;

    IF team_league <> draft_league THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Team is not in this draft''s league';
    END IF;

    SELECT COUNT(*) INTO team_count
    FROM Team
    WHERE league_id = draft_league;

    SELECT max_teams INTO league_max
    FROM League
    WHERE league_id = draft_league;

    IF team_count < league_max THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Draft order cannot be set until the league is full';
    END IF;
END$$

-- R7: team has to be in the draft and cant draft more than roster_size
CREATE TRIGGER draftpick_before_insert
BEFORE INSERT ON DraftPick
FOR EACH ROW
BEGIN
    DECLARE pick_count INT;
    DECLARE max_roster INT;

    IF NOT EXISTS (
        SELECT 1
        FROM DraftsIn
        WHERE draft_id = NEW.draft_id
          AND team_id = NEW.team_id
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Team is not part of this draft';
    END IF;

    SELECT COUNT(*) INTO pick_count
    FROM DraftPick
    WHERE draft_id = NEW.draft_id
      AND team_id = NEW.team_id;

    SELECT l.roster_size INTO max_roster
    FROM Team t
    JOIN League l ON t.league_id = l.league_id
    WHERE t.team_id = NEW.team_id;

    IF pick_count >= max_roster THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Team has already drafted a full roster';
    END IF;
END$$

-- R9: an artist cant be on 2 teams in the same league, also cant go over roster_size
CREATE TRIGGER rosters_before_insert
BEFORE INSERT ON Rosters
FOR EACH ROW
BEGIN
    DECLARE team_league INT;
    DECLARE active_count INT;
    DECLARE max_roster INT;

    SELECT league_id INTO team_league
    FROM Team
    WHERE team_id = NEW.team_id;

    IF NEW.released_at IS NULL THEN
        IF EXISTS (
            SELECT 1
            FROM Rosters r
            JOIN Team t ON r.team_id = t.team_id
            WHERE r.artist_id = NEW.artist_id
              AND r.released_at IS NULL
              AND t.league_id = team_league
        ) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Artist is already on a team in this league';
        END IF;

        SELECT COUNT(*) INTO active_count
        FROM Rosters
        WHERE team_id = NEW.team_id
          AND released_at IS NULL;

        SELECT roster_size INTO max_roster
        FROM League
        WHERE league_id = team_league;

        IF active_count >= max_roster THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Roster is full';
        END IF;
    END IF;
END$$

-- R9: same idea but for when an artist gets put back on a roster
CREATE TRIGGER rosters_before_update
BEFORE UPDATE ON Rosters
FOR EACH ROW
BEGIN
    DECLARE team_league INT;

    IF OLD.released_at IS NOT NULL AND NEW.released_at IS NULL THEN
        SELECT league_id INTO team_league
        FROM Team
        WHERE team_id = NEW.team_id;

        IF EXISTS (
            SELECT 1
            FROM Rosters r
            JOIN Team t ON r.team_id = t.team_id
            WHERE r.artist_id = NEW.artist_id
              AND r.released_at IS NULL
              AND t.league_id = team_league
        ) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Artist is already on a team in this league';
        END IF;
    END IF;
END$$

-- R10: you can only put artists in your lineup if theyre on your roster, and cant go over active_slots
CREATE TRIGGER lineup_before_insert
BEFORE INSERT ON Lineup
FOR EACH ROW
BEGIN
    DECLARE starter_count INT;
    DECLARE max_active INT;

    IF NOT EXISTS (
        SELECT 1
        FROM Rosters
        WHERE team_id = NEW.team_id
          AND artist_id = NEW.artist_id
          AND released_at IS NULL
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Artist is not on this team''s roster';
    END IF;

    IF NEW.is_starter THEN
        SELECT COUNT(*) INTO starter_count
        FROM Lineup
        WHERE team_id = NEW.team_id
          AND effective_date = NEW.effective_date
          AND is_starter = TRUE;

        SELECT l.active_slots INTO max_active
        FROM Team t
        JOIN League l ON t.league_id = l.league_id
        WHERE t.team_id = NEW.team_id;

        IF starter_count >= max_active THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'All active slots are filled for this date';
        END IF;
    END IF;
END$$

-- R10: cant switch someone from bench to starter if active slots are already full
CREATE TRIGGER lineup_before_update
BEFORE UPDATE ON Lineup
FOR EACH ROW
BEGIN
    DECLARE starter_count INT;
    DECLARE max_active INT;

    IF NEW.is_starter AND NOT OLD.is_starter THEN
        SELECT COUNT(*) INTO starter_count
        FROM Lineup
        WHERE team_id = NEW.team_id
          AND effective_date = NEW.effective_date
          AND is_starter = TRUE;

        SELECT l.active_slots INTO max_active
        FROM Team t
        JOIN League l ON t.league_id = l.league_id
        WHERE t.team_id = NEW.team_id;

        IF starter_count >= max_active THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'All active slots are filled for this date';
        END IF;
    END IF;
END$$

-- R11: you can only drop someone on your team and only add someone nobody in the league has
CREATE TRIGGER pickuprequest_before_insert
BEFORE INSERT ON PickupRequest
FOR EACH ROW
BEGIN
    DECLARE team_league INT;

    SELECT league_id INTO team_league
    FROM Team
    WHERE team_id = NEW.team_id;

    IF NOT EXISTS (
        SELECT 1
        FROM Rosters
        WHERE team_id = NEW.team_id
          AND artist_id = NEW.drop_artist_id
          AND released_at IS NULL
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Dropped artist is not on this team''s roster';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM Rosters r
        JOIN Team t ON r.team_id = t.team_id
        WHERE r.artist_id = NEW.add_artist_id
          AND r.released_at IS NULL
          AND t.league_id = team_league
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Added artist is already on a team in this league';
    END IF;
END$$

-- R14: both teams in a matchup have to be in the same league as the season
CREATE TRIGGER matchup_before_insert
BEFORE INSERT ON Matchup
FOR EACH ROW
BEGIN
    DECLARE season_league INT;

    SELECT league_id INTO season_league
    FROM Season
    WHERE season_id = NEW.season_id;

    IF (SELECT league_id FROM Team WHERE team_id = NEW.team_id_a) <> season_league
       OR (SELECT league_id FROM Team WHERE team_id = NEW.team_id_b) <> season_league THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Both teams must be in the season''s league';
    END IF;
END$$

DELIMITER ;